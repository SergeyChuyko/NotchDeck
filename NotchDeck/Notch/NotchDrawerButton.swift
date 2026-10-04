import SwiftUI

/// Кнопка-капсула в полосе под содержимым раздела: открывает нижний блок вытянутой плашки.
/// Общая для всех разделов с таким блоком — чтобы у переводчика и буфера она выглядела
/// одинаково и не разъехалась при следующей правке.
struct NotchDrawerButton: View {

    let title: String
    let systemName: String
    let isOpen: Bool
    /// Свой цвет значка, если он что-то значит, — как звёздочка у избранного.
    var iconColor: Color?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor ?? (isOpen ? Color.primary : Color.secondary))
            Text(title)
                .font(.system(size: 11, weight: .medium))
            // Шеврон говорит, куда поедет плашка: вниз — раскроется, вверх — свернётся.
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .opacity(0.7)
        }
        .foregroundStyle(isOpen ? Color.primary : Color.secondary)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background {
            Capsule().fill(Color.primary.opacity(isOpen ? 0.16 : (isHovered ? 0.12 : 0.07)))
        }
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        // Жест, а не Button: окно панели никогда не активно, и кнопки в нём ненадёжны.
        .onTapGesture(perform: action)
    }
}
