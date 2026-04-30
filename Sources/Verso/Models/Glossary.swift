import Foundation
import Combine

struct GlossaryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var term: String
    var translation: String
    var preserveAsIs: Bool = false
    var notes: String = ""
    var addedAt: Date = Date()
}

@MainActor
final class Glossary: ObservableObject {
    @Published var entries: [GlossaryEntry] = []

    private let storeURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Verso", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("glossary.json")
    }()

    init() {
        load()
    }

    func add(term: String, translation: String, preserveAsIs: Bool = false, notes: String = "") {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return }
        let entry = GlossaryEntry(
            term: trimmedTerm,
            translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
            preserveAsIs: preserveAsIs,
            notes: notes
        )
        entries.append(entry)
        save()
    }

    func remove(_ entry: GlossaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func update(_ entry: GlossaryEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
            save()
        }
    }

    /// Markdown-style block to inject into the LLM prompt
    func formattedForPrompt() -> String {
        guard !entries.isEmpty else { return "" }
        var lines: [String] = []
        for e in entries {
            if e.preserveAsIs {
                lines.append("- \"\(e.term)\" — preserve verbatim, do NOT translate")
            } else {
                lines.append("- \"\(e.term)\" ↔ \"\(e.translation)\"")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([GlossaryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            print("[glossary] save error: \(error)")
        }
    }
}
