//
//  NotchDeckApp.swift
//  NotchDeck
//
//  Created by Sergei A.I. on 09.08.2026.
//

import SwiftUI

@main
struct NotchDeckApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Обычного окна у приложения нет: вся жизнь идёт в панели над чёлкой,
        // а в меню-баре висит только управление на время разработки.
        MenuBarExtra("NotchDeck", systemImage: "macbook") {
            Button("Раскрыть плашку") {
                appDelegate.notchWindow.controller.expand()
            }
            Button("Свернуть плашку") {
                appDelegate.notchWindow.controller.collapse()
            }
            Divider()
            Button("Выход") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
