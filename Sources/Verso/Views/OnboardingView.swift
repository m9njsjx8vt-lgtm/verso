import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var step: Int = 0
    @State private var apiKeyDraft: String = ""
    @State private var deepLDraft: String = ""
    @State private var providerDraft: String = TranslationProvider.defaultProvider.rawValue
    @State private var localBackendDraft: String = LocalAIBackend.ollama.rawValue
    @State private var localEndpointDraft: String = LocalAIBackend.ollama.defaultEndpoint
    @State private var localModelDraft: String = LocalAIBackend.defaultModel
    @State private var isTestingLocalAI: Bool = false
    @State private var localAITestMessage: String?
    @State private var localAITestSucceeded: Bool = false
    @State private var isLoadingLocalAIModels: Bool = false
    @State private var localAIModelListMessage: String?
    @State private var discoveredLocalAIModels: [LocalAIModelInfo] = []
    @State private var discoveredLocalAIServers: [LocalAIServerDiscovery] = []
    @State private var localAIModelRefreshID = UUID()
    @State private var localAIAppLaunchMessage: String?
    @State private var localAIAppLaunchSucceeded: Bool = false
    @State private var skipNextLocalAIBackendChange: Bool = false

    let onComplete: () -> Void

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color(NSColor.separatorColor))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            // Step content
            ScrollView {
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: aiEngineStep
                    case 2: deepLStep
                    case 3: accessibilityStep
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }

            // Footer buttons
            Divider()
            HStack {
                if step > 0 {
                    Button("戻る") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Text("\(step + 1) / \(totalSteps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(primaryButtonTitle) {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            }
            .padding(20)
        }
        .frame(width: 600, height: 540)
        .onAppear {
            apiKeyDraft = settings.apiKey
            deepLDraft = settings.deeplApiKey
            providerDraft = settings.translationProvider
            localBackendDraft = settings.localAIBackend
            localEndpointDraft = settings.localAIEndpoint
            localModelDraft = settings.localAIModel
            refreshLocalAIModelsIfUseful()
        }
        .onChange(of: providerDraft) { _ in
            refreshLocalAIModelsIfUseful(force: true)
        }
    }

    private var primaryButtonTitle: String {
        if step == totalSteps - 1 { return "完了" }
        if step == 1,
           selectedProvider == .gemini,
           apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "あとで設定して次へ"
        }
        if step == 2 && deepLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "スキップして次へ"
        }
        return "次へ"
    }

    private var canAdvance: Bool {
        if step == 1 && selectedProvider == .localAI {
            return !localEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !localModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isTestingLocalAI
        }
        return true
    }

    private func advance() {
        // Save state at the appropriate step
        if step == 1 {
            settings.translationProvider = providerDraft
            settings.apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.localAIBackend = localBackendDraft
            settings.localAIEndpoint = localEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.localAIModel = localModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if step == 2 { settings.deeplApiKey = deepLDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
        if step == totalSteps - 1 {
            settings.hasCompletedOnboarding = true
            onComplete()
        } else {
            step += 1
        }
    }

    private var selectedProvider: TranslationProvider {
        TranslationProvider(rawValue: providerDraft) ?? TranslationProvider.defaultProvider
    }

    private var selectedLocalBackend: LocalAIBackend {
        LocalAIBackend(rawValue: localBackendDraft) ?? .ollama
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            AppIconMark(size: 76)
            Text("Versoへようこそ")
                .font(.largeTitle)
                .bold()
            Text("ハイライトしたテキストを **⌘C×2** で瞬時に翻訳。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "sparkles",
                           title: "AI翻訳 + 即時プレビュー",
                           subtitle: "Gemini または Local AI を選択。DeepL プレビューは任意")
                FeatureRow(icon: "book.closed.fill",
                           title: "用語を学習",
                           subtitle: "Glossary に登録した固有名詞は毎回正しく訳される")
                FeatureRow(icon: "viewfinder",
                           title: "画面OCR翻訳",
                           subtitle: "⌥⇧C で選択した領域のテキストを翻訳")
                FeatureRow(icon: "clock.arrow.circlepath",
                           title: "履歴 + 検索",
                           subtitle: "⌘⇧H でいつでも過去訳を呼び出せる")
            }
            .padding(.top, 8)
        }
    }

    private var aiEngineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("AI Engineを選択", systemImage: "sparkles")
                .font(.title2)
                .bold()
            Text("クラウドのGeminiか、ネットなしでも動くLocal AIを選べます。あとから Settings で変更できます。")
                .font(.body)
                .foregroundColor(.secondary)

            Picker("", selection: $providerDraft) {
                ForEach(TranslationProvider.allCases) { provider in
                    Text(provider.title).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selectedProvider == .gemini {
                geminiEngineSettings
            } else {
                localAIEngineSettings
            }
        }
    }

    private var geminiEngineSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("1.  下のボタンで Google AI Studio を開く")
                Text("2.  「Get API key」→「Create API key」")
                Text("3.  生成された `AIza...` で始まる文字列をコピー")
                Text("4.  下に貼り付け")
            }
            .font(.callout)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Button {
                if let url = URL(string: "https://aistudio.google.com/apikey") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Google AI Studio を開く", systemImage: "safari")
            }
            .buttonStyle(.bordered)

            SecureField("AIza...", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Text("あとで Settings → General → AI Engine から Gemini / Local AI を切り替えられます。")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("APIキーが空欄、またはオフライン時は Local AI に自動切替します。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var localAIEngineSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("1.  Ollama または LM Studio のローカルサーバーを起動")
                Text("2.  Backend と Endpoint を確認")
                Text("3.  Refresh Models でモデルを選択")
                Text("4.  Test Local AI で接続確認")
            }
            .font(.callout)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Picker("Backend", selection: $localBackendDraft) {
                ForEach(LocalAIBackend.allCases) { backend in
                    Text(backend.title).tag(backend.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: localBackendDraft) { _ in
                if skipNextLocalAIBackendChange {
                    skipNextLocalAIBackendChange = false
                    return
                }
                if localEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || LocalAIBackend.allCases.map(\.defaultEndpoint).contains(localEndpointDraft) {
                    localEndpointDraft = selectedLocalBackend.defaultEndpoint
                }
                resetLocalAIModelDiscovery()
                localAIAppLaunchMessage = nil
                localAIAppLaunchSucceeded = false
                refreshLocalAIModelsIfUseful(force: true)
            }

            HStack(spacing: 8) {
                Button {
                    openLocalAIServerApp()
                } label: {
                    Label(
                        LocalAIAppLauncher.buttonTitle(for: selectedLocalBackend),
                        systemImage: "play.circle"
                    )
                }

                if let message = localAIAppLaunchMessage {
                    Label(
                        message,
                        systemImage: localAIAppLaunchSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundColor(localAIAppLaunchSucceeded ? .green : .orange)
                    .lineLimit(2)
                    .textSelection(.enabled)
                }
            }

            TextField(selectedLocalBackend.endpointHelp, text: $localEndpointDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: localEndpointDraft) { _ in
                    resetLocalAIModelDiscovery()
                }

            TextField("Model name", text: $localModelDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: localModelDraft) { _ in
                    resetLocalAITestResult()
                }

            HStack(spacing: 8) {
                Button {
                    refreshLocalAIModels()
                } label: {
                    Label(
                        isLoadingLocalAIModels ? "Loading…" : "Refresh Models",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(isLoadingLocalAIModels
                    || localEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    detectLocalAIModels()
                } label: {
                    Label(
                        isLoadingLocalAIModels ? "Searching…" : "Detect Local AI",
                        systemImage: "magnifyingglass"
                    )
                }
                .disabled(isLoadingLocalAIModels)

                if isLoadingLocalAIModels {
                    ProgressView()
                        .controlSize(.small)
                }

                if !discoveredLocalAIServers.isEmpty {
                    Menu {
                        ForEach(discoveredLocalAIServers) { discovery in
                            Button {
                                applyLocalAIDiscovery(discovery, messagePrefix: "選択")
                            } label: {
                                if discovery.backend == selectedLocalBackend
                                    && discovery.endpoint == localEndpointDraft {
                                    Label(serverMenuTitle(discovery), systemImage: "checkmark")
                                } else {
                                    Text(serverMenuTitle(discovery))
                                }
                            }
                        }
                    } label: {
                        Label("Use Server", systemImage: "server.rack")
                    }
                }

                if !discoveredLocalAIModels.isEmpty {
                    Menu {
                        ForEach(discoveredLocalAIModels) { model in
                            Button {
                                localModelDraft = model.name
                            } label: {
                                if model.name == localModelDraft {
                                    Label(modelMenuTitle(model), systemImage: "checkmark")
                                } else {
                                    Text(modelMenuTitle(model))
                                }
                            }
                        }
                    } label: {
                        Label("Choose Model", systemImage: "list.bullet")
                    }
                }
            }

            if let message = localAIModelListMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button {
                    testLocalAIConnection()
                } label: {
                    Label(
                        isTestingLocalAI ? "Checking…" : "Test Local AI",
                        systemImage: "checkmark.circle"
                    )
                }
                .disabled(isTestingLocalAI
                    || localEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || localModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isTestingLocalAI {
                    ProgressView()
                        .controlSize(.small)
                }

                if let message = localAITestMessage {
                    Label(
                        message,
                        systemImage: localAITestSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundColor(localAITestSucceeded ? .green : .orange)
                    .lineLimit(2)
                    .textSelection(.enabled)
                }
            }

            Text("Local AIを選ぶと、インターネット接続がなくてもメイン翻訳を実行できます。DeepLプレビューだけはクラウド接続が必要です。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var deepLStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("DeepL APIキー（任意）", systemImage: "bolt.fill")
                .font(.title2)
                .bold()
            Text("登録すると ⌘C×2 した瞬間に DeepL の即時プレビューが表示され、その後メインAIの精緻版に置き換わります。")
                .font(.body)
                .foregroundColor(.secondary)
            Text("DeepLなしでも翻訳できます。空欄のままスキップして問題ありません。")
                .font(.callout)
                .foregroundColor(.secondary)

            Button {
                if let url = URL(string: "https://www.deepl.com/pro-api") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("DeepL Free を取得", systemImage: "safari")
            }
            .buttonStyle(.bordered)

            SecureField("xxxxxxxx-xxxx-xxxx:fx (空欄でもOK)", text: $deepLDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Text("無料枠: 月50万文字。ローカルAI利用時もDeepLはネット接続がある時だけ動きます。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Accessibility 権限", systemImage: "lock.shield.fill")
                .font(.title2)
                .bold()
            Text("⌘C×2 と ⌥⇧C を**どこからでも検出**するために、macOS の Accessibility 権限が必要です。")
                .font(.body)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1.  「完了」ボタンを押すと権限プロンプトが表示されます")
                Text("2.  「システム設定を開く」→ Verso をリストに追加 → トグルON")
                Text("3.  Verso をいったん終了して再起動")
            }
            .font(.callout)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                Text("Verso はキーストロークを保存・送信しません。⌘C×2 と ⌥⇧C の組み合わせを検出するためだけに使います。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func refreshLocalAIModels() {
        let backend = selectedLocalBackend
        let endpoint = localEndpointDraft
        let requestID = UUID()

        localAIModelRefreshID = requestID
        isLoadingLocalAIModels = true
        localAIModelListMessage = nil
        discoveredLocalAIModels = []

        Task {
            do {
                let models = try await LocalAIClient().listModels(
                    backend: backend,
                    endpoint: endpoint
                )

                if models.isEmpty {
                    let discoveries = await LocalAIClient().discoverServers()
                    await MainActor.run {
                        guard localAIModelRefreshID == requestID else { return }
                        guard currentLocalAIRequestMatches(backend: backend, endpoint: endpoint) else {
                            isLoadingLocalAIModels = false
                            return
                        }
                        applyLocalAIDiscoveryFallback(
                            discoveries,
                            fallbackMessage: "モデルが見つかりません"
                        )
                    }
                    return
                }

                await MainActor.run {
                    guard localAIModelRefreshID == requestID else { return }
                    guard currentLocalAIRequestMatches(backend: backend, endpoint: endpoint) else {
                        isLoadingLocalAIModels = false
                        return
                    }

                    discoveredLocalAIModels = models
                    discoveredLocalAIServers = [
                        LocalAIServerDiscovery(
                            backend: backend,
                            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                            models: models
                        )
                    ]
                    let currentModel = localModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let recommended = LocalAIModelInfo.recommendedReplacement(
                        from: models,
                        currentModel: currentModel
                    ) {
                        localModelDraft = recommended.name
                        localAIModelListMessage = "モデル\(models.count)件を検出 · \(recommended.name) を選択"
                    } else {
                        localAIModelListMessage = "モデル\(models.count)件を検出"
                    }
                    isLoadingLocalAIModels = false
                }
            } catch {
                let fallbackMessage = error.localizedDescription
                let discoveries = await LocalAIClient().discoverServers()
                await MainActor.run {
                    guard localAIModelRefreshID == requestID else { return }
                    guard currentLocalAIRequestMatches(backend: backend, endpoint: endpoint) else {
                        isLoadingLocalAIModels = false
                        return
                    }
                    applyLocalAIDiscoveryFallback(
                        discoveries,
                        fallbackMessage: fallbackMessage
                    )
                }
            }
        }
    }

    private func detectLocalAIModels() {
        let requestID = UUID()

        localAIModelRefreshID = requestID
        isLoadingLocalAIModels = true
        localAIModelListMessage = "ローカルAIを検索中…"
        discoveredLocalAIModels = []
        discoveredLocalAIServers = []

        Task {
            let discoveries = await LocalAIClient().discoverServers()
            await MainActor.run {
                guard localAIModelRefreshID == requestID else { return }
                guard selectedProvider == .localAI else {
                    isLoadingLocalAIModels = false
                    return
                }

                discoveredLocalAIServers = discoveries
                if let first = discoveries.first {
                    applyLocalAIDiscovery(first, messagePrefix: "検出")
                } else {
                    localAIModelListMessage = "ローカルAIサーバーが見つかりません。Start Ollama / Open LM Studio の後に再試行してください。"
                    isLoadingLocalAIModels = false
                }
            }
        }
    }

    private func applyLocalAIDiscovery(
        _ discovery: LocalAIServerDiscovery,
        messagePrefix: String
    ) {
        if localBackendDraft != discovery.backend.rawValue {
            skipNextLocalAIBackendChange = true
            localBackendDraft = discovery.backend.rawValue
        }
        localEndpointDraft = discovery.endpoint
        discoveredLocalAIModels = discovery.models

        let currentModel = localModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let recommended = LocalAIModelInfo.recommendedReplacement(
            from: discovery.models,
            currentModel: currentModel
        ) {
            localModelDraft = recommended.name
        }

        let selectedModel = localModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedSuffix = selectedModel.isEmpty ? "" : " · \(selectedModel) を選択"
        localAIModelListMessage = "\(messagePrefix): \(discovery.displayTitle) · モデル\(discovery.models.count)件\(selectedSuffix)"
        localAITestMessage = nil
        localAITestSucceeded = false
        isLoadingLocalAIModels = false
    }

    private func applyLocalAIDiscoveryFallback(
        _ discoveries: [LocalAIServerDiscovery],
        fallbackMessage: String
    ) {
        discoveredLocalAIServers = discoveries
        if let first = discoveries.first {
            applyLocalAIDiscovery(first, messagePrefix: "自動検出")
        } else {
            localAIModelListMessage = fallbackMessage
            isLoadingLocalAIModels = false
        }
    }

    private func currentLocalAIRequestMatches(
        backend: LocalAIBackend,
        endpoint: String
    ) -> Bool {
        selectedProvider == .localAI
            && backend == selectedLocalBackend
            && endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                == localEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetLocalAIModelDiscovery() {
        localAIModelRefreshID = UUID()
        discoveredLocalAIModels = []
        discoveredLocalAIServers = []
        localAIModelListMessage = nil
        resetLocalAITestResult()
    }

    private func resetLocalAITestResult() {
        localAITestMessage = nil
        localAITestSucceeded = false
    }

    private func openLocalAIServerApp() {
        let result = LocalAIAppLauncher.openServerApp(for: selectedLocalBackend)
        localAIAppLaunchSucceeded = result.succeeded
        localAIAppLaunchMessage = result.message

        guard result.succeeded else { return }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                refreshLocalAIModelsIfUseful(force: true)
            }
        }
    }

    private func refreshLocalAIModelsIfUseful(force: Bool = false) {
        guard selectedProvider == .localAI else { return }
        guard force || !isLoadingLocalAIModels else { return }
        guard !localEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let currentModel = localModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !discoveredLocalAIModels.isEmpty,
           discoveredLocalAIModels.contains(where: { $0.name == currentModel }) {
            return
        }

        refreshLocalAIModels()
    }

    private func testLocalAIConnection() {
        let backend = selectedLocalBackend
        let endpoint = localEndpointDraft
        let model = localModelDraft

        isTestingLocalAI = true
        localAITestMessage = nil
        localAITestSucceeded = false

        Task {
            do {
                let reply = try await LocalAIClient().healthCheck(
                    backend: backend,
                    endpoint: endpoint,
                    model: model
                )
                await MainActor.run {
                    localAITestSucceeded = true
                    localAITestMessage = "接続OK: \(reply.prefix(40))"
                    isTestingLocalAI = false
                }
            } catch {
                await MainActor.run {
                    localAITestSucceeded = false
                    localAITestMessage = error.localizedDescription
                    isTestingLocalAI = false
                }
            }
        }
    }

    private func modelMenuTitle(_ model: LocalAIModelInfo) -> String {
        let hint = model.selectionHint.map { "  ·  \($0)" } ?? ""
        guard let size = model.sizeBytes, size > 0 else {
            return model.name + hint
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return "\(model.name)  ·  \(formatter.string(fromByteCount: size))\(hint)"
    }

    private func serverMenuTitle(_ discovery: LocalAIServerDiscovery) -> String {
        "\(discovery.displayTitle)  ·  \(discovery.models.count) models"
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

struct AppIconMark: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: "character.bubble")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: size * 0.08, y: size * 0.04)
        .accessibilityLabel("Verso")
    }

    private var appIcon: NSImage? {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }
}
