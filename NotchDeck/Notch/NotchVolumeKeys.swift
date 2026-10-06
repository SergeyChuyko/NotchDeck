import AppKit
import ApplicationServices
import Combine

/// Перехватывает клавиши громкости, чтобы вместо системного индикатора громкость
/// показывалась только на чёлке.
///
/// Системный индикатор рисует сама macOS, когда до неё доходит нажатие. Спрятать его
/// иначе нельзя — поэтому нажатие до неё не доходит: мы ловим его раньше (event tap),
/// глотаем и меняем громкость сами. Для этого macOS требует разрешение
/// «Универсальный доступ». Без него ничего не ломается: клавиши работают как обычно,
/// просто системный индикатор остаётся.
@MainActor
final class NotchVolumeKeys: ObservableObject {

    enum Key {
        case up, down, mute
    }

    /// Разрешение «Универсальный доступ» выдано и перехват работает.
    @Published private(set) var isActive = false

    /// Нажали клавишу громкости. `fine` — с зажатыми ⇧⌥, мелкий шаг, как в системе.
    var onKey: ((Key, _ fine: Bool) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var permissionTimer: Timer?

    // Коды из IOKit/hidsystem/ev_keymap.h — публично в Swift их нет.
    private static let soundUp = 0
    private static let soundDown = 1
    private static let mute = 7
    /// Подтип NSSystemDefined, в котором приходят мультимедийные клавиши.
    private static let auxControlButtons: Int16 = 8

    func start() {
        // Спрашиваем разрешение один раз за запуск — macOS сама покажет окно
        // со ссылкой в настройки. Дальше ждём, пока его выдадут.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            installTap()
        } else {
            waitForPermission()
        }
    }

    /// Открыть нужный раздел настроек — для кнопки в разделе «Настройки».
    func openAccessibilitySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    /// Разрешение выдают в настройках, пока мы работаем, — уведомления об этом нет,
    /// поэтому изредка проверяем сами.
    private func waitForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.permissionTimer = nil
                self?.installTap()
            }
        }
    }

    private func installTap() {
        guard tap == nil else { return }

        let mask = CGEventMask(1 << 14) // NSSystemDefined
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let keys = Unmanaged<NotchVolumeKeys>.fromOpaque(userInfo).takeUnretainedValue()
            // Колбэк приходит на главный цикл — туда, куда мы поставили источник.
            return MainActor.assumeIsolated { keys.handle(type: type, event: event) }
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            // Разрешение отозвали между проверкой и созданием — ждём заново.
            waitForPermission()
            return
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        isActive = true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Система выключает перехват, если мы задержались с ответом, — включаем обратно.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlButtons else {
            return Unmanaged.passUnretained(event)
        }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let isDown = ((data & 0xFF00) >> 8) == 0xA

        let key: Key
        switch keyCode {
        case Self.soundUp: key = .up
        case Self.soundDown: key = .down
        case Self.mute: key = .mute
        default: return Unmanaged.passUnretained(event)
        }

        // Глотаем и нажатие, и отпускание: отпущенная клавиша, дошедшая до системы,
        // тоже показала бы её индикатор.
        if isDown {
            let fine = nsEvent.modifierFlags.contains([.shift, .option])
            onKey?(key, fine)
        }
        return nil
    }
}
