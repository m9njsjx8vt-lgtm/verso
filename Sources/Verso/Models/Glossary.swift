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
    @Published var entries: [GlossaryEntry] = [] {
        didSet { cachedFormattedPrompt = nil }
    }

    private var cachedFormattedPrompt: String?

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

    /// Markdown-style block to inject into the LLM prompt. Cached for re-use.
    func formattedForPrompt() -> String {
        if let cached = cachedFormattedPrompt { return cached }
        guard !entries.isEmpty else {
            cachedFormattedPrompt = ""
            return ""
        }
        var lines: [String] = []
        for e in entries {
            if e.preserveAsIs {
                lines.append("- Term \"\(e.term)\" — preserve verbatim, do NOT translate or modify.")
            } else {
                lines.append("- Term \"\(e.term)\" → translate as \"\(e.translation)\" (do not use alternatives).")
            }
        }
        let result = lines.joined(separator: "\n")
        cachedFormattedPrompt = result
        return result
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([GlossaryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        cachedFormattedPrompt = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            // Surface to user via NotificationCenter so SwiftUI can show alert
            print("[glossary] save error: \(error)")
            NotificationCenter.default.post(
                name: .versoGlossarySaveFailed,
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
        }
    }
}

extension Notification.Name {
    static let versoGlossarySaveFailed = Notification.Name("versoGlossarySaveFailed")
}
