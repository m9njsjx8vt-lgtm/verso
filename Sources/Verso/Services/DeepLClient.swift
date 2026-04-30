import Foundation

enum DeepLError: LocalizedError {
    case missingApiKey
    case httpError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "DeepL API key not configured."
        case .httpError(let code, let body): return "DeepL HTTP \(code): \(body.prefix(200))"
        case .invalidResponse: return "DeepL response parse failure"
        }
    }
}

/// Lightweight DeepL Free API client. Used to deliver an instant translation preview
/// while the slower LLM (Gemini) runs in parallel for the final, polished translation.
final class DeepLClient {
    private let timeout: TimeInterval = 5

    /// Translate via DeepL Free.
    /// - sourceLang / targetLang: BCP-47-like codes ("JA", "EN-US"). Source can be nil → auto-detect.
    func translate(
        text: String,
        sourceLang: String?,
        targetLang: String,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw DeepLError.missingApiKey }

        // Free-tier endpoint
        guard let url = URL(string: "https://api-free.deepl.com/v2/translate") else {
            throw DeepLError.invalidResponse
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")

        var formItems: [(String, String)] = [
            ("text", text),
            ("target_lang", targetLang)
        ]
        if let src = sourceLang { formItems.append(("source_lang", src)) }

        request.httpBody = encodeForm(formItems).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepLError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DeepLError.httpError(http.statusCode, body)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let translations = json["translations"] as? [[String: Any]],
            let first = translations.first,
            let translation = first["text"] as? String
        else {
            throw DeepLError.invalidResponse
        }
        return translation
    }

    private func encodeForm(_ items: [(String, String)]) -> String {
        items.map { key, value in
            let escapedKey = key.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }

    /// Map our internal language name to DeepL code.
    static func deepLLang(for fullName: String) -> String {
        switch fullName {
        case "Japanese": return "JA"
        case "English": return "EN-US"
        default: return "EN-US"
        }
    }
}
