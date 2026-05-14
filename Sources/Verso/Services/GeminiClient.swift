import Foundation

enum GeminiError: LocalizedError {
    case missingApiKey
    case httpError(Int, String)
    case rateLimited
    case safetyFiltered(String)
    case invalidResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Gemini APIキーが未設定です。Settings から登録してください。"
        case .httpError(let code, let body):
            let snippet = String(body.prefix(300))
            return "HTTP \(code)\n\(snippet)"
        case .rateLimited:
            return "レート制限に到達しました。しばらく待ってください（または Settings で別モデルへ切替）。"
        case .safetyFiltered(let reason):
            return "Gemini が翻訳を拒否しました: \(reason)"
        case .invalidResponse:
            return "APIレスポンス解析失敗"
        case .timedOut:
            return "タイムアウト。ネットワーク or APIが応答しません。"
        }
    }
}

/// Returned alongside translation text so callers can record token usage.
struct GeminiUsage {
    let promptTokens: Int
    let responseTokens: Int
}

final class GeminiClient {

    // MARK: - Translate

    func translate(
        text: String,
        from: String,
        to: String,
        context: String?,
        glossary: String?,
        sourceAppHint: String?,
        preserveMarkdownAndCode: Bool,
        model: String,
        apiKey: String
    ) async throws -> (text: String, usage: GeminiUsage?) {
        let prompt = Self.buildTranslatePrompt(
            text: text, from: from, to: to,
            context: context, glossary: glossary, sourceAppHint: sourceAppHint,
            preserveMarkdownAndCode: preserveMarkdownAndCode
        )
        return try await callWithRetry(prompt: prompt, model: model, apiKey: apiKey, textLen: text.count)
    }

    // MARK: - Streaming translate

