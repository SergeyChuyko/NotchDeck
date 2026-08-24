import AppKit
import Combine
import SwiftUI

/// История буфера обмена.
///
/// Система не умеет сообщать о копировании, поэтому единственный способ —
/// периодически заглядывать в `NSPasteboard` и сравнивать его `changeCount`.
@MainActor
final class NotchClipboard: ObservableObject {

    struct Item: Identifiable, Equatable, Codable {
        var id = UUID()
        let text: String
        let date: Date
        var isPinned = false
    }

    @Published private(set) var items: [Item] = [] {
        didSet { scheduleSave() }
    }

    /// Закреплённые идут первыми, остальные — в порядке копирования.
    var orderedItems: [Item] {
        items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }

    /// Менеджеры паролей помечают свои записи этим типом, прося их не сохранять.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private let pasteboard = NSPasteboard.general
    private let limit = 50
    private var lastChangeCount = 0
    private var pollTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    // MARK: - Наблюдение

    func start() {
        guard pollTask == nil else { return }

        load()

        // То, что лежит в буфере прямо сейчас, — уже первая запись истории.
        lastChangeCount = pasteboard.changeCount
        capture()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                self?.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        capture()
    }

    /// Забрать текущее содержимое буфера в историю.
    private func capture() {
        // Пароли из менеджеров в историю не попадают.
        guard pasteboard.types?.contains(Self.concealedType) != true else { return }

        // Скопировали файл, а не текст. Finder кладёт рядом с файлом ещё и его имя
        // строкой — без этой проверки история засорялась бы именами файлов.
        // Ссылки из интернета проверку проходят: она смотрит только на файловые.
        guard !pasteboard.canReadObject(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) else { return }

        guard let text = pasteboard.string(forType: .string) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard items.first?.text != text else { return }

        // Повтор старой записи не плодит дубликат, а всплывает наверх.
        // Закрепление при этом сохраняется.
        let wasPinned = items.first { $0.text == text }?.isPinned ?? false
        items.removeAll { $0.text == text }
        items.insert(Item(text: text, date: Date(), isPinned: wasPinned), at: 0)

        // Вытесняем только незакреплённые — закреплённое человек оставил намеренно.
        while items.count > limit, let index = items.lastIndex(where: { !$0.isPinned }) {
            items.remove(at: index)
        }
    }

    // MARK: - Действия

    /// Вернуть запись в буфер обмена. Порядок списка при этом не меняется:
    /// запись остаётся на своём месте, чтобы не сбивать прицел следующему клику.
    func copyToPasteboard(_ item: Item) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        // Это наша же запись — не хотим увидеть её как «новое копирование».
        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
    }

    /// Чистит только незакреплённое.
    func clear() {
        items.removeAll { !$0.isPinned }
    }

    // MARK: - Хранение

    /// История лежит обычным JSON в Application Support.
    private var storeURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("NotchDeck", isDirectory: true)
            .appendingPathComponent("clipboard.json")
    }

    private func load() {
        guard let storeURL,
              let data = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder().decode([Item].self, from: data)
        else { return }

        items = saved
    }

    /// Пишем не на каждое копирование, а когда поток событий утих.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Сохранить немедленно — на выходе ждать нечего.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func save() {
        guard let storeURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(items).write(to: storeURL, options: [.atomic])
            // В файле лежит всё скопированное — читать его должен только владелец.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storeURL.path
            )
        } catch {
            // История не настолько важна, чтобы из-за неё ронять приложение.
        }
    }
}
