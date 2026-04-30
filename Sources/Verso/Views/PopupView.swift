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
    /// Refines push the previous translation here so user can ⌘Z back.
    @Published var undoStack: [String] = []
    /// In-place editing of the Gemini translation
    @Published var isEditing: Bool = false
    @Published var editDraft: String = ""
    /// Brief toast message (auto-clears)
    @Published var toast: String?

    let fromLang: String
    let toLang: String

    let onInsert: (String) -> Void
    let onCopy: (String) -> Void
    let onClose: () -> Void
    let onRefine: (String) -> Void
    let onAddGlossary: (String, String, Bool) -> Void
    let onUndo: () -> Void
    let onRetry: () -> Void
    let onSaveEdit: (String) -> Void

    init(
        originalText: String,
        fromLang: String,
        toLang: String,
        deepLConfigured: Bool,
        onInsert: @escaping (String) -> Void,
        onCopy: @escaping (String) -> Void,
        onClose: @escaping () -> Void,
        onRefine: @escaping (String) -> Void,
        onAddGlossary: @escaping (String, String, Bool) -> Void,
        onUndo: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onSaveEdit: @escaping (String) -> Void
    ) {
        self.originalText = originalText
        self.fromLang = fromLang
        self.toLang = toLang
        self.deepLState = deepLConfigured ? .loading : .notConfigured
        self.onInsert = onInsert
        self.onCopy = onCopy
        self.onClose = onClose
        self.onRefine = onRefine
        self.onAddGlossary = onAddGlossary
        self.onUndo = onUndo
        self.onRetry = onRetry
        self.onSaveEdit = onSaveEdit
    }

    var primaryInsertText: String {
        if case .ok(let t) = geminiState { return t }
        if case .ok(let t) = deepLState { return t }
        return ""
    }

    var hasAnyTranslation: Bool {
        if case .ok = geminiState { return true }
        if case .ok = deepLState { return true }
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

    var showDeepLPanel: Bool {
        deepLState != .notConfigured
    }

    var canUndo: Bool {
        !undoStack.isEmpty && !isRefining
    }

    func showToast(_ message: String, duration: TimeInterval = 2.5) {
        toast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self?.toast == message {
                self?.toast = nil
            }
        }
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
                originalPanel
                if viewModel.showDeepLPanel {
                    providerPanel(
                        title: "DeepL",
                        icon: "bolt.fill",
                        color: .blue,
                        state: viewModel.deepLState,
                        isCompact: true,
                        editable: false
                    )
                }
                providerPanel(
                    title: viewModel.isRefining ? "Gemini  •  REFINING…" : "Gemini",
                    icon: "sparkles",
                    color: .purple,
                    state: viewModel.geminiState,
                    isCompact: false,
                    editable: true
                )
                if viewModel.isGeminiOk && !viewModel.isEditing {
                    refineBar
                }
                actionBar
            }
            .padding(16)

            // Toast overlay
            if let toast = viewModel.toast {
                Text(toast)
                    .font(.callout)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toast)
        .frame(
            minWidth: 500,
            idealWidth: 720,
            maxWidth: .infinity,
            minHeight: 380,
            idealHeight: viewModel.showDeepLPanel ? 580 : 480,
            maxHeight: .infinity
        )
        .background(keyboardShortcuts)
    }

    // Hidden buttons to register keyboard shortcuts
    private var keyboardShortcuts: some View {
        ZStack {
            if viewModel.canUndo {
                Button("") { viewModel.onUndo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .opacity(0)
            }
            if viewModel.isGeminiOk && !viewModel.isEditing {
                Button("") { viewModel.onRefine("Make the translation shorter and more concise while preserving meaning.") }
                    .keyboardShortcut("1", modifiers: .command).opacity(0)
                Button("") { viewModel.onRefine("Make the translation more casual and conversational.") }
                    .keyboardShortcut("2", modifiers: .command).opacity(0)
                Button("") { viewModel.onRefine("Make the translation more formal and polite.") }
                    .keyboardShortcut("3", modifiers: .command).opacity(0)
                Button("") { viewModel.onRefine("Provide an alternative translation with different word choices.") }
                    .keyboardShortcut("4", modifiers: .command).opacity(0)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("\(viewModel.fromLang)  →  \(viewModel.toLang)")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1.0)
                .foregroundColor(.secondary)
            Spacer()
            Text("⤡ ドラッグで拡縮  •  Esc で閉じる")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Original

    private var originalPanel: some View {
        ScrollView {
            Text(viewModel.originalText)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 90)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Provider panel

    @ViewBuilder
    private func providerPanel(
        title: String,
        icon: String,
        color: Color,
        state: PopupViewModel.ProviderState,
        isCompact: Bool,
        editable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                    .fontWeight(.bold)
                Text(title.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.8)
                    .foregroundColor(color)
                if case .loading = state {
                    ProgressView().controlSize(.mini)
                }
                Spacer()

                if case .failed = state {
                    Button(action: viewModel.onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                // Edit toggle (only Gemini)
                if editable, case .ok = state, !viewModel.isEditing, !viewModel.isRefining {
                    Button {
                        viewModel.editDraft = viewModel.geminiText
                        viewModel.isEditing = true
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Edit the translation; Verso will learn the corrections.")
                }
            }

            Group {
                switch state {
                case .notConfigured:
                    EmptyView()

                case .loading:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("translating…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                case .ok(let text):
                    if editable && viewModel.isEditing {
                        editor
                    } else {
                        ScrollView {
                            Text(text)
                                .font(isCompact ? .callout : .body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .textSelection(.enabled)
                        }
                    }

                case .failed(let msg):
                    ScrollView {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isCompact ? 110 : .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1.5)
            )
        }
    }

    // MARK: - Inline edit editor

    private var editor: some View {
        VStack(spacing: 6) {
            TextEditor(text: $viewModel.editDraft)
                .font(.body)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                )
            HStack {
                Text("修正内容から用語を学習します。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") {
                    viewModel.isEditing = false
                }
                .controlSize(.small)
                Button("Save & Learn") {
                    viewModel.onSaveEdit(viewModel.editDraft)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(8)
    }

    // MARK: - Refine bar

    private var refineBar: some View {
        HStack(spacing: 6) {
            if viewModel.isRefining {
                ProgressView().controlSize(.small)
            }
            Button { viewModel.onRefine("Make the translation shorter and more concise while preserving meaning.") } label: {
                Label("短く", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .help("⌘1 — shorter")

            Button { viewModel.onRefine("Make the translation more casual and conversational.") } label: {
                Label("砕け", systemImage: "bubble.left")
            }
            .help("⌘2 — casual")

            Button { viewModel.onRefine("Make the translation more formal and polite.") } label: {
                Label("丁寧", systemImage: "person.crop.circle.badge.checkmark")
            }
            .help("⌘3 — formal")

            Button { viewModel.onRefine("Provide an alternative translation with different word choices.") } label: {
                Label("別案", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("⌘4 — alternative")

            if viewModel.canUndo {
                Button { viewModel.onUndo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .help("⌘Z — revert refine")
            }

            Spacer()

            Button {
                newTerm = ""
                newTrans = ""
                newPreserve = false
                showGlossaryPopover = true
            } label: {
                Label("用語追加", systemImage: "book.closed.fill")
            }
            .popover(isPresented: $showGlossaryPopover, arrowEdge: .top) {
                addGlossaryPopover
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(viewModel.isRefining)
    }

    private var addGlossaryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glossaryに追加").font(.headline)
            Text("ここで登録した用語は今後すべての翻訳プロンプトに注入されます。")
                .font(.caption)
                .foregroundColor(.secondary)

            Group {
                Text("Term").font(.caption).foregroundColor(.secondary)
                TextField("例: DXPP, EARTHBRAIN", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Preserve as-is (固有名詞・訳さない)", isOn: $newPreserve)
                .controlSize(.small)

            if !newPreserve {
                Group {
                    Text("Translation").font(.caption).foregroundColor(.secondary)
                    TextField("例: Digital Transformation Performance Platform", text: $newTrans)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("キャンセル") { showGlossaryPopover = false }
                    .keyboardShortcut(.cancelAction)
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
        .padding(16)
        .frame(width: 380)
        .onDisappear {
            newTerm = ""; newTrans = ""; newPreserve = false
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button(action: insertAction) {
                HStack(spacing: 4) {
                    Image(systemName: "return")
                    Text(insertLabel)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.hasAnyTranslation || viewModel.isEditing)
            .keyboardShortcut(.defaultAction)

            Button(action: copyAction) {
                Label("コピー", systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.hasAnyTranslation || viewModel.isEditing)

            Button(action: viewModel.onClose) {
                Label("閉じる", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var insertLabel: String {
        if case .ok = viewModel.geminiState { return "挿入 (Gemini)" }
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
