import SwiftUI
import Translation

/// Раздел «Переводчик»: две колонки — слева оригинал, справа перевод, между ними обмен.
///
/// Колонки, а не столбик: раздел широкий и низкий, и в столбик правая половина пустовала,
/// а тексту доставалось три строки на двоих. Рядом каждому достаётся вся высота.
struct NotchTranslatorView: View {

    @ObservedObject var translator: NotchTranslator
    @ObservedObject var controller: NotchController

    @FocusState private var isInputFocused: Bool
    @State private var justCopied = false
    @State private var isSwapHovered = false
    @State private var drawer: NotchTranslator.Drawer?
    @State private var hoveredHistoryID: UUID?
    @State private var isStarHovered = false

    /// Один зазор и для шапки, и для колонок — иначе подписи не встают над своими
    /// колонками. Он же шире обычного не просто так: в нём стоит кнопка обмена,
    /// и 34 pt — это её ширина плюс по три с боков.
    private static let columnSpacing: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                header

                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    sourceColumn
                    targetColumn
                }
                // Кнопка обмена живёт в зазоре между колонками, по центру их высоты.
                // В ряду подписей она была бы в трёх точках от правой и в двухстах от левой:
                // подпись прижата к своей колонке, а зазор — почти у самого её края.
                .overlay { swapButton }

                bottomBar
            }
            // Верхняя часть всегда ровно в обычную высоту плашки: вытягивание добавляет
            // место снизу, и кнопки под колонками не уезжают из-под курсора.
            .frame(height: NotchConfig.sectionListHeight)

            if controller.isTall, let drawer {
                drawerContent(drawer)
                    .padding(.top, 10)
                    .frame(height: NotchConfig.tallExtraHeight)
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: controller.isTall) { _, tall in
            // Плашку втянули снаружи — закрытием или сменой раздела.
            if !tall { closeDrawer() }
        }
        .translationTask(translator.configuration) { session in
            await translator.perform(with: session)
        }
        .onChange(of: isInputFocused) { _, focused in
            // Пока человек печатает, курсор наверняка ушёл с плашки —
            // закрывать её по уходу мыши в этот момент нельзя.
            controller.setInteractionLocked(focused)
        }
        .onDisappear {
            controller.setInteractionLocked(false)
            translator.stopDetails()
        }
    }

    // MARK: - Заголовок

    /// Обе подписи прижаты к левому краю своей колонки — так же, как начинается текст
    /// под ними. Раньше правая была зеркальной, по правому краю, и половины выглядели
    /// разными разделами.
    ///
    private var header: some View {
        HStack(spacing: Self.columnSpacing) {
            Text(translator.direction.sourceTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(translator.direction.targetTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
    }

    /// Нажатия здесь и ниже сделаны через onTapGesture, а не Button: окно панели
    /// никогда не бывает активным, и обычная кнопка в нём срабатывает не всегда.
    private var swapButton: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 18)
            .background { Capsule().fill(Color.primary.opacity(isSwapHovered ? 0.18 : 0.10)) }
            .contentShape(Capsule())
            .onHover { isSwapHovered = $0 }
            .onTapGesture {
                translator.toggleDirection()
            }
            .help("Поменять направление перевода")
    }

    // MARK: - Колонки

    private var sourceColumn: some View {
        TextField("", text: $translator.input, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineLimit(1...6)
            .focused($isInputFocused)
            // Свой placeholder: у поля его цвет не настраивается, а нужен бледнее текста.
            .overlay(alignment: .topLeading) {
                if translator.input.isEmpty {
                    Text("Текст для перевода")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.28))
                        .allowsHitTesting(false)
                } else if !translator.completion.isEmpty {
                    completionGhost
                }
            }
            .onKeyPress(.tab) {
                translator.acceptCompletion() ? .handled : .ignored
            }
            .onChange(of: translator.input) { _, _ in
                translator.inputChanged()
            }
            .onSubmit {
                translator.requestTranslation()
            }
            .columnBackground()
            .contentShape(Rectangle())
            .onTapGesture {
                // Клавиатура достаётся активному приложению, а наше живёт в меню-баре
                // и само на передний план не выходит — для ввода его нужно активировать.
                NSApp.activate()
                isInputFocused = true
            }
            // Своя кнопка в том же углу, что и «скопировать» справа: угол колонки —
            // место для действия над её содержимым, и пустовать у одной из них он не должен.
            .overlay(alignment: .bottomTrailing) {
                if !translator.input.isEmpty {
                    clearButton.padding(5)
                }
            }
    }

    /// Подсказка рисуется поверх поля: весь набранный текст прозрачным, чтобы переносы
    /// строк легли так же, как в поле, а за ним — бледный хвост слова.
    private var completionGhost: some View {
        var typed = AttributedString(translator.input)
        typed.foregroundColor = .clear
        var tail = AttributedString(translator.completion)
        tail.foregroundColor = Color.primary.opacity(0.3)

        return Text(typed + tail)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }

    private var clearButton: some View {
        cornerButton(systemName: "xmark", tint: Color.primary.opacity(0.55))
            .onTapGesture {
                translator.input = ""
                translator.inputChanged()
            }
            .help("Очистить")
    }

    private var targetColumn: some View {
        result
            .columnBackground()
            .overlay(alignment: .bottomTrailing) {
                if !translator.output.isEmpty {
                    copyButton.padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if translator.canFavoriteCurrent || translator.isCurrentFavorite {
                    starButton.padding(4)
                }
            }
    }

    /// Звёздочка крупнее угловых кругляшей — в полтора раза, чтобы попадать не целясь.
    /// Контур, пока перевод не сохранён; залитая — когда он в избранном.
    private var starButton: some View {
        let isOn = translator.isCurrentFavorite

        return Image(systemName: isOn ? "star.fill" : "star")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(NotchConfig.favoriteYellow)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isOn)
            .frame(width: 30, height: 30)
            .background { Circle().fill(Color.primary.opacity(isStarHovered ? 0.12 : 0)) }
            .contentShape(Circle())
            .onHover { isStarHovered = $0 }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    translator.toggleFavoriteCurrent()
                }
            }
            .help(isOn ? "Убрать из избранного" : "В избранное")
    }

    // MARK: - Перевод

    @ViewBuilder
    private var result: some View {
        if let errorText = translator.errorText {
            Text(errorText)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if translator.isTranslating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Перевожу…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else if translator.output.isEmpty {
            // Ровно как плейсхолдер ввода: тот же кегль, тот же цвет, тот же угол.
            // По центру он смотрелся подписью к пустому месту, а не парой левому.
            Text("Здесь появится перевод")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.28))
        } else {
            ScrollView {
                Text(translator.output)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    // Справа сверху звёздочка — текст под неё не заезжает.
                    .padding(.trailing, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Место под кнопку копирования, чтобы текст под неё не заезжал.
                    .padding(.bottom, 18)
            }
            .scrollIndicators(.never)
        }
    }

    private var copyButton: some View {
        cornerButton(systemName: justCopied ? "checkmark" : "doc.on.doc",
                     tint: justCopied ? .green : Color.primary.opacity(0.55))
            .onTapGesture(perform: copyResult)
            .help("Скопировать перевод")
    }

    /// Общий вид угловых кнопок обеих колонок — чтобы они не разъехались при следующей правке.
    private func cornerButton(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 20, height: 20)
            .background { Circle().fill(Color.primary.opacity(0.10)) }
            .contentShape(Circle())
    }

    private func copyResult() {
        translator.recordCurrent()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translator.output, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) { justCopied = false }
        }
    }
}

