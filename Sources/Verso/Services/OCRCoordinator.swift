import AppKit

@MainActor
final class OCRCoordinator {
    private weak var popupController: PopupController?
    private var selectionWindow: RegionSelectionWindow?

    init(popupController: PopupController) {
        self.popupController = popupController
    }

    /// Capture the entire frontmost (non-Verso) window and OCR-translate it.
    func startWindowTranslation() {
        // Find the frontmost non-Verso app, then its main window
        guard let frontApp = NSWorkspace.shared.runningApplications
            .filter({ $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier })
            .sorted(by: { ($0.activationPolicy.rawValue, $0.processIdentifier) < ($1.activationPolicy.rawValue, $1.processIdentifier) })
            .first(where: { $0.isActive }) ?? NSWorkspace.shared.frontmostApplication
        else {
            showError("ターゲットウィンドウが見つかりません。")
            return
        }
        let pid = frontApp.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            showError("ウィンドウリスト取得失敗。")
            return
        }
        // Largest window owned by the target PID
        let candidates = infoList.compactMap { info -> (Int, Int, CGWindowID)? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  let id = info[kCGWindowNumber as String] as? CGWindowID
            else { return nil }
            return (Int(w * h), Int(w + h), id)
        }
        guard let target = candidates.max(by: { $0.0 < $1.0 }) else {
            showError("\(frontApp.localizedName ?? "対象アプリ") にキャプチャ可能なウィンドウがありません。")
            return
        }
        let windowID = target.2
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else {
            showError("ウィンドウキャプチャに失敗しました。Screen Recording 権限を確認してください。")
            return
        }
        Task { @MainActor in
            do {
                let text = try await OCRService.recognizeText(in: cgImage)
                self.popupController?.show(originalText: text)
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    /// Start the screen-region translation flow.
    func startRegionTranslation() {
        guard let screen = NSScreen.main else { return }

        // Close any existing selection window first
        selectionWindow?.orderOut(nil)
        selectionWindow = nil

        let window = RegionSelectionWindow(
            screen: screen,
            onSelect: { [weak self] cgRect in
                self?.captureAndTranslate(rect: cgRect)
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

    private func captureAndTranslate(rect: CGRect) {
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
                self.popupController?.show(originalText: text)
            } catch {
                self.showError(error.localizedDescription)
            }
        }
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
