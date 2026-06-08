import AppKit
import ApplicationServices

enum AccessibilityService {
    /// Returns true if Accessibility is granted; otherwise prompts the user
    /// (system-level prompt that opens System Settings).
    @discardableResult
    static func checkAndPromptIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: [String: Any] = [promptKey: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func isTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
}

enum ScreenCapturePermissionService {
    @discardableResult
    static func requestIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    static func isTrusted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}
