import SwiftUI

/// Форма плашки: снизу обычные скругления, сверху — «обратные» (вогнутые),
/// чтобы плашка не обрывалась углом, а перетекала в верхнюю кромку экрана.
///
/// Верхние скругления рисуются наружу за границы фрейма — так и задумано,
/// поэтому вокруг плашки нужен горизонтальный запас.
struct NotchShape: Shape {

    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.height))
        let bottom = max(0, min(bottomRadius, rect.height, rect.width / 2))

        // Нижние углы отдаём системе: у macOS это не дуга окружности, а суперэллипс,
        // и приблизить его кривой Безье на глаз не получится. UnevenRoundedRectangle
        // рисует ровно то же скругление, каким система скругляет окна и панели.
        let body = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: bottom,
                bottomTrailing: bottom,
                topTrailing: 0
            ),
            style: .continuous
        ).path(in: rect)

        guard top > 0 else { return body }

        return body
            .union(ear(in: rect, radius: top, onLeft: true))
            .union(ear(in: rect, radius: top, onLeft: false))
    }

    /// «Ухо» — вогнутый угол сбоку от плашки. Собираем его вычитанием: берём прямоугольник
    /// у верхней кромки и выедаем из него системное скругление. Так вогнутая кривая
    /// получается той же самой, что и выпуклая внизу, — а нарисовать её вручную нельзя,
    /// у Apple это суперэллипс.
    ///
    /// Занимает по горизонтали не радиус, а полтора: непрерывное скругление тянется
    /// вдоль стороны дальше, чем дуга того же радиуса. Место под это выделено в окне.
    private func ear(in rect: CGRect, radius: CGFloat, onLeft: Bool) -> Path {
        let span = radius * NotchConfig.continuousCornerSpan
        let edge = onLeft ? rect.minX : rect.maxX

        // С заходом в тело на точку, чтобы на стыке не осталось волоска.
        let earRect = CGRect(
            x: onLeft ? edge - span : edge - 1,
            y: rect.minY,
            width: span + 1,
            height: span
        )

        // Выедаемый кусок: его скруглённый угол приходится ровно на верх боковой грани
        // плашки. Берём с запасом, чтобы система не поджала радиус под размер фигуры.
        let biteRect = CGRect(
            x: onLeft ? edge - span * 3 : edge,
            y: rect.minY,
            width: span * 3,
            height: span * 3
        )
        let bite = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: onLeft ? 0 : radius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: onLeft ? radius : 0
            ),
            style: .continuous
        ).path(in: biteRect)

        return Path(earRect).subtracting(bite)
    }
}
