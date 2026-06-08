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
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = value
        }
        // Create the temp file with 0600 perms first, then swap it into place.
        let tmpURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("secrets.json.tmp")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(dict)

            try? FileManager.default.removeItem(at: tmpURL)
            guard FileManager.default.createFile(
                atPath: tmpURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tmpURL.path
            )
            if FileManager.default.fileExists(atPath: storeURL.path) {
                _ = try FileManager.default.replaceItemAt(storeURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: storeURL)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storeURL.path
            )
            return true
        } catch {
            print("[secrets] save error: \(error)")
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }
    }
}
