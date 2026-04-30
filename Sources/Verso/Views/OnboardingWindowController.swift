import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let settings: AppSettings
    private var window: NSWindow?
    private let onComplete: () -> Void

    init(settings: AppSettings, onComplete: @escaping () -> Void) {
        self.settings = settings
        self.onComplete = onComplete
    }

    func show() {
        if window != nil {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(onComplete: { [weak self] in
            self?.close()
            self?.onComplete()
        })
            .environmentObject(settings)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Verso へようこそ"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 600, height: 540))
        win.center()
        win.isReleasedWhenClosed = false
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
