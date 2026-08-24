import AppKit
import SwiftUI

/// Раздел «Поиск»: строка запроса, которая уходит в Google в браузере по умолчанию.
struct NotchSearchView: View {

    @ObservedObject var controller: NotchController

    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var tint: Color { NotchSection.search.tint ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Google")
                .font(.system(size: 20, weight: .semibold, design: .rounded))

            field

            Spacer(minLength: 0)
        }
        .onChange(of: isFocused) { _, focused in
            // Пока в строке стоит курсор, уход мыши не должен закрывать панель:
            // человек печатает, а курсор в это время где угодно.
            controller.setInteractionLocked(focused)
        }
        .onDisappear {
            controller.setInteractionLocked(false)
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { search() }
                // Свой placeholder, а не тот, что у TextField: его цвет не настраивается,
                // а нужен заметно бледнее обычного текста.
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        Text("Введите запрос")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.28))
                            .allowsHitTesting(false)
                    }
                }

            magnifier
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tint.opacity(isFocused ? 0.7 : 0), lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Клавиатура достаётся активному приложению, а наше живёт в меню-баре
            // и само на передний план не выходит — для ввода его нужно активировать.
            NSApp.activate()
            isFocused = true
        }
    }

    /// Жест, а не Button: в этой панели обычные кнопки срабатывают не всегда.
    private var magnifier: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(query.isEmpty ? Color.secondary : tint)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onTapGesture { search() }
            .help("Найти в Google")
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // URLComponents сам закодирует пробелы и кириллицу — руками этого делать нельзя.
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: text)]
        guard let url = components?.url else { return }

        // Без указания приложения система откроет ссылку в браузере по умолчанию.
        // Окном или вкладкой — решает сам браузер, у системного API такого параметра нет.
        NSWorkspace.shared.open(url)

        query = ""
        isFocused = false
        controller.setInteractionLocked(false)
        // Запрос ушёл в браузер — держать панель раскрытой поверх него незачем.
        controller.collapse()
    }
}
