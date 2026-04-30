import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {
    private let history: HistoryStore
    private var window: NSWindow?
    private weak var popupController: PopupController?

    init(history: HistoryStore, popupController: PopupController) {
        self.history = history
        self.popupController = popupController
    }

    func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        let view = HistoryView(
            history: history,
            onInsert: { [weak self] translation in
                self?.insertAndClose(translation)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Verso — Translation History"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 800, height: 600))
        win.center()
        win.isReleasedWhenClosed = false
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func insertAndClose(_ translation: String) {
        // Put in clipboard, then send to whatever was frontmost before History opened
        // (For history-driven inserts, easiest UX: copy to clipboard + close.
        //  User can ⌘V where they need it.)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)
        close()

        // Show a transient notification
        let alert = NSAlert()
        alert.messageText = "Copied"
        alert.informativeText = "Past translation copied to clipboard. Press ⌘V to paste."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        // Run modally but very briefly — use async dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.windows.first(where: { $0.title.isEmpty && $0.contentView != nil })?.close()
        }
        // Note: we don't synchronously runModal because it'd block; user can just see clipboard
    }
}
