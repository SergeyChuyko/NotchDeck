// Мост к системному «что сейчас играет» (приватный фреймворк MediaRemote).
//
// Почему это отдельная библиотека, а не код внутри NotchDeck.
// С macOS 15.4 MediaRemote отвечает только процессам, подписанным Apple. Обычному
// приложению он возвращает пустоту — проверено на 26.1: клиент nil, PID 0, словарь пуст,
// хотя музыка в этот момент играет. Публичной замены нет: MPNowPlayingInfoCenter отдаёт
// только то, что положило туда само приложение.
//
// Поэтому библиотеку грузит в себя /usr/bin/perl — он подписан Apple, и запрет на него
// не распространяется (osascript, для сравнения, уже не проходит). NotchDeck запускает
// perl подпроцессом, читает построчный JSON из его stdout и шлёт команды в stdin.
//
// Собирается скриптовой фазой Xcode в Resources/MediaRemoteAdapter.dylib, в приложение
// не линкуется. Точка входа вызывается из perl через DynaLoader::dl_install_xsub, поэтому
// у неё сигнатура XSUB — оба аргумента нам не нужны и не трогаются.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

// MARK: - Символы MediaRemote

typedef void (*MRGetNowPlayingInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetNowPlayingClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientBundleIdentifier)(id);
typedef void (*MRRegisterForNotifications)(dispatch_queue_t);
typedef Boolean (*MRSendCommand)(uint32_t, CFDictionaryRef);
typedef void (*MRSetElapsedTime)(double);
typedef void *(*MRGetLocalOrigin)(void);
typedef void (*MRGetSupportedCommandsForOrigin)(void *, dispatch_queue_t, void (^)(CFArrayRef));
typedef uint32_t (*MRCommandInfoGetCommand)(id);
typedef Boolean (*MRCommandInfoGetEnabled)(id);
typedef CFTypeRef (*MRCommandInfoCopyValueForKey)(id, CFStringRef);

// Коды команд плеера.
enum {
    kCommandPlay = 0,
    kCommandPause = 1,
    kCommandTogglePlayPause = 2,
    kCommandNextTrack = 4,
    kCommandPreviousTrack = 5,
    // «Нравится» — то, что в MPRemoteCommandCenter зовётся likeCommand. Регистрирует его
    // далеко не каждый плеер: Музыка да, видео в браузере — нет.
    kCommandLikeTrack = 0x6A,
};

static MRGetNowPlayingInfo gGetNowPlayingInfo;
static MRGetNowPlayingClient gGetNowPlayingClient;
static MRClientBundleIdentifier gClientBundleIdentifier;
static MRSendCommand gSendCommand;
static MRSetElapsedTime gSetElapsedTime;

// Лайк — необязательная часть: не нашлись эти символы, значит кнопки просто не будет,
// а остальной плеер продолжит работать.
static MRGetLocalOrigin gGetLocalOrigin;
static MRGetSupportedCommandsForOrigin gGetSupportedCommands;
static MRCommandInfoGetCommand gCommandInfoGetCommand;
static MRCommandInfoGetEnabled gCommandInfoGetEnabled;
static MRCommandInfoCopyValueForKey gCommandInfoCopyValue;
/// Ключ «команда сейчас включена» — у лайка это «трек уже отмечен».
static CFStringRef gIsActiveKey;
/// Опция «отменить»: тот же лайк с ней снимает отметку, а не ставит дизлайк.
static CFStringRef gIsNegativeOption;

/// Идентификатор последней отправленной обложки: сама картинка едет только когда сменилась.
static NSString *gSentArtworkID;
/// Счётчик отложенных обновлений — гасит пачку уведомлений об одном и том же событии.
static uint64_t gRefreshGeneration;

// MARK: - Вывод

