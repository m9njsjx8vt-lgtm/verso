import Foundation

enum DeepLError: LocalizedError {
    case missingApiKey
    case httpError(Int, String)
    case rateLimited
    case quotaExceeded
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "DeepL API key not configured."
        case .httpError(let code, let body): return "DeepL HTTP \(code): \(body.prefix(200))"
        case .rateLimited: return "DeepL rate-limited."
        case .quotaExceeded: return "DeepL monthly quota exceeded."
        case .invalidResponse: return "DeepL response parse failure"
        }
    }
}

final class DeepLClient {
    private let timeout: TimeInterval = 5

    func translate(
        text: String,
        sourceLang: String?,
        targetLang: String,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw DeepLError.missingApiKey }

        var attempt = 0
        var lastError: Error = DeepLError.invalidResponse
        while attempt < 2 {
            do {
                return try await callOnce(text: text, sourceLang: sourceLang,
                                          targetLang: targetLang, apiKey: apiKey)
            } catch DeepLError.rateLimited {
                attempt += 1
                lastError = DeepLError.rateLimited
                if attempt >= 2 { break }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func callOnce(
        text: String,
        sourceLang: String?,
        targetLang: String,
        apiKey: String
    ) async throws -> String {
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
        if http.statusCode == 429 { throw DeepLError.rateLimited }
        if http.statusCode == 456 { throw DeepLError.quotaExceeded }
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
}
