import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Громкость системного выхода — того устройства, куда сейчас идёт звук: динамики,
/// наушники, AirPods.
///
/// Это не громкость плеера, а общая, та же, что в меню-баре. У MediaRemote своей громкости
/// нет, а у браузерного видео её и подавно не достать. Работает через публичный CoreAudio,
/// разрешений не требует.
@MainActor
final class NotchVolume: ObservableObject {

    /// 0...1.
    @Published private(set) var level: Float = 0
    @Published private(set) var isMuted = false
    /// У некоторых устройств громкость не регулируется вовсе — HDMI-мониторы, часть
    /// внешних карт. Тогда полосу не показываем.
    @Published private(set) var isAvailable = false

    /// Громкость поменяли снаружи — клавишами, в меню-баре. Наши собственные изменения
    /// и переключение устройства сюда не попадают: показывать на чёлке там нечего.
    var onExternalChange: (() -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [AudioObjectPropertyAddress] = []
    private let listener: AudioObjectPropertyListenerBlock

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    init() {
        // Колбэки CoreAudio приходят на очередь, которую мы ему дали, — главную.
        // Поэтому изоляцию можно утверждать, а не перескакивать через Task.
        weak var weakSelf: NotchVolume?
        listener = { _, _ in
            MainActor.assumeIsolated { weakSelf?.reconnect() }
        }
        weakSelf = self
    }

    func start() {
        var address = Self.defaultDeviceAddress
        // Сменилось устройство — например, подключили наушники. Громкость у них своя.
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &address, .main, listener)
        reconnect()
    }

    func stop() {
        var address = Self.defaultDeviceAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, .main, listener)
        detachDevice()
    }

    // MARK: - Управление

    func setLevel(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        level = clamped

        var volume = Float32(clamped)
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        AudioObjectSetPropertyData(device, &address, 0, nil,
                                   UInt32(MemoryLayout<Float32>.size), &volume)

        // Двинули ползунок вверх на беззвучном — значит, хотят слышать.
        if isMuted && clamped > 0 { setMuted(false) }
    }

    func toggleMute() { setMuted(!isMuted) }

    /// Шаг клавишей: как у системы — 1/16 шкалы, с ⇧⌥ мельче, 1/64.
    /// Уровень сначала прижимаем к сетке шагов: иначе после ползунка он остался бы
    /// где-то между делениями и шаги шли бы вразнобой.
    func step(up: Bool, fine: Bool) {
        let step: Float = fine ? 1 / 64 : 1 / 16
        if up && isMuted {
            setMuted(false)
        }
        let current = isMuted ? 0 : level
        let snapped = (current / step).rounded() * step
        setLevel(snapped + (up ? step : -step))
    }

    private func setMuted(_ muted: Bool) {
        var address = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { return }

        isMuted = muted
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: - Устройство

    /// Переподписаться на текущее устройство и перечитать его состояние.
    /// Зовётся и на смену устройства, и на любое изменение громкости — разбирать,
    /// что именно поменялось, дороже, чем просто перечитать два числа.
    private func reconnect() {
        let current = Self.defaultOutputDevice()
        let deviceChanged = current != device
        if deviceChanged {
            detachDevice()
            device = current
            attachDevice()
        }

        let before = (level, isMuted)
        read()
        if !deviceChanged && isAvailable && (level, isMuted) != before {
            onExternalChange?()
        }
    }

    private func attachDevice() {
        guard device != kAudioObjectUnknown else { return }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = Self.address(selector)
            guard AudioObjectHasProperty(device, &address) else { continue }
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
            deviceListeners.append(address)
        }
    }

    private func detachDevice() {
        for var address in deviceListeners {
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
        }
        deviceListeners.removeAll()
    }

    private func read() {
        var volumeAddress = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        guard device != kAudioObjectUnknown,
              AudioObjectHasProperty(device, &volumeAddress),
              AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr,
              settable.boolValue else {
            isAvailable = false
            return
        }

        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr {
            level = volume
        }

        var muteAddress = Self.address(kAudioDevicePropertyMute)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddress),
           AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted) == noErr {
            isMuted = muted != 0
        } else {
            isMuted = false
        }

        isAvailable = true
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = defaultDeviceAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }
}