    func translateStreaming(
        text: String,
        from: String,
        to: String,
        context: String?,
        glossary: String?,
        sourceAppHint: String?,
        preserveMarkdownAndCode: Bool,
        model: String,
        apiKey: String,
        onChunk: @escaping (String) async -> Void
    ) async throws -> (text: String, usage: GeminiUsage?) {
        guard !apiKey.isEmpty else { throw GeminiError.missingApiKey }
        let prompt = Self.buildTranslatePrompt(
            text: text, from: from, to: to,
            context: context, glossary: glossary, sourceAppHint: sourceAppHint,
            preserveMarkdownAndCode: preserveMarkdownAndCode
        )

        guard let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
        ) else {
            throw GeminiError.invalidResponse
        }

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2]
        ]
        let timeout = min(60.0, max(12.0, 12.0 + Double(text.count) / 200.0))

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw GeminiError.timedOut
        } catch {
            throw GeminiError.httpError(-1, error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        if http.statusCode == 429 { throw GeminiError.rateLimited }
        guard http.statusCode == 200 else {
            var body = Data()
            for try await chunk in bytes { body.append(chunk) }
            let s = String(data: body, encoding: .utf8) ?? ""
            throw GeminiError.httpError(http.statusCode, s)
        }

        var accumulated = ""
        var promptTokens = 0
        var responseTokens = 0

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard
                let data = payload.data(using: .utf8),
                let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let pf = dict["promptFeedback"] as? [String: Any],
               let reason = pf["blockReason"] as? String {
                throw GeminiError.safetyFiltered(reason)
            }

            // Token usage may show up in the final chunk
            if let usage = dict["usageMetadata"] as? [String: Any] {
                promptTokens   = usage["promptTokenCount"]    as? Int ?? promptTokens
                responseTokens = usage["candidatesTokenCount"] as? Int ?? responseTokens
            }

            guard
                let candidates = dict["candidates"] as? [[String: Any]],
                let first = candidates.first
            else { continue }

            if let finish = first["finishReason"] as? String,
               finish == "SAFETY" || finish == "RECITATION" {
                throw GeminiError.safetyFiltered(finish)
            }

            guard
                let content = first["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]],
                let firstPart = parts.first,
                let chunk = firstPart["text"] as? String
            else { continue }

            accumulated += chunk
            await onChunk(accumulated)
        }

        let usage = (promptTokens > 0 || responseTokens > 0)
            ? GeminiUsage(promptTokens: promptTokens, responseTokens: responseTokens)
            : nil
        return (accumulated.trimmingCharacters(in: .whitespacesAndNewlines), usage)
    }

    // MARK: - Refine

    func refine(
        originalText: String,
        currentTranslation: String,
        instruction: String,
        from: String,
        to: String,
        context: String?,
        glossary: String?,
        preserveMarkdownAndCode: Bool,
        model: String,
        apiKey: String
    ) async throws -> (text: String, usage: GeminiUsage?) {
        let prompt = Self.buildRefinePrompt(
            originalText: originalText,
            currentTranslation: currentTranslation,
            instruction: instruction,
            from: from, to: to,
            context: context, glossary: glossary,
            preserveMarkdownAndCode: preserveMarkdownAndCode
        )
        return try await callWithRetry(prompt: prompt, model: model, apiKey: apiKey,
                                       textLen: originalText.count + currentTranslation.count)
    }

    // MARK: - Auto-glossary extraction (unchanged signature)

    func extractGlossaryDiff(
        originalText: String,
        modelTranslation: String,
        userTranslation: String,
        from: String,
        to: String,
        model: String,
        apiKey: String
    ) async throws -> [(term: String, translation: String)] {
        let prompt = """
        You are analysing a translation correction.

        ORIGINAL (\(from)):
        \(originalText)

        MODEL TRANSLATION (\(to)):
        \(modelTranslation)

        USER-EDITED TRANSLATION (\(to)):
        \(userTranslation)

        Identify any **term-level corrections** the user made — typically proper nouns, acronyms, technical jargon, or preferred wording. Output a JSON array of {"term": "<source-language term>", "translation": "<user's preferred target translation>"} pairs. Only include corrections that look like reusable glossary entries (skip purely stylistic edits). If no glossary-worthy corrections, return [].

        Output ONLY the JSON array. No code fence, no explanation.
        """
        let result = try await callWithRetry(prompt: prompt, model: model, apiKey: apiKey,
                                             textLen: originalText.count + userTranslation.count * 2)
        var trimmed = result.text
        if trimmed.hasPrefix("```") {
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            if trimmed.hasSuffix("```") {
                trimmed = String(trimmed.dropLast(3))
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = trimmed.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return array.compactMap { dict in
            guard let term = dict["term"]?.trimmingCharacters(in: .whitespaces),
                  let translation = dict["translation"]?.trimmingCharacters(in: .whitespaces),
                  !term.isEmpty, !translation.isEmpty
            else { return nil }
            return (term, translation)
        }
    }

    // MARK: - Networking with retry

    private func callWithRetry(
        prompt: String,
        model: String,
        apiKey: String,
        textLen: Int
    ) async throws -> (text: String, usage: GeminiUsage?) {
        guard !apiKey.isEmpty else { throw GeminiError.missingApiKey }
        let timeout = min(60.0, max(12.0, 12.0 + Double(textLen) / 200.0))

        var attempt = 0
        let maxAttempts = 3
        var lastError: Error = GeminiError.invalidResponse

        while attempt < maxAttempts {
            do {
                return try await callOnce(prompt: prompt, model: model, apiKey: apiKey, timeout: timeout)
            } catch GeminiError.rateLimited {
                attempt += 1
                lastError = GeminiError.rateLimited
                if attempt >= maxAttempts { break }
                let delay = UInt64(pow(2.0, Double(attempt)) - 1) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay + 1_000_000_000)
            } catch GeminiError.timedOut where attempt == 0 {
                attempt += 1
                lastError = GeminiError.timedOut
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func callOnce(prompt: String, model: String, apiKey: String, timeout: TimeInterval) async throws -> (text: String, usage: GeminiUsage?) {
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
        if httpResponse.statusCode == 429 { throw GeminiError.rateLimited }
        guard httpResponse.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.httpError(httpResponse.statusCode, errBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.invalidResponse
        }

        if let pf = json["promptFeedback"] as? [String: Any],
           let reason = pf["blockReason"] as? String {
            throw GeminiError.safetyFiltered(reason)
        }

        guard
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first
        else {
            throw GeminiError.invalidResponse
        }

        if let finishReason = first["finishReason"] as? String,
           finishReason == "SAFETY" || finishReason == "RECITATION" {
            throw GeminiError.safetyFiltered(finishReason)
        }

        guard
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let firstPart = parts.first,
            let textOut = firstPart["text"] as? String
        else {
            throw GeminiError.invalidResponse
        }

        var usage: GeminiUsage?
        if let usageDict = json["usageMetadata"] as? [String: Any] {
            let pt = usageDict["promptTokenCount"] as? Int ?? 0
            let rt = usageDict["candidatesTokenCount"] as? Int ?? 0
            if pt > 0 || rt > 0 { usage = GeminiUsage(promptTokens: pt, responseTokens: rt) }
        }

        return (textOut.trimmingCharacters(in: .whitespacesAndNewlines), usage)
    }

    // MARK: - Prompt builders

    private static func buildTranslatePrompt(
        text: String, from: String, to: String,
        context: String?, glossary: String?, sourceAppHint: String?,
        preserveMarkdownAndCode: Bool
    ) -> String {
        let ctxBlock = nonEmptyBlock(title: "USER CONTEXT", body: context)
        let gloBlock = nonEmptyBlock(title: "GLOSSARY (use these specific translations consistently)",
                                     body: glossary)
        let appBlock = sourceAppToneHint(for: sourceAppHint)
        let preserveBlock = preserveMarkdownAndCode ? markdownPreservationRule : ""

        return """
        You are a personal translator for a specific user. Use the user context, glossary, and source-app hint below to produce a translation that sounds like *that user* wrote it.
        \(ctxBlock)\(gloBlock)\(appBlock)\(preserveBlock)
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
        context: String?, glossary: String?,
        preserveMarkdownAndCode: Bool
    ) -> String {
        let ctxBlock = nonEmptyBlock(title: "USER CONTEXT", body: context)
        let gloBlock = nonEmptyBlock(title: "GLOSSARY", body: glossary)
        let preserveBlock = preserveMarkdownAndCode ? markdownPreservationRule : ""

        return """
        You are a personal translator. The user wants you to refine an existing translation.
        \(ctxBlock)\(gloBlock)\(preserveBlock)
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

    private static let markdownPreservationRule = """

    ## STRUCTURAL PRESERVATION
    - Preserve all Markdown formatting: # headers, **bold**, *italic*, `inline code`, ```code blocks```, > quotes, - lists, [links](url), images, tables.
    - Preserve verbatim: code identifiers (variable/function/class names), file paths, URLs, command-line snippets, JSON/YAML keys, SQL keywords.
    - Translate only the natural-language portions; keep code & structural syntax bit-identical.
    """

    private static func nonEmptyBlock(title: String, body: String?) -> String {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
            return ""
        }
        return "\n## \(title)\n\(body)\n"
    }

    private static func sourceAppToneHint(for appName: String?) -> String {
        guard let name = appName?.lowercased() else { return "" }
        let hint: String
        switch true {
        case name.contains("mail") || name.contains("outlook"):
            hint = "The user copied this from an email client. Lean toward formal, polite business register."
        case name.contains("slack") || name.contains("discord") || name.contains("teams") || name.contains("messages"):
            hint = "The user copied this from a chat app. Lean toward casual, conversational register."
        case name.contains("xcode") || name.contains("vscode") || name.contains("code") || name.contains("terminal") || name.contains("iterm"):
            hint = "The user copied this from a code editor. Preserve technical terms, code identifiers, and inline code formatting verbatim."
        case name.contains("notion") || name.contains("docs") || name.contains("word") || name.contains("pages"):
            hint = "The user copied this from a document app. Use a balanced, readable register."
        case name.contains("safari") || name.contains("chrome") || name.contains("firefox") || name.contains("arc"):
            hint = "The user copied this from a web browser. Tone depends on content; default to neutral."
        default:
            return ""
        }
        return "\n## SOURCE APP HINT\n\(hint) (Source app: \(name))\n"
    }
}
