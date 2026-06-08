import AppKit
import SwiftUI

/// Persistent translator workspace: a normal macOS window for longer text,
/// iterative edits, and result copying without relying on the floating popup.
@MainActor
final class WorkspaceWindowController {
    private var window: NSWindow?
    private let viewModel: WorkspaceViewModel
    private let settings: AppSettings

    init(
        popupController: PopupController,
        settings: AppSettings,
        glossary: Glossary,
        history: HistoryStore,
        usage: UsageTracker,
        cache: TranslationCache,
        network: NetworkMonitor
    ) {
        self.settings = settings
        self.viewModel = WorkspaceViewModel(
            popupController: popupController,
            settings: settings,
            glossary: glossary,
            history: history,
            usage: usage,
            cache: cache,
            network: network
        )
    }

    func show(text: String? = nil, forceTarget: String? = nil, translateImmediately: Bool = false) {
        if let text, !text.isEmpty {
            viewModel.setInput(text, forceTarget: forceTarget, translateImmediately: translateImmediately)
        } else if let forceTarget {
            viewModel.setTarget(forceTarget)
        }

        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        let view = WorkspaceView(viewModel: viewModel, settings: settings)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = L10n.workspaceTitle
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 920, height: 560))
        win.center()
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 720, height: 420)
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }
}

