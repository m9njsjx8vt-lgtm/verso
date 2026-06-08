import Foundation

enum LocalAIError: LocalizedError {
    case missingModel
    case invalidEndpoint(String)
    case connectionFailed(String)
    case httpError(Int, String)
    case invalidResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return "ローカルAIのモデル名が未設定です。Settings → General → Local AI で設定してください。"
        case .invalidEndpoint(let value):
            return "ローカルAIの接続先URLが不正です: \(value.isEmpty ? "未入力" : value)"
        case .connectionFailed(let detail):
            return "ローカルAIに接続できません。Ollama / LM Studio が起動しているか、Endpoint が正しいか確認してください。\(Self.formatDetail(detail))"
        case .httpError(let code, let body):
            return Self.describeHTTPError(code: code, body: body)
        case .invalidResponse:
            return "ローカルAIから予期しない応答形式が返りました。Backend と Model 名を確認してください。"
        case .timedOut:
            return "ローカルAIの応答が遅すぎます。軽いモデルに変えるか、もう一度試してください。"
        }
    }

    private static func describeHTTPError(code: Int, body: String) -> String {
        let detail = formatDetail(cleanHTTPBody(body))
        switch code {
        case 404:
            return "ローカルAIのモデルまたはAPIパスが見つかりません。Refresh Modelsでモデル名を選び直すか、Endpointを確認してください。\(detail)"
        case 401, 403:
            return "ローカルAIサーバーが認証を要求しています。認証なしで使えるローカルサーバー設定にするか、Endpointを確認してください。\(detail)"
        case 500...599:
            return "ローカルAIサーバー側でエラーが発生しました。モデルが読み込めるか、重すぎないかを確認してください。\(detail)"
        default:
            return "ローカルAI HTTP \(code)。Endpoint / Backend / Model を確認してください。\(detail)"
        }
    }

    private static func cleanHTTPBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error", "message", "detail"] {
                if let value = json[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }

        return String(trimmed.prefix(200))
    }

    private static func formatDetail(_ detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "（\(trimmed)）"
    }
}

struct LocalAIModelInfo: Identifiable, Equatable {
    let name: String
    let sizeBytes: Int64?

    var id: String { name }

    static func recommendedReplacement(
        from models: [LocalAIModelInfo],
        currentModel: String
    ) -> LocalAIModelInfo? {
        let trimmed = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, models.contains(where: { $0.name == trimmed }) {
            return nil
        }

        if let defaultModel = models.first(where: { $0.name == LocalAIBackend.defaultModel }) {
            return defaultModel
        }

        let nonChatHints = ["embed", "embedding", "bge-", "rerank"]
        return models.first { model in
            let lowercased = model.name.lowercased()
            return !nonChatHints.contains { lowercased.contains($0) }
        } ?? models.first
    }
}

final class LocalAIClient {

    func listModels(
        backend: LocalAIBackend,
        endpoint: String
    ) async throws -> [LocalAIModelInfo] {
        let url = try modelsURL(for: backend, rawEndpoint: endpoint)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw LocalAIError.timedOut
        } catch let urlError as URLError {
            throw LocalAIError.connectionFailed(urlError.localizedDescription)
        } catch {
            throw LocalAIError.connectionFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LocalAIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw LocalAIError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        switch backend {
        case .ollama:
            return try parseOllamaModels(data)
        case .openAICompatible:
            return try parseOpenAICompatibleModels(data)
        }
    }

    func healthCheck(
        backend: LocalAIBackend,
        endpoint: String,
        model: String
    ) async throws -> String {
        try await complete(
            prompt: "Reply with exactly this word and no explanation: OK",
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: 45
        )
    }

