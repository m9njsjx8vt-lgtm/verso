import AppKit
import SwiftUI

@MainActor
final class PopupController {
    private let settings: AppSettings
    private let glossary: Glossary
    private let history: HistoryStore
    private let usage: UsageTracker
    private let cache: TranslationCache
    private let network: NetworkMonitor
    private let geminiClient = GeminiClient()
    private let deepLClient = DeepLClient()
    private let tts = TTSService()
    private var window: PopupWindow?
    private var sourceApp: NSRunningApplication?
    private var currentViewModel: PopupViewModel?

    private var deepLTask: Task<Void, Never>?
    private var geminiTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var learnTask: Task<Void, Never>?
    private var altTask: Task<Void, Never>?
    private var furiganaTask: Task<Void, Never>?
    private var chatTask: Task<Void, Never>?

    private var activeLangPair: LanguageDetector.Pair?
    private var activeOriginal: String = ""
    private var historyRecorded: Bool = false

    /// Conversation context: prior (original, translation) pairs from same popup session.
    /// Only accumulated when settings.stayOpen is true.
    private var conversationHistory: [(original: String, translation: String)] = []

    init(settings: AppSettings, glossary: Glossary, history: HistoryStore,
         usage: UsageTracker, cache: TranslationCache, network: NetworkMonitor) {
        self.settings = settings
        self.glossary = glossary
        self.history = history
        self.usage = usage
        self.cache = cache
        self.network = network
    }

