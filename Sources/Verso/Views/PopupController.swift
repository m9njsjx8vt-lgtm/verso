import AppKit
import SwiftUI

@MainActor
final class PopupController {
    private let settings: AppSettings
    private let glossary: Glossary
    private let geminiClient = GeminiClient()
    private let deepLClient = DeepLClient()
    private var window: PopupWindow?
    private var sourceApp: NSRunningApplication?
    private var currentTaskId: Int = 0
    private var currentViewModel: PopupViewModel?
    private var currentFromFull: String = ""
    private var currentToFull: String = ""

    init(settings: AppSettings, glossary: Glossary) {
        self.settings = settings
        self.glossary = glossary
    }

    func show(originalText: String) {
        sourceApp = NSWorkspace.shared.frontmostApplication

        let isJa = Self.isJapanese(originalText)
        let fromShort = isJa ? "JA" : "EN"
        let toShort = isJa ? "EN" : "JA"
        let fromFull = isJa ? "Japanese" : "English"
        let toFull = isJa ? "English" : "Japanese"
        currentFromFull = fromFull
        currentToFull = toFull

        let deepLConfigured = !settings.deeplApiKey.isEmpty

        close(restoreFocus: false)

        let viewModel = PopupViewModel(
            originalText: originalText,
            fromLang: fromShort,
            toLang: toShort,
            deepLConfigured: deepLConfigured,
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
            },
            onRefine: { [weak self] instruction in
                self?.refine(instruction: instruction)
            },
            onAddGlossary: { [weak self] term, translation, preserve in
                self?.glossary.add(
                    term: term,
                    translation: translation,
                    preserveAsIs: preserve
                )
            }
        )
        currentViewModel = viewModel

        let popup = PopupWindow(
            rootView: PopupView(viewModel: viewModel),
            onResignKey: { [weak self] in
                self?.close(restoreFocus: false)
            },
            preferredHeight: deepLConfigured ? 560 : 460
        )
        window = popup
        popup.showAtMouse()

        currentTaskId += 1
        let taskId = currentTaskId

        // DeepL
        if deepLConfigured {
            Task { @MainActor in
                do {
                    let preview = try await deepLClient.translate(
                        text: originalText,
                        sourceLang: DeepLClient.deepLLang(for: fromFull),
                        targetLang: DeepLClient.deepLLang(for: toFull),
                        apiKey: settings.deeplApiKey
                    )
                    guard taskId == self.currentTaskId else { return }
                    viewModel.deepLState = .ok(preview)
                } catch {
                    guard taskId == self.currentTaskId else { return }
                    viewModel.deepLState = .failed(error.localizedDescription)
                }
            }
        }

        // Gemini
        Task { @MainActor in
            do {
                let translation = try await geminiClient.translate(
                    text: originalText,
                    from: fromFull,
                    to: toFull,
                    context: settings.translatorContext,
                    glossary: glossary.formattedForPrompt(),
                    model: settings.model,
                    apiKey: settings.apiKey
                )
                guard taskId == self.currentTaskId else { return }
                viewModel.geminiState = .ok(translation)
            } catch {
                guard taskId == self.currentTaskId else { return }
                viewModel.geminiState = .failed(error.localizedDescription)
            }
        }
    }

    private func refine(instruction: String) {
        guard let vm = currentViewModel, vm.isGeminiOk else { return }
        let snapshotTranslation = vm.geminiText
        vm.isRefining = true
        currentTaskId += 1
        let taskId = currentTaskId
        Task { @MainActor in
            do {
                let refined = try await geminiClient.refine(
                    originalText: vm.originalText,
                    currentTranslation: snapshotTranslation,
                    instruction: instruction,
                    from: currentFromFull,
                    to: currentToFull,
                    context: settings.translatorContext,
                    glossary: glossary.formattedForPrompt(),
                    model: settings.model,
                    apiKey: settings.apiKey
                )
                guard taskId == self.currentTaskId else { return }
                vm.geminiState = .ok(refined)
                vm.isRefining = false
            } catch {
                guard taskId == self.currentTaskId else { return }
                vm.geminiState = .failed(error.localizedDescription)
                vm.isRefining = false
            }
        }
    }

    private func insertAndClose(_ translation: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)

        let app = sourceApp
        window?.orderOut(nil)
        window = nil
        currentViewModel = nil

        if let app = app {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                PasteService.sendCommandV()
            }
        }
    }

    func close(restoreFocus: Bool) {
        let app = sourceApp
        window?.persistCurrentSize()  // remember last size for next popup
        window?.orderOut(nil)
        window = nil
        currentViewModel = nil
        if restoreFocus, let app = app {
            app.activate()
        }
    }

    private static func isJapanese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || (0x4E00...0x9FFF).contains(v)
            {
                return true
            }
        }
        return false
    }
}
