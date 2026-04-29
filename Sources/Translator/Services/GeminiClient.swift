import Foundation

enum GeminiError: LocalizedError {
    case missingApiKey
    case httpError(Int, String)
    case invalidResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Gemini APIキーが未設定です。Settings から登録してください。"
        case .httpError(let code, let body):
            let snippet = String(body.prefix(300))
            return "HTTP \(code)\n\(snippet)"
        case .invalidResponse:
            return "APIレスポンス解析失敗"
        case .timedOut:
            return "タイムアウト（12秒）。ネットワーク or APIが応答しません。"
        }
    }
}

final class GeminiClient {
    private let timeout: TimeInterval = 12

    func translate(
        text: String,
        from: String,
        to: String,
        context: String?,
        model: String,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingApiKey }

        let prompt = Self.buildPrompt(text: text, from: from, to: to, context: context)

        guard let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        ) else {
            throw GeminiError.invalidResponse
        }

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2]
        ]

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw GeminiError.timedOut
        } catch {
            throw GeminiError.httpError(-1, error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.httpError(httpResponse.statusCode, errBody)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let firstPart = parts.first,
            let translation = firstPart["text"] as? String
        else {
            throw GeminiError.invalidResponse
        }

        return translation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildPrompt(text: String, from: String, to: String, context: String?) -> String {
        if let ctx = context?.trimmingCharacters(in: .whitespacesAndNewlines), !ctx.isEmpty {
            return """
            You are a personal translator for a specific user. Read the user context below and translate so the result sounds like *that user* wrote it — match their tone, terminology, and proper-noun conventions.

            ## USER CONTEXT
            \(ctx)

            ## TASK
            Translate the following \(from) text into natural, fluent \(to). Apply the user's tone, glossary, and style rules from the context. Output ONLY the translation — no quotes, no explanations, no labels, no notes.

            ---
            \(text)
            """
        } else {
            return """
            You are a professional translator. Translate the following \(from) text into natural, fluent \(to). Preserve tone, register, and any technical terminology. Output ONLY the translation — no quotes, no explanations, no labels.

            ---
            \(text)
            """
        }
    }
}
