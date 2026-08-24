import SwiftUI

/// Раздел «Буфер обмена»: список скопированного, клик возвращает запись в буфер.
struct NotchClipboardView: View {

    @ObservedObject var clipboard: NotchClipboard

    @State private var hoveredID: UUID?
    @State private var copiedID: UUID?

    private static let timeFormat: Date.FormatStyle = .dateTime.hour().minute()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if clipboard.items.isEmpty {
                emptyState
            } else {
                list
                clearButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Под списком, а не над ним: наверху кнопка попадалась под руку при беглом просмотре,
    /// а очистка — действие редкое.
    private var clearButton: some View {
        Text("Очистить")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background { Capsule().fill(Color.primary.opacity(0.10)) }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { clipboard.clear() }
            }
            .help("Убрать всё, кроме закреплённого")
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var emptyState: some View {
        Text("Пока пусто. Скопируйте что-нибудь — и записи появятся здесь.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(clipboard.orderedItems) { item in
                    row(for: item)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func row(for item: NotchClipboard.Item) -> some View {
        let isCopied = copiedID == item.id
        let isHovered = hoveredID == item.id

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.date, format: Self.timeFormat)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            pinButton(for: item, isHovered: isHovered)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background(isCopied: isCopied, isHovered: isHovered))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .onTapGesture {
            copy(item)
        }
        .help("Нажмите, чтобы вернуть в буфер обмена")
    }

    /// Закреплённая запись показывает булавку всегда, обычная — только под курсором.
    @ViewBuilder
    private func pinButton(for item: NotchClipboard.Item, isHovered: Bool) -> some View {
        if item.isPinned || isHovered {
            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.isPinned ? Color.accentColor : Color.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        clipboard.togglePin(item)
                    }
                }
                .help(item.isPinned ? "Открепить" : "Закрепить наверху")
        }
    }

    /// Свежескопированная запись на мгновение зеленеет и возвращается к обычному фону.
    private func background(isCopied: Bool, isHovered: Bool) -> Color {
        if isCopied { return Color.green.opacity(0.30) }
        return Color.primary.opacity(isHovered ? 0.10 : 0.05)
    }

    private func copy(_ item: NotchClipboard.Item) {
        clipboard.copyToPasteboard(item)

        withAnimation(.easeInOut(duration: 0.06)) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeInOut(duration: 0.16)) {
                if copiedID == item.id { copiedID = nil }
            }
        }
    }
}