    func translate(
        text: String,
        from: String,
        to: String,
        context: String?,
        glossary: String?,
        sourceAppHint: String?,
        preserveMarkdownAndCode: Bool,
        backend: LocalAIBackend,
        endpoint: String,
        model: String
    ) async throws -> (text: String, usage: GeminiUsage?) {
        let prompt = GeminiClient.buildTranslatePrompt(
            text: text,
            from: from,
            to: to,
            context: context,
            glossary: glossary,
            sourceAppHint: sourceAppHint,
            preserveMarkdownAndCode: preserveMarkdownAndCode
        )
        let timeout = timeoutForTextLength(text.count)
        let output = try await complete(
            prompt: prompt,
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: timeout
        )
        return (output, nil)
    }

    func translateStreaming(
        text: String,
        from: String,
        to: String,
        context: String?,
        glossary: String?,
        sourceAppHint: String?,
        preserveMarkdownAndCode: Bool,
        backend: LocalAIBackend,
        endpoint: String,
        model: String,
        onChunk: @escaping (String) async -> Void
    ) async throws -> (text: String, usage: GeminiUsage?) {
        let prompt = GeminiClient.buildTranslatePrompt(
            text: text,
            from: from,
            to: to,
            context: context,
            glossary: glossary,
            sourceAppHint: sourceAppHint,
            preserveMarkdownAndCode: preserveMarkdownAndCode
        )
        let output = try await completeStreaming(
            prompt: prompt,
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: timeoutForTextLength(text.count),
            onChunk: onChunk
        )
        return (output, nil)
    }

    func refine(
        originalText: String,
        currentTranslation: String,
        instruction: String,
        from: String,
        to: String,
        context: String?,
        glossary: String?,
        preserveMarkdownAndCode: Bool,
        backend: LocalAIBackend,
        endpoint: String,
        model: String
    ) async throws -> (text: String, usage: GeminiUsage?) {
        let prompt = GeminiClient.buildRefinePrompt(
            originalText: originalText,
            currentTranslation: currentTranslation,
            instruction: instruction,
            from: from,
            to: to,
            context: context,
            glossary: glossary,
            preserveMarkdownAndCode: preserveMarkdownAndCode
        )
        let timeout = timeoutForTextLength(originalText.count + currentTranslation.count)
        let output = try await complete(
            prompt: prompt,
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: timeout
        )
        return (output, nil)
    }

    func chatAboutTranslation(
        originalText: String,
        translation: String,
        sourceLang: String,
        targetLang: String,
        priorMessages: [ChatMessage],
        newQuestion: String,
        backend: LocalAIBackend,
        endpoint: String,
        model: String
    ) async throws -> (text: String, usage: GeminiUsage?) {
        var historyBlock = ""
        if !priorMessages.isEmpty {
            historyBlock = "\n## CONVERSATION SO FAR\n" + priorMessages.map { msg in
                "\(msg.role == .user ? "User" : "Assistant"): \(msg.content)"
            }.joined(separator: "\n\n") + "\n"
        }
        let prompt = """
        You are a translation tutor. The user is studying or refining a translation between languages and asking follow-up questions.

        ## ORIGINAL (\(sourceLang))
        \(originalText)

        ## TRANSLATION (\(targetLang))
        \(translation)
        \(historyBlock)
        ## CURRENT QUESTION
        \(newQuestion)

        Respond in the user's question language. Keep the answer focused and concise. Use clear examples when explaining nuance.
        """
        let timeout = timeoutForTextLength(originalText.count + translation.count + newQuestion.count)
        let output = try await complete(
            prompt: prompt,
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: timeout
        )
        return (output, nil)
    }

