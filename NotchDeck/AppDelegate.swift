import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    let notchWindow = NotchWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Приложение живёт в меню-баре: без иконки в доке и без обычных окон.
        NSApp.setActivationPolicy(.accessory)

        notchWindow.show()

        // Подключили внешний монитор или сменили разрешение — панель нужно вернуть на чёлку.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        // Последние копирования могли не успеть попасть в отложенное сохранение.
        notchWindow.flushClipboard()
    }

    @objc private func screenParametersChanged() {
        notchWindow.reposition()
    }
}
