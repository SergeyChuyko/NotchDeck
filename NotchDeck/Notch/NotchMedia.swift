import AppKit
import Combine
import SwiftUI

/// Что играет в системном плеере — в любом: Музыка, Spotify, видео в браузере.
///
/// Данные достаёт не само приложение. С macOS 15.4 системный MediaRemote отвечает только
/// процессам, подписанным Apple, а нам возвращает пустоту. Поэтому работу делает подпроцесс
/// `/usr/bin/perl`, который грузит в себя нашу библиотеку `MediaRemoteAdapter.dylib`
/// (исходник и объяснение — в `MediaAdapter/MediaRemoteAdapter.m`).
/// Отсюда мы только читаем построчный JSON из его stdout и пишем команды в stdin.
@MainActor
final class NotchMedia: ObservableObject {

    struct Track: Equatable {
        let title: String
        let artist: String
        let album: String
        /// Чем играет — «Arc», «Музыка», «Telegram». Нужен, когда у источника нет подписи:
        /// видео в браузере сплошь и рядом отдаёт пустые название и исполнителя.
        let application: String
        let duration: TimeInterval
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    /// Цвет обложки — им красится эквалайзер на чёлке. Белый, пока обложки нет.
    @Published private(set) var accent: Color = .white
    @Published private(set) var isPlaying = false
    /// Позиция трека и момент, когда мост её прислал: между обновлениями досчитываем сами.
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var elapsedAt = Date()
    /// Мост не поднялся — показываем причину вместо плеера.
    @Published private(set) var failure: String?

    private var bridge: Process?
    private var commands: FileHandle?
    private var buffer = Data()
    private var artworkID: String?
    private var applicationNames: [String: String] = [:]
    /// До этого момента позицию от моста игнорируем — см. `seek(to:)`.
    private var seekSettlesAt: Date = .distantPast

    /// Загрузчик для perl: подтягивает библиотеку и вызывает её точку входа.
    /// Ровно этот приём и обходит запрет — код исполняется внутри perl, а он подписан Apple.
    private static let loader = """
    use DynaLoader;
    my $library = shift;
    my $handle = DynaLoader::dl_load_file($library, 0) or die "library\\n";
    my $symbol = DynaLoader::dl_find_symbol($handle, "notchdeck_media_run") or die "symbol\\n";
    DynaLoader::dl_install_xsub("main::run", $symbol);
    run();
    """

    // MARK: - Жизненный цикл

    func start() {
        guard bridge == nil else { return }

        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
            failure = "В системе нет /usr/bin/perl — без него не добраться до системного плеера."
            return
        }
        guard let adapter = Bundle.main.url(forResource: "MediaRemoteAdapter", withExtension: "dylib") else {
            failure = "В сборке нет MediaRemoteAdapter.dylib — не отработала скриптовая фаза."
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.loader, adapter.path]

        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        // Обработчики зовут нас с чужой очереди, поэтому возвращаемся на главный актор.
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            Task { @MainActor in self.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.bridgeDied() }
        }

        do {
            try process.run()
        } catch {
            failure = "Не удалось запустить мост к плееру: \(error.localizedDescription)"
            return
        }

