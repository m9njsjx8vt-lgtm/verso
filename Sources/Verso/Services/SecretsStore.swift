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
        do {
            let data = try JSONEncoder().encode(dict)
            try data.write(to: storeURL, options: [.atomic])
            // Restrict to owner read/write only
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storeURL.path
            )
            return true
        } catch {
            print("[secrets] save error: \(error)")
            return false
        }
    }
}
