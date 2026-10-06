import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Картинки для README: заставка с анимацией и снимки разделов.
//
// Рисуем, а не снимаем с экрана. Причина та же, по которой существует mock.swift:
// в настоящей панели лежит личное — буфер обмена и снимки экрана, — а картинки уходят
// в публичный репозиторий. Поэтому содержимое образцовое, а вот геометрия и пружины
// берутся прямо из NotchConfig и NotchShape: что там поменяется, то и здесь.

let outputDirectory = URL(fileURLWithPath: "/Users/sergeia.i./NotchDeck/Docs/media")

/// Размеры чёлки MacBook Air M4 13" — те же, по которым нарисован PDF.
let notchSize = CGSize(width: 179, height: 32)
let hintedSize = NotchConfig.hintedSize(for: notchSize, notchSize: notchSize)
let expandedSize = CGSize(width: 609,
                          height: NotchConfig.expandedHeight(notchHeight: notchSize.height))

// MARK: - Панель

/// Раскрытая панель: список разделов слева, содержимое справа, полоса состояния сверху.
/// Повторяет NotchExpandedView — тот же порядок, те же размеры из NotchConfig.
struct Panel<Detail: View>: View {
    let selected: NotchSection
    let size: CGSize
    /// Содержимое проявляется не сразу: в приложении оно появляется по мере раскрытия.
    var contentOpacity: CGFloat = 1
    /// Панель вытянута вниз — список разделов виден целиком. Задаётся явно, а не по
    /// размеру: на раскрытии пружина проскакивает обычную высоту, и по размеру список
    /// на эти кадры показывал бы шестую строку — в заставке он прыгал.
    var tall = false
    /// Радиусы задаются снаружи, чтобы в заставке они ехали вместе с размером.
    var topRadius = NotchConfig.expandedTopRadius
    var bottomRadius = NotchConfig.expandedBottomRadius
    /// Перетаскивание табов — приходит через environment, чтобы не тянуть через Still.
    /// Без него список рисуется обычным столбиком.
    @Environment(\.notchReorder) private var reorder
    @ViewBuilder let detail: Detail

    private var detailHeight: CGFloat {
        size.height - notchSize.height - NotchConfig.expandedTopPadding - NotchConfig.expandedBottomPadding
    }