static void writeLine(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *stringValue(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : nil;
}

static double doubleValue(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
}

/// Состояние лайка для текущего источника: «none» — плеер такой команды не знает,
/// «off» — можно отметить, «on» — уже отмечено.
static NSString *likeState(CFArrayRef commands) {
    if (!commands || !gCommandInfoGetCommand) return @"none";

    for (id info in (__bridge NSArray *)commands) {
        if (gCommandInfoGetCommand(info) != kCommandLikeTrack) continue;
        if (gCommandInfoGetEnabled && !gCommandInfoGetEnabled(info)) return @"none";

        CFTypeRef active = gIsActiveKey && gCommandInfoCopyValue
            ? gCommandInfoCopyValue(info, gIsActiveKey) : NULL;
        BOOL liked = active && [(__bridge id)active respondsToSelector:@selector(boolValue)]
            && [(__bridge id)active boolValue];
        if (active) CFRelease(active);
        return liked ? @"on" : @"off";
    }
    return @"none";
}

static void emit(NSDictionary *info, NSString *application, NSString *like) {
    NSString *title = stringValue(info, @"kMRMediaRemoteNowPlayingInfoTitle");
    NSString *artist = stringValue(info, @"kMRMediaRemoteNowPlayingInfoArtist");

    // По названию о простое судить нельзя: видео в браузере сплошь и рядом публикует
    // сессию с пустыми Title и Artist, но при этом честно играет. Признак простоя —
    // отсутствие самого воспроизведения, а не подписи к нему.
    BOOL hasContent = title || artist
        || info[@"kMRMediaRemoteNowPlayingInfoDuration"]
        || info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]
        || info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];

    if (!hasContent) {
        gSentArtworkID = nil;
        writeLine(@{ @"state": @"idle" });
        return;
    }

    double rate = doubleValue(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate");
    double elapsed = doubleValue(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime");

    // Позиция в словаре зафиксирована на момент Timestamp, а не «сейчас».
    id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if ([timestamp isKindOfClass:NSDate.class] && rate > 0) {
        elapsed += [[NSDate date] timeIntervalSinceDate:timestamp] * rate;
    }

    NSMutableDictionary *line = [NSMutableDictionary dictionary];
    line[@"state"] = @"now";
    line[@"playing"] = @(rate > 0);
    line[@"title"] = title ?: @"";
    line[@"artist"] = artist ?: @"";
    line[@"album"] = stringValue(info, @"kMRMediaRemoteNowPlayingInfoAlbum") ?: @"";
    // Когда подписи нет, показать хотя бы источник — «Arc», «Музыка», «Telegram».
    line[@"app"] = application ?: @"";
    line[@"duration"] = @(doubleValue(info, @"kMRMediaRemoteNowPlayingInfoDuration"));
    line[@"elapsed"] = @(MAX(elapsed, 0));
    line[@"like"] = like;

    id rawID = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    NSString *artworkID = rawID ? [NSString stringWithFormat:@"%@", rawID]
                                : (artwork ? @(artwork.length).stringValue : nil);

    if (artworkID) {
        line[@"artworkId"] = artworkID;
        // Обложка весит десятки килобайт — гоняем её только при смене трека.
        if ([artwork isKindOfClass:NSData.class] && ![artworkID isEqualToString:gSentArtworkID]) {
            line[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
            gSentArtworkID = artworkID;
        }
    } else {
        gSentArtworkID = nil;
    }

    writeLine(line);
}

/// Сначала спрашиваем, чей плеер сейчас главный, потом — что в нём. Вложенно, а не
/// параллельно: обе функции отвечают колбэком, а в строку они должны попасть вместе.
static void requestEmit(void) {
    gGetNowPlayingClient(dispatch_get_main_queue(), ^(id client) {
        CFStringRef bundle = client ? gClientBundleIdentifier(client) : NULL;
        NSString *application = bundle ? (__bridge NSString *)bundle : nil;

        gGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
            NSDictionary *dictionary = info ? (__bridge NSDictionary *)info : @{};

            if (!gGetLocalOrigin || !gGetSupportedCommands) {
                emit(dictionary, application, @"none");
                return;
            }
            // Третий вложенный запрос: какие команды понимает плеер. По нему и решаем,
            // показывать ли лайк, — и заодно узнаём, отмечен ли уже трек.
            gGetSupportedCommands(gGetLocalOrigin(), dispatch_get_main_queue(), ^(CFArrayRef commands) {
                emit(dictionary, application, likeState(commands));
            });
        });
    });
}

/// Плеер на одно действие присылает несколько уведомлений подряд — ждём, пока утихнет.
static void scheduleEmit(double delay) {
    uint64_t generation = ++gRefreshGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation == gRefreshGeneration) requestEmit();
    });
}

// MARK: - Команды из stdin

