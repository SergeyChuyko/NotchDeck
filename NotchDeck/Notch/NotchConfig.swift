import SwiftUI

/// Все размеры, радиусы и тайминги плашки собраны здесь — крутить нужно только этот файл.
enum NotchConfig {

    // MARK: - Размеры

    /// Ширина раскрытой плашки считается от размера экрана, а не фиксируется в точках:
    /// на 14" и на внешнем 4K она должна занимать одну и ту же долю.
    static let expandedWidthRatio: CGFloat = 0.414

    /// Пределы на случай совсем узких или огромных экранов.
    static let expandedWidthRange: ClosedRange<CGFloat> = 483...897

    /// А высота, наоборот, задаётся содержимым: под списком разделов не должно оставаться
    /// пустоты. Теперь, когда в списке одни значки, высота строки наша собственная,
    /// и весь список считается точно — новый раздел учтётся сам.
    static var sectionListHeight: CGFloat {
        let count = CGFloat(NotchSection.allCases.count)
        return sectionRowHeight * count + sectionRowSpacing * (count - 1)
    }

    /// Отступы содержимого раскрытой плашки. Живут здесь, а не во вьюхе, потому что
    /// из них же складывается её высота.
    static let expandedTopPadding: CGFloat = 10
    static let expandedBottomPadding: CGFloat = 14

    /// - Parameter notchHeight: верхнюю полосу плашки перекрывает физическая чёлка,
    ///   поэтому содержимое начинается под ней, и её высота входит в общую.
    static func expandedHeight(notchHeight: CGFloat) -> CGFloat {
        notchHeight + expandedTopPadding + sectionListHeight + expandedBottomPadding
    }

    /// Насколько плашка вытягивается вниз, когда в переводчике открыты варианты или история.
    /// Растёт только высота: ширина — доля экрана, и прыгать ей незачем.
    static let tallExtraHeight: CGFloat = 200

    /// Вытягивание и обратно — без отскока: плашка уже раскрыта, пружинить тут нечему.
    static let tallAnimation = Animation.spring(response: 0.34, dampingFraction: 0.9)

    /// Список разделов — узкая полоса значков без подписей, поэтому ширина фиксированная,
    /// а не доля плашки: значку шире не нужно, а содержимому справа место пригодится.
    static let sidebarWidth: CGFloat = 34
    static let sectionRowHeight: CGFloat = 30
    static let sectionRowSpacing: CGFloat = 4

    /// Насколько зона наведения выступает за края свёрнутой плашки.
    /// Небольшой запас снизу нужен, чтобы курсор ловился ещё на подлёте к чёлке.
    static let hoverSlop = CGSize(width: 8, height: 6)

    /// Насколько чёлка подрастает под курсором до того, как плашка раскроется.
    /// Долями от собственного размера, а не в точках: чёлка у разных Mac разной ширины,
    /// и одна и та же прибавка выглядела бы на них по-разному.
    static let hintGrowth = CGSize(width: 0.25, height: 0.15)

    /// - Parameter notchSize: прибавку считаем от самой чёлки, а не от переданного размера.
    ///   Иначе, когда чёлка расширена под играющий трек, наведение раздувало бы её вдвое
    ///   сильнее обычного.
    static func hintedSize(for size: CGSize, notchSize: CGSize) -> CGSize {
        CGSize(width: (size.width + notchSize.width * hintGrowth.width).rounded(),
               height: (size.height + notchSize.height * hintGrowth.height).rounded())
    }

    /// Пока жива сессия плеера, чёлка расширяется в стороны: слева обложка, справа
    /// эквалайзер. Высота не меняется — вверх расти некуда, а вниз это была бы уже
    /// другая плашка.
    static let mediaWingPadding: CGFloat = 9
    static let mediaArtworkInset: CGFloat = 6
    /// Обложка альбома квадратная, а превью видео широкое. Шире этого не растягиваем.
    static let mediaArtworkMaxAspect: CGFloat = 2

    static func mediaArtworkHeight(notchHeight: CGFloat) -> CGFloat {
        notchHeight - mediaArtworkInset * 2
    }

