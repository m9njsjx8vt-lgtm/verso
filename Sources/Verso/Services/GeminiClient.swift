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

    // MARK: - Translate

    func translate(
        text: String,
        from: String,
        to: String,
        context: String?,
        glossary: String?,
        model: String,
        apiKey: String
    ) async throws -> String {
        let prompt = Self.buildTranslatePrompt(
            text: text, from: from, to: to,
            context: context, glossary: glossary
        )
        return try await call(prompt: prompt, model: model, apiKey: apiKey)
    }

    // MARK: - Refine

    /// Re-translate the existing translation according to a refinement instruction.
    /// (e.g. "make it shorter", "more casual"). Keeps the same source text as ground truth.
    func refine(
        originalText: String,
        currentTranslation: String,
        instruction: String,
        from: String,
        to: String,
        context: String?,
        glossary: String?,
        model: String,
        apiKey: String
    ) async throws -> String {
        let prompt = Self.buildRefinePrompt(
            originalText: originalText,
            currentTranslation: currentTranslation,
            instruction: instruction,
            from: from, to: to,
            context: context, glossary: glossary
        )
        return try await call(prompt: prompt, model: model, apiKey: apiKey)
    }

    // MARK: - Internals

    private func call(prompt: String, model: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingApiKey }

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
            let textOut = firstPart["text"] as? String
        else {
            throw GeminiError.invalidResponse
        }

        return textOut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt builders

    private static func buildTranslatePrompt(
        text: String, from: String, to: String,
        context: String?, glossary: String?
    ) -> String {
        let ctxBlock = nonEmptyBlock(title: "USER CONTEXT", body: context)
        let gloBlock = nonEmptyBlock(title: "GLOSSARY (use these specific translations consistently)",
                                     body: glossary)

        let intro = ctxBlock.isEmpty && gloBlock.isEmpty
            ? "You are a professional translator."
            : "You are a personal translator for a specific user. Use the user context and glossary below so the result sounds like *that user* wrote it."

        return """
        \(intro)
        \(ctxBlock)\(gloBlock)
        ## TASK
        Translate the following \(from) text into natural, fluent \(to). \
        Match the user's tone, terminology, and proper-noun conventions. \
        Output ONLY the translation — no quotes, no explanations, no labels, no notes.

        ---
        \(text)
        """
    }

    private static func buildRefinePrompt(
        originalText: String, currentTranslation: String, instruction: String,
        from: String, to: String,
        context: String?, glossary: String?
    ) -> String {
        let ctxBlock = nonEmptyBlock(title: "USER CONTEXT", body: context)
        let gloBlock = nonEmptyBlock(title: "GLOSSARY", body: glossary)

        return """
        You are a personal translator. The user wants you to refine an existing translation.
        \(ctxBlock)\(gloBlock)
        ## ORIGINAL (\(from))
        \(originalText)

        ## CURRENT TRANSLATION (\(to))
        \(currentTranslation)

        ## REFINEMENT REQUEST
        \(instruction)

        Output ONLY the refined translation in \(to). \
        Preserve the meaning of the original. \
        No quotes, no explanations, no labels.
        """
    }

    private static func nonEmptyBlock(title: String, body: String?) -> String {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
            return ""
        }
        return "\n## \(title)\n\(body)\n"
    }
}
