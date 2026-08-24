import SwiftUI

// MARK: - Общие детали страницы

let ink = Color(white: 0.12)
let dim = Color(white: 0.42)
let panelBlack = Color.black

/// Текст документа — Helvetica Neue, а не системный шрифт. Дело не во вкусе: системный
/// вариативный SF при печати в PDF отдаёт кириллическую «к» как «ĸ», и поиск по документу
/// ломается. Проверено. Мокапы приложения при этом остаются на системном — там важно,
/// чтобы скриншоты выглядели как настоящие.
func docFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    switch weight {
    case .bold: .custom("HelveticaNeue-Bold", size: size)
    case .semibold, .medium: .custom("HelveticaNeue-Medium", size: size)
    default: .custom("HelveticaNeue", size: size)
    }
}

func heading(_ text: String) -> some View {
    Text(text).font(docFont(17, .bold)).foregroundStyle(ink)
}

func sub(_ text: String) -> some View {
    Text(text).font(docFont(11)).foregroundStyle(dim).fixedSize(horizontal: false, vertical: true)
}

func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
        Text("·").font(docFont(11, .bold)).foregroundStyle(dim)
        Text(try! AttributedString(markdown: text)).font(docFont(11)).foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Снимок раздела: чёрная плашка нужного размера с содержимым внутри.
func shot<C: View>(width: CGFloat = 514, height: CGFloat = 166, @ViewBuilder _ content: () -> C) -> some View {
    content()
        .frame(width: width, height: height)
        .padding(12)
        .background(panelBlack)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.colorScheme, .dark)
}

let sampleFill = Color.white.opacity(0.08)

func sampleBlock<C: View>(fills: Bool = false, @ViewBuilder _ c: () -> C) -> some View {
    c().padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
        .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(sampleFill) }
}

func artworkSample(_ w: CGFloat, _ h: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(LinearGradient(colors: [Color(red: 0.9, green: 0.4, blue: 0.35), Color(red: 0.35, green: 0.35, blue: 0.75)],
                             startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: w, height: h)
}