@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var resultText: String = ""
    @Published var selectedTarget: String = "auto"
    @Published var statusText: String = ""
    @Published var errorText: String?
    @Published var isTranslating: Bool = false
    @Published var sourceTargetSummary: String = ""

    private let popupController: PopupController
    private let settings: AppSettings
    private let glossary: Glossary
    private let history: HistoryStore
    private let usage: UsageTracker
    private let cache: TranslationCache
    private let network: NetworkMonitor
    private let geminiClient = GeminiClient()
    private let localAIClient = LocalAIClient()
    private var translateTask: Task<Void, Never>?

    init(
        popupController: PopupController,
        settings: AppSettings,
        glossary: Glossary,
        history: HistoryStore,
        usage: UsageTracker,
        cache: TranslationCache,
        network: NetworkMonitor
    ) {
        self.popupController = popupController
        self.settings = settings
        self.glossary = glossary
        self.history = history
        self.usage = usage
        self.cache = cache
        self.network = network
    }

    func setInput(_ text: String, forceTarget: String? = nil, translateImmediately: Bool = false) {
        inputText = text
        if let forceTarget {
            setTarget(forceTarget)
        }
        if translateImmediately {
            translate()
        }
    }

    func setTarget(_ target: String) {
        let normalized = target.uppercased()
        if LanguageDetector.availableTargets.contains(where: { $0.short == normalized }) {
            selectedTarget = normalized
        }
    }

    func translate() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        translateTask?.cancel()
        errorText = nil
        resultText = ""

        guard settings.usesLocalAI || network.isOnline else {
            errorText = GeminiError.offline.localizedDescription
            statusText = ""
            return
        }

        let forceTarget = selectedTarget == "auto" ? nil : selectedTarget
        let pair = LanguageDetector.detect(
            text,
            defaultTargetForEnglish: settings.targetWhenEnglish,
            defaultTargetForOther: settings.targetWhenOther,
            forceTargetShort: forceTarget
        )
        sourceTargetSummary = "\(pair.sourceShort) → \(pair.targetShort)"

        let context = settings.promptContext()
        let glossaryPrompt = glossary.formattedForPrompt()
        let cacheKey = cache.key(
            text: text,
            source: pair.sourceShort,
            target: pair.targetShort,
            glossary: glossaryPrompt,
            context: context,
            model: settings.activeModelKey,
            preserveMarkdownAndCode: settings.preserveMarkdownAndCode
        )

        if settings.cacheEnabled,
           let cached = cache.get(cacheKey)?.geminiTranslation,
           !cached.isEmpty {
            resultText = cached
            statusText = "Cache · \(settings.primaryProviderTitle) · \(sourceTargetSummary)"
            recordHistory(sourceText: text, translation: cached, pair: pair)
            return
        }

        isTranslating = true
        statusText = "Translating · \(settings.primaryProviderTitle) · \(sourceTargetSummary)"

        translateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isTranslating = false }
            do {
                let result: (text: String, usage: GeminiUsage?)
                if self.settings.usesLocalAI {
                    result = try await self.localAIClient.translateStreaming(
                        text: text,
                        from: pair.sourceFull,
                        to: pair.targetFull,
                        context: context,
                        glossary: glossaryPrompt,
                        sourceAppHint: "Verso Workspace",
                        preserveMarkdownAndCode: self.settings.preserveMarkdownAndCode,
                        backend: self.settings.selectedLocalAIBackend,
                        endpoint: self.settings.localAIEndpoint,
                        model: self.settings.localAIModel,
                        onChunk: { [weak self] partial in
                            await MainActor.run {
                                guard let self, !Task.isCancelled else { return }
                                self.resultText = partial
                                self.statusText = "Translating · \(self.settings.primaryProviderTitle) · \(self.sourceTargetSummary)"
                            }
                        }
                    )
                } else {
                    result = try await self.geminiClient.translateStreaming(
                        text: text,
                        from: pair.sourceFull,
                        to: pair.targetFull,
                        context: context,
                        glossary: glossaryPrompt,
                        sourceAppHint: "Verso Workspace",
                        preserveMarkdownAndCode: self.settings.preserveMarkdownAndCode,
                        model: self.settings.model,
                        apiKey: self.settings.apiKey,
                        onChunk: { [weak self] partial in
                            await MainActor.run {
                                guard let self, !Task.isCancelled else { return }
                                self.resultText = partial
                                self.statusText = "Translating · \(self.settings.primaryProviderTitle) · \(self.sourceTargetSummary)"
                            }
                        }
                    )
                }
                if Task.isCancelled { return }

                self.resultText = result.text
                self.statusText = "Done · \(self.settings.primaryProviderTitle) · \(self.sourceTargetSummary)"
                if let u = result.usage {
                    self.usage.record(
                        model: self.settings.activeModelKey,
                        promptTokens: u.promptTokens,
                        responseTokens: u.responseTokens
                    )
                }
                if self.settings.cacheEnabled {
                    self.cache.set(cacheKey, geminiTranslation: result.text)
                }
                self.recordHistory(sourceText: text, translation: result.text, pair: pair)
            } catch is CancellationError {
                self.statusText = "Cancelled"
            } catch {
                if Task.isCancelled { return }
                self.errorText = error.localizedDescription
                self.statusText = ""
            }
        }
    }

    func cancelTranslation() {
        translateTask?.cancel()
        translateTask = nil
        isTranslating = false
        statusText = "Cancelled"
    }

    func clear() {
        cancelTranslation()
        inputText = ""
        resultText = ""
        statusText = ""
        errorText = nil
        sourceTargetSummary = ""
    }

    func loadFromClipboard() {
        if let s = NSPasteboard.general.string(forType: .string), !s.isEmpty {
            inputText = s
            errorText = nil
        } else {
            NSSound.beep()
        }
    }

    func copyResult() {
        let text = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = "Copied"
    }

    func useResultAsInput() {
        let text = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = text
        resultText = ""
        errorText = nil
        statusText = ""
        sourceTargetSummary = ""
    }

    func openPopupForInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        popupController.show(originalText: text, forceTarget: selectedTarget == "auto" ? nil : selectedTarget)
    }

    private func recordHistory(
        sourceText: String,
        translation: String,
        pair: LanguageDetector.Pair
    ) {
        guard !settings.privacyMode,
              !sourceText.isEmpty,
              !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        history.record(
            sourceLang: pair.sourceShort,
            targetLang: pair.targetShort,
            sourceText: sourceText,
            translation: translation,
            sourceApp: "Verso Workspace"
        )
    }
}

