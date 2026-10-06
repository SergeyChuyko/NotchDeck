import Combine
import Foundation

/// Настройки приложения. Хранятся в UserDefaults — их немного, и переживать перезапуск
/// им нужно, а больше ничего.
@MainActor
final class NotchSettings: ObservableObject {

    private enum Key {
        static let showsPausedPlayer = "showsPausedPlayer"
        static let greetsOnLaunch = "greetsOnLaunch"
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

    init() {
        greetsOnLaunch = defaults.object(forKey: Key.greetsOnLaunch) as? Bool ?? true
        // По умолчанию как было до настроек: крылья держатся и на паузе.
        showsPausedPlayer = defaults.object(forKey: Key.showsPausedPlayer) as? Bool ?? true
    }
}
