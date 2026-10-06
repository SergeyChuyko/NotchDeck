import SwiftUI

/// Раздел «Плеер»: обложка слева, справа название, кнопки и полоса перемотки,
/// у самого края — громкость.
/// Показывает то, что играет в системе, — хоть трек в Музыке, хоть видео в браузере.
struct NotchMediaView: View {

    @ObservedObject var media: NotchMedia
    @ObservedObject var volume: NotchVolume
    @ObservedObject var controller: NotchController

    /// Какая из кнопок под курсором: 0–2 управление, 3 обновление, 4 лайк.
    @State private var hoveredControl: Int?
    /// Позиция, которую пользователь тащит прямо сейчас. Пока она есть, время и полоса
    /// показывают её, а не то, что приходит от плеера, — иначе ползунок дёргался бы.
    @State private var scrubbing: TimeInterval?
    /// Громкость тянут прямо сейчас — кружок на её полосе подрастает.
    @State private var adjustingVolume = false

    var body: some View {
        Group {
            if let failure = media.failure {
                message(failure, tint: .orange)
            } else if let track = media.track {
                player(track)
            } else {
                message("Ничего не играет. Включите музыку или видео — раздел подхватит их сам.",
                        tint: .secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func message(_ text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)

            refreshButton
        }
    }

    /// Плеер иногда молчит: браузер не прислал метаданные, уведомление потерялось.
    /// Эта кнопка переспрашивает систему, не трогая само воспроизведение. Живёт только
    /// в пустом состоянии — там от неё есть толк; над играющим треком обновлять нечего.
    private var refreshButton: some View {
        control(index: 3, name: "arrow.triangle.2.circlepath", size: 11) {
            media.reload()
        }
        .help("Обновить плеер")
    }

    // MARK: - Плеер

    /// Слева обложка во всю высоту раздела, справа от неё столбец: название с исполнителем,
    /// кнопки и полоса перемотки. У правого края — вертикальная громкость.
    private func player(_ track: NotchMedia.Track) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 14) {
                artwork(height: min(geometry.size.height, NotchConfig.playerArtworkHeight))
                    // Верх обложки вровень с верхом названия.
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 0) {
                    header(track)
                    // Кнопки посередине между названием и полосой, а не прижаты к ней.
                    Spacer(minLength: 4)
                    controls
                    Spacer(minLength: 4)
                    if track.duration > 0 {
                        progress(track)
                    }
                }
                // Полоса не прижата к самому низу — так она читается частью плеера,
                // а не кромкой плашки.
                .padding(.bottom, NotchConfig.playerBottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if volume.isAvailable {
                    volumeControl(height: geometry.size.height)
                }
            }
        }
    }

    /// Заголовок и подпись под ним. Названия может не быть вовсе — видео в браузере часто
    /// не публикует ни его, ни исполнителя. Тогда показываем сам источник: «Arc», «Telegram».
    private func captions(_ track: NotchMedia.Track) -> (title: String, subtitle: String) {
        if track.title.isEmpty {
            return (track.application.isEmpty ? "Идёт воспроизведение" : track.application, "")
        }
        return (track.title, track.artist.isEmpty ? track.application : track.artist)
    }

    /// Название, под ним исполнитель, справа лайк — если источник его понимает.
    private func header(_ track: NotchMedia.Track) -> some View {
        let captions = captions(track)

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // Две строки названию: обложка теперь сбоку, и по высоте место есть,
                // а длинные названия видео в одну строку обрезались на полуслове.
                Text(captions.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)

                if !captions.subtitle.isEmpty {
                    Text(captions.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if media.like != .unavailable {
                likeButton
            }
        }
    }

    /// У видео — палец вверх, у музыки — сердечко. Отмеченный закрашен жёлтым.
    private var likeButton: some View {
        let liked = media.like == .on
        let symbol = isVideo ? "hand.thumbsup" : "heart"

        return Image(systemName: liked ? symbol + ".fill" : symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(liked ? NotchConfig.favoriteYellow : Color.primary.opacity(0.7))
            .frame(width: 30, height: 30)
            .background {
                Circle().fill(Color.primary.opacity(hoveredControl == 4 ? 0.12 : 0))
            }
            .contentShape(Circle())
            .onHover { hovering in
                hoveredControl = hovering ? 4 : (hoveredControl == 4 ? nil : hoveredControl)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { media.toggleLike() }
            }
            .scaleEffect(liked ? 1.08 : 1)
            .help(liked ? "Убрать отметку" : "Нравится")
    }

    /// Видео узнаём по широкому превью: у альбомов обложка квадратная.
    private var isVideo: Bool { artworkAspect > 1.2 }

    /// Пропорции самой картинки: у альбомов обложка квадратная, у видео — широкая.
    /// Крайности зажимаем: обложка стоит сбоку, и слишком широкая съела бы столбец справа.
    private var artworkAspect: CGFloat {
        guard let size = media.artwork?.size, size.width > 0, size.height > 0 else { return 1 }
        return min(max(size.width / size.height, 1), 1.6)
    }

    private func artwork(height: CGFloat) -> some View {
        let size = CGSize(width: (height * artworkAspect).rounded(), height: height)

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: size.width, height: size.height)
            .overlay {
                if let image = media.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.2), value: artworkAspect)
    }

    // MARK: - Перемотка

    /// Мост присылает позицию редко, поэтому между его сообщениями досчитываем её сами.
    private func progress(_ track: NotchMedia.Track) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = scrubbing ?? media.position(at: context.date)
            let fraction = min(max(position / track.duration, 0), 1)

            HStack(spacing: 8) {
                timeCode(position)
                NotchSlider(axis: .horizontal, fraction: CGFloat(fraction),
                            isActive: scrubbing != nil) { value, ended in
                    let target = TimeInterval(value) * track.duration
                    if ended {
                        media.seek(to: target)
                        scrubbing = nil
                    } else {
                        scrubbing = target
                    }
                    // Пока тянут, панель не должна закрыться, даже если курсор
                    // соскользнёт с её края.
                    controller.setInteractionLocked(!ended)
                }
                timeCode(track.duration)
            }
        }
        .frame(height: 16)
    }

    private func timeCode(_ time: TimeInterval) -> some View {
        Text(Self.timeCode(time))
            .font(.system(size: 9))
            // Без этого подписи дёргаются по ширине на каждой секунде.
            .monospacedDigit()
            .foregroundStyle(.secondary)
            // Полоса тянется, подписи — нет: иначе они отъедали бы у неё ширину.
            .fixedSize()
    }

    /// Часы показываем только когда они есть: у трека это «3:41», у длинного видео «2:12:45».
    private static func timeCode(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Громкость

    /// Сверху динамик — по нему звук глушится, под ним толстая полоса без кружка,
    /// растёт снизу вверх, как громкость в Пункте управления.
    /// Полоса — на две трети высоты раздела: во всю высоту она стояла столбом.
    private func volumeControl(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(systemName: speakerSymbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24, height: 18)
                .contentShape(Rectangle())
                .onTapGesture { volume.toggleMute() }
                .help(volume.isMuted ? "Включить звук" : "Выключить звук")

            NotchSlider(axis: .vertical, fraction: CGFloat(volume.isMuted ? 0 : volume.level),
                        isActive: adjustingVolume, thickness: 10, showsThumb: false) { value, ended in
                adjustingVolume = !ended
                volume.setLevel(Float(value))
                controller.setInteractionLocked(!ended)
            }
            .frame(height: max(height * 2 / 3 - 26, 30))
        }
        .frame(width: 24)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var speakerSymbol: String {
        if volume.isMuted || volume.level == 0 { return "speaker.slash.fill" }
        return volume.level < 0.33 ? "speaker.wave.1.fill"
            : volume.level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    // MARK: - Кнопки

    /// Пауза по центру, предыдущий и следующий разнесены по сторонам от неё.
    private var controls: some View {
        HStack(spacing: 22) {
            control(index: 0, name: "backward.fill", size: 24) { media.previousTrack() }
            control(index: 1, name: media.isPlaying ? "pause.fill" : "play.fill", size: 34) {
                media.togglePlayPause()
            }
            control(index: 2, name: "forward.fill", size: 24) { media.nextTrack() }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func control(index: Int, name: String, size: CGFloat,
                         action: @escaping () -> Void) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .frame(width: size + 12, height: size + 12)
            .background {
                Circle().fill(Color.primary.opacity(hoveredControl == index ? 0.12 : 0))
            }
            .contentShape(Circle())
            .onHover { hovering in
                hoveredControl = hovering ? index : (hoveredControl == index ? nil : hoveredControl)
            }
            .onTapGesture(perform: action)
    }
}

/// Полоса для перемотки и для громкости.
///
/// Своя, а не системный Slider: окно панели никогда не активно, и готовые элементы
/// управления в нём ведут себя ненадёжно. У перемотки кружок виден всегда и чуть толще
/// полосы, под курсором подрастает. У громкости кружка нет — сама полоса толстая.
struct NotchSlider: View {

    let axis: Axis
    /// Заполненная доля, 0...1.
    let fraction: CGFloat
    /// Тянут прямо сейчас — кружок крупнее.
    let isActive: Bool
    var thickness: CGFloat = 4
    var showsThumb = true
    /// Новая доля и признак того, что палец отпущен.
    let onChange: (CGFloat, Bool) -> Void

    @State private var isHovered = false

    /// Тонкую полосу трудно поймать курсором — ловим на всю эту ширину.
    private var hitArea: CGFloat { max(thickness, 16) }

    var body: some View {
        GeometryReader { geometry in
            let length = axis == .horizontal ? geometry.size.width : geometry.size.height
            let thumb: CGFloat = showsThumb ? (isActive ? 14 : (isHovered ? 13 : 11)) : 0
            let clamped = min(max(fraction, 0), 1)
            // Кружок не должен вылезать за концы полосы, поэтому ездит по укороченной.
            let thumbOffset = (length - thumb) * clamped
            let filled = showsThumb ? thumbOffset + thumb / 2 : length * clamped

            ZStack(alignment: axis == .horizontal ? .leading : .bottom) {
                Capsule().fill(Color.white.opacity(0.25))
                    .frame(width: axis == .horizontal ? length : thickness,
                           height: axis == .horizontal ? thickness : length)

                // Без своей обрезки капсула короче собственной толщины сплющилась бы
                // в овал — внизу громкости это видно.
                Rectangle().fill(Color.white)
                    .frame(width: axis == .horizontal ? filled : thickness,
                           height: axis == .horizontal ? thickness : filled)
                    .frame(width: axis == .horizontal ? length : thickness,
                           height: axis == .horizontal ? thickness : length,
                           alignment: axis == .horizontal ? .leading : .bottom)
                    .clipShape(Capsule())

                if showsThumb {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .frame(width: thumb, height: thumb)
                        .offset(x: axis == .horizontal ? thumbOffset : 0,
                                y: axis == .horizontal ? 0 : -thumbOffset)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height,
                   alignment: axis == .horizontal ? .leading : .bottom)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: thumb)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onChange(value(at: $0.location, length: length), false) }
                    .onEnded { onChange(value(at: $0.location, length: length), true) }
            )
        }
        .frame(width: axis == .vertical ? hitArea : nil, height: axis == .horizontal ? hitArea : nil)
    }

    private func value(at location: CGPoint, length: CGFloat) -> CGFloat {
        guard length > 0 else { return 0 }
        // Вертикальная растёт снизу вверх, а координаты SwiftUI — сверху вниз.
        let raw = axis == .horizontal ? location.x / length : 1 - location.y / length
        return min(max(raw, 0), 1)
    }
}
