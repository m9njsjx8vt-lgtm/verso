import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {
    private let history: HistoryStore
    private var window: NSWindow?
    private weak var workspaceController: WorkspaceWindowController?
    private weak var sourceApp: NSRunningApplication?

    init(
        history: HistoryStore,
        workspaceController: WorkspaceWindowController?
    ) {
        self.history = history
        self.workspaceController = workspaceController
    }

    func show() {
        if let app = frontmostNonVersoApplication() {
            sourceApp = app
        }

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
            onOpenWorkspace: { [weak self] entry in
                self?.workspaceController?.show(
                    text: entry.sourceText,
                    forceTarget: entry.targetLang,
                    translateImmediately: false
                )
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)
        let app = sourceApp
        close()

        if let app {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                PasteService.sendCommandV()
            }
        }
    }

    private func frontmostNonVersoApplication() -> NSRunningApplication? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundleID = Bundle.main.bundleIdentifier

        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        if frontmost.processIdentifier == currentPID {
            return nil
        }
        if let currentBundleID, frontmost.bundleIdentifier == currentBundleID {
            return nil
        }
        return frontmost
    }
}
