import AppKit
import Combine
import SwiftUI
import Translation

/// Переводчик между русским и английским поверх системного фреймворка Translation.
/// Переводит локально, без сети и ключей; языковые пакеты система скачивает сама
/// при первом обращении.
@MainActor
final class NotchTranslator: ObservableObject {

    enum Direction {
        case ruToEn
        case enToRu

        var sourceLanguage: Locale.Language {
            Locale.Language(identifier: self == .ruToEn ? "ru" : "en")
        }

        var targetLanguage: Locale.Language {
            Locale.Language(identifier: self == .ruToEn ? "en" : "ru")
        }

        var sourceTitle: String { self == .ruToEn ? "Русский" : "English" }
        var targetTitle: String { self == .ruToEn ? "English" : "Русский" }

        var reversed: Direction { self == .ruToEn ? .enToRu : .ruToEn }
    }

    /// Одна запись истории. Направление хранится русским флагом, а не самим Direction:
    /// так формат на диске не зависит от того, как перечисление устроено внутри.
    struct HistoryEntry: Codable, Equatable, Identifiable {
        var id = UUID()
        let source: String
        let target: String
        let sourceIsRussian: Bool
        var date = Date()

        var direction: Direction { sourceIsRussian ? .ruToEn : .enToRu }
    }

    /// Что показывает нижняя часть вытянутой плашки.
    enum Drawer {
        case details
        case history
    }

    enum DetailsState: Equatable {
        case idle
        case loading
        case loaded(NotchTranslatorDictionary.Details)
        case failed
    }

    @Published var direction: Direction = .ruToEn
    @Published var input: String = ""
    @Published private(set) var output: String = ""
    @Published private(set) var isTranslating = false
    @Published private(set) var errorText: String?

    /// Бледное продолжение слова, которое человек сейчас набирает. Только хвост —
    /// то, что допишется по Tab.
    @Published private(set) var completion: String = ""

    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var details: DetailsState = .idle

    /// Для какой пары уже загружены варианты — чтобы не спрашивать сеть заново
    /// при каждом открытии.
    private var detailsKey: String?
    private var detailsTask: Task<Void, Never>?

    /// Запись в историю откладываем: пока человек печатает, переводы идут на каждой паузе,
    /// и без этого в истории копились бы «hel», «hello», «hello wo».
    private var historyTask: Task<Void, Never>?

    private static let historyKey = "translatorHistory"
    private static let historyLimit = 50

    /// Меняя её, мы просим `.translationTask` начать новый перевод.
    @Published private(set) var configuration: TranslationSession.Configuration?

    private var debounceTask: Task<Void, Never>?

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init() {
        loadHistory()
    }

    // MARK: - Ввод

    /// Переводим не на каждую букву, а когда человек перестал печатать.
    func inputChanged() {
        debounceTask?.cancel()
        historyTask?.cancel()
        updateCompletion()

        guard !trimmedInput.isEmpty else {
            output = ""
            errorText = nil
            isTranslating = false
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.requestTranslation()
        }
    }

    // MARK: - Подсказка слова

    /// Словарь проверки орфографии знает и русский, и английский, и даёт продолжения
    /// по началу слова — ровно то, что нужно для подсказки. Работает локально.
    private func updateCompletion() {
        completion = ""

        // Подсказываем только посреди слова: после пробела или знака человек
        // уже закончил и ждёт перевода, а не продолжения.
        guard let last = input.unicodeScalars.last,
              CharacterSet.letters.contains(last) else { return }

        let nsInput = input as NSString
        var start = nsInput.length
        while start > 0 {
            let scalar = nsInput.character(at: start - 1)
            guard let unicode = Unicode.Scalar(scalar), CharacterSet.letters.contains(unicode) else { break }
            start -= 1
        }
        let range = NSRange(location: start, length: nsInput.length - start)
        // С двух букв вариантов слишком много, и первый почти всегда мимо.
        guard range.length >= 2 else { return }

        let prefix = nsInput.substring(with: range)
        let isCyrillic = prefix.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        let words = NSSpellChecker.shared.completions(
            forPartialWordRange: range,
            in: input,
            language: isCyrillic ? "ru" : "en",
            inSpellDocumentWithTag: 0
        ) ?? []

        // Набранное — уже самое вероятное слово: дописывать к «run» «runs» только мешает.
        if let first = words.first, first.caseInsensitiveCompare(prefix) == .orderedSame { return }

        guard let word = words.first(where: {
            $0.count > prefix.count && $0.lowercased().hasPrefix(prefix.lowercased())
        }) else { return }

        // Хвост берём от слова словаря, а начало оставляем как набрал человек:
        // «Hel» + «lo», а не «hello» поверх заглавной.
        completion = String(word.dropFirst(prefix.count))
    }

