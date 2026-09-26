import Foundation

/// Другие варианты перевода и примеры — то, что у обычных переводчиков лежит под основным
/// результатом.
///
/// Сам перевод остаётся локальным, а это берётся из сети, потому что у системного
/// Translation есть только один вариант и нет примеров вовсе. Запрос уходит, только
/// когда человек сам развернул плашку за вариантами.
///
/// Варианты — из словаря Яндекса: тот же открытый адрес, которым пользуется их сайт.
/// Примеры — из Tatoeba: живые предложения с переводами, под свободной лицензией.
enum NotchTranslatorDictionary {

    struct Details: Equatable {
        var groups: [Group]
        var examples: [Example]

        var isEmpty: Bool { groups.isEmpty && examples.isEmpty }
    }

    /// Одна часть речи: «глагол» и варианты под ним.
    struct Group: Equatable, Identifiable {
        let partOfSpeech: String
        let variants: [Variant]
        var id: String { partOfSpeech + variants.map(\.text).joined() }
    }

    struct Variant: Equatable, Identifiable {
        /// Перевод на целевой язык.
        let text: String
        /// Как этот вариант переводится обратно — чем он отличается от соседних.
        let meanings: [String]
        var id: String { text }
    }

    struct Example: Equatable, Identifiable {
        let english: String
        let russian: String
        var id: String { english }
    }

    /// - Parameters:
    ///   - text: исходный текст — по нему ищем варианты.
    ///   - englishWord: английская сторона пары. Примеры всегда ищем по ней:
    ///     английских предложений в Tatoeba на порядок больше, чем русских.
    static func lookup(text: String, sourceIsRussian: Bool, englishWord: String) async throws -> Details {
        async let groups = variants(for: text, sourceIsRussian: sourceIsRussian)
        async let examples = examples(for: englishWord)
        // Примеры — приятное дополнение: если Tatoeba не ответила, варианты всё равно нужны.
        return Details(groups: try await groups, examples: (try? await examples) ?? [])
    }

    // MARK: - Варианты

    private static func variants(for text: String, sourceIsRussian: Bool) async throws -> [Group] {
        var components = URLComponents(string: "https://dictionary.yandex.net/dicservice.json/lookup")!
        components.queryItems = [
            URLQueryItem(name: "lang", value: sourceIsRussian ? "ru-en" : "en-ru"),
            URLQueryItem(name: "ui", value: "ru"),
            URLQueryItem(name: "text", value: text),
        ]

        let response: YandexResponse = try await fetch(components.url!)
        return response.def.compactMap { entry in
            let variants = entry.tr.prefix(6).map { translation in
                Variant(text: translation.text,
                        meanings: (translation.mean ?? []).prefix(3).map(\.text))
            }
            guard !variants.isEmpty else { return nil }
            return Group(partOfSpeech: entry.pos ?? "", variants: Array(variants))
        }
    }

    private struct YandexResponse: Decodable {
        struct Entry: Decodable {
            let pos: String?
            let tr: [Translation]
        }
        struct Translation: Decodable {
            let text: String
            let mean: [Text]?
        }
        struct Text: Decodable {
            let text: String
        }
        let def: [Entry]
    }

    // MARK: - Примеры

    private static func examples(for englishWord: String) async throws -> [Example] {
        let word = englishWord.trimmingCharacters(in: .whitespacesAndNewlines)
        // Для целой фразы предложений с ней почти никогда нет, а запрос всё равно уйдёт.
        guard !word.isEmpty, word.split(separator: " ").count <= 3 else { return [] }

        var components = URLComponents(string: "https://api.tatoeba.org/unstable/sentences")!
        components.queryItems = [
            URLQueryItem(name: "lang", value: "eng"),
            URLQueryItem(name: "q", value: word),
            URLQueryItem(name: "trans:lang", value: "rus"),
            URLQueryItem(name: "sort", value: "relevance"),
            // Самые релевантные — это «Run.» и «Run!», из них ничего не понять.
            URLQueryItem(name: "word_count", value: "4-14"),
            URLQueryItem(name: "limit", value: "12"),
        ]

        let response: TatoebaResponse = try await fetch(components.url!)
        var seen = Set<String>()
        return response.data.compactMap { sentence -> Example? in
            // Прямой перевод точнее: косвенный сделан через третий язык.
            let translations = sentence.translations.filter { $0.lang == "rus" }
            guard let russian = translations.first(where: { $0.is_direct == true }) ?? translations.first,
                  seen.insert(sentence.text).inserted else { return nil }
            return Example(english: sentence.text, russian: russian.text)
        }
        .prefix(4)
        .map { $0 }
    }

    private struct TatoebaResponse: Decodable {
        struct Sentence: Decodable {
            let text: String
            let translations: [Translation]
        }
        struct Translation: Decodable {
            let text: String
            let lang: String?
            let is_direct: Bool?
        }
        let data: [Sentence]
    }

    // MARK: - Сеть

    private static func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
