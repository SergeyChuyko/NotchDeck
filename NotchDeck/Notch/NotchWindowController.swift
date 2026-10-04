import AppKit
import Combine
import SwiftUI

/// Панель, в которой живёт плашка: без рамки, поверх меню-бара, не активирует приложение.
final class NotchPanel: NSPanel {
    /// Нужно, чтобы плашка могла принимать клики и ввод, не выводя приложение на передний план.
    override var canBecomeKey: Bool { true }
}

/// Хостинг SwiftUI, который пропускает клики сквозь пустые места окна.
/// Без этого прозрачный «воздух» вокруг плашки съедал бы клики по тому, что под ним.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не поддерживается")
    }

    /// Область в координатах окна, в которой лежит сама плашка.
    /// Всё вне её — прозрачный запас под тени и «уши», он мышь ловить не должен.
    var interactiveRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Проверять «вернул ли super сам себя» здесь бесполезно: SwiftUI рисует всю
        // вёрстку внутри одного NSHostingView, поэтому self возвращается почти всегда,
        // и такой passthrough ронял бы сквозь окно вообще все клики.
        guard interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }

    /// Приложение живёт в меню-баре, окно никогда не становится активным, поэтому каждый
    /// клик по плашке для AppKit — «первый». Без этого он уходил бы на активацию окна,
    /// а до разделов внутри не доходил вовсе.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

}

/// Создаёт панель над чёлкой, держит её на месте и подгоняет размер окна под состояние плашки.
///
/// Окно живёт в двух размерах: пока плашка свёрнута, оно размером с чёлку и ничего вокруг
/// не перекрывает; перед раскрытием оно мгновенно вырастает (прозрачное — визуально этого
/// не видно), чтобы анимации было куда разворачиваться.
@MainActor
final class NotchWindowController {

    let controller = NotchController()
    private let translator = NotchTranslator()
    private let clipboard = NotchClipboard()
    private let screenshots = NotchScreenshots()
    private let media = NotchMedia()
    private let battery = NotchBattery()
    private let system = NotchSystemControls()

    private var panel: NotchPanel?
    private var hostingView: PassthroughHostingView<NotchRootView>?
    private var metrics: NotchScreenMetrics?
    private var collapseWorkItem: DispatchWorkItem?
    private var tallShrinkWorkItem: DispatchWorkItem?
    private var playbackObservers: Set<AnyCancellable> = []
    private var resignActiveObserver: NSObjectProtocol?

    // MARK: - Жизненный цикл

    func show() {
        guard panel == nil else { return }
        guard let metrics = NotchScreenMetrics.current() else { return }

        let panel = NotchPanel(
            contentRect: CGRect(origin: .zero, size: collapsedWindowSize(for: metrics)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Плашка притворяется продолжением чёлки, а чёлка чёрная всегда — значит и тема
        // внутри окна всегда тёмная, независимо от системной. Прибиваем её к окну, а не
        // к вьюхам: так тёмными становятся и элементы AppKit внутри — курсор и выделение
        // в поле ввода переводчика, индикатор загрузки, контекстные меню.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Выше меню-бара, видна на всех рабочих столах и поверх полноэкранных приложений.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = PassthroughHostingView(rootView: makeRootView(metrics: metrics))
        host.autoresizingMask = [.width, .height]
        // Панель стоит прямо в зоне чёлки, поэтому её safe area постоянно «дрожит».
        // Если этого не отключить, каждый сдвиг окна запускает у SwiftUI новый пересчёт
        // констрейнтов внутри уже идущего — AppKit ловит рекурсию и роняет приложение.
        host.safeAreaRegions = []
        // Размер окна задаём только мы. Пока плашка свёрнута, окно размером с чёлку,
        // а раскрытая вёрстка внутри заведомо больше — без этого SwiftUI пытался бы
        // продавить свой размер обратно в окно, и разметка зацикливалась.
        host.sizingOptions = []
        panel.contentView = host

        self.panel = panel
        self.hostingView = host

        bindController()
        watchOutsideClicks()
        apply(metrics)
        panel.orderFrontRegardless()
        clipboard.start()
        screenshots.start()
        media.start()
        battery.start()
        system.start()
        watchPlayback()

    }

    /// Пока жива сессия плеера, чёлка шире — вместе с ней должна меняться и зона, которой
    /// окно ловит мышь. Значение берём из подписки: @Published сообщает об изменении
    /// до того, как оно применится, и media.track здесь был бы ещё прежним.
    private func watchPlayback() {
        media.$track
            .map { $0 != nil }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] hasSession in
                guard let self, let metrics = self.metrics, !self.controller.isExpanded else { return }
                self.applyWindowSize(
                    self.collapsedWindowSize(for: metrics),
                    panelSize: self.collapsedPanelSize(for: metrics,
                                                       hinted: self.controller.isHinted,
                                                       media: hasSession)
                )
            }
            .store(in: &playbackObservers)
    }