    /// Дописать подсказанное слово. - Returns: было ли что дописывать.
    @discardableResult
    func acceptCompletion() -> Bool {
        guard !completion.isEmpty else { return false }
        input += completion
        completion = ""
        return true
    }

    func toggleDirection() {
        direction = direction.reversed
        // Перевод в обратную сторону — уже другая пара языков, старый результат не годится.
        output = ""
        requestTranslation()
    }

    // MARK: - Перевод

    func requestTranslation() {
        debounceTask?.cancel()

        guard !trimmedInput.isEmpty else {
            output = ""
            isTranslating = false
            return
        }

        isTranslating = true
        errorText = nil

        if var existing = configuration,
           existing.source == direction.sourceLanguage,
           existing.target == direction.targetLanguage {
            // Языки те же — просим тот же сеанс отработать ещё раз.
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(
                source: direction.sourceLanguage,
                target: direction.targetLanguage
            )
        }
    }

    /// Вызывается из `.translationTask`, когда система выдала готовый сеанс.
    func perform(with session: TranslationSession) async {
        let text = trimmedInput
        guard !text.isEmpty else {
            isTranslating = false
            return
        }

        do {
            // Языковые пакеты система держит у себя и качает по требованию,
            // поэтому самый первый перевод может занять секунд десять.
            try await session.prepareTranslation()
            let response = try await session.translate(text)
            output = response.targetText
            errorText = nil
            scheduleHistoryRecord(source: text, target: response.targetText)
            // Варианты открыты — пусть следуют за переводом.
            if detailsKey != nil { loadDetails() }
        } catch {
            output = ""
            errorText = "Не удалось перевести: \(error.localizedDescription)"
        }
        isTranslating = false
    }
}

// MARK: - История

extension NotchTranslator {

    /// Перевод считается законченным, если после него пару секунд ничего не меняли.
    private func scheduleHistoryRecord(source: String, target: String) {
        historyTask?.cancel()
        let isRussian = direction == .ruToEn
        historyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.record(HistoryEntry(source: source, target: target, sourceIsRussian: isRussian))
        }
    }

    /// Сразу, без ожидания: человек скопировал перевод — значит, он ему нужен.
    func recordCurrent() {
        historyTask?.cancel()
        let text = trimmedInput
        guard !text.isEmpty, !output.isEmpty, errorText == nil else { return }
        record(HistoryEntry(source: text, target: output, sourceIsRussian: direction == .ruToEn))
    }

    private func record(_ entry: HistoryEntry) {
        // Тот же текст уже был — поднимаем наверх, а не дублируем.
        history.removeAll { $0.source.caseInsensitiveCompare(entry.source) == .orderedSame }

        // Человек вернулся и дописал фразу после паузы — это правка прошлой записи,
        // а не новая. Так же и если стёр хвост.
        if let last = history.first,
           Date().timeIntervalSince(last.date) < 60,
           last.sourceIsRussian == entry.sourceIsRussian,
           entry.source.hasPrefix(last.source) || last.source.hasPrefix(entry.source) {
            history.removeFirst()
        }

        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        saveHistory()
    }

    /// Вернуть запись из истории в поля — с её направлением.
    func restore(_ entry: HistoryEntry) {
        debounceTask?.cancel()
        historyTask?.cancel()
        direction = entry.direction
        input = entry.source
        output = entry.target
        completion = ""
        errorText = nil
        isTranslating = false
    }

    func removeFromHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        history = entries
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Self.historyKey)
    }
}

// MARK: - Варианты и примеры

extension NotchTranslator {

    /// Подтянуть варианты для того, что сейчас в полях. Одну и ту же пару дважды не грузим.
    func loadDetails() {
        let text = trimmedInput
        let translated = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !translated.isEmpty else {
            detailsTask?.cancel()
            detailsKey = ""
            details = .idle
            return
        }

        let isRussian = direction == .ruToEn
        let key = "\(isRussian)|\(text)"
        if key == detailsKey, details != .failed { return }
        detailsKey = key

        detailsTask?.cancel()
        details = .loading
        detailsTask = Task { [weak self] in
            do {
                let result = try await NotchTranslatorDictionary.lookup(
                    text: text,
                    sourceIsRussian: isRussian,
                    englishWord: isRussian ? translated : text
                )
                guard !Task.isCancelled else { return }
                self?.details = .loaded(result)
            } catch {
                guard !Task.isCancelled else { return }
                self?.details = .failed
            }
        }
    }

    /// Варианты закрыли — следить за переводом им больше незачем.
    func stopDetails() {
        detailsTask?.cancel()
        detailsKey = nil
    }
}
