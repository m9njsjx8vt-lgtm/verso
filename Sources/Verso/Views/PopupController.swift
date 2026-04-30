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
    private var currentViewModel: PopupViewModel?

    /// Cancellable in-flight tasks for the current popup
    private var deepLTask: Task<Void, Never>?
    private var geminiTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?

    /// Captured language pair for the active popup (used by refine + retry)
    private var activeLangPair: LanguageDetector.Pair?
    private var activeOriginal: String = ""

    init(settings: AppSettings, glossary: Glossary) {
        self.settings = settings
        self.glossary = glossary
    }

    func show(originalText: String) {
        sourceApp = NSWorkspace.shared.frontmostApplication
        activeOriginal = originalText

        let pair = LanguageDetector.detect(originalText)
        activeLangPair = pair

        let deepLConfigured = !settings.deeplApiKey.isEmpty

        close(restoreFocus: false)

        let viewModel = PopupViewModel(
            originalText: originalText,
            fromLang: pair.sourceShort,
            toLang: pair.targetShort,
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
            },
            onUndo: { [weak self] in
                self?.undoLastRefine()
            },
            onRetry: { [weak self] in
                self?.retry()
            }
        )
        currentViewModel = viewModel

        let popup = PopupWindow(
            rootView: PopupView(viewModel: viewModel),
            onResignKey: { [weak self] in
                self?.close(restoreFocus: false)
            }
        )
        window = popup
        popup.showAtMouse()

        startInitialTranslations(viewModel: viewModel)
    }

    private func startInitialTranslations(viewModel: PopupViewModel) {
        // Cancel any prior tasks (defensive — close() already nilled them)
        deepLTask?.cancel(); geminiTask?.cancel()

        guard let pair = activeLangPair else { return }
        let originalText = activeOriginal
        let appHint = sourceApp?.localizedName

        // DeepL
        if !settings.deeplApiKey.isEmpty, let deepLSrc = pair.deepLSource {
            deepLTask = Task { @MainActor [weak self, weak viewModel] in
                guard let self = self, let viewModel = viewModel else { return }
                do {
                    let preview = try await self.deepLClient.translate(
                        text: originalText,
                        sourceLang: deepLSrc,
                        targetLang: pair.deepLTarget,
                        apiKey: self.settings.deeplApiKey
                    )
                    if Task.isCancelled { return }
                    viewModel.deepLState = .ok(preview)
                } catch {
                    if Task.isCancelled { return }
                    viewModel.deepLState = .failed(error.localizedDescription)
                }
            }
        }

        // Gemini
        geminiTask = Task { @MainActor [weak self, weak viewModel] in
            guard let self = self, let viewModel = viewModel else { return }
            do {
                let translation = try await self.geminiClient.translate(
                    text: originalText,
                    from: pair.sourceFull,
                    to: pair.targetFull,
                    context: self.settings.translatorContext,
                    glossary: self.glossary.formattedForPrompt(),
                    sourceAppHint: appHint,
                    model: self.settings.model,
                    apiKey: self.settings.apiKey
                )
                if Task.isCancelled { return }
                viewModel.geminiState = .ok(translation)
            } catch {
                if Task.isCancelled { return }
                viewModel.geminiState = .failed(error.localizedDescription)
            }
        }
    }

    private func refine(instruction: String) {
        guard let vm = currentViewModel, vm.isGeminiOk,
              let pair = activeLangPair else { return }
        let snapshot = vm.geminiText
        vm.undoStack.append(snapshot)
        vm.isRefining = true

        refineTask?.cancel()
        refineTask = Task { @MainActor [weak self, weak vm] in
            guard let self = self, let vm = vm else { return }
            do {
                let refined = try await self.geminiClient.refine(
                    originalText: vm.originalText,
                    currentTranslation: snapshot,
                    instruction: instruction,
                    from: pair.sourceFull,
                    to: pair.targetFull,
                    context: self.settings.translatorContext,
                    glossary: self.glossary.formattedForPrompt(),
                    model: self.settings.model,
                    apiKey: self.settings.apiKey
                )
                if Task.isCancelled { vm.isRefining = false; return }
                vm.geminiState = .ok(refined)
                vm.isRefining = false
            } catch {
                if Task.isCancelled { vm.isRefining = false; return }
                vm.geminiState = .failed(error.localizedDescription)
                vm.isRefining = false
                // Revert the snapshot push since refine failed
                if vm.undoStack.last == snapshot {
                    vm.undoStack.removeLast()
                }
            }
        }
    }

    private func undoLastRefine() {
        guard let vm = currentViewModel, !vm.undoStack.isEmpty else { return }
        let previous = vm.undoStack.removeLast()
        vm.geminiState = .ok(previous)
    }

    private func retry() {
        guard let vm = currentViewModel else { return }
        vm.geminiState = .loading
        if vm.showDeepLPanel { vm.deepLState = .loading }
        startInitialTranslations(viewModel: vm)
    }

    private func insertAndClose(_ translation: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)

        let app = sourceApp
        cancelAllTasks()
        window?.persistCurrentSize()
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
        cancelAllTasks()
        if let vm = currentViewModel { vm.isRefining = false }
        window?.persistCurrentSize()
        window?.orderOut(nil)
        window = nil
        currentViewModel = nil
        if restoreFocus, let app = app {
            app.activate()
        }
    }

    private func cancelAllTasks() {
        deepLTask?.cancel(); deepLTask = nil
        geminiTask?.cancel(); geminiTask = nil
        refineTask?.cancel(); refineTask = nil
    }
}
