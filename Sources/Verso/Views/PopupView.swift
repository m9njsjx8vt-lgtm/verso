import SwiftUI

@MainActor
final class PopupViewModel: ObservableObject {
    enum ProviderState: Equatable {
        case notConfigured
        case loading
        case ok(String)
        case failed(String)
    }

    @Published var originalText: String
    @Published var deepLState: ProviderState
    @Published var geminiState: ProviderState = .loading
    @Published var isRefining: Bool = false
    @Published var undoStack: [String] = []
    @Published var isEditing: Bool = false
    @Published var editDraft: String = ""
    @Published var toast: String?
    @Published var stayOpen: Bool
    @Published var privacyMode: Bool
    @Published var conversationDepth: Int
    @Published var aiProviderTitle: String
    @Published var aiProviderIcon: String
    @Published var allowsCloudPro: Bool
    @Published var canStartLocalAIServer: Bool
    @Published var localAIStartButtonTitle: String
    @Published var showsAIResult: Bool
    @Published var writingSummaries: [WritingMistakeSummary]
    @Published var writingObservationCount: Int

    let deepLConfigured: Bool

    // --- Grammar chat state ---
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatInput: String = ""
    @Published var isChatExpanded: Bool = false
    @Published var isChatThinking: Bool = false

    let fromLang: String
    let toLang: String

    let onInsert: (String) -> Void
    let onCopy: (String) -> Void
    let onClose: () -> Void
    let onRefine: (String) -> Void
    let onCorrectOwnWriting: () -> Void
    let onAddGlossary: (String, String, Bool) -> Void
    let onUndo: () -> Void
    let onRetry: () -> Void
    let onSaveEdit: (String) -> Void
    let onChangeTarget: (String) -> Void
    let onTogglePin: () -> Void
    let onSpeak: (String) -> Void
    let onTryWithPro: () -> Void
    let onFurigana: () -> Void
    let onSendChat: (String) -> Void
    let onClearChat: () -> Void
    let onOpenSettings: () -> Void
    let onStartLocalAIServer: () -> Void

    init(
        originalText: String, fromLang: String, toLang: String,
        deepLConfigured: Bool, stayOpen: Bool, privacyMode: Bool,
        conversationDepth: Int,
        aiProviderTitle: String,
        aiProviderIcon: String,
        allowsCloudPro: Bool,
        canStartLocalAIServer: Bool,
        localAIStartButtonTitle: String,
        showAIResult: Bool,
        showDeepLResult: Bool,
        writingSummaries: [WritingMistakeSummary],
        writingObservationCount: Int,
        onInsert: @escaping (String) -> Void,
        onCopy: @escaping (String) -> Void,
        onClose: @escaping () -> Void,
        onRefine: @escaping (String) -> Void,
        onCorrectOwnWriting: @escaping () -> Void,
        onAddGlossary: @escaping (String, String, Bool) -> Void,
        onUndo: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onSaveEdit: @escaping (String) -> Void,
        onChangeTarget: @escaping (String) -> Void,
        onTogglePin: @escaping () -> Void,
        onSpeak: @escaping (String) -> Void,
        onTryWithPro: @escaping () -> Void,
        onFurigana: @escaping () -> Void,
        onSendChat: @escaping (String) -> Void,
        onClearChat: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onStartLocalAIServer: @escaping () -> Void
    ) {
        self.originalText = originalText
        self.fromLang = fromLang
        self.toLang = toLang
        self.deepLConfigured = deepLConfigured
        self.deepLState = deepLConfigured && showDeepLResult ? .loading : .notConfigured
        self.stayOpen = stayOpen
        self.privacyMode = privacyMode
        self.conversationDepth = conversationDepth
        self.aiProviderTitle = aiProviderTitle
        self.aiProviderIcon = aiProviderIcon
        self.allowsCloudPro = allowsCloudPro
        self.canStartLocalAIServer = canStartLocalAIServer
        self.localAIStartButtonTitle = localAIStartButtonTitle
        self.showsAIResult = showAIResult
        self.writingSummaries = writingSummaries
        self.writingObservationCount = writingObservationCount
        self.onInsert = onInsert
        self.onCopy = onCopy
        self.onClose = onClose
        self.onRefine = onRefine
        self.onCorrectOwnWriting = onCorrectOwnWriting
        self.onAddGlossary = onAddGlossary
        self.onUndo = onUndo
        self.onRetry = onRetry
        self.onSaveEdit = onSaveEdit
        self.onChangeTarget = onChangeTarget
        self.onTogglePin = onTogglePin
        self.onSpeak = onSpeak
        self.onTryWithPro = onTryWithPro
        self.onFurigana = onFurigana
        self.onSendChat = onSendChat
        self.onClearChat = onClearChat
        self.onOpenSettings = onOpenSettings
        self.onStartLocalAIServer = onStartLocalAIServer
    }