    var body: some View {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .fill(Color.black)
            .frame(width: size.width, height: size.height)
            .overlay {
                HStack(spacing: 14) {
                    // Прижат к верху: HStack по умолчанию центрирует по высоте, и пока пружина
                    // качала панель, список ездил вверх-вниз вместе с ней.
                    sidebar
                        .frame(width: NotchConfig.sidebarWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                    // Высота задана числом, а не .infinity: раздел со снимками выше
                    // отведённого места, и с гибкой высотой он растягивал бы панель
                    // вместо того, чтобы обрезаться, как в приложении под прокруткой.
                    detail
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(height: detailHeight, alignment: .topLeading)
                        .clipped()
                }
                .padding(.horizontal, 16)
                .padding(.top, notchSize.height + NotchConfig.expandedTopPadding)
                .padding(.bottom, NotchConfig.expandedBottomPadding)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .overlay(alignment: .topLeading) { title }
                .overlay(alignment: .topTrailing) { statusBar }
                .opacity(contentOpacity)
            }
            // Как в приложении: всё, что не влезло в плашку на раскрытии, обрезается
            // её формой. Без этого строки списка торчали из-под неё и мигали.
            .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
            .environment(\.colorScheme, .dark)
    }

    private var title: some View {
        HStack(spacing: 4) {
            Text(selected.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            // У скриншотов рядом с заголовком — синяя папка, как в приложении.
            if selected == .screenshots {
                Image(systemName: "folder.fill").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchConfig.accentBlue).frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: notchSize.height)
    }

    private var statusBar: some View {
        HStack(spacing: 2) {
            Image(systemName: "wifi").font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchConfig.accentBlue).frame(width: 20, height: 20)
            BluetoothGlyph()
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(width: 8, height: 12).frame(width: 20, height: 20)
            Image(systemName: "gearshape").font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 20, height: 20)
            HStack(spacing: 2) {
                Image(systemName: "battery.75percent").font(.system(size: 13))
                Text("64%").font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            .foregroundStyle(.secondary).padding(.leading, 6)
        }
        .padding(.horizontal, 14)
        .frame(height: notchSize.height)
    }

    /// Видно пять строк, настройки шестой — под прокруткой. Когда открыты настройки,
    /// список прокручен вниз; когда панель вытянута, видно всё.
    private var visibleSections: [NotchSection] {
        let all = NotchSection.allCases
        if tall { return Array(all) }
        return selected == .settings ? Array(all.suffix(NotchConfig.visibleSectionRows))
                                     : Array(all.prefix(NotchConfig.visibleSectionRows))
    }

    @ViewBuilder private var sidebar: some View {
        if let reorder {
            let lifted = reorder.lifted, liftScale = reorder.liftScale, rowY = reorder.rowY
            // Поднятый таб рисуется последним — поверх соседей, как zIndex в приложении.
            let order = visibleSections.filter { $0 != lifted } + (lifted.map { [$0] } ?? [])
            ZStack(alignment: .topLeading) {
                ForEach(order) { section in
                    row(section)
                        // Под курсором таб подсвечен, как при наведении в приложении.
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(section == reorder.cursor && section != selected ? 0.1 : 0))
                        }
                        .scaleEffect(section == lifted ? liftScale : 1)
                        .shadow(color: .black.opacity(section == lifted ? 0.5 * Double(liftScale - 1) / 0.12 : 0),
                                radius: 6, y: 2)
                        .offset(y: rowY[section] ?? 0)
                }
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 0.5)
                    .offset(x: NotchConfig.sidebarWidth * 0.55,
                            y: (rowY[reorder.cursor] ?? 0) + NotchConfig.sectionRowHeight * 0.45)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: NotchConfig.sectionRowSpacing) {
                ForEach(visibleSections) { row($0) }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ section: NotchSection) -> some View {
        Image(systemName: section.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(section.tint ?? Color.white.opacity(section == selected ? 1 : 0.6))
            .frame(width: NotchConfig.sidebarWidth, height: NotchConfig.sectionRowHeight)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(section == selected ? 0.14 : 0))
            }
    }
}

@ViewBuilder
func detail(for section: NotchSection) -> some View {
    switch section {
    case .player: MockPlayer()
    case .search: MockSearch()
    case .screenshots: MockShots()
    case .clipboard: MockClipboard()
    case .translator: MockTranslator()
    case .settings: MockSettings()
    }
}

/// Где стоит каждый таб и какой поднят — для анимации перетаскивания.
struct NotchReorder {
    let rowY: [NotchSection: CGFloat]
    let lifted: NotchSection?
    let liftScale: CGFloat
    /// Над каким табом нарисовать курсор — чтобы на GIF было видно, кто его тянет.
    let cursor: NotchSection
}

private struct NotchReorderKey: EnvironmentKey {
    static let defaultValue: NotchReorder? = nil
}

extension EnvironmentValues {
    var notchReorder: NotchReorder? {
        get { self[NotchReorderKey.self] }
        set { self[NotchReorderKey.self] = newValue }
    }
}

// MARK: - Снимки разделов

/// Панель на подложке — на белом фоне README чёрная плашка иначе сливается с краем.
struct Still<Detail: View>: View {
    let section: NotchSection
    var size = expandedSize
    @ViewBuilder let content: Detail
    var body: some View {
        Panel(selected: section, size: size, tall: size.height > expandedSize.height) { content }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(Color(red: 0.10, green: 0.11, blue: 0.13))
    }
}

// MARK: - Заставка

/// Верх экрана с чёлкой: по нему и видно, что плашка растёт из выреза.
struct Hero: View {
    let size: CGSize
    let contentOpacity: CGFloat
    let selected: NotchSection
    let expanded: Bool
    /// Насколько форма уже «раскрытая»: 0 — радиусы чёлки, 1 — радиусы панели.
    var openness: Double = 0