static void runCommandLoop(void) {
    char buffer[64];
    while (fgets(buffer, sizeof(buffer), stdin)) {
        // «seek 123.4» — перемотка на позицию в секундах.
        double position = 0;
        if (sscanf(buffer, "seek %lf", &position) == 1) {
            dispatch_async(dispatch_get_main_queue(), ^{
                gSetElapsedTime(MAX(position, 0));
                // Плеер о перемотке уведомляет не всегда — спрашиваем сами. Ждём дольше,
                // чем после обычных команд: сразу после перемотки он какое-то время
                // отдаёт ещё старую позицию.
                scheduleEmit(0.8);
            });
            continue;
        }

        uint32_t command = UINT32_MAX;
        // «like» / «unlike» — одна и та же команда, отмена идёт опцией.
        BOOL unlike = strncmp(buffer, "unlike", 6) == 0;
        if (unlike || strncmp(buffer, "like", 4) == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSDictionary *options = unlike && gIsNegativeOption
                    ? @{ (__bridge NSString *)gIsNegativeOption: @YES } : nil;
                gSendCommand(kCommandLikeTrack, (__bridge CFDictionaryRef)options);
                scheduleEmit(0.5);
            });
            continue;
        }

        if (strncmp(buffer, "toggle", 6) == 0) command = kCommandTogglePlayPause;
        else if (strncmp(buffer, "next", 4) == 0) command = kCommandNextTrack;
        else if (strncmp(buffer, "previous", 8) == 0) command = kCommandPreviousTrack;
        else if (strncmp(buffer, "play", 4) == 0) command = kCommandPlay;
        else if (strncmp(buffer, "pause", 5) == 0) command = kCommandPause;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (command == UINT32_MAX) {
                // «refresh» — панель открылась и хочет свежее состояние прямо сейчас.
                requestEmit();
                return;
            }
            gSendCommand(command, NULL);
            // Уведомление о смене состояния обычно приходит само, но не от всех плееров.
            scheduleEmit(0.35);
        });
    }
    // stdin закрылся — NotchDeck завершился, и нам больше незачем жить.
    exit(0);
}

// MARK: - Точка входа

void notchdeck_media_run(void *perlInterpreter, void *cv) {
    setvbuf(stdout, NULL, _IOLBF, 0);

    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
                          RTLD_NOW);
    if (!handle) {
        writeLine(@{ @"state": @"unavailable", @"reason": @"MediaRemote не открывается" });
        exit(1);
    }

    gGetNowPlayingInfo = (MRGetNowPlayingInfo)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    gGetNowPlayingClient = (MRGetNowPlayingClient)dlsym(handle, "MRMediaRemoteGetNowPlayingClient");
    gClientBundleIdentifier =
        (MRClientBundleIdentifier)dlsym(handle, "MRNowPlayingClientGetBundleIdentifier");
    gSendCommand = (MRSendCommand)dlsym(handle, "MRMediaRemoteSendCommand");
    gSetElapsedTime = (MRSetElapsedTime)dlsym(handle, "MRMediaRemoteSetElapsedTime");
    MRRegisterForNotifications registerForNotifications =
        (MRRegisterForNotifications)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");

    if (!gGetNowPlayingInfo || !gGetNowPlayingClient || !gClientBundleIdentifier
        || !gSendCommand || !gSetElapsedTime || !registerForNotifications) {
        writeLine(@{ @"state": @"unavailable", @"reason": @"MediaRemote сменил состав функций" });
        exit(1);
    }

    gGetLocalOrigin = (MRGetLocalOrigin)dlsym(handle, "MRMediaRemoteGetLocalOrigin");
    gGetSupportedCommands =
        (MRGetSupportedCommandsForOrigin)dlsym(handle, "MRMediaRemoteGetSupportedCommandsForOrigin");
    gCommandInfoGetCommand = (MRCommandInfoGetCommand)dlsym(handle, "MRMediaRemoteCommandInfoGetCommand");
    gCommandInfoGetEnabled = (MRCommandInfoGetEnabled)dlsym(handle, "MRMediaRemoteCommandInfoGetEnabled");
    gCommandInfoCopyValue =
        (MRCommandInfoCopyValueForKey)dlsym(handle, "MRMediaRemoteCommandInfoCopyValueForKey");
    CFStringRef *activeKey = dlsym(handle, "kMRMediaRemoteCommandInfoIsActiveKey");
    CFStringRef *negativeOption = dlsym(handle, "kMRMediaRemoteOptionIsNegative");
    gIsActiveKey = activeKey ? *activeKey : NULL;
    gIsNegativeOption = negativeOption ? *negativeOption : NULL;

    registerForNotifications(dispatch_get_main_queue());

    NSArray<NSString *> *notifications = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        @"kMRNowPlayingPlaybackQueueChangedNotification",
        // Лайк поставили в самом плеере — сердечко у нас должно это увидеть.
        @"kMRMediaRemoteSupportedCommandsDidChangeNotification",
    ];
    for (NSString *name in notifications) {
        [NSNotificationCenter.defaultCenter addObserverForName:name
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            scheduleEmit(0.12);
        }];
    }

    // Страховка от пропущенных уведомлений — и заодно свежая позиция трека.
    [NSTimer scheduledTimerWithTimeInterval:5
                                    repeats:YES
                                      block:^(NSTimer *timer) { requestEmit(); }];

    [NSThread detachNewThreadWithBlock:^{ runCommandLoop(); }];

    requestEmit();
    CFRunLoopRun();
}
