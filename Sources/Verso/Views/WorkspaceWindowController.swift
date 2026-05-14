import AppKit
import SwiftUI

/// Persistent translator workspace — a regular (non-popup) window that lets you
/// type or paste text, hit ⌘↵, and see the translation. Stays open across
/// translations. Does NOT auto-dismiss like the ⌘C×2 popup.
@MainActor
final class WorkspaceWindowController {
    private let popupController: PopupController
    private var window: NSWindow?
    private let viewModel: WorkspaceViewModel

    init(popupController: PopupController) {
        self.popupController = popupController
        self.viewModel = WorkspaceViewModel(popupController: popupController)
    }

    func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        let view = WorkspaceView(viewModel: viewModel)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = L10n.workspaceTitle
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 540, height: 360))
        win.center()
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 460, height: 300)
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
    @Published var lastInsertedAt: Date?
    private let popupController: PopupController

    init(popupController: PopupController) {
        self.popupController = popupController
    }

    func translate(forceTarget: String? = nil) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        popupController.show(originalText: trimmed, forceTarget: forceTarget)
    }

    func clear() {
        inputText = ""
    }

    func loadFromClipboard() {
        if let s = NSPasteboard.general.string(forType: .string), !s.isEmpty {
            inputText = s
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @State private var selectedTarget: String = "auto"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "character.bubble.fill")
                    .foregroundColor(.accentColor)
                Text(L10n.workspaceTitle)
                    .font(.headline)
                Spacer()

                // Optional target language override
                Menu {
                    Button {
                        selectedTarget = "auto"
                    } label: {
                        if selectedTarget == "auto" {
                            Label(L10n.t("Auto", "自動"), systemImage: "checkmark")
                        } else { Text(L10n.t("Auto", "自動")) }
                    }
                    Divider()
                    ForEach(LanguageDetector.availableTargets, id: \.short) { lang in
                        Button {
                            selectedTarget = lang.short
                        } label: {
                            if selectedTarget == lang.short {
                                Label("\(lang.short)  \(lang.fullName)", systemImage: "checkmark")
                            } else {
                                Text("\(lang.short)  \(lang.fullName)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(L10n.t("→ \(selectedTarget == "auto" ? "Auto" : selectedTarget)",
                                    "→ \(selectedTarget == "auto" ? "自動" : selectedTarget)"))
                            .font(.caption).fontWeight(.semibold)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }

            // Input area
            ZStack(alignment: .topLeading) {
                if viewModel.inputText.isEmpty {
                    Text(L10n.workspaceInputPlaceholder)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
                TextEditor(text: $viewModel.inputText)
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
            .frame(minHeight: 120, maxHeight: .infinity)

            // Action row
            HStack {
                Button {
                    viewModel.loadFromClipboard()
                } label: {
                    Label(L10n.t("Paste", "ペースト"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .help("⌘⇧V — paste from clipboard")

                Button {
                    viewModel.clear()
                } label: {
                    Label(L10n.workspaceClearBtn, systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.inputText.isEmpty)

                Spacer()

                Button {
                    let target = selectedTarget == "auto" ? nil : selectedTarget
                    viewModel.translate(forceTarget: target)
                } label: {
                    Label(L10n.workspaceTranslateBtn, systemImage: "sparkles")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Help text
            Text(L10n.t(
                "Translation appears in the floating popup. This window stays open so you can keep translating without re-typing.",
                "翻訳結果はフロート ポップアップに表示されます。このウィンドウは開いたままなので、続けて翻訳できます。"
            ))
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(16)
    }
}