    /// Крыло рассчитано на самую широкую обложку, а не на текущую: иначе чёлка меняла бы
    /// ширину на каждой смене трека — с квадратной обложки на превью видео и обратно.
    /// Под квадратной просто останется воздух.
    static func mediaWingWidth(notchHeight: CGFloat) -> CGFloat {
        mediaWingPadding + mediaArtworkHeight(notchHeight: notchHeight) * mediaArtworkMaxAspect + 5
    }

    static func collapsedSize(notchSize: CGSize, media: Bool) -> CGSize {
        guard media else { return notchSize }
        let wing = mediaWingWidth(notchHeight: notchSize.height)
        return CGSize(width: notchSize.width + wing * 2, height: notchSize.height)
    }

    /// Непрерывное скругление тянется вдоль стороны дальше своего радиуса — замерено
    /// по системному пути, ровно 1.529. Столько места нужно «уху» снаружи плашки.
    static let continuousCornerSpan: CGFloat = 1.53

    static func cornerSpan(for radius: CGFloat) -> CGFloat {
        (radius * continuousCornerSpan).rounded(.up)
    }

    /// Запас внутри окна вокруг раскрытой плашки — под «обратные» скругления и тень.
    static let windowSidePadding: CGFloat = 60
    static let windowBottomPadding: CGFloat = 60

    /// Размер-заглушка для мониторов без физической чёлки.
    static let fallbackNotchSize = CGSize(width: 220, height: 32)

    // MARK: - Форма

    /// Низ свёрнутых состояний повторяет физический вырез макбука: плашка притворяется
    /// продолжением чёлки, и своей формы у неё тут быть не должно. Значение подобрано
    /// на глаз — радиус выреза в железе, программно его не спросить.
    static let notchBottomRadius: CGFloat = 10

    /// У раскрытой низ свой: она уже не притворяется чёлкой, и при высоте 188
    /// десять точек смотрелись бы почти прямым углом.
    static let expandedBottomRadius: CGFloat = 16

    /// А «уши» разные, и это единственное отличие, которое работает: при ширине раскрытой
    /// плашки в 609 переход в кромку экрана на восьми точках теряется, ему нужно больше.
    static let collapsedTopRadius: CGFloat = 8
    static let expandedTopRadius: CGFloat = 12

    // MARK: - Анимация

    /// Пружина в духе Dynamic Island: раскрывается чуть упруго, закрывается собраннее.
    ///
    /// У закрытия отскока нет вовсе, и это не вкусовщина. Упругая пружина проскакивает
    /// цель: на закрытии плашка ныряла на 5 pt ниже чёлки и на треть секунды становилась
    /// ниже выреза. Пока она была ровно шириной с чёлку, этого не было видно — вырез всё
    /// закрывал собой. С крыльями под играющий трек провал вылезает по бокам.
    static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.74)
    static let closeAnimation = Animation.spring(response: 0.34, dampingFraction: 1)

    /// Подрастание короткое и почти без отскока — оно не должно спорить с раскрытием,
    /// которое начнётся следом.
    static let hintAnimation = Animation.spring(response: 0.26, dampingFraction: 0.82)

    /// Сколько курсор должен пролежать на чёлке, прежде чем плашка раскроется.
    static let hintDelay: TimeInterval = 0.5

    /// Небольшая задержка перед закрытием, когда курсор ушёл с плашки.
    /// Гасит дребезг: при смене размера окна SwiftUI успевает прислать ложный «мышь ушла».
    static let hoverCloseDelay: TimeInterval = 0.15

    /// Сколько не реагировать на наведение после закрытия кликом.
    /// Без этого плашка мгновенно откроется обратно, если курсор остался на чёлке.
    static let reopenCooldown: TimeInterval = 0.6

    // MARK: - Цвет

    /// Синий приложения: им подсвечен раздел поиска и значок Wi-Fi. Один на всё,
    /// чтобы акцент читался как один и тот же, а не как два похожих.
    static let accentBlue = Color(red: 0.36, green: 0.62, blue: 1)

    /// Английский текст в истории и словаре переводчика. Сочный, но приглушённый:
    /// им набраны целые строки, и системный .green на чёрном в таком количестве
    /// резал бы глаз.
    static let englishGreen = Color(red: 0.42, green: 0.74, blue: 0.40)
}
