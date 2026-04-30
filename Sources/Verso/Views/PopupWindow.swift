import AppKit
import SwiftUI

final class PopupWindow: NSPanel {
    private let onResignKey: () -> Void
    private static let sizeKey = "PopupWindow.lastSize"

    init(rootView: PopupView, onResignKey: @escaping () -> Void, preferredHeight: CGFloat = 460) {
        self.onResignKey = onResignKey

        // Restore last user-resized size if available, else use defaults
        let defaultSize = NSSize(width: 720, height: preferredHeight)
        let restoredSize: NSSize
        if let dict = UserDefaults.standard.dictionary(forKey: Self.sizeKey),
           let w = dict["w"] as? CGFloat, let h = dict["h"] as? CGFloat,
           w >= 500, h >= 380 {
            restoredSize = NSSize(width: w, height: h)
        } else {
            restoredSize = defaultSize
        }

        super.init(
            contentRect: NSRect(origin: .zero, size: restoredSize),
            // Standard panel chrome (no .utilityWindow) so the green zoom button
            // appears and edge-drag resize is fully discoverable.
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        contentMinSize = NSSize(width: 500, height: 380)
        self.title = "翻訳"
        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.contentView = NSHostingView(rootView: rootView)
    }

    /// Show the popup near the current mouse pointer, clamped to the visible screen.
    func showAtMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouse, $0.frame, false)
        }) ?? NSScreen.main

        if let visible = screen?.visibleFrame {
            var x = mouse.x + 20
            // mouse y is bottom-left origin; place popup BELOW cursor by subtracting height
            var y = mouse.y - 20 - frame.height
            x = min(x, visible.maxX - frame.width - 20)
            x = max(x, visible.minX + 20)
            y = max(y, visible.minY + 20)
            y = min(y, visible.maxY - frame.height - 20)
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // When user clicks elsewhere, dismiss the popup (DeepL behaviour)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onResignKey()
        }
    }

    /// Persist the window's current content size so the next popup opens at the same dims.
    func persistCurrentSize() {
        let size = frame.size
        UserDefaults.standard.set(["w": size.width, "h": size.height], forKey: Self.sizeKey)
    }
}
