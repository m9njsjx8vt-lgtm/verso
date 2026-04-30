import Foundation

/// File-backed secret storage. Trades Keychain encryption for zero permission prompts.
/// Stored at `~/Library/Application Support/Verso/secrets.json` with `0600` (owner-only) perms.
enum SecretsStore {
    private static let storeURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Verso", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("secrets.json")
    }()

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    static func get(_ key: String) -> String? {
        loadAll()[key]
    }

    @discardableResult
    static func set(_ value: String, forKey key: String) -> Bool {
        var dict = loadAll()
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = value
        }
        // Write to a temp file with 0600 perms FIRST, then atomic rename.
        // This avoids the brief world-readable window of write-then-chmod.
        let tmpURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("secrets.json.tmp")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(dict)

            // Create empty file with 0600 perms first
            FileManager.default.createFile(
                atPath: tmpURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
            try data.write(to: tmpURL, options: [.atomic])
            // Verify perms (in case createFile didn't apply them in some edge case)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tmpURL.path
            )
            // Atomic rename
            _ = try FileManager.default.replaceItemAt(storeURL, withItemAt: tmpURL)
            return true
        } catch {
            print("[secrets] save error: \(error)")
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }
    }
}
