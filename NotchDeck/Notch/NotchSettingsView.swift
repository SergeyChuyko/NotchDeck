import SwiftUI

/// Раздел «Настройки»: карточки в две колонки. Каждая — название, короткая подсказка
/// и управление справа, по центру карточки. Рамка у каждой, чтобы они не сливались.
struct NotchSettingsView: View {

    @ObservedObject var settings: NotchSettings
    @ObservedObject var volumeKeys: NotchVolumeKeys
    @ObservedObject var controller: NotchController

    @State private var hoveredButton: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Обычная Grid, а не ленивая: карточек немного, а в одном ряду они так
            // получают одну высоту и рамки стоят ровно.
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    card(title: "Плеер на паузе",
                         detail: "Обложка остаётся на чёлке, пока музыка на паузе.") {
                        NotchSwitch(isOn: $settings.showsPausedPlayer)
                    }

                    card(title: "Приветствие", detail: "«hello» из чёлки при каждом запуске.",
                         link: ("Показать", { controller.requestGreeting?() })) {
                        NotchSwitch(isOn: $settings.greetsOnLaunch)
                    }
                }

                GridRow {
                    card(title: "Громкость на чёлке",
                         detail: volumeKeys.isActive
                            ? "Системный индикатор скрыт."
                            : "Нужен «Универсальный доступ».",
                         status: volumeKeys.isActive ? .green : NotchConfig.settingsOrange) {
                        if !volumeKeys.isActive {
                            button(id: "accessibility", title: "Открыть", isEnabled: true) {
                                volumeKeys.openAccessibilitySettings()
                            }
                        }
                    }

                    card(title: "Порядок табов", detail: "Табы слева переставляются перетаскиванием.") {
                        button(id: "resetOrder", title: "Сбросить", isEnabled: !settings.isDefaultSectionOrder) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                settings.resetSectionOrder()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Карточка настройки. `link` — необязательное действие строкой под подсказкой,
    /// `status` — цветная точка у названия.
    private func card<Control: View>(title: String, detail: String,
                                     status: Color? = nil,
                                     link: (String, () -> Void)? = nil,
                                     @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    if let status {
                        Circle().fill(status).frame(width: 6, height: 6)
                    }
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Text(link.0)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchConfig.settingsOrange)
                        .opacity(hoveredButton == "link-" + title ? 0.7 : 1)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredButton = hovering ? "link-" + title : nil
                        }
                        .onTapGesture(perform: link.1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    /// Оранжевая, когда есть что делать; серая и неактивная — когда нечего.
    private func button(id: String, title: String, isEnabled: Bool,
                        action: @escaping () -> Void) -> some View {
        let hovered = hoveredButton == id && isEnabled

        return Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(isEnabled
                               ? NotchConfig.settingsOrange.opacity(hovered ? 0.8 : 1)
                               : Color.primary.opacity(0.1))
            }
            .contentShape(Capsule())
            .onHover { hovering in
                hoveredButton = hovering ? id : (hoveredButton == id ? nil : hoveredButton)
            }
            .onTapGesture { if isEnabled { action() } }
            .animation(.easeOut(duration: 0.15), value: isEnabled)
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
