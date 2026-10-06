import AppKit
import Combine
import CoreServices
import QuickLookThumbnailing
import SwiftUI

/// Лента сделанных скриншотов, новые первыми.
///
/// Читаем папку, куда система складывает снимки, и оставляем только те файлы,
/// у которых Spotlight проставил метку `kMDItemIsScreenCapture` — по именам ориентироваться
/// нельзя, они локализованы. За появлением новых файлов следим через ядро, без опроса.
@MainActor
final class NotchScreenshots: NSObject, ObservableObject {

    struct Shot: Identifiable, Equatable {
        var id: URL { url }
        let url: URL
        let date: Date
    }

    @Published private(set) var shots: [Shot] = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    /// Система не пустила в папку со снимками — без разрешения показывать нечего.
    @Published private(set) var accessDenied = false

    private let limit = 30
    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"]
    private var directorySource: DispatchSourceFileSystemObject?
    /// Путь, за которым сейчас следим. Папку снимков можно поменять в системных
    /// настройках на ходу — тогда наблюдателя нужно перевесить на новую.
    private var watchedPath: String?
    private var reloadTask: Task<Void, Never>?

    /// Куда система кладёт снимки: настройка `com.apple.screencapture`, иначе Рабочий стол.
    private var screenshotDirectory: URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"), !location.isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    // MARK: - Наблюдение

    func start() {
        guard directorySource == nil else { return }
        reload()
        watchDirectory()
    }

    /// Панель открывают на секунду — лента должна быть свежей сразу.
    /// Событий от папки может и не быть: наблюдатель не встал (в момент запуска
    /// не было доступа), папку снимков сменили или её пересоздали под тем же именем.
    func refresh() {
        if directorySource == nil || watchedPath != screenshotDirectory.path {
            stop()
            watchDirectory()
        }
        reload()
    }

    func stop() {
        reloadTask?.cancel()
        reloadTask = nil
        directorySource?.cancel()
        directorySource = nil
        watchedPath = nil
    }

    /// Ядро само сообщит, что в папке что-то изменилось — опрашивать диск не нужно.
    private func watchDirectory() {
        // Darwin.open, а не наш метод open(_:) ниже.
        let descriptor = Darwin.open(screenshotDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        directorySource = source
        watchedPath = screenshotDirectory.path
    }

    /// Перечитываем не один раз, а серией с нарастающей паузой.
    /// Файл в папке появляется раньше, чем Spotlight успевает проставить ему метку снимка:
    /// одного прохода не хватило бы, а второго события от папки уже не придёт.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            for pause in [400, 1200, 3000] {
                try? await Task.sleep(for: .milliseconds(pause))
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }
    }

    private func reload() {
        let directory = screenshotDirectory
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]

        let files: [URL]
        do {
            // Это обращение заодно и вызывает системный запрос доступа к папке.
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            accessDenied = false
        } catch {
            accessDenied = true
            shots = []
            return
        }

        // Если под снимки выделена отдельная папка, там всё и есть снимки.
        // На общем Рабочем столе полагаемся на системную метку.
        let isDedicatedFolder = directory.lastPathComponent != "Desktop"

        let found: [Shot] = files.compactMap { url in
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            guard isDedicatedFolder || Self.isScreenCapture(url) else { return nil }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            return Shot(url: url, date: date)
        }

        shots = Array(found.sorted { $0.date > $1.date }.prefix(limit))
        loadThumbnails()
    }

    /// Метку ставит система при съёмке — она переживает переименование файла.
    private static func isScreenCapture(_ url: URL) -> Bool {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return false }
        let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString)
        if let flag = value as? Bool { return flag }
        if let number = value as? Int { return number == 1 }
        return false
    }

    // MARK: - Миниатюры

    /// Полноразмерный снимок с ретины весит мегабайты, поэтому показываем системные
    /// миниатюры — Quick Look отдаёт их быстро и кэширует за нас.
    private func loadThumbnails() {
        let urls = Set(shots.map(\.url))
        thumbnails = thumbnails.filter { urls.contains($0.key) }

        for url in urls where thumbnails[url] == nil {
            Task { [weak self] in
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: CGSize(width: 160, height: 110),
                    scale: 2,
                    representationTypes: .thumbnail
                )
                guard let representation = try? await QLThumbnailGenerator.shared
                    .generateBestRepresentation(for: request) else { return }
                self?.thumbnails[url] = representation.nsImage
            }
        }
    }

    // MARK: - Действия

    /// Кладём и файл, и картинку: одни приложения ждут вставки файла, другие — изображения.
    func copyToPasteboard(_ shot: Shot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var objects: [NSPasteboardWriting] = [shot.url as NSURL]
        if let image = NSImage(contentsOf: shot.url) {
            objects.append(image)
        }
        pasteboard.writeObjects(objects)
    }

    /// Убираем в Корзину, а не удаляем насовсем: снимок всегда можно вернуть.
    func moveToTrash(_ shot: Shot) {
        let path = shot.url.path
        var trashed = FileManager.default.fileExists(atPath: path) == false

        if !trashed {
            do {
                try FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
                trashed = true
            } catch {
                // trashItem спотыкается на томах без Корзины и на снимках, лежащих
                // в чужой песочнице. Через Workspace то же самое делает уже система.
                NSWorkspace.shared.recycle([shot.url]) { [weak self] _, error in
                    guard let self else { return }
                    if error != nil {
                        NSSound.beep()
                        // Файл на месте, убрать не вышло — карточка должна остаться.
                        self.reload()
                    }
                }
                trashed = true
            }
        }

        guard trashed else { return }

        // Наблюдатель за папкой пришлёт обновление с задержкой в несколько секунд,
        // а карточка должна исчезнуть в тот же момент, когда по ней кликнули.
        shots.removeAll { $0.url == shot.url }
        thumbnails[shot.url] = nil
    }

    /// Открыть в Finder саму папку, куда система складывает скриншоты.
    func openFolder() {
        NSWorkspace.shared.open(screenshotDirectory)
    }

    func revealInFinder(_ shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    func open(_ shot: Shot) {
        NSWorkspace.shared.open(shot.url)
    }
}
