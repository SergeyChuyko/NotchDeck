import SwiftUI

/// Корневая вьюха панели: сама плашка сверху по центру, всё остальное — прозрачный воздух,
/// который не должен ловить мышь.
struct NotchRootView: View {

    @ObservedObject var controller: NotchController
    @ObservedObject var translator: NotchTranslator
    @ObservedObject var clipboard: NotchClipboard
    @ObservedObject var screenshots: NotchScreenshots
    @ObservedObject var media: NotchMedia
    @ObservedObject var battery: NotchBattery
    @ObservedObject var system: NotchSystemControls
    let notchSize: CGSize
    let expandedSize: CGSize

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .allowsHitTesting(false)

            notchPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - Плашка

    private var notchPanel: some View {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .fill(fillColor)
            .overlay(alignment: .top) { nowPlayingWings }
            .overlay(alignment: .top) { expandedContent }
            .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
            .frame(width: panelSize.width, height: panelSize.height)
            // Ключ — именно наличие сессии, а не showsNowPlaying: тот меняется ещё и при
            // раскрытии, и тогда этот модификатор перебивал бы анимацию закрытия своей.
            .animation(NotchConfig.openAnimation, value: media.track != nil)
            .shadow(color: .black.opacity(controller.isExpanded ? 0.35 : 0), radius: 22, y: 10)
            // Запас вокруг плашки — чтобы курсор ловился чуть раньше, чем дойдёт до края.
            .padding(.horizontal, NotchConfig.hoverSlop.width)
            .padding(.bottom, NotchConfig.hoverSlop.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                controller.hoverChanged(hovering)
            }
    }

    /// Обложка и эквалайзер по краям расширенной чёлки. Из иерархии их убираем совсем,
    /// а не прячем прозрачностью: у эквалайзера бесконечная анимация, и на невидимой
    /// вьюхе она продолжала бы крутиться.
    @ViewBuilder
    private var nowPlayingWings: some View {
        if showsNowPlaying {
            NotchNowPlayingView(media: media, notchHeight: notchSize.height)
                .frame(width: panelSize.width)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    /// Пока жива сессия плеера — не только пока он играет. На паузе крылья остаются,
    /// иначе чёлка дёргалась бы туда-сюда на каждое нажатие пробела; замирает эквалайзер.
    ///
    /// Только в свёрнутом виде: у раскрытой плашки для плеера есть целый раздел.
    private var showsNowPlaying: Bool {
        media.track != nil && !controller.isExpanded
    }

    private var expandedContent: some View {
        NotchExpandedView(
            controller: controller,
            translator: translator,
            clipboard: clipboard,
            screenshots: screenshots,
            media: media,
            battery: battery,
            system: system,
            topInset: notchSize.height,
            expandedSize: expandedSize
        )
        .frame(width: expandedSize.width, height: expandedSize.height)
        .opacity(controller.isExpanded ? 1 : 0)
        .scaleEffect(controller.isExpanded ? 1 : 0.92, anchor: .top)
        .blur(radius: controller.isExpanded ? 0 : 6)
        // Пока плашка свёрнута, разделы не должны ловить мышь: они хоть и невидимы,
        // но лежат ровно там же и перехватывали бы клики по чёлке.
        .allowsHitTesting(controller.isExpanded)
    }

    // MARK: - Оформление

    private var panelSize: CGSize {
        if controller.isExpanded { return expandedSize }

        let collapsed = NotchConfig.collapsedSize(notchSize: notchSize, media: media.track != nil)
        return controller.isHinted
            ? NotchConfig.hintedSize(for: collapsed, notchSize: notchSize)
            : collapsed
    }

    private var bottomRadius: CGFloat {
        controller.isExpanded ? NotchConfig.expandedBottomRadius : NotchConfig.notchBottomRadius
    }

    private var topRadius: CGFloat {
        controller.isExpanded ? NotchConfig.expandedTopRadius : NotchConfig.collapsedTopRadius
    }

    /// Всегда чёрная, в любой системной теме: белая плашка росла бы из чёрной чёлки,
    /// и шов между ними был бы виден. Тема окна прибита к тёмной там же, где окно создаётся.
    private var fillColor: Color { .black }
}
