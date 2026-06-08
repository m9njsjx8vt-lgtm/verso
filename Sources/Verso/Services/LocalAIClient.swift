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

struct LocalAIModelInfo: Identifiable, Equatable, Sendable {
    let name: String
    let sizeBytes: Int64?

    var id: String { name }

    var selectionHint: String? {
        if name == LocalAIBackend.defaultModel {
            return "Recommended"
        }
        if isEmbeddingModel {
            return "Embedding"
        }
        if isCodeModel {
            return "Code model"
        }
        if isLikelyHeavyModel {
            return "Heavy"
        }
        if isLikelyChatModel {
            return "Chat"
        }
        return nil
    }

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

        return models.sorted(by: recommendationSort).first
    }

    private static func recommendationSort(_ lhs: LocalAIModelInfo, _ rhs: LocalAIModelInfo) -> Bool {
        let lhsRank = lhs.recommendationRank
        let rhsRank = rhs.recommendationRank
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        switch (lhs.sizeBytes, rhs.sizeBytes) {
        case let (lhsSize?, rhsSize?) where lhsSize != rhsSize:
            return lhsSize < rhsSize
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var recommendationRank: Int {
        if name == LocalAIBackend.defaultModel { return 0 }
        if isEmbeddingModel { return 900 }
        if isCodeModel { return 800 }
        if isLikelyHeavyModel { return 700 }
        if isLikelyChatModel { return 100 }
        return 300
    }

    private var lowercasedName: String {
        name.lowercased()
    }

    private var isEmbeddingModel: Bool {
        ["embed", "embedding", "bge-", "rerank"].contains { lowercasedName.contains($0) }
    }

    private var isCodeModel: Bool {
        ["coder", "code-", "-code", "codestral"].contains { lowercasedName.contains($0) }
    }

    private var isLikelyHeavyModel: Bool {
        if let sizeBytes, sizeBytes >= 35_000_000_000 {
            return true
        }
        return ["70b", "72b", "80b", "120b"].contains { lowercasedName.contains($0) }
    }

    private var isLikelyChatModel: Bool {
        ["qwen", "llama", "mistral", "gemma", "phi", "chat", "instruct"].contains {
            lowercasedName.contains($0)
        }
    }
}

struct LocalAIServerDiscovery: Identifiable, Equatable, Sendable {
    let backend: LocalAIBackend
    let endpoint: String
    let models: [LocalAIModelInfo]

    var id: String { "\(backend.rawValue)|\(endpoint)" }

    var displayTitle: String {
        let compactEndpoint = endpoint
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        return "\(backend.title) · \(compactEndpoint)"
    }
}

final class LocalAIClient {

    func listModels(
        backend: LocalAIBackend,
        endpoint: String,
        timeout: TimeInterval = 15
    ) async throws -> [LocalAIModelInfo] {
        let url = try modelsURL(for: backend, rawEndpoint: endpoint)
        var request = URLRequest(url: url, timeoutInterval: timeout)
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

    func discoverServers(timeout: TimeInterval = 2.5) async -> [LocalAIServerDiscovery] {
        await withTaskGroup(of: (Int, LocalAIServerDiscovery)?.self) { group in
            for (index, candidate) in Self.discoveryCandidates.enumerated() {
                group.addTask {
                    do {
                        let models = try await LocalAIClient().listModels(
                            backend: candidate.backend,
                            endpoint: candidate.endpoint,
                            timeout: timeout
                        )
                        guard !models.isEmpty else { return nil }
                        return (
                            index,
                            LocalAIServerDiscovery(
                                backend: candidate.backend,
                                endpoint: candidate.endpoint,
                                models: models
                            )
                        )
                    } catch {
                        return nil
                    }
                }
            }

            var discoveries: [(Int, LocalAIServerDiscovery)] = []
            for await discovery in group {
                if let discovery {
                    discoveries.append(discovery)
                }
            }
            return discoveries
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    func healthCheck(
        backend: LocalAIBackend,
        endpoint: String,
        model: String
    ) async throws -> String {
        try await complete(
            prompt: "Reply with exactly this word and no explanation: OK",
            systemPrompt: Self.conciseSystemPrompt,
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
            systemPrompt: Self.translationSystemPrompt(targetLanguage: to),
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: timeout,
            preserveCodeFences: preserveMarkdownAndCode
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
            systemPrompt: Self.translationSystemPrompt(targetLanguage: to),
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: timeoutForTextLength(text.count),
            preserveCodeFences: preserveMarkdownAndCode,
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
            systemPrompt: Self.translationSystemPrompt(targetLanguage: to),
            backend: backend,
            endpoint: endpoint,
            model: model,
            timeout: timeout,
            preserveCodeFences: preserveMarkdownAndCode
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
            systemPrompt: Self.tutorSystemPrompt,
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
            systemPrompt: Self.jsonOnlySystemPrompt,
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
        systemPrompt: String,
        backend: LocalAIBackend,
        endpoint: String,
        model: String,
        timeout: TimeInterval,
        preserveCodeFences: Bool = false
    ) async throws -> String {
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else { throw LocalAIError.missingModel }

        let request = try completionRequest(
            prompt: prompt,
            systemPrompt: systemPrompt,
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
        let cleaned = cleanModelOutput(raw, preserveCodeFences: preserveCodeFences)
        guard !cleaned.isEmpty else { throw LocalAIError.invalidResponse }
        return cleaned
    }

    private func completeStreaming(
        prompt: String,
        systemPrompt: String,
        backend: LocalAIBackend,
        endpoint: String,
        model: String,
        timeout: TimeInterval,
        preserveCodeFences: Bool = false,
        onChunk: @escaping (String) async -> Void
    ) async throws -> String {
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else { throw LocalAIError.missingModel }

        let request = try completionRequest(
            prompt: prompt,
            systemPrompt: systemPrompt,
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
                accumulated = try await readOllamaStream(
                    bytes: bytes,
                    preserveCodeFences: preserveCodeFences,
                    onChunk: onChunk
                )
            case .openAICompatible:
                accumulated = try await readOpenAICompatibleStream(
                    bytes: bytes,
                    preserveCodeFences: preserveCodeFences,
                    onChunk: onChunk
                )
            }
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw LocalAIError.timedOut
        } catch let error as LocalAIError {
            throw error
        } catch {
            throw LocalAIError.connectionFailed(error.localizedDescription)
        }

        let cleaned = cleanModelOutput(accumulated, preserveCodeFences: preserveCodeFences)
        guard !cleaned.isEmpty else { throw LocalAIError.invalidResponse }
        return cleaned
    }

    private func completionRequest(
        prompt: String,
        systemPrompt: String,
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
                "messages": chatMessages(systemPrompt: systemPrompt, prompt: prompt),
                "stream": streaming,
                "options": ["temperature": 0.1]
            ])
        case .openAICompatible:
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": modelName,
                "messages": chatMessages(systemPrompt: systemPrompt, prompt: prompt),
                "temperature": 0.1,
                "stream": streaming
            ])
        }

        return request
    }

    private func chatMessages(systemPrompt: String, prompt: String) -> [[String: String]] {
        [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt]
        ]
    }

    private func readOllamaStream(
        bytes: URLSession.AsyncBytes,
        preserveCodeFences: Bool,
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
                let cleaned = cleanModelOutput(accumulated, preserveCodeFences: preserveCodeFences)
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
        preserveCodeFences: Bool,
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
            let cleaned = cleanModelOutput(accumulated, preserveCodeFences: preserveCodeFences)
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

    private func cleanModelOutput(_ raw: String, preserveCodeFences: Bool = false) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preserveCodeFences {
            text = strippingSurroundingCodeFence(from: text)
        }

        for tag in ["think", "thinking", "reasoning"] {
            text = removingTag(named: tag, from: text)
            text = removingOrphanedClosingTagPrefix(named: tag, from: text)
            text = text.replacingOccurrences(of: "</\(tag)>", with: "", options: [.caseInsensitive])
        }

        let prefixes = [
            "Assistant:",
            "Output:",
            "Result:",
            "Translation:",
            "Translated text:",
            "Here is the translation:",
            "Here's the translation:",
            "**Translation:**",
            "### Translation",
            "翻訳:",
            "翻訳結果:",
            "訳:"
        ]
        var didStripPrefix = true
        while didStripPrefix {
            didStripPrefix = false
            for prefix in prefixes where text.range(of: prefix, options: [.caseInsensitive])?.lowerBound == text.startIndex {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                didStripPrefix = true
            }
        }
        if !preserveCodeFences {
            text = strippingSurroundingCodeFence(from: text)
        }
        text = strippingSurroundingQuotes(from: text)
        return text
    }

    private func removingTag(named tag: String, from raw: String) -> String {
        var text = raw
        let open = "<\(tag)>"
        let close = "</\(tag)>"

        while let start = text.range(of: open, options: [.caseInsensitive]) {
            if let end = text.range(
                of: close,
                options: [.caseInsensitive],
                range: start.upperBound..<text.endIndex
            ) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                text.removeSubrange(start.lowerBound..<text.endIndex)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    private func removingOrphanedClosingTagPrefix(named tag: String, from raw: String) -> String {
        var text = raw
        let close = "</\(tag)>"

        if let end = text.range(of: close, options: [.caseInsensitive]) {
            text.removeSubrange(text.startIndex..<end.upperBound)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func strippingSurroundingCodeFence(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.components(separatedBy: .newlines)
        guard let first = lines.first, first.hasPrefix("```") else { return trimmed }
        lines.removeFirst()

        if let last = lines.last,
           last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }

        let unfenced = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return unfenced.isEmpty ? trimmed : unfenced
    }

    private func strippingSurroundingQuotes(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotePairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'")
        ]

        var didStrip = true
        while didStrip, text.count >= 2 {
            didStrip = false
            for (open, close) in quotePairs where text.first == open && text.last == close {
                text.removeFirst()
                text.removeLast()
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
        }
        return text
    }

    private func timeoutForTextLength(_ count: Int) -> TimeInterval {
        min(180.0, max(20.0, 20.0 + Double(count) / 120.0))
    }

    private static func translationSystemPrompt(targetLanguage: String) -> String {
        """
        You are Verso, a private local translation engine.
        Translate into \(targetLanguage) only.
        Return only the final translated text.
        Do not explain, analyze, restate the task, ask questions, or add labels.
        Do not include <think> tags or hidden reasoning text.
        Do not answer in the source language or in a third language.
        If the target language is English, every natural-language sentence in the output must be English.
        Preserve the speech act: statements stay statements, questions stay questions, commands stay commands.
        Never turn a declarative status update into an instruction or imperative.
        For Japanese-to-English status updates, translate "shimasu" / "shiteimasu" as "I will..." or "I am..." when the speaker is reporting their own action.
        Translate engineering status shorthand naturally: "kakunin OK" as "check passed" or "confirmed OK"; "logs have not increased" as "no new logs have appeared" or "no new logs were added".
        """
    }

    private static let conciseSystemPrompt = """
    You are Verso, a private local assistant. Follow the user instruction exactly and answer with the shortest valid output.
    """

    private static let tutorSystemPrompt = """
    You are Verso, a private local translation tutor. Answer only the user's current question, in the user's question language, without re-translating unless asked.
    """

    private static let jsonOnlySystemPrompt = """
    You are Verso, a private local translation analysis engine. Output valid JSON only, with no explanation, labels, or code fences.
    """

    private static let discoveryCandidates: [(backend: LocalAIBackend, endpoint: String)] = [
        (.ollama, "http://localhost:11434"),
        (.ollama, "http://127.0.0.1:11434"),
        (.openAICompatible, "http://localhost:1234/v1"),
        (.openAICompatible, "http://127.0.0.1:1234/v1"),
        (.openAICompatible, "http://localhost:8080/v1"),
        (.openAICompatible, "http://127.0.0.1:8080/v1"),
        (.openAICompatible, "http://localhost:8000/v1"),
        (.openAICompatible, "http://127.0.0.1:8000/v1"),
        (.openAICompatible, "http://localhost:5001/v1"),
        (.openAICompatible, "http://127.0.0.1:5001/v1")
    ]
}