    func extractGlossaryDiff(
        originalText: String,
        modelTranslation: String,
        userTranslation: String,
        from: String,
        to: String,
        backend: LocalAIBackend,
        endpoint: String,
        model: String
    ) async throws -> [(term: String, translation: String)] {
        let prompt = """
        You are analysing a translation correction.

        ORIGINAL (\(from)):
        \(originalText)

        MODEL TRANSLATION (\(to)):
        \(modelTranslation)

        USER-EDITED TRANSLATION (\(to)):
        \(userTranslation)

        Identify any term-level corrections the user made. Output a JSON array of {"term":"<source-language term>","translation":"<preferred target translation>"} pairs.
        Only include reusable glossary entries. If none, return [].
        Output ONLY the JSON array. No code fence, no explanation.
        """
        let output = try await complete(
            prompt: prompt,
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: timeoutForTextLength(originalText.count + userTranslation.count * 2)
        )
        var trimmed = output
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
            guard let term = dict["term"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let translation = dict["translation"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !term.isEmpty,
                  !translation.isEmpty
            else { return nil }
            return (term, translation)
        }
    }

    private func complete(
        prompt: String,
        backend: LocalAIBackend,
        endpoint: String,
        model: String,
        timeout: TimeInterval
    ) async throws -> String {
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else { throw LocalAIError.missingModel }

        let request = try completionRequest(
            prompt: prompt,
            backend: backend,
            endpoint: endpoint,
            modelName: modelName,
            timeout: timeout,
            streaming: false
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw LocalAIError.timedOut
        } catch let urlError as URLError {
            throw LocalAIError.connectionFailed(urlError.localizedDescription)
        } catch {
            throw LocalAIError.connectionFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LocalAIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw LocalAIError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let raw: String
        switch backend {
        case .ollama:
            raw = try parseOllamaResponse(data)
        case .openAICompatible:
            raw = try parseOpenAICompatibleResponse(data)
        }
        let cleaned = cleanModelOutput(raw)
        guard !cleaned.isEmpty else { throw LocalAIError.invalidResponse }
        return cleaned
    }

    private func completeStreaming(
        prompt: String,
        backend: LocalAIBackend,
        endpoint: String,
        model: String,
        timeout: TimeInterval,
        onChunk: @escaping (String) async -> Void
    ) async throws -> String {
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else { throw LocalAIError.missingModel }

        let request = try completionRequest(
            prompt: prompt,
            backend: backend,
            endpoint: endpoint,
            modelName: modelName,
            timeout: timeout,
            streaming: true
        )

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw LocalAIError.timedOut
        } catch let urlError as URLError {
            throw LocalAIError.connectionFailed(urlError.localizedDescription)
        } catch {
            throw LocalAIError.connectionFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LocalAIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            var body = Data()
            for try await byte in bytes {
                body.append(contentsOf: [byte])
            }
            throw LocalAIError.httpError(http.statusCode, String(data: body, encoding: .utf8) ?? "")
        }

        var accumulated = ""
        do {
            switch backend {
            case .ollama:
                accumulated = try await readOllamaStream(bytes: bytes, onChunk: onChunk)
            case .openAICompatible:
                accumulated = try await readOpenAICompatibleStream(bytes: bytes, onChunk: onChunk)
            }
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw LocalAIError.timedOut
        } catch let error as LocalAIError {
            throw error
        } catch {
            throw LocalAIError.connectionFailed(error.localizedDescription)
        }

        let cleaned = cleanModelOutput(accumulated)
        guard !cleaned.isEmpty else { throw LocalAIError.invalidResponse }
        return cleaned
    }

    private func completionRequest(
        prompt: String,
        backend: LocalAIBackend,
        endpoint: String,
        modelName: String,
        timeout: TimeInterval,
        streaming: Bool
    ) throws -> URLRequest {
        let url = try endpointURL(for: backend, rawEndpoint: endpoint)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch backend {
        case .ollama:
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": modelName,
                "messages": [["role": "user", "content": prompt]],
                "stream": streaming,
                "options": ["temperature": 0.2]
            ])
        case .openAICompatible:
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": modelName,
                "messages": [
                    [
                        "role": "system",
                        "content": "You are Verso, a private local translation assistant. Follow the user prompt exactly."
                    ],
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.2,
                "stream": streaming
            ])
        }

        return request
    }

    private func readOllamaStream(
        bytes: URLSession.AsyncBytes,
        onChunk: @escaping (String) async -> Void
    ) async throws -> String {
        var accumulated = ""

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard
                let data = trimmed.data(using: .utf8),
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if let error = json["error"] as? String, !error.isEmpty {
                throw LocalAIError.connectionFailed(error)
            }

            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                accumulated += content
                let cleaned = cleanModelOutput(accumulated)
                if !cleaned.isEmpty {
                    await onChunk(cleaned)
                }
            }

            if (json["done"] as? Bool) == true {
                break
            }
        }

        return accumulated
    }

    private func readOpenAICompatibleStream(
        bytes: URLSession.AsyncBytes,
        onChunk: @escaping (String) async -> Void
    ) async throws -> String {
        var accumulated = ""

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" { break }
            guard
                let data = payload.data(using: .utf8),
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "OpenAI-compatible stream error"
                throw LocalAIError.connectionFailed(message)
            }

            guard
                let choices = json["choices"] as? [[String: Any]],
                let first = choices.first,
                let delta = first["delta"] as? [String: Any],
                let content = delta["content"] as? String,
                !content.isEmpty
            else {
                continue
            }

            accumulated += content
            let cleaned = cleanModelOutput(accumulated)
            if !cleaned.isEmpty {
                await onChunk(cleaned)
            }
        }

        return accumulated
    }

    private func endpointURL(for backend: LocalAIBackend, rawEndpoint: String) throws -> URL {
        let base = try baseURL(rawEndpoint)
        let lowerPath = base.path.lowercased()
        if lowerPath.hasSuffix("/api/chat") || lowerPath.hasSuffix("/chat/completions") {
            return base
        }

        switch backend {
        case .ollama:
            return base.appendingPathComponent("api").appendingPathComponent("chat")
        case .openAICompatible:
            return base.appendingPathComponent("chat").appendingPathComponent("completions")
        }
    }

    private func modelsURL(for backend: LocalAIBackend, rawEndpoint: String) throws -> URL {
        let base = try baseURL(rawEndpoint)
        let lowerPath = base.path.lowercased()

        switch backend {
        case .ollama:
            if lowerPath.hasSuffix("/api/tags") {
                return base
            }
            if lowerPath.hasSuffix("/api/chat") {
                return base.deletingLastPathComponent().appendingPathComponent("tags")
            }
            return base.appendingPathComponent("api").appendingPathComponent("tags")
        case .openAICompatible:
            if lowerPath.hasSuffix("/models") {
                return base
            }
            if lowerPath.hasSuffix("/chat/completions") {
                return base
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("models")
            }
            return base.appendingPathComponent("models")
        }
    }

    private func baseURL(_ rawEndpoint: String) throws -> URL {
        let trimmed = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed), base.scheme != nil, base.host != nil else {
            throw LocalAIError.invalidEndpoint(rawEndpoint)
        }
        return base
    }

    private func parseOllamaModels(_ data: Data) throws -> [LocalAIModelInfo] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = json["models"] as? [[String: Any]]
        else {
            throw LocalAIError.invalidResponse
        }
        return models.compactMap { model in
            guard let name = model["name"] as? String, !name.isEmpty else { return nil }
            let size = (model["size"] as? NSNumber)?.int64Value
            return LocalAIModelInfo(name: name, sizeBytes: size)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseOpenAICompatibleModels(_ data: Data) throws -> [LocalAIModelInfo] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = json["data"] as? [[String: Any]]
        else {
            throw LocalAIError.invalidResponse
        }
        return models.compactMap { model in
            guard let id = model["id"] as? String, !id.isEmpty else { return nil }
            return LocalAIModelInfo(name: id, sizeBytes: nil)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseOllamaResponse(_ data: Data) throws -> String {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw LocalAIError.invalidResponse
        }
        return content
    }

    private func parseOpenAICompatibleResponse(_ data: Data) throws -> String {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw LocalAIError.invalidResponse
        }
        return content
    }

    private func cleanModelOutput(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let start = text.range(of: "<think>"),
              let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let openThink = text.range(of: "<think>") {
            text.removeSubrange(openThink.lowerBound..<text.endIndex)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let prefixes = ["Translation:", "翻訳:", "訳:"]
        for prefix in prefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func timeoutForTextLength(_ count: Int) -> TimeInterval {
        min(180.0, max(20.0, 20.0 + Double(count) / 120.0))
    }
}
