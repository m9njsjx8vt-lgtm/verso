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

    let fromLang: String
    let toLang: String

    let onInsert: (String) -> Void
    let onCopy: (String) -> Void
    let onClose: () -> Void
    let onRefine: (String) -> Void
    let onAddGlossary: (String, String, Bool) -> Void

    init(
        originalText: String,
        fromLang: String,
        toLang: String,
        deepLConfigured: Bool,
        onInsert: @escaping (String) -> Void,
        onCopy: @escaping (String) -> Void,
        onClose: @escaping () -> Void,
        onRefine: @escaping (String) -> Void,
        onAddGlossary: @escaping (String, String, Bool) -> Void
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
    }

    /// Best available translation: Gemini > DeepL.
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
}

struct PopupView: View {
    @ObservedObject var viewModel: PopupViewModel

    @State private var showGlossaryPopover = false
    @State private var newTerm: String = ""
    @State private var newTrans: String = ""
    @State private var newPreserve: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            originalPanel
            if viewModel.showDeepLPanel {
                providerPanel(
                    title: "DeepL",
                    icon: "bolt.fill",
                    color: Color(red: 0.07, green: 0.45, blue: 0.95),  // DeepL blue
                    state: viewModel.deepLState,
                    isCompact: true
                )
            }
            providerPanel(
                title: viewModel.isRefining ? "Gemini  •  REFINING…" : "Gemini",
                icon: "sparkles",
                color: Color(red: 0.55, green: 0.20, blue: 0.85),  // Gemini purple
                state: viewModel.geminiState,
                isCompact: false
            )
            if viewModel.isGeminiOk {
                refineBar
            }
            actionBar
        }
        .padding(14)
        .frame(
            minWidth: 500,
            idealWidth: 720,
            maxWidth: .infinity,
            minHeight: 380,
            idealHeight: viewModel.showDeepLPanel ? 560 : 460,
            maxHeight: .infinity
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("\(viewModel.fromLang)  →  \(viewModel.toLang)")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.secondary)
            Spacer()
            Text("⤡ ドラッグで拡縮  •  Esc で閉じる")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Original

    private var originalPanel: some View {
        ScrollView {
            Text(viewModel.originalText)
                .font(.system(size: 13))
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

    // MARK: - Provider panel (DeepL or Gemini)

    @ViewBuilder
    private func providerPanel(
        title: String,
        icon: String,
        color: Color,
        state: PopupViewModel.ProviderState,
        isCompact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 11, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(color)
                if case .loading = state {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
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
                    ScrollView {
                        Text(text)
                            .font(.system(size: isCompact ? 14 : 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .textSelection(.enabled)
                    }

                case .failed(let msg):
                    Text("⚠️ \(msg)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
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

    // MARK: - Refine bar

    private var refineBar: some View {
        HStack(spacing: 6) {
            if viewModel.isRefining {
                ProgressView().controlSize(.small)
            }
            Button("🔁 短く") {
                viewModel.onRefine("Make the translation shorter and more concise while preserving meaning.")
            }
            Button("🔁 砕け") {
                viewModel.onRefine("Make the translation more casual and conversational.")
            }
            Button("🔁 丁寧") {
                viewModel.onRefine("Make the translation more formal and polite.")
            }
            Button("🔁 別案") {
                viewModel.onRefine("Provide an alternative translation with different word choices.")
            }
            Spacer()
            Button("📚 用語追加") {
                newTerm = ""
                newTrans = ""
                newPreserve = false
                showGlossaryPopover = true
            }
            .popover(isPresented: $showGlossaryPopover, arrowEdge: .top) {
                addGlossaryPopover
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
        .disabled(viewModel.isRefining)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button(action: insertAction) {
                HStack(spacing: 4) {
                    Text(insertLabel)
                    Text("↵").font(.system(size: 10))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.hasAnyTranslation)
            .keyboardShortcut(.defaultAction)

            Button(action: copyAction) {
                Text("📋 コピー")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!viewModel.hasAnyTranslation)

            Button(action: viewModel.onClose) {
                HStack(spacing: 4) {
                    Text("閉じる")
                    Text("Esc").font(.system(size: 10))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
    }

    private var insertLabel: String {
        if case .ok = viewModel.geminiState { return "↩ 挿入 (Gemini)" }
        if case .ok = viewModel.deepLState { return "↩ 挿入 (DeepL)" }
        return "↩ 挿入"
    }

    // MARK: - Add to glossary popover

    private var addGlossaryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glossaryに追加")
                .font(.headline)
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

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed
                ? Color.accentColor.opacity(0.7)
                : Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed
                ? Color.gray.opacity(0.2)
                : Color(NSColor.controlBackgroundColor))
            .foregroundColor(.primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )
    }
}