    static let canvas = CGSize(width: 660, height: 268)

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.13, green: 0.14, blue: 0.17)

            menuBar

            Group {
                // Радиусы едут той же пружиной, что и размер, — как NotchShape в приложении.
                let top = lerp(NotchConfig.collapsedTopRadius, NotchConfig.expandedTopRadius, openness)
                let bottom = lerp(NotchConfig.notchBottomRadius, NotchConfig.expandedBottomRadius, openness)
                if expanded {
                    Panel(selected: selected, size: size, contentOpacity: contentOpacity,
                          topRadius: top, bottomRadius: max(bottom, 0)) {
                        detail(for: selected)
                    }
                } else {
                    NotchShape(topRadius: top, bottomRadius: max(bottom, 0))
                        .fill(Color.black)
                        .frame(width: size.width, height: size.height)
                }
            }
            // Плашка висит на верхней кромке — вырез начинается ровно от неё.
            .frame(width: Hero.canvas.width, alignment: .center)
        }
        .frame(width: Hero.canvas.width, height: Hero.canvas.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// Меню-бар нужен только для масштаба: без него непонятно, что это верх экрана.
    private var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: 12))
            Text("Finder").font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            Image(systemName: "wifi").font(.system(size: 11))
            Image(systemName: "battery.75percent").font(.system(size: 13))
            Text("11:24").font(.system(size: 12)).monospacedDigit()
        }
        .foregroundStyle(Color.white.opacity(0.75))
        .padding(.horizontal, 16)
        .frame(height: notchSize.height)
    }
}