    /// Поля ввода активируют приложение — иначе клавиатура до них не доходит. Поэтому клик
    /// в любое другое место приходит к нам как «приложение перестало быть активным».
    ///
    /// Фокус с полей снимаем сами: окно при этом не закрывается, и SwiftUI считал бы,
    /// что курсор всё ещё стоит в поле, — а вместе с ним держалась бы и защита от закрытия.
    private func watchOutsideClicks() {
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel?.makeFirstResponder(nil)
                self.controller.interactionEndedOutside()
            }
        }
    }

    /// Дописать историю буфера на диск, не дожидаясь отложенного сохранения.
    func flushClipboard() {
        clipboard.flush()
    }

    /// Пересчитать экран и вернуть панель на место — после смены монитора или разрешения.
    ///
    /// Система шлёт «параметры экрана изменились» и когда ничего не изменилось: например,
    /// при переключении рабочих столов или подключении внешнего устройства. Пересобирать
    /// на это вьюху и двигать окно незачем — лишняя перерисовка видна пользователю.
    func reposition() {
        guard let metrics = NotchScreenMetrics.current(), metrics != self.metrics else { return }
        apply(metrics)
    }

    private func apply(_ metrics: NotchScreenMetrics) {
        self.metrics = metrics
        hostingView?.rootView = makeRootView(metrics: metrics)
        if controller.isExpanded {
            applyWindowSize(expandedWindowSize(tall: controller.isTall),
                            panelSize: metrics.expandedSize(tall: controller.isTall))
        } else {
            applyWindowSize(collapsedWindowSize(for: metrics),
                            panelSize: collapsedPanelSize(for: metrics, hinted: controller.isHinted,
                                                          media: media.track != nil))
        }
    }

    // MARK: - Состояние

    /// Размер окна меняем по краям анимации, а не внутри неё: перед раскрытием — сразу,
    /// после закрытия — когда пружина доиграет.
    private func bindController() {
        controller.willExpand = { [weak self] in
            guard let self else { return }
            self.collapseWorkItem?.cancel()
            // Панель открывают на секунду — состояние плеера должно быть свежим сразу.
            self.media.refresh()
            self.screenshots.refresh()
            self.battery.refresh()
            self.system.refresh()
            // Строго асинхронно: наведение прилетает из tracking area, а она обновляется
            // внутри прохода разметки. Менять frame окна прямо там нельзя — это и есть
            // тот самый рекурсивный Layout pass, на котором приложение падало.
            DispatchQueue.main.async {
                guard let metrics = self.metrics else { return }
                self.applyWindowSize(self.expandedWindowSize(tall: false), panelSize: metrics.expandedSize)
            }
        }
        controller.didCollapse = { [weak self] in
            self?.tallShrinkWorkItem?.cancel()
            self?.scheduleWindowShrink()
        }
        controller.willGrowTall = { [weak self] in
            guard let self else { return }
            self.tallShrinkWorkItem?.cancel()
            DispatchQueue.main.async {
                guard let metrics = self.metrics, self.controller.isExpanded else { return }
                self.applyWindowSize(self.expandedWindowSize(tall: true),
                                     panelSize: metrics.expandedSize(tall: true))
            }
        }
        controller.didShrinkTall = { [weak self] in
            self?.scheduleTallShrink()
        }
        // Размер окна при этом не трогаем — оно и так с запасом под подросшую чёлку.
        // Меняется только зона, которой окно ловит мышь.
        controller.didChangeHint = { [weak self] hinted in
            guard let self, let metrics = self.metrics, !self.controller.isExpanded else { return }
            // Именно из параметра, а не из controller.isHinted: на расширении зоны колбэк
            // приходит раньше, чем меняется сам флаг, — иначе зона осталась бы прежней.
            self.applyWindowSize(self.collapsedWindowSize(for: metrics),
                                 panelSize: self.collapsedPanelSize(for: metrics, hinted: hinted,
                                                                    media: self.media.track != nil))
        }
    }

    /// Ужать окно обратно только после того, как анимация закрытия доиграет.
    private func scheduleWindowShrink() {
        guard let metrics else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.controller.isExpanded else { return }
            self.applyWindowSize(self.collapsedWindowSize(for: metrics),
                                 panelSize: self.collapsedPanelSize(for: metrics, hinted: self.controller.isHinted,
                                                                    media: self.media.track != nil))
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    /// Вернуть окно к обычной раскрытой высоте, когда плашка доиграет втягивание.
    private func scheduleTallShrink() {
        tallShrinkWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let metrics = self.metrics,
                  self.controller.isExpanded, !self.controller.isTall else { return }
            self.applyWindowSize(self.expandedWindowSize(tall: false), panelSize: metrics.expandedSize)
        }
        tallShrinkWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    // MARK: - Геометрия окна

    /// Какого размера сейчас свёрнутая плашка: обычная чёлка, расширенная под играющий
    /// трек, подросшая под курсором — или всё сразу.
    private func collapsedPanelSize(for metrics: NotchScreenMetrics,
                                    hinted: Bool, media: Bool) -> CGSize {
        let base = NotchConfig.collapsedSize(notchSize: metrics.notchSize, media: media)
        return hinted ? NotchConfig.hintedSize(for: base, notchSize: metrics.notchSize) : base
    }

    /// Окно считаем по самому широкому из свёрнутых состояний — с крыльями и под курсором.
    /// Оно прозрачное, лишнего не видно, зато ни расширение под трек, ни подрастание
    /// не требуют менять frame окна: это здесь самая хрупкая операция.
    private func collapsedWindowSize(for metrics: NotchScreenMetrics) -> CGSize {
        let widest = collapsedPanelSize(for: metrics, hinted: true, media: true)
        // Места по бокам должно хватить и на «уши»: они рисуются за границами плашки,
        // и непрерывному скруглению их нужно полтора радиуса. Зона, ловящая мышь,
        // от этого не растёт — она считается отдельно, по hoverSlop.
        let sidePadding = max(NotchConfig.hoverSlop.width,
                              NotchConfig.cornerSpan(for: NotchConfig.collapsedTopRadius))
        return CGSize(
            width: widest.width + sidePadding * 2,
            height: widest.height + NotchConfig.hoverSlop.height
        )
    }

    private func expandedWindowSize(tall: Bool) -> CGSize {
        guard let metrics else { return .zero }
        let panel = metrics.expandedSize(tall: tall)
        return CGSize(
            width: panel.width + NotchConfig.windowSidePadding * 2,
            height: panel.height + NotchConfig.windowBottomPadding
        )
    }

    /// Окно всегда центрировано по чёлке и прижато к верхней кромке экрана.
    /// - Parameter panelSize: размер плашки, ради которой окно меняется. Передаётся явно,
    ///   потому что при раскрытии окно растёт раньше, чем `isExpanded` станет `true`.
    private func applyWindowSize(_ size: CGSize, panelSize: CGSize) {
        guard let panel, let metrics else { return }

        // Клики принимает только сама плашка плюс запас, на котором ловится наведение.
        let hitWidth = panelSize.width + NotchConfig.hoverSlop.width * 2
        let hitHeight = panelSize.height + NotchConfig.hoverSlop.height
        hostingView?.interactiveRect = CGRect(
            x: ((size.width - hitWidth) / 2).rounded(),
            y: (size.height - hitHeight).rounded(),
            width: hitWidth,
            height: hitHeight
        )

        let frame = CGRect(
            x: (metrics.notchCenterX - size.width / 2).rounded(),
            y: (metrics.screenTopY - size.height).rounded(),
            width: size.width,
            height: size.height
        )
        guard panel.frame != frame else { return }
        // display: false — перерисовка придёт обычным циклом, без немедленного
        // прохода по констрейнтам прямо посреди обработки события.
        panel.setFrame(frame, display: false)
    }

    // MARK: - Содержимое

    private func makeRootView(metrics: NotchScreenMetrics) -> NotchRootView {
        NotchRootView(
            controller: controller,
            translator: translator,
            clipboard: clipboard,
            screenshots: screenshots,
            media: media,
            battery: battery,
            system: system,
            notchSize: metrics.notchSize,
            expandedSize: metrics.expandedSize
        )
    }
}
