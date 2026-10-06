import SwiftUI

/// Раздел «Настройки»: вертикальный список переключателей.
struct NotchSettingsView: View {

    @ObservedObject var settings: NotchSettings
    @ObservedObject var volumeKeys: NotchVolumeKeys
    @ObservedObject var controller: NotchController

    @State private var hoveredButton: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                row(title: "Плеер на паузе",
                    detail: "Обложка и эквалайзер остаются на чёлке, когда музыка на паузе. "
                        + "Выключите — и на паузе чёлка станет обычной.",
                    isOn: $settings.showsPausedPlayer)

                row(title: "Приветствие при запуске",
                    detail: "При каждом запуске из чёлки спускается «hello».",
                    isOn: $settings.greetsOnLaunch)

                volumeKeysRow

                button(id: "greet", title: "Показать приветствие") { controller.requestGreeting?() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NotchSwitch(isOn: isOn)
        }
    }

    /// Громкость только на чёлке: работает, когда выдан «Универсальный доступ».
    /// Без него — подсказка и кнопка в нужный раздел настроек.
    private var volumeKeysRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Громкость на чёлке")
                    .font(.system(size: 13, weight: .medium))
                Circle()
                    .fill(volumeKeys.isActive ? Color.green : NotchConfig.settingsOrange)
                    .frame(width: 6, height: 6)
            }
            Text(volumeKeys.isActive
                 ? "Системный индикатор громкости скрыт — громкость видна только на чёлке."
                 : "Чтобы скрыть системный индикатор громкости, разрешите NotchDeck "
                    + "«Универсальный доступ» в настройках.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !volumeKeys.isActive {
                button(id: "accessibility", title: "Открыть настройки") {
                    volumeKeys.openAccessibilitySettings()
                }
            }
        }
    }

    private func button(id: String, title: String, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(Color.primary.opacity(hoveredButton == id ? 0.16 : 0.09))
            }
            .contentShape(Capsule())
            .onHover { hovering in
                hoveredButton = hovering ? id : (hoveredButton == id ? nil : hoveredButton)
            }
            .onTapGesture(perform: action)
    }
}

/// Переключатель. Свой, а не системный Toggle: окно панели никогда не активно,
/// и готовые элементы управления в нём ведут себя ненадёжно.
struct NotchSwitch: View {

    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? NotchConfig.settingsOrange : Color.primary.opacity(0.2))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() }
            }
    }
}
