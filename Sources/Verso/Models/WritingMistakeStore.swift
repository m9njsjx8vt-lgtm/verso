import Combine
import Foundation

enum WritingCorrectionParseError: LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        "添削結果を読み取れませんでした。もう一度試してください。"
    }
}

struct WritingCorrectionIssue: Codable, Hashable {
    var category: String
    var before: String
    var after: String
    var explanation: String
    var pattern: String

    init(
        category: String = "other",
        before: String,
        after: String,
        explanation: String = "",
        pattern: String = ""
    ) {
        self.category = Self.clean(category).isEmpty ? "other" : Self.clean(category)
        self.before = Self.clean(before)
        self.after = Self.clean(after)
        self.explanation = Self.clean(explanation)
        self.pattern = Self.clean(pattern)
    }

    var semanticKey: String {
        [
            category.lowercased(),
            pattern.lowercased(),
            before.lowercased(),
            after.lowercased()
        ].joined(separator: "\u{1f}")
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WritingCorrectionResult: Hashable {
    var correctedText: String
    var mistakes: [WritingCorrectionIssue]

    static func parse(from output: String, fallbackText: String? = nil) throws -> WritingCorrectionResult {
        let jsonText = extractJSONObject(from: output)
        guard let data = jsonText.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw WritingCorrectionParseError.invalidJSON
        }

        let corrected = stringValue(
            from: dict,
            keys: ["correctedText", "corrected_text", "corrected", "text"]
        )
        let fallback = fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let correctedText = corrected.isEmpty ? fallback : corrected
        guard !correctedText.isEmpty else {
            throw WritingCorrectionParseError.invalidJSON
        }

        let rawMistakes = (dict["mistakes"] as? [[String: Any]])
            ?? (dict["issues"] as? [[String: Any]])
            ?? (dict["corrections"] as? [[String: Any]])
            ?? []

        var seen = Set<String>()
        let mistakes = rawMistakes.compactMap { raw -> WritingCorrectionIssue? in
            let before = stringValue(from: raw, keys: ["before", "original", "from"])
            let after = stringValue(from: raw, keys: ["after", "corrected", "to"])
            guard !before.isEmpty || !after.isEmpty else { return nil }

            let issue = WritingCorrectionIssue(
                category: stringValue(from: raw, keys: ["category", "type"]),
                before: before,
                after: after,
                explanation: stringValue(from: raw, keys: ["explanation", "reason", "note"]),
                pattern: stringValue(from: raw, keys: ["pattern", "rule", "habit"])
            )
            guard seen.insert(issue.semanticKey).inserted else { return nil }
            return issue
        }

        return WritingCorrectionResult(correctedText: correctedText, mistakes: mistakes)
    }

    private static func extractJSONObject(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: .newlines)
            lines.removeFirst()
            if let last = lines.last,
               last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                lines.removeLast()
            }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let first = text.firstIndex(of: "{"),
           let last = text.lastIndex(of: "}"),
           first <= last {
            return String(text[first...last])
        }
        return text
    }

    private static func stringValue(from dict: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }
}

struct WritingMistakeObservation: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var sourceText: String
    var correctedText: String
    var category: String
    var before: String
    var after: String
    var explanation: String
    var pattern: String
    var sourceApp: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        sourceText: String,
        correctedText: String,
        issue: WritingCorrectionIssue,
        sourceApp: String?
    ) {
        self.id = id
        self.date = date
        self.sourceText = sourceText
        self.correctedText = correctedText
        self.category = issue.category
        self.before = issue.before
        self.after = issue.after
        self.explanation = issue.explanation
        self.pattern = issue.pattern
        self.sourceApp = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = (try? container.decode(Date.self, forKey: .date)) ?? Date()
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
        correctedText = try container.decodeIfPresent(String.self, forKey: .correctedText) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "other"
        before = try container.decodeIfPresent(String.self, forKey: .before) ?? ""
        after = try container.decodeIfPresent(String.self, forKey: .after) ?? ""
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
    }

    var categoryLabel: String {
        WritingMistakeSummary.categoryLabel(for: category)
    }
}

struct WritingMistakeSummary: Identifiable, Hashable {
    var id: String
    var category: String
    var pattern: String
    var count: Int
    var latestAt: Date
    var sampleBefore: String
    var sampleAfter: String
    var sampleExplanation: String

    var categoryLabel: String {
        Self.categoryLabel(for: category)
    }

    var title: String {
        pattern.isEmpty ? categoryLabel : pattern
    }

    static func categoryLabel(for raw: String) -> String {
        switch raw.lowercased() {
        case "articles", "article":
            return "冠詞"
        case "prepositions", "preposition":
            return "前置詞"
        case "tense":
            return "時制"
        case "agreement":
            return "主語と動詞"
        case "word choice", "word_choice", "vocabulary":
            return "単語選び"
        case "punctuation":
            return "句読点"
        case "capitalization":
            return "大文字小文字"
        case "clarity":
            return "明確さ"
        case "grammar":
            return "文法"
        default:
            return raw.isEmpty ? "その他" : raw
        }
    }
}

@MainActor
final class WritingMistakeStore: ObservableObject {
    @Published private(set) var entries: [WritingMistakeObservation] = []

    private let maxEntries = 500
    private let storeURL: URL = {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let support = applicationSupport
            .appendingPathComponent("Verso", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("writing_mistakes.json")
    }()

    init() {
        load()
    }

    @discardableResult
    func record(
        sourceText: String,
        correctedText: String,
        issues: [WritingCorrectionIssue],
        sourceApp: String?
    ) -> Int {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !corrected.isEmpty else { return 0 }

        var seen = Set<String>()
        let newEntries = issues.compactMap { issue -> WritingMistakeObservation? in
            guard !issue.before.isEmpty || !issue.after.isEmpty else { return nil }
            guard seen.insert(issue.semanticKey).inserted else { return nil }
            return WritingMistakeObservation(
                sourceText: source,
                correctedText: corrected,
                issue: issue,
                sourceApp: sourceApp
            )
        }
        guard !newEntries.isEmpty else { return 0 }

        entries.append(contentsOf: newEntries)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        save()
        return newEntries.count
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func summaries(limit: Int = 20) -> [WritingMistakeSummary] {
        let groups = Dictionary(grouping: entries) { entry in
            summaryKey(for: entry)
        }

        return groups.compactMap { key, observations in
            guard let latest = observations.max(by: { $0.date < $1.date }) else {
                return nil
            }
            return WritingMistakeSummary(
                id: key,
                category: latest.category,
                pattern: latest.pattern,
                count: observations.count,
                latestAt: latest.date,
                sampleBefore: latest.before,
                sampleAfter: latest.after,
                sampleExplanation: latest.explanation
            )
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.latestAt > $1.latestAt
        }
        .prefix(limit)
        .map { $0 }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([WritingMistakeObservation].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            print("[writing-mistakes] save error: \(error)")
        }
    }

    private func summaryKey(for entry: WritingMistakeObservation) -> String {
        let pattern = entry.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !pattern.isEmpty {
            return "\(entry.category.lowercased())|\(pattern)"
        }
        return [
            entry.category.lowercased(),
            entry.before.lowercased(),
            entry.after.lowercased()
        ].joined(separator: "|")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