struct WorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 12) {
                textPane(
                    title: L10n.t("Source", "原文"),
                    placeholder: L10n.workspaceInputPlaceholder,
                    text: $viewModel.inputText
                )

                textPane(
                    title: L10n.t("Result", "結果"),
                    placeholder: L10n.t("Translation result", "翻訳結果"),
                    text: $viewModel.resultText
                )
            }

            statusRow
            actions
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(L10n.workspaceTitle, systemImage: "character.bubble.fill")
                .font(.headline)
                .foregroundColor(.primary)

            if !viewModel.sourceTargetSummary.isEmpty {
                Text(viewModel.sourceTargetSummary)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }

            Spacer()
            styleMenu
            targetMenu
        }
    }

    private var styleMenu: some View {
        Menu {
            ForEach(TranslationStyle.allCases) { style in
                Button {
                    settings.translationStyle = style.rawValue
                } label: {
                    if settings.translationStyle == style.rawValue {
                        Label(style.title, systemImage: "checkmark")
                    } else {
                        Text(style.title)
                    }
                }
            }
        } label: {
            Label(settings.selectedTranslationStyle.title, systemImage: "slider.horizontal.3")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var targetMenu: some View {
        Menu {
            Button {
                viewModel.selectedTarget = "auto"
            } label: {
                if viewModel.selectedTarget == "auto" {
                    Label(L10n.t("Auto", "自動"), systemImage: "checkmark")
                } else {
                    Text(L10n.t("Auto", "自動"))
                }
            }
            Divider()
            ForEach(LanguageDetector.availableTargets, id: \.short) { lang in
                Button {
                    viewModel.selectedTarget = lang.short
                } label: {
                    if viewModel.selectedTarget == lang.short {
                        Label("\(lang.short)  \(lang.fullName)", systemImage: "checkmark")
                    } else {
                        Text("\(lang.short)  \(lang.fullName)")
                    }
                }
            }
        } label: {
            Label(targetTitle, systemImage: "arrow.right.circle")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var targetTitle: String {
        viewModel.selectedTarget == "auto"
            ? L10n.t("Auto", "自動")
            : viewModel.selectedTarget
    }

    private func textPane(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
                TextEditor(text: text)
                    .font(.body)
                    .padding(8)
                    .scrollContentBackground(.hidden)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .frame(minHeight: 300, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if viewModel.isTranslating {
                ProgressView()
                    .controlSize(.small)
            }

            if let error = viewModel.errorText, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text(settings.selectedTranslationStyle.subtitle)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .font(.caption)
        .frame(minHeight: 18)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.loadFromClipboard()
            } label: {
                Label(L10n.t("Paste", "ペースト"), systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button {
                viewModel.clear()
            } label: {
                Label(L10n.workspaceClearBtn, systemImage: "trash")
            }
            .disabled(viewModel.inputText.isEmpty && viewModel.resultText.isEmpty)

            Button {
                viewModel.useResultAsInput()
            } label: {
                Label(L10n.t("Use Result", "結果を原文へ"), systemImage: "arrow.uturn.left")
            }
            .disabled(viewModel.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            if viewModel.isTranslating {
                Button {
                    viewModel.cancelTranslation()
                } label: {
                    Label(L10n.t("Cancel", "キャンセル"), systemImage: "xmark")
                }
            }

            Button {
                viewModel.copyResult()
            } label: {
                Label(L10n.t("Copy Result", "結果をコピー"), systemImage: "doc.on.doc")
            }
            .disabled(viewModel.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                viewModel.openPopupForInput()
            } label: {
                Label(L10n.t("Popup", "ポップアップ"), systemImage: "rectangle.on.rectangle")
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                viewModel.translate()
            } label: {
                Label(L10n.workspaceTranslateBtn, systemImage: "sparkles")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isTranslating)
        }
        .buttonStyle(.bordered)
    }
}