// MARK: - Нижняя полоса и выдвижная часть

private extension NotchTranslatorView {

    /// История слева, варианты справа — под той колонкой, к которой они относятся:
    /// история — про то, что человек вводил, варианты — про перевод.
    var bottomBar: some View {
        HStack(spacing: 0) {
            barButton(.history, title: "История", systemName: "clock.arrow.circlepath")
            barButton(.favorites, title: "Избранное", systemName: "star")
                .padding(.leading, 6)
            Spacer(minLength: 0)
            barButton(.details, title: "Варианты и примеры", systemName: "text.book.closed")
        }
    }

    func barButton(_ kind: NotchTranslator.Drawer, title: String, systemName: String) -> some View {
        let isOpen = controller.isTall && drawer == kind
        // У избранного значок своего цвета — того же, что у звёздочки над переводом,
        // чтобы связь между ними читалась сразу.
        let isFavorites = kind == .favorites

        return NotchDrawerButton(title: title,
                                 systemName: isFavorites && isOpen ? "star.fill" : systemName,
                                 isOpen: isOpen,
                                 iconColor: isFavorites ? NotchConfig.favoriteYellow : nil) {
            toggleDrawer(kind)
        }
    }

    /// Та же кнопка сворачивает; соседняя — переключает содержимое, не втягивая плашку.
    func toggleDrawer(_ kind: NotchTranslator.Drawer) {
        if controller.isTall && drawer == kind {
            controller.setTall(false)
            closeDrawer()
            return
        }

        drawer = kind
        if kind == .details {
            translator.loadDetails()
        } else {
            translator.stopDetails()
        }
        controller.setTall(true)
    }

    func closeDrawer() {
        drawer = nil
        translator.stopDetails()
    }

    @ViewBuilder
    func drawerContent(_ drawer: NotchTranslator.Drawer) -> some View {
        switch drawer {
        case .details: detailsContent
        case .history: historyContent
        case .favorites: favoritesContent
        }
    }

    // MARK: Варианты и примеры

