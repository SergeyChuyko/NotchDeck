import SwiftUI

/// Содержимое раскрытой плашки: слева список разделов, справа — выбранный раздел.
/// Сами разделы пока заглушки, живой здесь только переключатель.
struct NotchExpandedView: View {

    @ObservedObject var controller: NotchController
    @ObservedObject var translator: NotchTranslator
    @ObservedObject var clipboard: NotchClipboard
    @ObservedObject var screenshots: NotchScreenshots
    @ObservedObject var media: NotchMedia
    @ObservedObject var battery: NotchBattery
    @ObservedObject var system: NotchSystemControls

    /// Высота физической чёлки: верхнюю полосу плашки она перекрывает,
    /// поэтому контент начинается ниже.
    let topInset: CGFloat
    let expandedSize: CGSize

    @State private var hoveredSection: NotchSection?
    /// Какая из кнопок верхней полосы под курсором.
    @State private var hoveredControl: String?

    var body: some View {
        HStack(spacing: 14) {
            sidebar
                .frame(width: NotchConfig.sidebarWidth, alignment: .topLeading)

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset + NotchConfig.expandedTopPadding)
        .padding(.bottom, NotchConfig.expandedBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) { sectionTitle }
        .overlay(alignment: .topTrailing) { statusBar }
    }

    /// Правый край верхней полосы: переключатели, потом заряд.
    /// Заряд крайний — он про состояние, а не про действие, и в меню-баре стоит так же.
    private var statusBar: some View {
        HStack(spacing: 2) {
            wiFiButton
            bluetoothButton
            settingsButton

            batteryBadge.padding(.leading, 6)
        }
        .padding(.horizontal, 14)
        .frame(height: topInset)
    }

    /// Синий, пока сеть включена, — цвет тут означает «работает», а не выделяет кнопку.
    /// Выключенный Wi-Fi серый и перечёркнутый: два признака сразу, чтобы состояние
    /// читалось и без различения цветов.
    private var wiFiButton: some View {
        stripButton(id: "wifi", help: "Настройки Wi-Fi") {
            system.openWiFiSettings()
        } content: {
            Image(systemName: system.isWiFiOn ? "wifi" : "wifi.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(system.isWiFiOn ? NotchConfig.accentBlue : Color.secondary)
        }
    }

    /// Значок нарисован вручную: в SF Symbols руны Bluetooth нет.
    /// Состояния он не показывает и не переключает — почему, объяснено у кнопки настроек.
    private var bluetoothButton: some View {
        stripButton(id: "bluetooth", help: "Настройки Bluetooth") {
            system.openBluetoothSettings()
        } content: {
            BluetoothGlyph()
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(width: 8, height: 12)
        }
    }

    private var settingsButton: some View {
        stripButton(id: "settings", help: "Системные настройки") {
            system.openSystemSettings()
        } content: {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Жест, а не Button: окно панели никогда не активно, и кнопки в нём ненадёжны.
    private func stripButton<Content: View>(id: String, help: String,
                                            action: @escaping () -> Void,
                                            @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 20, height: 20)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(hoveredControl == id ? 0.12 : 0))
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                hoveredControl = hovering ? id : (hoveredControl == id ? nil : hoveredControl)
            }
            .onTapGesture(perform: action)
            .help(help)
    }

    /// Заряд. Проценты вплотную к значку — 2 pt, чтобы читались как одна надпись,
    /// а не как два отдельных элемента.
    private var batteryBadge: some View {
        Group {
            if let percent = battery.percent {
                HStack(spacing: 2) {
                    Image(systemName: Self.batterySymbol(percent))
                        .font(.system(size: 13))

                    // Молния отдельным значком: у системных батарей она есть только
                    // у полной, и на 43% такой значок врал бы. Заодно зарядка читается
                    // не только цветом.
                    if battery.isOnPower {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                    }

                    Text("\(percent)%")
                        .font(.system(size: 11, weight: .medium))
                        // Без этого ширина скачет на каждой смене цифры.
                        .monospacedDigit()
                }
                .foregroundStyle(batteryColor(percent))
            }
        }
        .allowsHitTesting(false)
    }

    /// Значок ближайшей четверти: границы посередине между ступенями, а не по ним,
    /// иначе на 74% батарея выглядела бы наполовину пустой.
    private static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    /// Цвет означает состояние, а не уровень: проценты и так написаны цифрами, и красить
    /// их вторично незачем. Поэтому обычная работа выглядит спокойно, а цвет появляется,
    /// только когда есть что сказать.
    ///
    /// Порядок проверок и есть смысл шкалы: питание важнее всего, тревога важнее режима,
    /// уровень — в последнюю очередь.
    private func batteryColor(_ percent: Int) -> Color {
        if battery.isOnPower { return .green }
        if percent < 20 { return .red }
        if battery.isLowPowerMode { return .orange }
        if percent < 45 { return warningYellow }
        return .secondary
    }

    /// Системный жёлтый: на чёрном он читается хорошо, а другого фона у плашки не бывает.
    private var warningYellow: Color { .yellow }

    /// Название текущего раздела. Живёт в полосе рядом с чёлкой — она всё равно пустует,
    /// и это единственное место, где заголовок не займёт высоту у содержимого и не
    /// столкнётся с тем, что разделы держат у себя наверху: в буфере там «Очистить»,
    /// в плеере — название трека.
    ///
    /// Список слева теперь из одних значков, так что подписать раздел больше негде.
    private var sectionTitle: some View {
        Text(controller.selectedSection.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: topInset)
            .allowsHitTesting(false)
    }

    // MARK: - Список разделов

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: NotchConfig.sectionRowSpacing) {
            ForEach(NotchSection.allCases) { section in
                row(for: section)
            }
            Spacer(minLength: 0)
        }
    }

    /// Только значок: название раздела уезжает в подсказку по наведению.
    private func row(for section: NotchSection) -> some View {
        let isSelected = controller.selectedSection == section
        let isHovered = hoveredSection == section

        return Image(systemName: section.systemImage)
            .font(.system(size: 14, weight: .semibold))
            // Свой цвет раздела не гаснет от того, что он не выбран, — в этом и смысл.
            .foregroundStyle(section.tint ?? Color.primary.opacity(isSelected ? 1 : 0.6))
            .frame(width: NotchConfig.sidebarWidth, height: NotchConfig.sectionRowHeight)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.14 : (isHovered ? 0.07 : 0)))
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                hoveredSection = hovering ? section : (hoveredSection == section ? nil : hoveredSection)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.16)) {
                    controller.selectedSection = section
                }
            }
            .help(section.title)
            .accessibilityLabel(section.title)
    }

    // MARK: - Содержимое раздела

    private var detail: some View {
        Group {
            switch controller.selectedSection {
            case .translator:
                NotchTranslatorView(translator: translator, controller: controller)
            case .clipboard:
                NotchClipboardView(clipboard: clipboard)
            case .screenshots:
                NotchScreenshotsView(screenshots: screenshots)
            case .player:
                NotchMediaView(media: media, controller: controller)
            case .search:
                NotchSearchView(controller: controller)
            }
        }
        .id(controller.selectedSection)
        .transition(.opacity)
    }
}
