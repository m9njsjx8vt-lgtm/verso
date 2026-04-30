import AppKit

enum PasteService {
    /// Posts a synthetic ⌘V keystroke to whichever app is currently frontmost.
    static func sendCommandV() {
        let vKeyCode: CGKeyCode = 0x09  // V
        let source = CGEventSource(stateID: .combinedSessionState)

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}
