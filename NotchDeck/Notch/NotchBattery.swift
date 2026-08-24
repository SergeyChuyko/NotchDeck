import Combine
import Foundation
import IOKit.ps

/// Заряд встроенного аккумулятора.
///
/// Систему слушаем, а не опрашиваем таймером: IOKit сам дёргает колбэк, когда заряд
/// или питание меняются. Опрос тут был бы и лишней работой, и врал бы между тиками.
@MainActor
final class NotchBattery: ObservableObject {

    /// Проценты заряда. `nil` — у машины нет встроенного аккумулятора: Mac mini, Studio,
    /// и на них значок показывать нечего.
    @Published private(set) var percent: Int?
    @Published private(set) var isCharging = false
    /// Питание от сети — в том числе когда батарея уже заряжена и ток не идёт.
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Питание от сети или зарядка — для цвета это одно и то же состояние.
    var isOnPower: Bool { isCharging || isPluggedIn }

    private var runLoopSource: CFRunLoopSource?
    private var powerModeObserver: NSObjectProtocol?

    func start() {
        guard runLoopSource == nil else { return }
        refresh()

        // Колбэк — обычная C-функция без замыкания, поэтому себя протаскиваем указателем.
        // Держать себя сильно не нужно: объект живёт столько же, сколько само приложение.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let battery = Unmanaged<NotchBattery>.fromOpaque(context).takeUnretainedValue()
            // Источник добавлен в главный runloop, так что это главный поток.
            MainActor.assumeIsolated { battery.refresh() }
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source

        // Энергосбережение живёт отдельно от источников питания, у него своё уведомление.
        powerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        if let powerModeObserver {
            NotificationCenter.default.removeObserver(powerModeObserver)
            self.powerModeObserver = nil
        }
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        self.runLoopSource = nil
    }

    func refresh() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            percent = nil
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0
            else { continue }

            // Ёмкость система обычно отдаёт уже в процентах, но не обязана — считаем долю.
            percent = min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100)
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return
        }

        percent = nil
    }
}