    func show(originalText: String, forceTarget: String? = nil) {
        sourceApp = NSWorkspace.shared.frontmostApplication

        // If pinned & previous popup exists with prior translation, push to conversation history
        if settings.stayOpen, let prevVM = currentViewModel, case .ok(let prevTrans) = prevVM.geminiState {
            conversationHistory.append((prevVM.originalText, prevTrans))
            // Cap at last 10 turns to avoid unbounded prompt growth
            if conversationHistory.count > 10 {
                conversationHistory = Array(conversationHistory.suffix(10))
            }
        } else if !settings.stayOpen {
            conversationHistory.removeAll()
        }

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

        close(restoreFocus: false, preserveConversation: settings.stayOpen)

        let viewModel = PopupViewModel(
            originalText: originalText,
            fromLang: pair.sourceShort,
            toLang: pair.targetShort,
            deepLConfigured: deepLConfigured,
            stayOpen: settings.stayOpen,
            privacyMode: settings.privacyMode,
            conversationDepth: conversationHistory.count,
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
            onChangeTarget: { [weak self] newTarget in
                self?.show(originalText: self?.activeOriginal ?? "", forceTarget: newTarget)
            },
            onTogglePin: { [weak self] in
                guard let self = self else { return }
                self.settings.stayOpen.toggle()
                self.currentViewModel?.stayOpen = self.settings.stayOpen
                if !self.settings.stayOpen { self.conversationHistory.removeAll() }
                self.currentViewModel?.showToast(self.settings.stayOpen ? "📌 ピン留めON (会話モード)" : "ピン解除")
            },
            onSpeak: { [weak self] text in
                guard let self = self, let pair = self.activeLangPair else { return }
                self.tts.speak(text, languageShort: pair.targetShort)
            },
            onTryWithPro: { [weak self] in self?.tryWithPro() },
            onFurigana: { [weak self] in self?.addFurigana() },
            onSendChat: { [weak self] question in self?.sendChat(question: question) },
            onClearChat: { [weak self] in
                self?.currentViewModel?.chatMessages.removeAll()
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

        // Offline guard
        if !network.isOnline {
            viewModel.geminiState = .failed("オフライン中。ネットワーク接続を確認してから Retry を押してください。")
            if deepLConfigured {
                viewModel.deepLState = .failed("オフライン中。")
            }
            return
        }

        let cacheKey = makeCacheKey(text: originalText, pair: pair)

        if settings.cacheEnabled, let entry = cache.get(cacheKey) {
            if let g = entry.geminiTranslation { viewModel.geminiState = .ok(g) }
            if let d = entry.deepLTranslation, deepLConfigured { viewModel.deepLState = .ok(d) }
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

        let extendedContext = activePromptContext()

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
                    context: extendedContext,
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

    private func buildConversationContextBlock() -> String {
        guard !conversationHistory.isEmpty else { return "" }
        var lines = ["## CONVERSATION SO FAR (use as context, do not re-translate)"]
        for (i, turn) in conversationHistory.enumerated() {
            lines.append("Turn \(i+1) — Original: \(turn.original)")
            lines.append("Turn \(i+1) — Translation: \(turn.translation)")
        }
        return lines.joined(separator: "\n")
    }

    private func activePromptContext() -> String {
        let conversationContext = settings.stayOpen ? buildConversationContextBlock() : nil
        return [settings.translatorContext, conversationContext]
            .compactMap { value in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty
                else { return nil }
                return value
            }
            .joined(separator: "\n\n")
    }

    private func makeCacheKey(text: String, pair: LanguageDetector.Pair) -> String {
        cache.key(
            text: text,
            source: pair.sourceShort,
            target: pair.targetShort,
            glossary: glossary.formattedForPrompt(),
            context: activePromptContext(),
            model: settings.model,
            preserveMarkdownAndCode: settings.preserveMarkdownAndCode
        )
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
        let cacheKey = makeCacheKey(text: activeOriginal, pair: pair)
        vm.geminiState = .loading
        if vm.showDeepLPanel { vm.deepLState = .loading }
        startInitialTranslations(viewModel: vm, cacheKey: cacheKey)
    }

    /// Re-translate using gemini-2.5-pro for higher quality
    private func tryWithPro() {
        guard let vm = currentViewModel, let pair = activeLangPair else { return }
        vm.isRefining = true
        vm.showToast("Pro モデルで再翻訳中…", duration: 2.0)

        altTask?.cancel()
        altTask = Task { @MainActor [weak self, weak vm] in
            guard let self = self, let vm = vm else { return }
            do {
                let result = try await self.geminiClient.translate(
                    text: vm.originalText,
                    from: pair.sourceFull,
                    to: pair.targetFull,
                    context: self.settings.translatorContext,
                    glossary: self.glossary.formattedForPrompt(),
                    sourceAppHint: self.sourceApp?.localizedName,
                    preserveMarkdownAndCode: self.settings.preserveMarkdownAndCode,
                    model: "gemini-2.5-pro",
                    apiKey: self.settings.apiKey
                )
                if Task.isCancelled { vm.isRefining = false; return }
                if vm.isGeminiOk {
                    vm.undoStack.append(vm.geminiText)
                }
                vm.geminiState = .ok(result.text)
                vm.isRefining = false
                vm.showToast("Pro モデル ✨ — Undo で元に戻せます")
                if let u = result.usage {
                    self.usage.record(model: "gemini-2.5-pro",
                                      promptTokens: u.promptTokens,
                                      responseTokens: u.responseTokens)
                }
            } catch {
                if Task.isCancelled { vm.isRefining = false; return }
                vm.isRefining = false
                vm.showToast("Pro 失敗: \(error.localizedDescription)", duration: 4.0)
            }
        }
    }

    /// Add furigana (kanji readings in parentheses) to a Japanese-target translation
    private func addFurigana() {
        guard let vm = currentViewModel, let pair = activeLangPair,
              pair.targetShort == "JA", vm.isGeminiOk else { return }
        let snapshot = vm.geminiText
        vm.isRefining = true

        furiganaTask?.cancel()
        furiganaTask = Task { @MainActor [weak self, weak vm] in
            guard let self = self, let vm = vm else { return }
            do {
                let prompt = """
                Annotate the following Japanese text with furigana for kanji.
                Format: 漢字(かんじ) — wrap each kanji or kanji compound with its reading in parentheses immediately after.
                Leave hiragana/katakana/ASCII unchanged.
                Output ONLY the annotated text, no explanation.

                ---
                \(snapshot)
                """
                let result = try await self.geminiClient.translate(
                    text: prompt,
                    from: "Japanese",
                    to: "Japanese (with furigana)",
                    context: nil,
                    glossary: nil,
                    sourceAppHint: nil,
                    preserveMarkdownAndCode: false,
                    model: self.settings.model,
                    apiKey: self.settings.apiKey
                )
                if Task.isCancelled { vm.isRefining = false; return }
                vm.undoStack.append(snapshot)
                vm.geminiState = .ok(result.text)
                vm.isRefining = false
                vm.showToast("ふりがな付与 — Undo で元に戻せます")
            } catch {
                if Task.isCancelled { vm.isRefining = false; return }
                vm.isRefining = false
                vm.showToast("ふりがな失敗: \(error.localizedDescription)", duration: 4.0)
            }
        }
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
        tts.stop()
        window?.persistCurrentSize()

        // In stay-open mode, don't close — just paste
        if settings.stayOpen {
            if let app = app {
                app.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    PasteService.sendCommandV()
                }
            }
            return
        }

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

    func close(restoreFocus: Bool, preserveConversation: Bool = false) {
        let app = sourceApp
        cancelAllTasks()
        tts.stop()
        if let vm = currentViewModel { vm.isRefining = false }
        window?.persistCurrentSize()
        window?.orderOut(nil)
        window = nil
        currentViewModel = nil
        if !preserveConversation {
            conversationHistory.removeAll()
        }
        if restoreFocus, let app = app { app.activate() }
    }

    /// Send a follow-up question to the LLM about the current translation.
    private func sendChat(question: String) {
        guard let vm = currentViewModel, vm.isGeminiOk,
              let pair = activeLangPair else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        vm.chatMessages.append(ChatMessage(role: .user, content: trimmed))
        vm.chatInput = ""
        vm.isChatThinking = true

        let priorMessages = Array(vm.chatMessages.dropLast())
        let translation = vm.geminiText

        chatTask?.cancel()
        chatTask = Task { @MainActor [weak self, weak vm] in
            guard let self = self, let vm = vm else { return }
            do {
                let result = try await self.geminiClient.chatAboutTranslation(
                    originalText: vm.originalText,
                    translation: translation,
                    sourceLang: pair.sourceFull,
                    targetLang: pair.targetFull,
                    priorMessages: priorMessages,
                    newQuestion: trimmed,
                    model: self.settings.model,
                    apiKey: self.settings.apiKey
                )
                if Task.isCancelled { vm.isChatThinking = false; return }
                vm.chatMessages.append(ChatMessage(role: .assistant, content: result.text))
                vm.isChatThinking = false
                if let u = result.usage {
                    self.usage.record(model: self.settings.model,
                                      promptTokens: u.promptTokens,
                                      responseTokens: u.responseTokens)
                }
            } catch {
                if Task.isCancelled { vm.isChatThinking = false; return }
                vm.chatMessages.append(ChatMessage(role: .assistant,
                                                   content: "⚠️ \(error.localizedDescription)"))
                vm.isChatThinking = false
            }
        }
    }

    private func cancelAllTasks() {
        deepLTask?.cancel(); deepLTask = nil
        geminiTask?.cancel(); geminiTask = nil
        refineTask?.cancel(); refineTask = nil
        learnTask?.cancel(); learnTask = nil
        altTask?.cancel(); altTask = nil
        furiganaTask?.cancel(); furiganaTask = nil
        chatTask?.cancel(); chatTask = nil
    }
}
