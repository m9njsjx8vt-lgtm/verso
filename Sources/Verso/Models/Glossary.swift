import Foundation
import Combine

struct GlossaryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var term: String
    var translation: String
    var preserveAsIs: Bool = false
    var notes: String = ""
    var addedAt: Date = Date()

    init(
        id: UUID = UUID(),
        term: String,
        translation: String,
        preserveAsIs: Bool = false,
        notes: String = "",
        addedAt: Date = Date()
    ) {
        self.id = id
        self.term = term
        self.translation = translation
        self.preserveAsIs = preserveAsIs
        self.notes = notes
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        term = try container.decode(String.self, forKey: .term)
        translation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        preserveAsIs = try container.decodeIfPresent(Bool.self, forKey: .preserveAsIs) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        addedAt = (try? container.decode(Date.self, forKey: .addedAt)) ?? Date()
    }
}

struct GlossaryImportResult {
    let added: Int
    let skipped: Int
}

@MainActor
final class Glossary: ObservableObject {
    @Published var entries: [GlossaryEntry] = [] {
        didSet { cachedFormattedPrompt = nil }
    }

    private var cachedFormattedPrompt: String?

    private let storeURL: URL = {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let support = applicationSupport
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

    @discardableResult
    func importEntries(_ imported: [GlossaryEntry], replacingExisting: Bool) -> GlossaryImportResult {
        var nextEntries = replacingExisting ? [] : entries
        let existingKeys = Set(replacingExisting ? [] : entries.map { Self.semanticKey(for: $0) })
        var importedKeys = Set<String>()
        var added = 0
        var skipped = 0

        for entry in imported {
            guard let normalized = Self.normalizedImportedEntry(entry) else {
                skipped += 1
                continue
            }

            let key = Self.semanticKey(for: normalized)
            guard !existingKeys.contains(key), !importedKeys.contains(key) else {
                skipped += 1
                continue
            }

            importedKeys.insert(key)
            nextEntries.append(normalized)
            added += 1
        }

        entries = nextEntries
        save()
        return GlossaryImportResult(added: added, skipped: skipped)
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

    private static func normalizedImportedEntry(_ entry: GlossaryEntry) -> GlossaryEntry? {
        let trimmedTerm = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = entry.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return nil }
        guard entry.preserveAsIs || !trimmedTranslation.isEmpty else { return nil }

        return GlossaryEntry(
            term: trimmedTerm,
            translation: entry.preserveAsIs ? "" : trimmedTranslation,
            preserveAsIs: entry.preserveAsIs,
            notes: trimmedNotes,
            addedAt: entry.addedAt
        )
    }

    private static func semanticKey(for entry: GlossaryEntry) -> String {
        [
            entry.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            entry.translation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            entry.preserveAsIs ? "preserve" : "translate",
            entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: "\u{1f}")
    }
}

extension Notification.Name {
    static let versoGlossarySaveFailed = Notification.Name("versoGlossarySaveFailed")
    static let versoLanguageChanged = Notification.Name("versoLanguageChanged")
}
