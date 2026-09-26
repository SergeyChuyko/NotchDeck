import AppKit

/// Геометрия «чёлки» конкретного экрана.
///
/// macOS отдаёт вырез под камеру не напрямую: `safeAreaInsets.top` даёт его высоту,
/// а `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` — свободные области слева и справа
/// от него. Ширина чёлки = ширина экрана минус эти две области.
struct NotchScreenMetrics: Equatable {

    let screen: NSScreen
    /// Размер выреза под камеру. На мониторах без чёлки — размер-заглушка.
    let notchSize: CGSize
    /// Центр чёлки по горизонтали в глобальных координатах.
    let notchCenterX: CGFloat
    /// Верхняя кромка экрана в глобальных координатах.
    let screenTopY: CGFloat
    /// Есть ли на этом экране настоящая чёлка.
    let hasRealNotch: Bool
    /// Размер раскрытой плашки — доля от экрана, зажатая в разумные пределы.
    let expandedSize: CGSize

    /// Экран с чёлкой, если такой есть, иначе основной.
    static func current() -> NotchScreenMetrics? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            return nil
        }
        return NotchScreenMetrics(screen: screen)
    }

    init(screen: NSScreen) {
        self.screen = screen
        self.screenTopY = screen.frame.maxY

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            self.notchSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            self.notchCenterX = screen.frame.minX + left.width + width / 2
            self.hasRealNotch = true
        } else {
            self.notchSize = NotchConfig.fallbackNotchSize
            self.notchCenterX = screen.frame.midX
            self.hasRealNotch = false
        }

        // Считается после чёлки: её высота входит в высоту плашки.
        let width = min(max(screen.frame.width * NotchConfig.expandedWidthRatio,
                            NotchConfig.expandedWidthRange.lowerBound),
                        NotchConfig.expandedWidthRange.upperBound)
        self.expandedSize = CGSize(
            width: width.rounded(),
            height: NotchConfig.expandedHeight(notchHeight: notchSize.height).rounded()
        )
    }

    /// Раскрытая плашка, вытянутая вниз под варианты перевода или историю.
    func expandedSize(tall: Bool) -> CGSize {
        guard tall else { return expandedSize }
        return CGSize(width: expandedSize.width, height: expandedSize.height + NotchConfig.tallExtraHeight)
    }
}
