import Foundation
import Combine

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var sourceLang: String
    var targetLang: String
    var sourceText: String
    var translation: String
    var sourceApp: String?
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private let maxEntries = 1000

    private let storeURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Verso", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("history.json")
    }()

    init() {
        load()
    }

    func record(
        sourceLang: String,
        targetLang: String,
        sourceText: String,
        translation: String,
        sourceApp: String?
    ) {
        let normalizedSource = normalize(sourceText)
        let normalizedTranslation = normalize(translation)
        guard !normalizedSource.isEmpty, !normalizedTranslation.isEmpty else { return }

        let entry = HistoryEntry(
            sourceLang: sourceLang,
            targetLang: targetLang,
            sourceText: normalizedSource,
            translation: normalizedTranslation,
            sourceApp: sourceApp
        )
        entries.removeAll {
            $0.sourceLang == sourceLang
                && $0.targetLang == targetLang
                && normalize($0.sourceText) == normalizedSource
                && normalize($0.translation) == normalizedTranslation
        }
        entries.insert(entry, at: 0)
        trimToLimit()
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func search(_ query: String) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return entries }
        return entries.filter {
            $0.sourceText.lowercased().contains(q)
                || $0.translation.lowercased().contains(q)
                || $0.sourceLang.lowercased().contains(q)
                || $0.targetLang.lowercased().contains(q)
                || ($0.sourceApp?.lowercased().contains(q) ?? false)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
        trimToLimit()
        if entries.count != decoded.count {
            save()
        }
    }

    private func trimToLimit() {
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            print("[history] save error: \(error)")
        }
    }
}
