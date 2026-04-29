import SwiftUI

@MainActor
final class PopupViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ok
        case error(String)
    }

    @Published var originalText: String
    @Published var translation: String = ""
    @Published var state: State = .loading

    let fromLang: String
    let toLang: String

    let onInsert: (String) -> Void
    let onCopy: (String) -> Void
    let onClose: () -> Void

    init(
        originalText: String,
        fromLang: String,
        toLang: String,
        onInsert: @escaping (String) -> Void,
        onCopy: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.originalText = originalText
        self.fromLang = fromLang
        self.toLang = toLang
        self.onInsert = onInsert
        self.onCopy = onCopy
        self.onClose = onClose
    }

    var isOk: Bool {
        if case .ok = state { return true }
        return false
    }
}

struct PopupView: View {
    @ObservedObject var viewModel: PopupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(headerText)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(headerColor)
                Spacer()
                Text("Esc で閉じる")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Original text panel
            ScrollView {
                Text(viewModel.originalText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 110)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // Translation / loading / error panel
            translationPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                )

            // Actions
            HStack(spacing: 6) {
                Button(action: insertAction) {
                    HStack(spacing: 4) {
                        Text("↩ 挿入")
                        Text("↵").font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.isOk)
                .keyboardShortcut(.defaultAction)

                Button(action: copyAction) {
                    Text("📋 コピー")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!viewModel.isOk)

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
        .padding(14)
        .frame(width: 540, height: 380)
    }

    @ViewBuilder
    private var translationPanel: some View {
        switch viewModel.state {
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        case .ok:
            ScrollView {
                Text(viewModel.translation)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }

        case .error(let msg):
            ScrollView {
                Text("⚠️ \(msg)")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
    }

    private func insertAction() {
        if case .ok = viewModel.state {
            viewModel.onInsert(viewModel.translation)
        }
    }

    private func copyAction() {
        if case .ok = viewModel.state {
            viewModel.onCopy(viewModel.translation)
        }
    }

    private var headerText: String {
        switch viewModel.state {
        case .loading: return "TRANSLATING…"
        case .error: return "ERROR"
        case .ok: return "\(viewModel.fromLang)  →  \(viewModel.toLang)"
        }
    }

    private var headerColor: Color {
        if case .error = viewModel.state { return .red }
        return .secondary
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
                ? Color(NSColor.tertiarySystemFill)
                : Color(NSColor.controlBackgroundColor))
            .foregroundColor(.primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )
    }
}
