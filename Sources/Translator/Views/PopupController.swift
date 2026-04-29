import AppKit
import SwiftUI

@MainActor
final class PopupController {
    private let settings: Settings
    private let client = GeminiClient()
    private var window: PopupWindow?
    private var sourceApp: NSRunningApplication?
    private var currentTaskId: Int = 0

    init(settings: Settings) {
        self.settings = settings
    }

    func show(originalText: String) {
        // Capture the active app BEFORE we steal focus
        sourceApp = NSWorkspace.shared.frontmostApplication

        let isJa = Self.isJapanese(originalText)
        let fromShort = isJa ? "JA" : "EN"
        let toShort = isJa ? "EN" : "JA"
        let fromFull = isJa ? "Japanese" : "English"
        let toFull = isJa ? "English" : "Japanese"

        // Close any existing popup
        close(restoreFocus: false)

        // Build the SwiftUI view-model with action callbacks
        let viewModel = PopupViewModel(
            originalText: originalText,
            fromLang: fromShort,
            toLang: toShort,
            onInsert: { [weak self] translation in
                self?.insertAndClose(translation)
            },
            onCopy: { [weak self] translation in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(translation, forType: .string)
                self?.close(restoreFocus: true)
            },
            onClose: { [weak self] in
                self?.close(restoreFocus: true)
            }
        )

        let popup = PopupWindow(
            rootView: PopupView(viewModel: viewModel),
            onResignKey: { [weak self] in
                self?.close(restoreFocus: false)
            }
        )
        window = popup
        popup.showAtMouse()

        // Bump task id so any in-flight callback is ignored if we open a new popup
        currentTaskId += 1
        let taskId = currentTaskId

        Task { @MainActor in
            do {
                let translation = try await client.translate(
                    text: originalText,
                    from: fromFull,
                    to: toFull,
                    context: settings.translatorContext,
                    model: settings.model,
                    apiKey: settings.apiKey
                )
                guard taskId == self.currentTaskId else { return }
                viewModel.translation = translation
                viewModel.state = .ok
            } catch {
                guard taskId == self.currentTaskId else { return }
                viewModel.state = .error(error.localizedDescription)
            }
        }
    }

    private func insertAndClose(_ translation: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)

        let app = sourceApp
        // Tear down the popup WITHOUT restoring focus — we want to focus sourceApp
        window?.orderOut(nil)
        window = nil

        if let app = app {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                PasteService.sendCommandV()
            }
        }
    }

    func close(restoreFocus: Bool) {
        let app = sourceApp
        window?.orderOut(nil)
        window = nil
        if restoreFocus, let app = app {
            app.activate()
        }
    }

    /// Heuristic: any hiragana / katakana / CJK code-point ⇒ treat as Japanese.
    private static func isJapanese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v)   // Hiragana
                || (0x30A0...0x30FF).contains(v) // Katakana
                || (0x4E00...0x9FFF).contains(v) // CJK Unified Ideographs
            {
                return true
            }
        }
        return false
    }
}
