import SwiftUI

struct GlossaryView: View {
    @ObservedObject var glossary: Glossary

    @State private var newTerm: String = ""
    @State private var newTranslation: String = ""
    @State private var newPreserveAsIs: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glossary")
                .font(.headline)
            Text("登録した用語は毎回プロンプトに自動注入されます。固有名詞、ブランド名、好みの訳語をここに集約。")
                .font(.caption)
                .foregroundColor(.secondary)

            // Add row
            VStack(spacing: 8) {
                HStack {
                    TextField("Term (例: DXPP, EARTHBRAIN)", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                    Text("↔")
                        .foregroundColor(.secondary)
                    TextField(
                        newPreserveAsIs ? "(preserve as-is)" : "Translation (例: Digital Transformation Performance Platform)",
                        text: $newTranslation
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(newPreserveAsIs)
                }
                HStack {
                    Toggle("Preserve as-is (固有名詞・訳さない)", isOn: $newPreserveAsIs)
                        .controlSize(.small)
                    Spacer()
                    Button("Add") { addEntry() }
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty
                            || (!newPreserveAsIs && newTranslation.trimmingCharacters(in: .whitespaces).isEmpty))
                        .keyboardShortcut(.return)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(NSColor.separatorColor))
            )

            Divider()

            // Entry list
            if glossary.entries.isEmpty {
                Spacer()
                Text("まだ登録なし。\n上のフォーム or 翻訳ポップアップの「📚 用語追加」から追加できます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(glossary.entries) { entry in
                            GlossaryRow(entry: entry, glossary: glossary)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func addEntry() {
        glossary.add(
            term: newTerm,
            translation: newTranslation,
            preserveAsIs: newPreserveAsIs
        )
        newTerm = ""
        newTranslation = ""
        newPreserveAsIs = false
    }
}

private struct GlossaryRow: View {
    let entry: GlossaryEntry
    @ObservedObject var glossary: Glossary

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.term)
                .fontWeight(.medium)
                .lineLimit(1)
            if entry.preserveAsIs {
                Text("preserve as-is")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            } else {
                Text("↔")
                    .foregroundColor(.secondary)
                Text(entry.translation)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { glossary.remove(entry) }) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
}