    var primaryInsertText: String {
        if showsAIResult, case .ok(let t) = geminiState { return t }
        if showDeepLPanel, case .ok(let t) = deepLState { return t }
        if case .ok(let t) = geminiState { return t }
        if case .ok(let t) = deepLState { return t }
        return ""
    }

    var hasAnyTranslation: Bool {
        if showsAIResult, case .ok = geminiState { return true }
        if showDeepLPanel, case .ok = deepLState { return true }
        return false
    }

    var isGeminiOk: Bool {
        if case .ok = geminiState { return true }
        return false
    }

    var geminiText: String {
        if case .ok(let t) = geminiState { return t }
        return ""
    }

    var showDeepLPanel: Bool { deepLState != .notConfigured }
    var showAIPanel: Bool { showsAIResult }
    var canUndo: Bool { !undoStack.isEmpty && !isRefining }
    var canCorrectOwnWriting: Bool { fromLang == "EN" }

    var isAILoading: Bool {
        if case .loading = geminiState { return true }
        return false
    }

    func showToast(_ message: String, duration: TimeInterval = 2.5) {
        toast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self?.toast == message { self?.toast = nil }
        }
    }

    func updateAITranslation(_ text: String) {
        geminiState = .ok(text)
    }

    func updateWritingInsights(summaries: [WritingMistakeSummary], observationCount: Int) {
        writingSummaries = summaries
        writingObservationCount = observationCount
    }
}

struct PopupView: View {
    @ObservedObject var viewModel: PopupViewModel

