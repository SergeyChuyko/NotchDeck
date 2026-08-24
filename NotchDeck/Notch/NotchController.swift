import Combine
import SwiftUI

/// Состояние плашки. Знает только «раскрыта или нет» — окном занимается NotchWindowController.
@MainActor
final class NotchController: ObservableObject {

    @Published private(set) var isExpanded = false

    /// Курсор на чёлке, но плашка ещё не раскрылась: чёлка просто подросла и ждёт,
    /// пока курсор пролежит на ней положенное время.
    @Published private(set) var isHinted = false

    /// Выбранный раздел живёт здесь, а не в @State вьюхи: так он переживает
    /// и сворачивание плашки, и пересоздание вьюхи при смене монитора.
    @Published var selectedSection: NotchSection = .player

    /// Окну нужно вырасти до начала анимации, иначе развернуться будет некуда.
    /// Вызывается строго вне анимационной транзакции: менять размер окна во время
    /// обновления SwiftUI нельзя — AppKit ловит рекурсивный пересчёт и роняет приложение.
    var willExpand: (() -> Void)?

    /// А ужаться окно должно уже после того, как анимация закрытия доиграет.
    var didCollapse: (() -> Void)?

    /// Чёлка подросла или вернулась к обычному размеру. Окну это нужно, чтобы подвинуть
    /// зону, которая ловит мышь: держать её всегда по подросшей нельзя — вокруг чёлки
    /// живут пункты меню и иконки статус-бара, и лишняя мёртвая полоса съедала бы клики.
    var didChangeHint: ((Bool) -> Void)?

    /// Пауза действует только после закрытия кликом: курсор остаётся лежать на плашке,
    /// и без паузы она распахнулась бы обратно в тот же миг.
    private var cooldownUntil: Date = .distantPast

    /// Отложенное закрытие после ухода курсора — отменяется, если он вернулся.
    private var hoverExitWork: DispatchWorkItem?

    /// Отложенное раскрытие: заводится, как только чёлка подросла.
    private var hintWork: DispatchWorkItem?

    /// Пока внутри плашки идёт работа с клавиатурой, уход курсора её не закрывает.
    private var isInteractionLocked = false

    func setInteractionLocked(_ locked: Bool) {
        isInteractionLocked = locked
        if locked {
            hoverExitWork?.cancel()
            hoverExitWork = nil
        }
    }

    // MARK: - Наведение

    /// Курсор зашёл на плашку или ушёл с неё.
    func hoverChanged(_ isHovering: Bool) {
        hoverExitWork?.cancel()
        hoverExitWork = nil

        if isHovering {
            guard Date() >= cooldownUntil else { return }
            beginHint()
        } else {
            cancelHint()
            scheduleHoverCollapse()
        }
    }

    /// Чёлка подрастает сразу, а раскрывается только если курсор никуда не делся.
    private func beginHint() {
        // Повторные «мышь здесь» прилетают и без движения курсора. Если на каждое
        // заводить отсчёт заново, он не истечёт никогда.
        guard !isExpanded, hintWork == nil else { return }

        setHinted(true)

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hintWork = nil
            self.expand()
        }
        hintWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchConfig.hintDelay, execute: work)
    }

    private func cancelHint() {
        hintWork?.cancel()
        hintWork = nil
        setHinted(false)
    }

    /// Как и раскрытие, меняем состояние следующим тиком: событие наведения приходит
    /// из прохода разметки, а запускать в нём анимацию нельзя.
    private func setHinted(_ hinted: Bool) {
        guard isHinted != hinted else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isHinted != hinted else { return }
            // Плашка успела раскрыться, пока мы ждали тик, — подрастать уже некуда.
            if hinted && self.isExpanded { return }

            // Зону под мышь расширяем до анимации, а сужаем после неё: пока чёлка растёт,
            // курсор уже должен считаться наведённым на её будущий край, иначе SwiftUI
            // пришлёт «мышь ушла» и всё схлопнется обратно.
            if hinted { self.didChangeHint?(true) }

            withAnimation(NotchConfig.hintAnimation) {
                self.isHinted = hinted
            }

            if !hinted { self.didChangeHint?(false) }
        }
    }

    /// Курсор мог выскочить за край всего на мгновение — даём ему шанс вернуться.
    private func scheduleHoverCollapse() {
        guard isExpanded, !isInteractionLocked else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.collapse()
        }
        hoverExitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchConfig.hoverCloseDelay, execute: work)
    }

    // MARK: - Состояние

    func expand() {
        guard !isExpanded else { return }
        hintWork?.cancel()
        hintWork = nil
        willExpand?()
        // Анимацию запускаем следующим тиком — к нему окно уже успело вырасти,
        // и раскрываться есть куда. Заодно withAnimation не попадает внутрь
        // прохода разметки, из которого пришло событие наведения.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isExpanded else { return }
            withAnimation(NotchConfig.openAnimation) {
                self.isExpanded = true
                self.isHinted = false
            }
        }
    }

    /// - Parameter startCooldown: закрытие кликом ставит паузу на повторное раскрытие,
    ///   закрытие по уходу курсора — нет, иначе плашку нельзя было бы сразу открыть снова.
    func collapse(startCooldown: Bool = false) {
        hoverExitWork?.cancel()
        hoverExitWork = nil
        hintWork?.cancel()
        hintWork = nil

        guard isExpanded else { return }
        if startCooldown {
            cooldownUntil = Date().addingTimeInterval(NotchConfig.reopenCooldown)
        }
        withAnimation(NotchConfig.closeAnimation) {
            isExpanded = false
            // Закрыли кликом — курсор остался лежать на чёлке, но подрастать ей уже незачем.
            isHinted = false
        }
        didCollapse?()
    }
}