    @ViewBuilder
    var detailsContent: some View {
        switch translator.details {
        case .idle:
            drawerMessage("Введите слово — здесь появятся другие варианты и примеры")
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Ищу варианты…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            drawerMessage("Не удалось загрузить варианты — нужна сеть")
        case .loaded(let details) where details.isEmpty:
            drawerMessage("Других вариантов нет — словарь знает слова и короткие фразы")
        case .loaded(let details):
            // Те же две колонки, что и сверху: варианты под переводом у них общий язык,
            // но слева им было бы тесно рядом с примерами, а справа — пусто.
            HStack(alignment: .top, spacing: Self.columnSpacing) {
                ScrollView {
                    variantsList(details.groups)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ScrollView {
                    examplesList(details.examples)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.never)
        }
    }

    func variantsList(_ groups: [NotchTranslatorDictionary.Group]) -> some View {
        let targetIsEnglish = translator.direction == .ruToEn

        return VStack(alignment: .leading, spacing: 8) {
            drawerSectionTitle("Варианты")
            if groups.isEmpty {
                drawerNote("Нет в словаре")
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    if !group.partOfSpeech.isEmpty {
                        Text(group.partOfSpeech)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                    ForEach(group.variants) { variant in
                        variantRow(variant, targetIsEnglish: targetIsEnglish)
                    }
                }
            }
        }
    }

    /// Вариант и то, как он переводится обратно: по обратному переводу и видно,
    /// чем «бежать» отличается от «удирать».
    func variantRow(_ variant: NotchTranslatorDictionary.Variant, targetIsEnglish: Bool) -> some View {
        var line = AttributedString(variant.text)
        line.foregroundColor = targetIsEnglish ? NotchConfig.englishGreen : Color.primary
        if !variant.meanings.isEmpty {
            var meanings = AttributedString("  " + variant.meanings.joined(separator: ", "))
            meanings.foregroundColor = targetIsEnglish ? Color.secondary : NotchConfig.englishGreen.opacity(0.75)
            line += meanings
        }
        return Text(line)
            .font(.system(size: 12))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    func examplesList(_ examples: [NotchTranslatorDictionary.Example]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            drawerSectionTitle("Примеры")
            if examples.isEmpty {
                drawerNote("Примеров не нашлось")
            }
            ForEach(examples) { example in
                VStack(alignment: .leading, spacing: 1) {
                    Text(example.english)
                        .foregroundStyle(NotchConfig.englishGreen)
                    Text(example.russian)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: История

    @ViewBuilder
    var historyContent: some View {
        if translator.history.isEmpty {
            drawerMessage("История пуста — сюда попадут ваши переводы")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    drawerSectionTitle("Недавние")
                    Spacer()
                    Text("Очистить")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture { translator.clearHistory() }
                }

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(translator.history) { entry in
                            historyRow(entry, englishColor: NotchConfig.englishGreen) {
                                translator.removeFromHistory(entry)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    // MARK: Избранное

    /// Тот же список, что история, только английский — цветом звёздочки:
    /// по цвету сразу видно, в каком из двух списков ты сейчас.
    @ViewBuilder
    var favoritesContent: some View {
        if translator.favorites.isEmpty {
            drawerMessage("Избранное пусто — отметьте перевод звёздочкой")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                drawerSectionTitle("Сохранённые")

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(translator.favorites) { entry in
                            historyRow(entry, englishColor: NotchConfig.favoriteYellow) {
                                translator.removeFromFavorites(entry)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    /// Строка истории разложена по тем же колонкам, что и поля сверху: оригинал под
    /// оригиналом, перевод под переводом. Английский — зелёным, с какой бы стороны он ни был.
    func historyRow(_ entry: NotchTranslator.HistoryEntry, englishColor: Color,
                    remove: @escaping () -> Void) -> some View {
        let isHovered = hoveredHistoryID == entry.id

        return HStack(alignment: .firstTextBaseline, spacing: Self.columnSpacing) {
            Text(entry.source)
                .foregroundStyle(entry.sourceIsRussian ? Color.primary : englishColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.target)
                .foregroundStyle(entry.sourceIsRussian ? englishColor : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .lineLimit(2)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0.04))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredHistoryID = hovering ? entry.id : (hoveredHistoryID == entry.id ? nil : hoveredHistoryID)
        }
        .onTapGesture { translator.restore(entry) }
        .contextMenu {
            Button("Удалить") { remove() }
        }
        .help("Вернуть в переводчик")
    }

    // MARK: Общее

    func drawerSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    func drawerNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.primary.opacity(0.28))
    }

    func drawerMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.primary.opacity(0.35))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {

    /// Обе колонки выглядят одинаково — в этом и смысл переделки: ввод и перевод
    /// половины одного действия, а не элемент управления и подпись к нему.
    func columnBackground() -> some View {
        self
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
    }
}