    @State private var showGlossaryPopover = false
    @State private var newTerm: String = ""
    @State private var newTrans: String = ""
    @State private var newPreserve: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                header
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        originalPanel
                        primaryResultPanel
                        if viewModel.showAIPanel && viewModel.isGeminiOk && !viewModel.isEditing { refineBar }
                        if viewModel.showAIPanel && viewModel.isChatExpanded && viewModel.isGeminiOk { chatPanel }
                        actionBar
                    }
                    .frame(minWidth: 440, maxWidth: .infinity, alignment: .topLeading)

                    Divider()
                        .frame(maxHeight: .infinity)

                    writingLensPanel
                        .frame(width: 240, alignment: .top)
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            if let toast = viewModel.toast {
                Text(toast).font(.callout).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.85)).cornerRadius(8)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toast)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isChatExpanded)
        .frame(minWidth: 740, idealWidth: 900, maxWidth: .infinity,
               minHeight: 400,
               idealHeight: viewModel.isChatExpanded ? 740 : idealPopupHeight,
               maxHeight: .infinity)
        .background(keyboardShortcuts)
    }

    private var idealPopupHeight: CGFloat {
        switch (viewModel.showDeepLPanel, viewModel.showAIPanel) {
        case (true, true): return 560
        case (true, false): return 460
        case (false, true): return 520
        case (false, false): return 400
        }
    }

    private var keyboardShortcuts: some View {
        ZStack {
            if viewModel.canUndo {
                Button("") { viewModel.onUndo() }.keyboardShortcut("z", modifiers: .command).opacity(0)
            }
            if viewModel.showAIPanel && viewModel.isGeminiOk && !viewModel.isEditing {
                Button("") { viewModel.onRefine("Make the translation shorter and more concise while preserving meaning.") }
                    .keyboardShortcut("1", modifiers: .command).opacity(0)
                Button("") { viewModel.onRefine("Make the translation more casual and conversational.") }
                    .keyboardShortcut("2", modifiers: .command).opacity(0)
                Button("") { viewModel.onRefine("Make the translation more formal and polite.") }
                    .keyboardShortcut("3", modifiers: .command).opacity(0)
                Button("") { viewModel.onRefine("Provide an alternative translation with different word choices.") }
                    .keyboardShortcut("4", modifiers: .command).opacity(0)
                if viewModel.canCorrectOwnWriting {
                    Button("") { viewModel.onCorrectOwnWriting() }
                        .keyboardShortcut("5", modifiers: .command).opacity(0)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(viewModel.fromLang).font(.caption).fontWeight(.semibold).tracking(1.0).foregroundColor(.secondary)
                .padding(.leading, 28)
            Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)

            Menu {
                ForEach(LanguageDetector.availableTargets, id: \.short) { lang in
                    Button { viewModel.onChangeTarget(lang.short) } label: {
                        if lang.short == viewModel.toLang {
                            Label("\(lang.short)  \(lang.fullName)", systemImage: "checkmark")
                        } else {
                            Text("\(lang.short)  \(lang.fullName)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(viewModel.toLang).font(.caption).fontWeight(.semibold).tracking(1.0)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundColor(.accentColor)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            if viewModel.conversationDepth > 0 {
                Text("·  会話 \(viewModel.conversationDepth) 往復")
                    .font(.caption2).foregroundColor(.accentColor.opacity(0.8))
            }

            Spacer()

            if viewModel.privacyMode {
                Image(systemName: "lock.fill").foregroundColor(.orange).font(.caption2)
                    .help("Privacy mode: not saved to history")
            }
            Button { viewModel.onTogglePin() } label: {
                Image(systemName: viewModel.stayOpen ? "pin.fill" : "pin")
                    .foregroundColor(viewModel.stayOpen ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(viewModel.stayOpen ? "📌 Pinned (会話モード)" : "Pin to keep open")

            Text(viewModel.stayOpen ? "📌 会話モード" : "Esc で閉じる")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Original

    private var originalPanel: some View {
        ScrollView {
            Text(viewModel.originalText).font(.callout).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12).textSelection(.enabled)
        }
        .frame(maxHeight: 90)
        .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(NSColor.separatorColor), lineWidth: 1))
    }

    // MARK: - Provider panel

    private var primaryResultPanel: some View {
        providerPanel(
            title: primaryResultTitle,
            icon: primaryResultIcon,
            color: primaryResultColor,
            state: primaryResultState,
            isCompact: false,
            editable: viewModel.showAIPanel
        )
    }

    private var primaryResultTitle: String {
        let provider = viewModel.showAIPanel ? viewModel.aiProviderTitle : "DeepL"
        if viewModel.isRefining {
            return "\(provider)  •  Working"
        }
        return provider
    }

    private var primaryResultIcon: String {
        viewModel.showAIPanel ? viewModel.aiProviderIcon : "bolt.fill"
    }

    private var primaryResultColor: Color {
        guard viewModel.showAIPanel else { return .blue }
        return viewModel.aiProviderTitle == "Local AI" ? .green : .purple
    }

    private var primaryResultState: PopupViewModel.ProviderState {
        viewModel.showAIPanel ? viewModel.geminiState : viewModel.deepLState
    }

    @ViewBuilder
    private func providerPanel(
        title: String, icon: String, color: Color,
        state: PopupViewModel.ProviderState, isCompact: Bool, editable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(color).font(.caption).fontWeight(.bold)
                Text(title.uppercased()).font(.caption2).fontWeight(.bold).tracking(0.8).foregroundColor(color)
                if case .loading = state { ProgressView().controlSize(.mini) }
                Spacer()

                if case .ok(let text) = state, !viewModel.isEditing {
                    Button { viewModel.onSpeak(text) } label: { Image(systemName: "speaker.wave.2.fill") }
                        .buttonStyle(.borderless).controlSize(.small).help("読み上げ")
                }

                if case .failed = state {
                    if editable && viewModel.canStartLocalAIServer {
                        Button(action: viewModel.onStartLocalAIServer) {
                            Label(viewModel.localAIStartButtonTitle, systemImage: "play.circle")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help("Start the selected local AI server and retry")
                    }

                    Button(action: viewModel.onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless).controlSize(.small)

                    if editable {
                        Button(action: viewModel.onOpenSettings) {
                            Label("Settings", systemImage: "gearshape").labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help("AI Engine, Endpoint, Model, and API keys")
                    }
                }

                if editable, case .ok = state, !viewModel.isEditing, !viewModel.isRefining {
                    Button {
                        viewModel.editDraft = viewModel.geminiText
                        viewModel.isEditing = true
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                    .help("Edit; Verso will learn from corrections")
                }
            }

            Group {
                switch state {
                case .notConfigured: EmptyView()
                case .loading:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("translating…").font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
                case .ok(let text):
                    if editable && viewModel.isEditing { editor }
                    else {
                        ScrollView {
                            Text(text).font(isCompact ? .callout : .body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).textSelection(.enabled)
                        }
                    }
                case .failed(let msg):
                    ScrollView {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text(msg).font(.caption).foregroundColor(.primary).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isCompact ? 110 : .infinity)
            .background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.4), lineWidth: 1.5))
        }
    }

    // MARK: - Writing Lens

    private var writingLensPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("WRITING LENS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.8)
                    .foregroundColor(.green)
                Spacer()
            }

            writingActionCard
            writingStatsCard

            if viewModel.showAIPanel && viewModel.showDeepLPanel {
                deepLPreviewCard
            }

            engineStatusCard
        }
    }

    private var writingActionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("自分の英文")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                viewModel.onCorrectOwnWriting()
            } label: {
                Label("添削して記録", systemImage: "text.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!viewModel.showAIPanel || !viewModel.canCorrectOwnWriting
                      || viewModel.isRefining || viewModel.isAILoading)
            .help("自分が書いた英文だけを直して、ミス傾向に追加します")

            Text(writingActionHint)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.green.opacity(0.35), lineWidth: 1))
    }

    private var writingActionHint: String {
        if !viewModel.showAIPanel {
            return "AI結果を表示している時に使えます。"
        }
        if !viewModel.canCorrectOwnWriting {
            return "英文を選択した時だけ記録します。"
        }
        if viewModel.privacyMode {
            return "Privacy mode 中は記録しません。"
        }
        return "よくあるミスを自動で蓄積します。"
    }

    private var writingStatsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statPill(title: "記録", value: "\(viewModel.writingObservationCount)")
                statPill(title: "傾向", value: "\(viewModel.writingSummaries.count)")
            }

            if viewModel.writingSummaries.isEmpty {
                Text("まだ傾向はありません。添削を使うとここに出ます。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.writingSummaries.prefix(3)) { summary in
                        writingSummaryRow(summary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(NSColor.separatorColor), lineWidth: 1))
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    private func writingSummaryRow(_ summary: WritingMistakeSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(summary.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(summary.count)回")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text("\(summary.sampleBefore) → \(summary.sampleAfter)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var deepLPreviewCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.blue)
                Text("DEEPL PREVIEW")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.7)
                    .foregroundColor(.blue)
                Spacer()
            }

            switch viewModel.deepLState {
            case .notConfigured:
                EmptyView()
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("previewing…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            case .ok(let text):
                Text(text)
                    .font(.caption)
                    .lineLimit(5)
                    .textSelection(.enabled)
            case .failed(let message):
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.blue.opacity(0.25), lineWidth: 1))
    }

    private var engineStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(viewModel.aiProviderTitle, systemImage: viewModel.aiProviderIcon)
                .font(.caption)
                .foregroundColor(viewModel.aiProviderTitle == "Local AI" ? .green : .purple)
            Label(viewModel.privacyMode ? "履歴保存なし" : "履歴保存あり", systemImage: viewModel.privacyMode ? "lock.fill" : "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundColor(.secondary)
            if viewModel.deepLConfigured && !viewModel.showDeepLPanel {
                Label("DeepL非表示", systemImage: "eye.slash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(NSColor.separatorColor), lineWidth: 1))
    }

    private var editor: some View {
        VStack(spacing: 6) {
            TextEditor(text: $viewModel.editDraft).font(.body).padding(8)
                .background(Color(NSColor.textBackgroundColor)).cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
            HStack {
                Text("修正内容から用語を学習します。").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { viewModel.isEditing = false }.controlSize(.small)
                Button("Save & Learn") { viewModel.onSaveEdit(viewModel.editDraft) }
                    .buttonStyle(.borderedProminent).controlSize(.small).keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(8)
    }

    private var refineBar: some View {
        HStack(spacing: 6) {
            if viewModel.isRefining { ProgressView().controlSize(.small) }
            Button { viewModel.onRefine("Make the translation shorter and more concise while preserving meaning.") }
                label: { Label("短く", systemImage: "arrow.down.right.and.arrow.up.left").fixedSize() }
                .help("⌘1 — shorter")
            Button { viewModel.onRefine("Make the translation more casual and conversational.") }
                label: { Label("砕け", systemImage: "bubble.left").fixedSize() }
                .help("⌘2 — casual")
            Button { viewModel.onRefine("Make the translation more formal and polite.") }
                label: { Label("丁寧", systemImage: "person.crop.circle.badge.checkmark").fixedSize() }
                .help("⌘3 — formal")
            Button { viewModel.onRefine("Provide an alternative translation with different word choices.") }
                label: { Label("別案", systemImage: "arrow.triangle.2.circlepath").fixedSize() }
                .help("⌘4 — alternative")
            Button {
                viewModel.isChatExpanded.toggle()
            } label: {
                Label("解説",
                      systemImage: viewModel.isChatExpanded ? "bubble.left.and.bubble.right.fill"
                                                            : "bubble.left.and.bubble.right")
                    .fixedSize()
            }
            .help("文法・ニュアンスを質問する")
            if viewModel.canUndo {
                Button { viewModel.onUndo() }
                    label: { Label("Undo", systemImage: "arrow.uturn.backward").labelStyle(.iconOnly) }
                    .help("元に戻す (⌘Z)")
            }

            Spacer()

            Button {
                newTerm = ""; newTrans = ""; newPreserve = false; showGlossaryPopover = true
            } label: { Label("用語追加", systemImage: "book.closed.fill").labelStyle(.iconOnly) }
                .help("用語をGlossaryに追加")
                .popover(isPresented: $showGlossaryPopover, arrowEdge: .top) { addGlossaryPopover }

            if viewModel.allowsCloudPro || viewModel.toLang == "JA" {
                Menu {
                    if viewModel.allowsCloudPro {
                        Button { viewModel.onTryWithPro() }
                            label: { Label("Proモデルで再翻訳", systemImage: "star.fill") }
                    }
                    if viewModel.toLang == "JA" {
                        Button { viewModel.onFurigana() }
                            label: { Label("ふりがなを付ける", systemImage: "character.book.closed.fill") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("その他の操作")
            }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(viewModel.isRefining)
    }

    // MARK: - Chat panel (grammar / nuance Q&A)

    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.accentColor).font(.caption).fontWeight(.bold)
                Text("ASK ABOUT THIS TRANSLATION")
                    .font(.caption2).fontWeight(.bold).tracking(0.8).foregroundColor(.accentColor)
                if viewModel.isChatThinking { ProgressView().controlSize(.mini) }
                Spacer()
                if !viewModel.chatMessages.isEmpty {
                    Button { viewModel.onClearChat() } label: {
                        Label("Clear", systemImage: "trash").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless).controlSize(.small).help("Clear chat")
                }
            }

            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if viewModel.chatMessages.isEmpty {
                            Text("例:  「なぜ have to ではなく must なの？」 / 「もっと自然な言い方は？」 / 「文化的なニュアンスは？」")
                                .font(.caption).foregroundColor(.secondary)
                                .padding(8)
                        }
                        ForEach(viewModel.chatMessages) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1))
                .onChange(of: viewModel.chatMessages.count) { _ in
                    if let last = viewModel.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Input row
            HStack(spacing: 6) {
                TextField("質問を入力 (例: なぜこの表現？)", text: $viewModel.chatInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit { sendChatIfReady() }
                Button {
                    sendChatIfReady()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.chatInput.trimmingCharacters(in: .whitespaces).isEmpty
                       || viewModel.isChatThinking)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (⌘↵)")
            }
        }
    }

    private func chatBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if msg.role == .assistant {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple).font(.caption2)
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 24)
            }
            Text(msg.content)
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(msg.role == .user
                            ? Color.accentColor.opacity(0.15)
                            : Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
            if msg.role == .user {
                Image(systemName: "person.fill")
                    .foregroundColor(.accentColor).font(.caption2)
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 24)
            }
        }
    }

    private func sendChatIfReady() {
        let q = viewModel.chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !viewModel.isChatThinking else { return }
        viewModel.onSendChat(q)
    }

    private var addGlossaryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glossaryに追加").font(.headline)
            Text("ここで登録した用語は今後すべての翻訳プロンプトに注入されます。")
                .font(.caption).foregroundColor(.secondary)
            Group {
                Text("Term").font(.caption).foregroundColor(.secondary)
                TextField("例: DXPP, EARTHBRAIN", text: $newTerm).textFieldStyle(.roundedBorder)
            }
            Toggle("Preserve as-is (固有名詞・訳さない)", isOn: $newPreserve).controlSize(.small)
            if !newPreserve {
                Group {
                    Text("Translation").font(.caption).foregroundColor(.secondary)
                    TextField("例: Digital Transformation Performance Platform", text: $newTrans)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Button("キャンセル") { showGlossaryPopover = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("追加") {
                    viewModel.onAddGlossary(newTerm, newTrans, newPreserve)
                    showGlossaryPopover = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty
                    || (!newPreserve && newTrans.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(16).frame(width: 380)
        .onDisappear { newTerm = ""; newTrans = ""; newPreserve = false }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button(action: insertAction) {
                HStack(spacing: 4) {
                    Image(systemName: "return")
                    Text(insertLabel)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!viewModel.hasAnyTranslation || viewModel.isEditing)
            .keyboardShortcut(.defaultAction)

            Button(action: copyAction) {
                Label("コピー", systemImage: "doc.on.doc").labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(!viewModel.hasAnyTranslation || viewModel.isEditing)

            Button(action: viewModel.onClose) {
                Label("閉じる", systemImage: "xmark").labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered).controlSize(.large).keyboardShortcut(.cancelAction)
        }
    }

    private var insertLabel: String {
        if viewModel.showAIPanel, case .ok = viewModel.geminiState { return "挿入 (\(viewModel.aiProviderTitle))" }
        if viewModel.showDeepLPanel, case .ok = viewModel.deepLState { return "挿入 (DeepL)" }
        if case .ok = viewModel.geminiState { return "挿入 (\(viewModel.aiProviderTitle))" }
        if case .ok = viewModel.deepLState { return "挿入 (DeepL)" }
        return "挿入"
    }

    private func insertAction() {
        let text = viewModel.primaryInsertText
        guard !text.isEmpty else { return }
        viewModel.onInsert(text)
    }

    private func copyAction() {
        let text = viewModel.primaryInsertText
        guard !text.isEmpty else { return }
        viewModel.onCopy(text)
    }
}
