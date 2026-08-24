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

    @Published var direction: Direction = .ruToEn
    @Published var input: String = ""
    @Published private(set) var output: String = ""
    @Published private(set) var isTranslating = false
    @Published private(set) var errorText: String?

    /// Меняя её, мы просим `.translationTask` начать новый перевод.
    @Published private(set) var configuration: TranslationSession.Configuration?

    private var debounceTask: Task<Void, Never>?

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Ввод

    /// Переводим не на каждую букву, а когда человек перестал печатать.
    func inputChanged() {
        debounceTask?.cancel()

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
        } catch {
            output = ""
            errorText = "Не удалось перевести: \(error.localizedDescription)"
        }
        isTranslating = false
    }
}
