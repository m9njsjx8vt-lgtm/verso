import AppKit

/// Detects two ⌘C presses within `doubleThreshold` seconds and fires `onDoubleCmdC`.
/// Uses an NSEvent global monitor (requires Accessibility permission).
final class HotkeyMonitor {
    private let doubleThreshold: TimeInterval = 0.5
    private let cKeyCode: UInt16 = 8

    private var lastCmdC: Date = .distantPast
    private var monitor: Any?
    private let onDoubleCmdC: () -> Void

    init(onDoubleCmdC: @escaping () -> Void) {
        self.onDoubleCmdC = onDoubleCmdC
    }

    func start() {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == cKeyCode else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Cmd only — no Shift/Option/Ctrl
        guard flags == .command else { return }

        let now = Date()
        if now.timeIntervalSince(lastCmdC) < doubleThreshold {
            lastCmdC = .distantPast
            DispatchQueue.main.async { [weak self] in
                self?.onDoubleCmdC()
            }
        } else {
            lastCmdC = now
        }
    }

    deinit {
        stop()
    }
}