/// Верх экрана с меню-баром и чёлкой — фон для анимаций громкости и приветствия.
struct Screen<Notch: View>: View {
    let height: CGFloat
    @ViewBuilder let notch: Notch

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.13, green: 0.14, blue: 0.17)
            HStack(spacing: 14) {
                Image(systemName: "apple.logo").font(.system(size: 12))
                Text("Finder").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "wifi").font(.system(size: 11))
                Image(systemName: "battery.75percent").font(.system(size: 13))
                Text("11:24").font(.system(size: 12)).monospacedDigit()
            }
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 16)
            .frame(height: notchSize.height)
            notch.frame(width: Hero.canvas.width, alignment: .center)
        }
        .frame(width: Hero.canvas.width, height: height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Пружины

/// Та же пружина, что у SwiftUI: response — период, dampingFraction — затухание.
/// Значения берём из NotchConfig, чтобы заставка совпадала с тем, что видит человек.
func spring(_ t: Double, response: Double, damping: Double) -> Double {
    guard t > 0 else { return 0 }
    let w0 = 2 * Double.pi / response
    if damping < 1 {
        let wd = w0 * (1 - damping * damping).squareRoot()
        return 1 - exp(-damping * w0 * t) * (cos(wd * t) + (damping * w0 / wd) * sin(wd * t))
    }
    return 1 - exp(-w0 * t) * (1 + w0 * t)
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

func lerp(_ a: CGSize, _ b: CGSize, _ t: Double) -> CGSize {
    CGSize(width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}

// MARK: - Сборка

MainActor.assumeIsolated {

    @MainActor func png<V: View>(_ view: V, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    @MainActor func write(_ image: CGImage, to name: String) {
        let url = outputDirectory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("· \(name)")
    }

    for section in NotchSection.allCases {
        guard let image = png(Still(section: section) { detail(for: section) }) else { continue }
        write(image, to: "\(section.rawValue).png")
    }

    // Переводчик вытянутый вниз — с вариантами и с историей.
    let tallSize = CGSize(width: expandedSize.width, height: expandedSize.height + NotchConfig.tallExtraHeight)
    for (drawer, name) in [(MockDrawer.details, "translator-details"), (.history, "translator-history"),
                           (.favorites, "translator-favorites")] {
        guard let image = png(Still(section: .translator, size: tallSize) { MockTranslator(drawer: drawer) }) else { continue }
        write(image, to: "\(name).png")
    }

    if let image = png(Still(section: .clipboard, size: tallSize) { MockClipboard(searchOpen: true) }) {
        write(image, to: "clipboard-search.png")
    }

    // Иконка приложения — для шапки README.
    if let icon = NSImage(contentsOfFile: "/Users/sergeia.i./NotchDeck/NotchDeck/Assets.xcassets/AppIcon.appiconset/AppIcon_256.png"),
       let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        write(cg, to: "icon.png")
    }

    @MainActor func gif(_ frames: [CGImage], fps: Double, to name: String) {
        let url = outputDirectory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        for image in frames {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]
            ] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        print("· \(name) — кадров: \(frames.count)")
    }

    // MARK: Громкость на чёлке

    do {
        let fps = 25.0
        let openAt = 0.35
        /// Шаги клавишей: время нажатия и новый уровень. В конце — до нуля, звук выключен.
        let steps: [(Double, CGFloat)] = [(0, 0.44), (0.75, 0.5), (1.0, 0.56), (1.25, 0.62),
                                          (1.95, 0.44), (2.15, 0.25), (2.35, 0.06), (2.55, 0)]
        let mutedAt = openAt + 2.55
        let closeAt = mutedAt + 1.2
        let duration = closeAt + 0.8
        let hudSize = NotchConfig.collapsedSize(notchSize: notchSize, media: false, volumeHUD: true)

        func level(at t: Double) -> CGFloat {
            var value = steps[0].1
            var previous = value
            for (at, target) in steps where t >= openAt + at {
                previous = value
                value = target
                let k = min(1, (t - openAt - at) / 0.12)
                value = previous + (target - previous) * CGFloat(k)
            }
            return value
        }

        var frames: [CGImage] = []
        var time = 0.0
        while time < duration {
            let size: CGSize
            if time < openAt {
                size = notchSize
            } else if time < closeAt {
                size = lerp(notchSize, hudSize, spring(time - openAt, response: 0.42, damping: 0.74))
            } else {
                size = lerp(hudSize, notchSize, spring(time - closeAt, response: 0.34, damping: 1))
            }
            // Тряска значка при выключении: -3, 3, -2.5, 2, 0 за четверть секунды.
            var shake: CGFloat = 0
            let s = time - mutedAt
            if s > 0 && s < 0.26 {
                let keys: [(Double, CGFloat)] = [(0, 0), (0.04, -3), (0.10, 3), (0.16, -2.5), (0.21, 2), (0.26, 0)]
                for i in 1..<keys.count where s <= keys[i].0 {
                    let k = (s - keys[i - 1].0) / (keys[i].0 - keys[i - 1].0)
                    shake = keys[i - 1].1 + (keys[i].1 - keys[i - 1].1) * CGFloat(k)
                    break
                }
            }
            let showsHUD = time >= openAt && (time < closeAt || size.width > notchSize.width + 40)
            let frame = Screen(height: 56) {
                NotchShape(topRadius: NotchConfig.collapsedTopRadius, bottomRadius: NotchConfig.notchBottomRadius)
                    .fill(Color.black)
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .top) {
                        if showsHUD {
                            MockVolumeHUD(level: level(at: time), shake: shake, notchHeight: notchSize.height)
                                .frame(width: size.width).clipped()
                                .opacity(time >= closeAt ? max(0, 1 - (time - closeAt) * 4) : min(1, (time - openAt) * 6))
                        }
                    }
            }
            if let image = png(frame) { frames.append(image) }
            time += 1 / fps
        }
        gif(frames, fps: fps, to: "volume.gif")
    }

    // MARK: Перетаскивание табов

    do {
        let fps = 25.0
        let step = NotchConfig.sectionRowHeight + NotchConfig.sectionRowSpacing
        let base = Array(NotchSection.allCases.prefix(NotchConfig.visibleSectionRows))
        let dragged = NotchSection.translator
        let from = CGFloat(base.firstIndex(of: dragged)!) * step
        let to = 1 * step
        // Раскадровка: зажали → тянем вверх → отпустили → пауза → обратно вниз, чтобы
        // петля GIF сходилась без скачка.
        let pressAt = 0.5, upAt = 0.75, upEnd = 1.9, dropAt = 2.0
        let backPress = 3.0, downAt = 3.25, downEnd = 4.4, backDrop = 4.5, duration = 5.4

        func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
        func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }

        var shown: [NotchSection: CGFloat] = [:]
        for (i, section) in base.enumerated() { shown[section] = CGFloat(i) * step }

        var frames: [CGImage] = []
        var time = 0.0
        while time < duration {
            // Где таб под курсором и насколько он поднят.
            let y: CGFloat
            var lift: Double = 0
            if time < downAt - 0.25 {
                y = lerp(from, to, ease(progress(time, upAt, upEnd)))
                lift = progress(time, pressAt, pressAt + 0.15) - progress(time, dropAt, dropAt + 0.15)
            } else {
                y = lerp(to, from, ease(progress(time, downAt, downEnd)))
                lift = progress(time, backPress, backPress + 0.15) - progress(time, backDrop, backDrop + 0.15)
            }
            let isLifted = lift > 0

            // Новый порядок: тащимый — на ближайшее место, остальные заполняют оставшиеся.
            let slot = min(max(Int((y / step).rounded()), 0), base.count - 1)
            var order = base.filter { $0 != dragged }
            order.insert(dragged, at: slot)

            // Соседи догоняют свои места с затуханием — как пружина в приложении.
            for (i, section) in order.enumerated() where section != dragged {
                let target = CGFloat(i) * step
                shown[section] = (shown[section] ?? target) + (target - (shown[section] ?? target)) * 0.35
            }
            // Поднятый таб — строго под курсором; отпущенный садится на место.
            shown[dragged] = isLifted ? y : (shown[dragged] ?? y) + (CGFloat(slot) * step - (shown[dragged] ?? y)) * 0.45

            let frame = Still(section: .player) {
                MockPlayer()
            }
            .environment(\.notchReorder, NotchReorder(rowY: shown, lifted: isLifted ? dragged : nil,
                                                     liftScale: 1 + 0.12 * CGFloat(lift), cursor: dragged))
            if let image = png(frame) { frames.append(image) }
            time += 1 / fps
        }
        gif(frames, fps: fps, to: "reorder.gif")
    }

    // MARK: Чёлка, пока играет музыка

    do {
        let fps = 25.0
        let duration = 3.2
        let wings = NotchConfig.collapsedSize(notchSize: notchSize, media: true)
        let accent = Color(red: 0.93, green: 0.42, blue: 0.48)
        // Те же числа, что у NotchEqualizerView: столбики «дышат» с разными периодами.
        let low: [CGFloat] = [3, 5, 3, 4], high: [CGFloat] = [11, 8, 13, 9]
        let periods = [0.84, 1.10, 0.72, 0.96], phases = [0, 0.35, 0.7, 1.05]

        var frames: [CGImage] = []
        var time = 0.0
        while time < duration {
            let frame = Screen(height: 56) {
                NotchShape(topRadius: NotchConfig.collapsedTopRadius, bottomRadius: NotchConfig.notchBottomRadius)
                    .fill(Color.black)
                    .frame(width: wings.width, height: wings.height)
                    .overlay(alignment: .top) {
                        HStack(spacing: 0) {
                            let side = NotchConfig.mediaArtworkHeight(notchHeight: notchSize.height)
                            artworkSample(side, side)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Spacer(minLength: 0)
                            HStack(spacing: 2.5) {
                                ForEach(0..<4, id: \.self) { i in
                                    let phase = (time / periods[i] + phases[i]) * 2 * .pi
                                    let k = CGFloat((sin(phase) + 1) / 2)
                                    Capsule().fill(accent).frame(width: 2.5, height: low[i] + (high[i] - low[i]) * k)
                                }
                            }
                            .frame(height: 14)
                        }
                        .padding(.horizontal, NotchConfig.mediaWingPadding)
                        .frame(width: wings.width, height: notchSize.height)
                    }
            }
            if let image = png(frame) { frames.append(image) }
            time += 1 / fps
        }
        gif(frames, fps: fps, to: "now-playing.gif")
    }

    // MARK: Приветствие

    do {
        let fps = 25.0
        let openAt = 0.4
        let writeAt = openAt + 0.25
        let closeAt = writeAt + NotchConfig.greetingWriteDuration + NotchConfig.greetingHoldDuration
        let duration = closeAt + 0.8
        let greeting = NotchConfig.greetingSize(width: notchSize.width, notchHeight: notchSize.height)

        func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }

        var frames: [CGImage] = []
        var time = 0.0
        while time < duration {
            // Радиус низа едет вместе с размером, той же пружиной — как в приложении,
            // где NotchShape анимирует радиусы. Скачком он менялся заметно.
            let size: CGSize
            let radius: CGFloat
            if time < openAt {
                size = notchSize
                radius = NotchConfig.notchBottomRadius
            } else if time < closeAt {
                let t = spring(time - openAt, response: 0.42, damping: 0.74)
                size = lerp(notchSize, greeting, t)
                radius = lerp(NotchConfig.notchBottomRadius, NotchConfig.greetingBottomRadius, t)
            } else {
                let t = spring(time - closeAt, response: 0.34, damping: 1)
                size = lerp(greeting, notchSize, t)
                radius = lerp(NotchConfig.greetingBottomRadius, NotchConfig.notchBottomRadius, t)
            }
            let progress = CGFloat(easeInOut(min(1, max(0, (time - writeAt) / NotchConfig.greetingWriteDuration))))
            let opacity = time >= closeAt ? max(0, 1 - (time - closeAt) * 4) : 1
            let frame = Screen(height: 150) {
                NotchShape(topRadius: NotchConfig.collapsedTopRadius, bottomRadius: max(radius, 0))
                    .fill(Color.black)
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .top) {
                        HelloShape()
                            .trim(from: 0, to: progress)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .padding(.horizontal, 18)
                            .padding(.top, notchSize.height + 8)
                            .padding(.bottom, 14)
                            .frame(width: greeting.width, height: greeting.height)
                            .frame(width: size.width, height: size.height, alignment: .top)
                            .clipped()
                            .opacity(opacity)
                    }
            }
            if let image = png(frame) { frames.append(image) }
            time += 1 / fps
        }
        gif(frames, fps: fps, to: "hello.gif")
    }

    // MARK: Кадры заставки

    let fps = 20.0
    /// Раскадровка: наведение → пауза → раскрытие → показ → закрытие.
    /// Длительности пружин и задержка взяты из NotchConfig.
    let hintAt = 0.45
    let openAt = hintAt + NotchConfig.hintDelay
    let switchAt = openAt + 1.30
    let closeAt = openAt + 2.40
    let duration = closeAt + 1.10

    var frames: [CGImage] = []
    var time = 0.0
    while time < duration {
        let size: CGSize
        var opacity: CGFloat = 0
        var expanded = false
        var openness = 0.0

        if time < hintAt {
            size = notchSize
        } else if time < openAt {
            let t = spring(time - hintAt, response: 0.26, damping: 0.82)
            size = lerp(notchSize, hintedSize, t)
        } else if time < closeAt {
            let t = spring(time - openAt, response: 0.42, damping: 0.74)
            size = lerp(hintedSize, expandedSize, t)
            openness = t
            expanded = true
            // Содержимое догоняет форму, а не появляется вместе с ней.
            opacity = min(1, max(0, (time - openAt - 0.10) / 0.22))
        } else {
            let t = spring(time - closeAt, response: 0.34, damping: 1)
            size = lerp(expandedSize, notchSize, t)
            openness = 1 - t
            expanded = t < 0.92
            opacity = max(0, 1 - CGFloat(t) * 3)
        }

        let selected: NotchSection = time < switchAt ? .player : .screenshots
        let frame = Hero(size: size, contentOpacity: opacity, selected: selected, expanded: expanded,
                         openness: openness)
        if let image = png(frame, scale: 2) { frames.append(image) }
        time += 1 / fps
    }

    let gifURL = outputDirectory.appendingPathComponent("hero.gif")
    if let destination = CGImageDestinationCreateWithURL(
        gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil) {
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        for image in frames {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]
            ] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        print("· hero.gif — кадров: \(frames.count)")
    }
}
