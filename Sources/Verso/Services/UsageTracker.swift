import Foundation
import Combine

struct UsageRecord: Codable {
    var date: Date
    var model: String
    var promptTokens: Int
    var responseTokens: Int
}

/// Persistent token + cost tracker. Stores per-day rollups in
/// ~/Library/Application Support/Verso/usage.json.
@MainActor
final class UsageTracker: ObservableObject {
    @Published private(set) var records: [UsageRecord] = []

    /// Approximate Gemini pricing (paid tier, USD per 1M tokens).
    /// Free tier shows the same numbers as a "what you would pay" indicator.
    private static let pricing: [String: (input: Double, output: Double)] = [
        "gemini-2.5-flash-lite": (0.075, 0.30),
        "gemini-2.5-flash":      (0.30,  2.50),
        "gemini-2.5-pro":        (1.25, 10.00),
    ]

    private let storeURL: URL = {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let support = applicationSupport
            .appendingPathComponent("Verso", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("usage.json")
    }()

    init() {
        load()
    }

    func record(model: String, promptTokens: Int, responseTokens: Int) {
        records.append(UsageRecord(
            date: Date(),
            model: model,
            promptTokens: promptTokens,
            responseTokens: responseTokens
        ))
        // Cap at last 10000 records to keep file size bounded
        if records.count > 10_000 {
            records = Array(records.suffix(10_000))
        }
        save()
    }

    func cost(for record: UsageRecord) -> Double {
        let prices = Self.pricing[record.model] ?? (0.5, 2.0)
        return Double(record.promptTokens) / 1_000_000 * prices.input
            + Double(record.responseTokens) / 1_000_000 * prices.output
    }

    func todayStats() -> (calls: Int, tokens: Int, cost: Double) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todays = records.filter { cal.isDate($0.date, inSameDayAs: today) }
        let tokens = todays.reduce(0) { $0 + $1.promptTokens + $1.responseTokens }
        let costSum = todays.reduce(0.0) { $0 + cost(for: $1) }
        return (todays.count, tokens, costSum)
    }

    func monthStats() -> (calls: Int, tokens: Int, cost: Double) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        let start = cal.date(from: comps) ?? Date()
        let monthly = records.filter { $0.date >= start }
        let tokens = monthly.reduce(0) { $0 + $1.promptTokens + $1.responseTokens }
        let costSum = monthly.reduce(0.0) { $0 + cost(for: $1) }
        return (monthly.count, tokens, costSum)
    }

    func allTimeStats() -> (calls: Int, tokens: Int, cost: Double) {
        let tokens = records.reduce(0) { $0 + $1.promptTokens + $1.responseTokens }
        let costSum = records.reduce(0.0) { $0 + cost(for: $1) }
        return (records.count, tokens, costSum)
    }

    func clear() {
        records.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([UsageRecord].self, from: data))
            ?? (try? JSONDecoder().decode([UsageRecord].self, from: data))
        guard let decoded else {
            print("[usage] load error: failed to decode saved usage records")
            return
        }
        records = decoded
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            print("[usage] save error: \(error)")
        }
    }
}
