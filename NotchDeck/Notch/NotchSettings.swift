import Combine
import Foundation

/// Настройки приложения. Хранятся в UserDefaults — их немного, и переживать перезапуск
/// им нужно, а больше ничего.
@MainActor
final class NotchSettings: ObservableObject {

    private enum Key {
        static let showsPausedPlayer = "showsPausedPlayer"
        static let greetsOnLaunch = "greetsOnLaunch"
        static let sectionOrder = "sectionOrder"
    }

    private let defaults = UserDefaults.standard

    /// Крылья с обложкой и эквалайзером остаются на чёлке и на паузе. Выключено —
    /// крылья живут только пока что-то играет, а на паузе чёлка снова обычная.
    @Published var showsPausedPlayer: Bool {
        didSet { defaults.set(showsPausedPlayer, forKey: Key.showsPausedPlayer) }
    }

    /// «hello» при каждом запуске приложения.
    @Published var greetsOnLaunch: Bool {
        didSet { defaults.set(greetsOnLaunch, forKey: Key.greetsOnLaunch) }
    }

    /// Порядок разделов в списке слева — его меняют перетаскиванием.
    @Published var sectionOrder: [NotchSection] {
        didSet { defaults.set(sectionOrder.map(\.rawValue), forKey: Key.sectionOrder) }
    }

    var isDefaultSectionOrder: Bool { sectionOrder == NotchSection.allCases }

    func resetSectionOrder() { sectionOrder = NotchSection.allCases }

    init() {
        // Сохранённый порядок плюс разделы, которых в нём ещё нет (появились в новой
        // версии), — в конец. Исчезнувшие из приложения просто отбрасываются.
        let saved = (defaults.stringArray(forKey: Key.sectionOrder) ?? [])
            .compactMap(NotchSection.init(rawValue:))
        sectionOrder = saved + NotchSection.allCases.filter { !saved.contains($0) }

        greetsOnLaunch = defaults.object(forKey: Key.greetsOnLaunch) as? Bool ?? true
        // По умолчанию как было до настроек: крылья держатся и на паузе.
        showsPausedPlayer = defaults.object(forKey: Key.showsPausedPlayer) as? Bool ?? true
    }
}
