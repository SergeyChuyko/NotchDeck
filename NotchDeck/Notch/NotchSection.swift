import SwiftUI

/// Разделы меню — в том порядке, в котором они идут в списке слева.
enum NotchSection: String, CaseIterable, Identifiable {

    case player
    case search
    case screenshots
    case clipboard
    case translator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .player: "Плеер"
        case .search: "Поиск"
        case .screenshots: "Скриншоты"
        case .clipboard: "Буфер обмена"
        case .translator: "Переводчик"
        }
    }

    /// Свой цвет есть только у поиска: он ведёт наружу, в браузер, и выделен намеренно.
    /// У остальных разделов цвет берётся от состояния — выбран, под курсором, обычный.
    var tint: Color? {
        self == .search ? NotchConfig.accentBlue : nil
    }

    var systemImage: String {
        switch self {
        case .player: "play.circle"
        case .search: "globe"
        case .screenshots: "camera.viewfinder"
        case .clipboard: "doc.on.clipboard"
        case .translator: "character.bubble"
        }
    }
}
