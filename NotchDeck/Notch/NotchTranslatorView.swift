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

    /// Один зазор и для шапки, и для колонок — иначе подписи не встают над своими
    /// колонками. Он же шире обычного не просто так: в нём стоит кнопка обмена,
    /// и 34 pt — это её ширина плюс по три с боков.
    private static let columnSpacing: CGFloat = 34

    var body: some View {
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
                }
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translator.output, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) { justCopied = false }
        }
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
