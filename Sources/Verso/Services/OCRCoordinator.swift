import AppKit

@MainActor
final class OCRCoordinator {
    private weak var popupController: PopupController?
    private var selectionWindow: RegionSelectionWindow?

    private struct CapturableWindow {
        let id: CGWindowID
        let ownerName: String
        let ownerPID: Int32
    }

    init(popupController: PopupController) {
        self.popupController = popupController
    }

    /// Capture the entire frontmost (non-Verso) window and OCR-translate it.
    func startWindowTranslation() {
        guard ensureScreenCapturePermission() else { return }

        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            showError("ウィンドウリスト取得失敗。")
            return
        }

        guard let target = frontmostCapturableWindow(in: infoList) else {
            showError("キャプチャ可能な前面ウィンドウが見つかりません。対象アプリのウィンドウを前面に出してから再試行してください。")
            return
        }
        let sourceApp = NSRunningApplication(processIdentifier: target.ownerPID)
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            target.id,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else {
            showError("\(target.ownerName) のウィンドウキャプチャに失敗しました。Screen Recording 権限を確認してください。")
            return
        }
        Task { @MainActor in
            do {
                let text = try await OCRService.recognizeText(in: cgImage)
                self.showRecognizedText(text, sourceApp: sourceApp)
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    /// Start the screen-region translation flow.
    func startRegionTranslation() {
        guard ensureScreenCapturePermission() else { return }
        guard let screen = NSScreen.main else { return }

        // Close any existing selection window first
        selectionWindow?.orderOut(nil)
        selectionWindow = nil
        let sourceApp = frontmostNonVersoApplication()

        let window = RegionSelectionWindow(
            screen: screen,
            onSelect: { [weak self] cgRect in
                self?.captureAndTranslate(rect: cgRect, sourceApp: sourceApp)
                self?.selectionWindow = nil
            },
            onCancel: { [weak self] in
                self?.selectionWindow = nil
            }
        )
        selectionWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func captureAndTranslate(rect: CGRect, sourceApp: NSRunningApplication?) {
        // CGWindowListCreateImage works on macOS 10.5+ (deprecated in 14 but still functional)
        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else {
            showError("スクリーンキャプチャに失敗しました。Screen Recording権限を確認してください。")
            return
        }

        Task { @MainActor in
            do {
                let text = try await OCRService.recognizeText(in: cgImage)
                self.showRecognizedText(text, sourceApp: sourceApp)
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    private func showRecognizedText(_ text: String, sourceApp: NSRunningApplication?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError("テキストを検出できませんでした。範囲を少し広げるか、文字がはっきり見える場所を選んでください。")
            return
        }
        popupController?.show(originalText: trimmed, sourceApplication: sourceApp)
    }

    private func frontmostCapturableWindow(in infoList: [[String: Any]]) -> CapturableWindow? {
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)

        for info in infoList {
            guard let ownerPID = int32Value(info[kCGWindowOwnerPID as String]),
                  ownerPID != currentPID,
                  intValue(info[kCGWindowLayer as String]) == 0,
                  let windowID = windowIDValue(info[kCGWindowNumber as String]),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = cgFloatValue(bounds["Width"]),
                  let height = cgFloatValue(bounds["Height"]),
                  width >= 48,
                  height >= 48
            else {
                continue
            }

            let alpha = cgFloatValue(info[kCGWindowAlpha as String]) ?? 1
            guard alpha > 0.01 else { continue }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "対象アプリ"
            return CapturableWindow(id: windowID, ownerName: ownerName, ownerPID: ownerPID)
        }

        return nil
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

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }

    private func int32Value(_ value: Any?) -> Int32? {
        if let number = value as? NSNumber { return number.int32Value }
        if let int32 = value as? Int32 { return int32 }
        if let int = value as? Int { return Int32(int) }
        return nil
    }

    private func windowIDValue(_ value: Any?) -> CGWindowID? {
        if let number = value as? NSNumber { return CGWindowID(number.uint32Value) }
        if let id = value as? CGWindowID { return id }
        if let int = value as? Int { return CGWindowID(int) }
        return nil
    }

    private func cgFloatValue(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(number.doubleValue) }
        if let double = value as? Double { return CGFloat(double) }
        if let int = value as? Int { return CGFloat(int) }
        if let value = value as? CGFloat { return value }
        return nil
    }

    private func ensureScreenCapturePermission() -> Bool {
        if ScreenCapturePermissionService.isTrusted() {
            return true
        }
        if ScreenCapturePermissionService.requestIfNeeded() {
            return true
        }
        showError("Screen Recording 権限が未許可です。System Settings → Privacy & Security → Screen Recording で Verso を許可してください。")
        return false
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "OCR / 翻訳エラー"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        // If the error mentions Screen Recording, offer to open System Settings
        if message.lowercased().contains("screen recording") || message.contains("キャプチャ") {
            alert.addButton(withTitle: "Open Settings")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            alert.runModal()
        }
    }
}
