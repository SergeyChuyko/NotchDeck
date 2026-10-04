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
    @ViewBuilder let detail: Detail

    private var detailHeight: CGFloat {
        size.height - notchSize.height - NotchConfig.expandedTopPadding - NotchConfig.expandedBottomPadding
    }

    var body: some View {
        NotchShape(topRadius: NotchConfig.expandedTopRadius,
                   bottomRadius: NotchConfig.expandedBottomRadius)
            .fill(Color.black)
            .frame(width: size.width, height: size.height)
            .overlay {
                HStack(spacing: 14) {
                    sidebar
                        .frame(width: NotchConfig.sidebarWidth, alignment: .topLeading)
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
            .environment(\.colorScheme, .dark)
    }

    private var title: some View {
        Text(selected.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: NotchConfig.sectionRowSpacing) {
            ForEach(NotchSection.allCases) { section in
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(section.tint ?? Color.white.opacity(section == selected ? 1 : 0.6))
                    .frame(width: NotchConfig.sidebarWidth, height: NotchConfig.sectionRowHeight)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(section == selected ? 0.14 : 0))
                    }
            }
            Spacer(minLength: 0)
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
    }
}

// MARK: - Снимки разделов

/// Панель на подложке — на белом фоне README чёрная плашка иначе сливается с краем.
struct Still<Detail: View>: View {
    let section: NotchSection
    var size = expandedSize
    @ViewBuilder let content: Detail
    var body: some View {
        Panel(selected: section, size: size) { content }
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

    static let canvas = CGSize(width: 660, height: 268)

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.13, green: 0.14, blue: 0.17)

            menuBar

            Group {
                if expanded {
                    Panel(selected: selected, size: size, contentOpacity: contentOpacity) {
                        detail(for: selected)
                    }
                } else {
                    NotchShape(topRadius: NotchConfig.collapsedTopRadius,
                               bottomRadius: NotchConfig.notchBottomRadius)
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

        if time < hintAt {
            size = notchSize
        } else if time < openAt {
            let t = spring(time - hintAt, response: 0.26, damping: 0.82)
            size = lerp(notchSize, hintedSize, t)
        } else if time < closeAt {
            let t = spring(time - openAt, response: 0.42, damping: 0.74)
            size = lerp(hintedSize, expandedSize, t)
            expanded = true
            // Содержимое догоняет форму, а не появляется вместе с ней.
            opacity = min(1, max(0, (time - openAt - 0.10) / 0.22))
        } else {
            let t = spring(time - closeAt, response: 0.34, damping: 1)
            size = lerp(expandedSize, notchSize, t)
            expanded = t < 0.92
            opacity = max(0, 1 - CGFloat(t) * 3)
        }

        let selected: NotchSection = time < switchAt ? .player : .screenshots
        let frame = Hero(size: size, contentOpacity: opacity, selected: selected, expanded: expanded)
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
