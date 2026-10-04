import SwiftUI

/// Раздел «Буфер обмена»: список скопированного, клик возвращает запись в буфер.
///
/// Снизу полоса: поиск слева, очистка справа. Поиск, как варианты в переводчике,
/// вытягивает плашку вниз — список сверху остаётся на месте, найденное идёт под ним.
struct NotchClipboardView: View {

    @ObservedObject var clipboard: NotchClipboard
    @ObservedObject var controller: NotchController

    @State private var hoveredID: UUID?
    @State private var copiedID: UUID?
    @State private var isSearchOpen = false
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private static let timeFormat: Date.FormatStyle = .dateTime.hour().minute()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if clipboard.items.isEmpty {
                    emptyState
                    Spacer(minLength: 0)
                } else {
                    list(clipboard.orderedItems)
                    bottomBar
                }
            }
            // Верхняя часть всегда в обычную высоту плашки — кнопки не уезжают из-под курсора.
            .frame(height: NotchConfig.sectionListHeight, alignment: .top)

            if controller.isTall && isSearchOpen {
                search
                    .padding(.top, 10)
                    .frame(height: NotchConfig.tallExtraHeight, alignment: .top)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: controller.isTall) { _, tall in
            // Плашку втянули снаружи — закрытием или сменой раздела.
            if !tall { closeSearch() }
        }
        .onChange(of: isSearchFocused) { _, focused in
            // Пока человек печатает запрос, курсор наверняка ушёл с плашки.
            controller.setInteractionLocked(focused)
        }
        .onDisappear {
            controller.setInteractionLocked(false)
        }
    }

    // MARK: - Нижняя полоса

    private var bottomBar: some View {
        HStack(spacing: 0) {
            NotchDrawerButton(title: "Поиск", systemName: "magnifyingglass",
                              isOpen: controller.isTall && isSearchOpen) {
                toggleSearch()
            }
            Spacer(minLength: 0)
            clearButton
        }
    }

    private func toggleSearch() {
        if controller.isTall && isSearchOpen {
            controller.setTall(false)
            closeSearch()
            return
        }

        isSearchOpen = true
        controller.setTall(true)
        // Клавиатура достаётся активному приложению — как и у поля переводчика,
        // наше нужно сначала активировать. Фокус ставим, когда поле уже появилось.
        NSApp.activate()
        DispatchQueue.main.async { isSearchFocused = true }
    }

    private func closeSearch() {
        isSearchOpen = false
        isSearchFocused = false
        query = ""
    }

    // MARK: - Поиск

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Без учёта регистра и диакритики: «ёлка» находится по «елка», «Hello» — по «hello».
    private var results: [NotchClipboard.Item] {
        let needle = trimmedQuery
        guard !needle.isEmpty else { return [] }
        return clipboard.orderedItems.filter {
            $0.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 6) {
            searchField

            if trimmedQuery.isEmpty {
                searchMessage("Введите текст — найдём его среди скопированного")
            } else if results.isEmpty {
                searchMessage("Ничего не нашлось")
            } else {
                list(results, highlighting: trimmedQuery)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                // Свой placeholder: у поля его цвет не настраивается, а нужен бледнее текста.
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        Text("Поиск в буфере")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.28))
                            .allowsHitTesting(false)
                    }
                }
                .onKeyPress(.escape) {
                    controller.setTall(false)
                    closeSearch()
                    return .handled
                }

            if !query.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .contentShape(Rectangle())
                    .onTapGesture { query = "" }
                    .help("Очистить запрос")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.activate()
            isSearchFocused = true
        }
    }

    private func searchMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.primary.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Список

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
    }

    private var emptyState: some View {
        Text("Пока пусто. Скопируйте что-нибудь — и записи появятся здесь.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func list(_ items: [NotchClipboard.Item], highlighting needle: String? = nil) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    row(for: item, highlighting: needle)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func row(for item: NotchClipboard.Item, highlighting needle: String? = nil) -> some View {
        let isCopied = copiedID == item.id
        let isHovered = hoveredID == item.id

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted(item.text, needle: needle))
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

    /// Найденное выделено синим приложения и жирным — двумя признаками, чтобы читалось
    /// и без различения цветов. Длинную запись начинаем с совпадения: иначе оно часто
    /// оказывалось за двумя видимыми строками.
    private func highlighted(_ text: String, needle: String?) -> AttributedString {
        guard let needle, !needle.isEmpty else { return AttributedString(text) }

        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var shown = text
        if let first = text.range(of: needle, options: options),
           text.distance(from: text.startIndex, to: first.lowerBound) > 60 {
            let start = text.index(first.lowerBound, offsetBy: -20)
            shown = "…" + text[start...]
        }

        var result = AttributedString(shown)
        var searchStart = shown.startIndex
        while let range = shown.range(of: needle, options: options, range: searchStart..<shown.endIndex) {
            if let attributed = Range(range, in: result) {
                result[attributed].foregroundColor = NotchConfig.accentBlue
                result[attributed].inlinePresentationIntent = .stronglyEmphasized
            }
            searchStart = range.upperBound
        }
        return result
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
