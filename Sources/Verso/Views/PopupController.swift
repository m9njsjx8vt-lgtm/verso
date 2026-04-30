import AppKit
import SwiftUI

@MainActor
final class PopupController {
    private let settings: AppSettings
    private let glossary: Glossary
    private let history: HistoryStore
    private let geminiClient = GeminiClient()
    private let deepLClient = DeepLClient()
    private var window: PopupWindow?
    private var sourceApp: NSRunningApplication?
    private var currentViewModel: PopupViewModel?

    private var deepLTask: Task<Void, Never>?
    private var geminiTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var learnTask: Task<Void, Never>?

    private var activeLangPair: LanguageDetector.Pair?
    private var activeOriginal: String = ""
    /// True once Gemini's first successful translation has been recorded to history
    private var historyRecorded: Bool = false

    init(settings: AppSettings, glossary: Glossary, history: HistoryStore) {
        self.settings = settings
        self.glossary = glossary
        self.history = history
    }

    func show(originalText: String) {
        sourceApp = NSWorkspace.shared.frontmostApplication
        activeOriginal = originalText
        historyRecorded = false

        let pair = LanguageDetector.detect(originalText)
        activeLangPair = pair

        let deepLConfigured = !settings.deeplApiKey.isEmpty

        close(restoreFocus: false)

        let viewModel = PopupViewModel(
            originalText: originalText,
            fromLang: pair.sourceShort,
            toLang: pair.targetShort,
            deepLConfigured: deepLConfigured,
            onInsert: { [weak self] t in self?.insertAndClose(t) },
            onCopy: { [weak self] t in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
                self?.close(restoreFocus: true)
            },
            onClose: { [weak self] in self?.close(restoreFocus: true) },
            onRefine: { [weak self] instr in self?.refine(instruction: instr) },
            onAddGlossary: { [weak self] term, t, preserve in
                self?.glossary.add(term: term, translation: t, preserveAsIs: preserve)
                self?.currentViewModel?.showToast("用語を追加: \(term)")
            },
            onUndo: { [weak self] in self?.undoLastRefine() },
            onRetry: { [weak self] in self?.retry() },
            onSaveEdit: { [weak self] edited in self?.saveEdit(edited) }
        )
        currentViewModel = viewModel

        let popup = PopupWindow(
            rootView: PopupView(viewModel: viewModel),
            onResignKey: { [weak self] in self?.close(restoreFocus: false) }
        )
        window = popup
        popup.showAtMouse()

        startInitialTranslations(viewModel: viewModel)
    }

    private func startInitialTranslations(viewModel: PopupViewModel) {
        deepLTask?.cancel(); geminiTask?.cancel()

        guard let pair = activeLangPair else { return }
        let originalText = activeOriginal
        let appHint = sourceApp?.localizedName

        // DeepL preview
        if !settings.deeplApiKey.isEmpty {
            deepLTask = Task { @MainActor [weak self, weak viewModel] in
                guard let self = self, let viewModel = viewModel else { return }
                do {
                    let preview = try await self.deepLClient.translate(
                        text: originalText,
                        sourceLang: pair.deepLSource,
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

        // Gemini — STREAMING
        geminiTask = Task { @MainActor [weak self, weak viewModel] in
            guard let self = self, let viewModel = viewModel else { return }
            do {
                let final = try await self.geminiClient.translateStreaming(
                    text: originalText,
                    from: pair.sourceFull,
                    to: pair.targetFull,
                    context: self.settings.translatorContext,
                    glossary: self.glossary.formattedForPrompt(),
                    sourceAppHint: appHint,
                    model: self.settings.model,
                    apiKey: self.settings.apiKey,
                    onChunk: { [weak viewModel] partial in
                        await MainActor.run {
                            viewModel?.geminiState = .ok(partial)
                        }
                    }
                )
                if Task.isCancelled { return }
                // Final pass to ensure trimmed text is set
                viewModel.geminiState = .ok(final)
                self.recordHistoryIfNeeded(translation: final, pair: pair, appHint: appHint)
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
                if vm.undoStack.last == snapshot { vm.undoStack.removeLast() }
            }
        }
    }

    private func undoLastRefine() {
        guard let vm = currentViewModel, !vm.undoStack.isEmpty else { return }
        let prev = vm.undoStack.removeLast()
        vm.geminiState = .ok(prev)
    }

    private func retry() {
        guard let vm = currentViewModel else { return }
        vm.geminiState = .loading
        if vm.showDeepLPanel { vm.deepLState = .loading }
        startInitialTranslations(viewModel: vm)
    }

    /// User edited the translation in-line. Update state, then asynchronously ask Gemini
    /// to extract any term-level corrections and add them to the glossary.
    private func saveEdit(_ edited: String) {
        guard let vm = currentViewModel,
              let pair = activeLangPair else { return }
        let originalTranslation = vm.geminiText
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)

        vm.geminiState = .ok(trimmed)
        vm.isEditing = false

        // No diff → no learning
        guard !trimmed.isEmpty, trimmed != originalTranslation else {
            vm.showToast("変更なし")
            return
        }
        vm.showToast("保存しました — 用語を学習中…", duration: 2.0)

        learnTask?.cancel()
        learnTask = Task { @MainActor [weak self, weak vm] in
            guard let self = self, let vm = vm else { return }
            do {
                let pairs = try await self.geminiClient.extractGlossaryDiff(
                    originalText: vm.originalText,
                    modelTranslation: originalTranslation,
                    userTranslation: trimmed,
                    from: pair.sourceFull,
                    to: pair.targetFull,
                    model: self.settings.model,
                    apiKey: self.settings.apiKey
                )
                if Task.isCancelled { return }
                if pairs.isEmpty {
                    vm.showToast("用語の変更は検出されませんでした")
                } else {
                    for pair in pairs {
                        self.glossary.add(
                            term: pair.term,
                            translation: pair.translation,
                            preserveAsIs: false
                        )
                    }
                    vm.showToast("\(pairs.count)個の用語を Glossary に追加しました")
                }
            } catch {
                if Task.isCancelled { return }
                vm.showToast("用語抽出失敗: \(error.localizedDescription)")
            }
        }
    }

    private func recordHistoryIfNeeded(translation: String, pair: LanguageDetector.Pair, appHint: String?) {
        guard !historyRecorded, !translation.isEmpty else { return }
        historyRecorded = true
        history.record(
            sourceLang: pair.sourceShort,
            targetLang: pair.targetShort,
            sourceText: activeOriginal,
            translation: translation,
            sourceApp: appHint
        )
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
        if restoreFocus, let app = app { app.activate() }
    }

    private func cancelAllTasks() {
        deepLTask?.cancel(); deepLTask = nil
        geminiTask?.cancel(); geminiTask = nil
        refineTask?.cancel(); refineTask = nil
        learnTask?.cancel(); learnTask = nil
    }
}
