import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    @State private var query: String = ""
    @State private var selectedID: HistoryEntry.ID?

    let onInsert: (String) -> Void
    let onClose: () -> Void

    private var filtered: [HistoryEntry] {
        history.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header / search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search past translations…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(filtered.count) / \(history.entries.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // List
            if filtered.isEmpty {
                emptyState
            } else {
                List(selection: $selectedID) {
                    ForEach(filtered) { entry in
                        HistoryRow(entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Insert into source") {
                                    onInsert(entry.translation)
                                }
                                Button("Copy translation") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.translation, forType: .string)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    history.remove(entry)
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer
            HStack {
                Button("Clear All", role: .destructive) {
                    history.clear()
                }
                .disabled(history.entries.isEmpty)
                Spacer()
                if let id = selectedID, let entry = filtered.first(where: { $0.id == id }) {
                    Button {
                        onInsert(entry.translation)
                    } label: {
                        Label("Insert", systemImage: "return")
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.translation, forType: .string)
                    }
                }
                Button("Close") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 500, idealHeight: 600)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(query.isEmpty ? "No translations yet" : "No matches")
                .font(.headline)
                .foregroundColor(.secondary)
            if query.isEmpty {
                Text("Translations are saved automatically when you use ⌘C×2.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(entry.sourceLang) → \(entry.targetLang)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(0.5)
                    .foregroundColor(.accentColor)
                if let app = entry.sourceApp {
                    Text("·  \(app)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(entry.sourceText)
                .font(.callout)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text(entry.translation)
                .font(.body)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}
