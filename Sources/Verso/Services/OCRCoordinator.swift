import AppKit

@MainActor
final class OCRCoordinator {
    private weak var popupController: PopupController?
    private var selectionWindow: RegionSelectionWindow?

    init(popupController: PopupController) {
        self.popupController = popupController
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
