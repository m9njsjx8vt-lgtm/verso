import AppKit
import SwiftUI

@MainActor
final class PopupController {
    private let settings: AppSettings
    private let glossary: Glossary
    private let history: HistoryStore
    private let usage: UsageTracker
    private let cache: TranslationCache
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
    private var historyRecorded: Bool = false

    init(settings: AppSettings, glossary: Glossary, history: HistoryStore,
         usage: UsageTracker, cache: TranslationCache) {
        self.settings = settings
        self.glossary = glossary
        self.history = history
        self.usage = usage
        self.cache = cache
    }

    func show(originalText: String, forceTarget: String? = nil) {
        sourceApp = NSWorkspace.shared.frontmostApplication
        activeOriginal = originalText
        historyRecorded = false

        let pair = LanguageDetector.detect(
            originalText,
            defaultTargetForEnglish: settings.targetWhenEnglish,
            defaultTargetForOther: settings.targetWhenOther,
            forceTargetShort: forceTarget
        )
        activeLangPair = pair

        let deepLConfigured = !settings.deeplApiKey.isEmpty

        close(restoreFocus: false)

        let viewModel = PopupViewModel(
            originalText: originalText,
            fromLang: pair.sourceShort,
            toLang: pair.targetShort,
            deepLConfigured: deepLConfigured,
            stayOpen: settings.stayOpen,
            privacyMode: settings.privacyMode,
            onInsert: { [weak self] t in self?.insertAndClose(t) },
            onCopy: { [weak self] t in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
                if self?.settings.stayOpen == true {
                    self?.currentViewModel?.showToast("コピーしました")
                } else {
                    self?.close(restoreFocus: true)
                }
            },
            onClose: { [weak self] in self?.close(restoreFocus: true) },
            onRefine: { [weak self] instr in self?.refine(instruction: instr) },
            onAddGlossary: { [weak self] term, t, preserve in
                self?.glossary.add(term: term, translation: t, preserveAsIs: preserve)
                self?.currentViewModel?.showToast("用語を追加: \(term)")
            },
            onUndo: { [weak self] in self?.undoLastRefine() },
            onRetry: { [weak self] in self?.retry() },
            onSaveEdit: { [weak self] edited in self?.saveEdit(edited) },
            onChangeTarget: { [weak self] newTargetShort in
                self?.show(originalText: self?.activeOriginal ?? "", forceTarget: newTargetShort)
            },
            onTogglePin: { [weak self] in
                guard let self = self else { return }
                self.settings.stayOpen.toggle()
                self.currentViewModel?.stayOpen = self.settings.stayOpen
                self.currentViewModel?.showToast(self.settings.stayOpen ? "📌 ピン留めON" : "ピン解除")
            }
        )
        currentViewModel = viewModel

        let popup = PopupWindow(
            rootView: PopupView(viewModel: viewModel),
            onResignKey: { [weak self] in
                guard let self = self else { return }
                if !self.settings.stayOpen {
                    self.close(restoreFocus: false)
                }
            }
        )
        window = popup
        popup.showAtMouse()

        // Cache check first — if both Gemini & DeepL are cached, no API call needed
        let cacheKey = cache.key(text: originalText,
                                 source: pair.sourceShort,
                                 target: pair.targetShort,
                                 glossary: glossary.formattedForPrompt())

        if settings.cacheEnabled, let entry = cache.get(cacheKey) {
            if let g = entry.geminiTranslation { viewModel.geminiState = .ok(g) }
            if let d = entry.deepLTranslation, deepLConfigured { viewModel.deepLState = .ok(d) }
            // If both are present, we're done. Otherwise fall through and fetch missing ones.
            if entry.geminiTranslation != nil && (!deepLConfigured || entry.deepLTranslation != nil) {
                viewModel.showToast("⚡ キャッシュ")
                if !settings.privacyMode {
                    recordHistoryIfNeeded(translation: entry.geminiTranslation ?? "", pair: pair, appHint: sourceApp?.localizedName)
                }
                return
            }
        }

        startInitialTranslations(viewModel: viewModel, cacheKey: cacheKey)
    }

    private func startInitialTranslations(viewModel: PopupViewModel, cacheKey: String) {
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
                    if self.settings.cacheEnabled {
                        self.cache.set(cacheKey, deepLTranslation: preview)
                    }
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
                let result = try await self.geminiClient.translateStreaming(
                    text: originalText,
                    from: pair.sourceFull,
                    to: pair.targetFull,
                    context: self.settings.translatorContext,
                    glossary: self.glossary.formattedForPrompt(),
                    sourceAppHint: appHint,
                    preserveMarkdownAndCode: self.settings.preserveMarkdownAndCode,
                    model: self.settings.model,
                    apiKey: self.settings.apiKey,
                    onChunk: { [weak viewModel] partial in
                        await MainActor.run {
                            viewModel?.geminiState = .ok(partial)
                        }
                    }
                )
                if Task.isCancelled { return }
                viewModel.geminiState = .ok(result.text)
                if let u = result.usage {
                    self.usage.record(model: self.settings.model,
                                      promptTokens: u.promptTokens,
                                      responseTokens: u.responseTokens)
                }
                if self.settings.cacheEnabled {
                    self.cache.set(cacheKey, geminiTranslation: result.text)
                }
                if !self.settings.privacyMode {
                    self.recordHistoryIfNeeded(translation: result.text, pair: pair, appHint: appHint)
                }
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
                let result = try await self.geminiClient.refine(
                    originalText: vm.originalText,
                    currentTranslation: snapshot,
                    instruction: instruction,
                    from: pair.sourceFull,
                    to: pair.targetFull,
                    context: self.settings.translatorContext,
                    glossary: self.glossary.formattedForPrompt(),
                    preserveMarkdownAndCode: self.settings.preserveMarkdownAndCode,
                    model: self.settings.model,
                    apiKey: self.settings.apiKey
                )
                if Task.isCancelled { vm.isRefining = false; return }
                vm.geminiState = .ok(result.text)
                vm.isRefining = false
                if let u = result.usage {
                    self.usage.record(model: self.settings.model,
                                      promptTokens: u.promptTokens,
                                      responseTokens: u.responseTokens)
                }
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
        guard let vm = currentViewModel, let pair = activeLangPair else { return }
        let cacheKey = cache.key(text: activeOriginal,
                                 source: pair.sourceShort,
                                 target: pair.targetShort,
                                 glossary: glossary.formattedForPrompt())
        vm.geminiState = .loading
        if vm.showDeepLPanel { vm.deepLState = .loading }
        startInitialTranslations(viewModel: vm, cacheKey: cacheKey)
    }

    private func saveEdit(_ edited: String) {
        guard let vm = currentViewModel,
              let pair = activeLangPair else { return }
        let originalTranslation = vm.geminiText
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)

        vm.geminiState = .ok(trimmed)
        vm.isEditing = false

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