        bridge = process
        commands = input.fileHandleForWriting
    }

    func stop() {
        commands = nil
        // Мост сам завершится, увидев закрытый stdin, но ждать этого незачем.
        bridge?.terminate()
        bridge = nil
    }

    private func bridgeDied() {
        bridge = nil
        commands = nil
        track = nil
        artwork = nil
        artworkID = nil
        isPlaying = false
        failure = "Мост к плееру завершился. Перезапустите приложение."
    }

    /// Позиция трека на заданный момент: мост присылает её редко, между его сообщениями
    /// она просто растёт вместе со временем.
    func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return elapsed }
        return elapsed + max(date.timeIntervalSince(elapsedAt), 0)
    }

    // MARK: - Команды

    func togglePlayPause() {
        // Отвечаем на нажатие сразу: подтверждение от плеера придёт своим чередом.
        isPlaying.toggle()
        elapsedAt = Date()
        send("toggle")
    }

    func nextTrack() { send("next") }

    func previousTrack() { send("previous") }

    /// Перемотать на позицию в секундах.
    ///
    /// Показанную позицию двигаем сразу, не дожидаясь ответа: мост подтвердит через
    /// треть секунды, и без этого ползунок отскакивал бы назад под пальцем.
    func seek(to position: TimeInterval) {
        let target = min(max(position, 0), track?.duration ?? position)
        elapsed = target
        elapsedAt = Date()
        // Секунду после перемотки держим свою позицию. Плеер отвечает не мгновенно и
        // успевает прислать ещё старую — без этой паузы ползунок отскакивал бы назад.
        seekSettlesAt = Date().addingTimeInterval(1)
        send("seek \(target)")
    }

    /// Спросить состояние прямо сейчас — на случай, если уведомление от плеера потерялось.
    /// Зовём при раскрытии панели: именно в этот момент показанное и должно быть свежим.
    func refresh() { send("refresh") }

    /// Кнопка обновления в разделе. Обычно достаточно переспросить, но если мост успел
    /// завершиться, спрашивать некого — тогда поднимаем его заново.
    func reload() {
        guard bridge != nil else {
            failure = nil
            start()
            return
        }
        refresh()
    }

    private func send(_ command: String) {
        guard let commands else { return }
        try? commands.write(contentsOf: Data((command + "\n").utf8))
    }

    // MARK: - Разбор ответов моста

    private func consume(_ data: Data) {
        buffer.append(data)

        // Обложка приезжает в той же строке, поэтому строка бывает и на десятки килобайт.
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            apply(line)
        }
    }

    private func apply(_ line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let state = json["state"] as? String else { return }

        switch state {
        case "idle":
            track = nil
            artwork = nil
            artworkID = nil
            isPlaying = false

        case "unavailable":
            failure = json["reason"] as? String ?? "Системный плеер недоступен."

        default:
            failure = nil
            track = Track(
                title: json["title"] as? String ?? "",
                artist: json["artist"] as? String ?? "",
                album: json["album"] as? String ?? "",
                application: applicationName(json["app"] as? String),
                duration: json["duration"] as? TimeInterval ?? 0
            )
            isPlaying = json["playing"] as? Bool ?? false
            if Date() >= seekSettlesAt {
                elapsed = json["elapsed"] as? TimeInterval ?? 0
                elapsedAt = Date()
            }
            applyArtwork(json)
        }
    }

    /// Мост присылает идентификатор приложения, а показать нужно человеческое имя.
    /// Ответы кэшируем: идентификатор между треками почти всегда один и тот же.
    private func applicationName(_ bundleIdentifier: String?) -> String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return "" }
        if let known = applicationNames[bundleIdentifier] { return known }

        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? ""
        applicationNames[bundleIdentifier] = name
        return name
    }

    /// Картинку мост шлёт только при смене трека, поэтому на неё нужен отдельный разбор:
    /// пришёл прежний идентификатор без данных — оставляем что было.
    private func applyArtwork(_ json: [String: Any]) {
        let identifier = json["artworkId"] as? String

        if let encoded = json["artwork"] as? String,
           let data = Data(base64Encoded: encoded),
           let image = NSImage(data: data) {
            artwork = image
            accent = Self.accent(for: image)
            artworkID = identifier
            return
        }

        if identifier == nil || identifier != artworkID {
            artwork = nil
            accent = .white
            artworkID = identifier
        }
    }

    /// Один цвет, которым можно покрасить эквалайзер.
    ///
    /// Усреднять обложку в лоб нельзя — на пёстрой картинке выходит серая каша. Поэтому
    /// вес каждой точки — квадрат её насыщенности: блёклые и серые пиксели почти не влияют,
    /// а цветные тянут результат на себя. В конце поднимаем насыщенность и яркость:
    /// на чёрной чёлке приглушённый цвет просто не виден.
    private static func accent(for image: NSImage) -> Color {
        let side = 16
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .white
        }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .white }

        var weightSum = 0.0, red = 0.0, green = 0.0, blue = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255

            let brightest = max(r, g, b)
            let saturation = brightest > 0 ? (brightest - min(r, g, b)) / brightest : 0
            let weight = saturation * saturation * brightest

            red += r * weight; green += g * weight; blue += b * weight
            weightSum += weight
        }

        // Обложка целиком серая — красить нечем, оставляем белый.
        guard weightSum > 0.001 else { return .white }

        let color = NSColor(red: red / weightSum, green: green / weightSum,
                            blue: blue / weightSum, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return Color(hue: hue, saturation: max(saturation, 0.55), brightness: max(brightness, 0.85))
    }
}
