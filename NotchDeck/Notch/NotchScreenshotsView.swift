import SwiftUI

/// Раздел «Скриншоты»: сетка снимков в четыре столбца, свежие сверху.
/// Клик копирует, из карточки можно тащить файл, правая кнопка открывает или показывает в Finder.
struct NotchScreenshotsView: View {

    @ObservedObject var screenshots: NotchScreenshots

    @State private var hoveredURL: URL?
    @State private var copiedURL: URL?

    private static let timeFormat: Date.FormatStyle = .dateTime.hour().minute()

    /// Сколько снимков в ряду. Ширина карточки считается от места, а не задаётся в точках:
    /// панель зависит от размера экрана, а столбцов всегда должно быть четыре.
    private let columns = 4
    private let spacing: CGFloat = 8
    /// Высота миниатюры как доля ширины. Снимок экрана шире (примерно 1.6), так что
    /// по краям его подрежет, — но в сетке важнее ровные ряды, чем целый кадр.
    private static let thumbnailAspect: CGFloat = 0.72

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if screenshots.accessDenied {
                Text("Нет доступа к папке со снимками. Разрешите его в Системных настройках → Конфиденциальность и безопасность → Файлы и папки.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if screenshots.shots.isEmpty {
                Text("Скриншотов пока не видно. Сделайте снимок — он появится здесь.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                lane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Сетка

    private var lane: some View {
        GeometryReader { geometry in
            let itemWidth = max(44, (geometry.size.width - spacing * CGFloat(columns - 1))
                                    / CGFloat(columns))
            let itemHeight = (itemWidth * NotchScreenshotsView.thumbnailAspect).rounded()

            ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing),
                                   count: columns),
                    alignment: .leading,
                    spacing: spacing
                ) {
                    ForEach(screenshots.shots) { shot in
                        card(for: shot, width: itemWidth, height: itemHeight)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }

    private func card(for shot: NotchScreenshots.Shot, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            // Перетаскивание висит на самой миниатюре, а не на карточке целиком:
            // накрытые им кнопки перестают получать клик — жест утаскивает нажатие
            // себе ещё до того, как палец оторвётся от кнопки.
            thumbnail(for: shot, width: width, height: height)
                .draggable(shot.url)

            HStack(spacing: 3) {
                overlayButton("arrow.up.forward", help: "Открыть снимок") {
                    screenshots.open(shot)
                }
                overlayButton("xmark", help: "Переместить в Корзину") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        screenshots.moveToTrash(shot)
                    }
                }
            }
            .padding(4)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredURL = hovering ? shot.url : (hoveredURL == shot.url ? nil : hoveredURL)
        }
        .onTapGesture {
            copy(shot)
        }
        .contextMenu {
            Button("Показать в Finder") { screenshots.revealInFinder(shot) }
            Button("Открыть") { screenshots.open(shot) }
        }
        .help("\(shot.date.formatted(Self.timeFormat)) — нажмите, чтобы скопировать. Или перетащите прямо отсюда.")
    }

    private func thumbnail(for shot: NotchScreenshots.Shot, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .overlay {
                if let image = screenshots.thumbnails[shot.url] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor(isCopied: copiedURL == shot.url,
                                              isHovered: hoveredURL == shot.url),
                                  lineWidth: 2)
            }
    }

    /// Кнопки лежат поверх снимка, поэтому цвета заданы явно, а не темой: под ними
    /// не фон плашки, а сама картинка, и в тёмной теме они должны выглядеть так же.
    ///
    /// Жест, а не Button: в этой панели обычные кнопки срабатывают не всегда — окно
    /// никогда не бывает активным. Приоритетный, чтобы клик доставался кнопке,
    /// а не копированию, которое висит на карточке целиком.
    private func overlayButton(_ symbol: String, help: String,
                               action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color(white: 0.32))
            .frame(width: 15, height: 15)
            .background {
                Circle()
                    .fill(Color(white: 0.9))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            // Кружок маленький, поэтому область нажатия чуть шире рисунка.
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { action() })
            .help(help)
    }

    private func borderColor(isCopied: Bool, isHovered: Bool) -> Color {
        if isCopied { return .green }
        return Color.primary.opacity(isHovered ? 0.35 : 0.10)
    }

    private func copy(_ shot: NotchScreenshots.Shot) {
        screenshots.copyToPasteboard(shot)

        withAnimation(.easeInOut(duration: 0.06)) { copiedURL = shot.url }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeInOut(duration: 0.16)) {
                if copiedURL == shot.url { copiedURL = nil }
            }
        }
    }
}
