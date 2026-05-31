import Foundation
import CryptoKit

/// In-memory LRU-ish cache for completed translations. Keyed by SHA256 of the
/// text plus every setting that can materially change the translation. Cleared
/// on app restart.
@MainActor
final class TranslationCache {
    struct Entry {
        let geminiTranslation: String?
        let deepLTranslation: String?
        let timestamp: Date
    }

    private var store: [String: Entry] = [:]
    private let maxEntries = 500
    private var insertionOrder: [String] = []

    func key(
        text: String,
        source: String,
        target: String,
        glossary: String,
        context: String,
        model: String,
        preserveMarkdownAndCode: Bool
    ) -> String {
        let combined = [
            "source=\(source)",
            "target=\(target)",
            "model=\(model)",
            "preserve=\(preserveMarkdownAndCode)",
            "glossary=\(glossary)",
            "context=\(context)",
            "text=\(text)"
        ].joined(separator: "\n---\n")
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    func get(_ key: String) -> Entry? {
        store[key]
    }

    func set(_ key: String, geminiTranslation: String? = nil, deepLTranslation: String? = nil) {
        let existing = store[key]
        let entry = Entry(
            geminiTranslation: geminiTranslation ?? existing?.geminiTranslation,
            deepLTranslation: deepLTranslation ?? existing?.deepLTranslation,
            timestamp: Date()
        )
        if store[key] == nil {
            insertionOrder.append(key)
            if insertionOrder.count > maxEntries {
                let evict = insertionOrder.removeFirst()
                store.removeValue(forKey: evict)
            }
        }
        store[key] = entry
    }

    func clear() {
        store.removeAll()
        insertionOrder.removeAll()
    }

    var count: Int { store.count }
}
