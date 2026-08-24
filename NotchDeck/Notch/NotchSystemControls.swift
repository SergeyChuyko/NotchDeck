import AppKit
import Combine
import CoreWLAN
import SwiftUI

/// Системные переключатели в верхней полосе панели.
///
/// Пока здесь живёт только Wi-Fi: его состояние читается публичным CoreWLAN и не требует
/// ни прав администратора, ни разрешений. Bluetooth так не умеет, см. `NotchExpandedView`.
@MainActor
final class NotchSystemControls: NSObject, ObservableObject {

    @Published private(set) var isWiFiOn = false

    private let client = CWWiFiClient.shared()

    func start() {
        refresh()
        client.delegate = self
        // Wi-Fi выключают и из меню-бара — без подписки значок бы врал.
        try? client.startMonitoringEvent(with: .powerDidChange)
    }

    func stop() {
        try? client.stopMonitoringAllEvents()
        client.delegate = nil
    }

    func refresh() {
        isWiFiOn = client.interface()?.powerOn() ?? false
    }

    /// Раздел Wi-Fi в настройках. Идентификатор у него менялся, поэтому пробуем
    /// современный, затем прежний сетевой, и только потом настройки целиком.
    func openWiFiSettings() {
        let panes = ["x-apple.systempreferences:com.apple.wifi-settings-extension",
                     "x-apple.systempreferences:com.apple.preference.network"]

        for pane in panes {
            if let url = URL(string: pane), NSWorkspace.shared.open(url) { return }
        }
        openSystemSettings()
    }

    // MARK: - Системные настройки

    func openSystemSettings() {
        // Через путь к приложению, а не по ссылке: так надёжнее и не зависит от того,
        // как система назвала разделы в этой версии.
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func openBluetoothSettings() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")
        guard let pane, NSWorkspace.shared.open(pane) else {
            openSystemSettings()
            return
        }
    }
}

extension NotchSystemControls: CWEventDelegate {

    /// Приходит с чужой очереди — возвращаемся на главный актор.
    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.refresh() }
    }
}

/// Руна Bluetooth. Рисуем сами: в SF Symbols такого значка нет — Apple его не поставляет.
/// Один непрерывный штрих, как в оригинальном знаке.
struct BluetoothGlyph: Shape {

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.1, 0.3))
        path.addLine(to: point(0.9, 0.7))
        path.addLine(to: point(0.5, 0.97))
        path.addLine(to: point(0.5, 0.03))
        path.addLine(to: point(0.9, 0.3))
        path.addLine(to: point(0.1, 0.7))
        return path
    }
}
