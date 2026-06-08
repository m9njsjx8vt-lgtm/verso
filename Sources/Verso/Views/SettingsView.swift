import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var glossary: Glossary
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var writingMistakes: WritingMistakeStore
    @EnvironmentObject var usage: UsageTracker
    @State private var showApiKey: Bool = false
    @State private var isConfirmingClearUsage: Bool = false
    @State private var isConfirmingClearWritingMistakes: Bool = false
    @State private var isConfirmingResetContext: Bool = false
    @State private var isTestingLocalAI: Bool = false
    @State private var localAITestMessage: String?
    @State private var localAITestSucceeded: Bool = false
    @State private var localAITestRequestID = UUID()
    @State private var isLoadingLocalAIModels: Bool = false
    @State private var localAIModelListMessage: String?
    @State private var discoveredLocalAIModels: [LocalAIModelInfo] = []
    @State private var discoveredLocalAIServers: [LocalAIServerDiscovery] = []
    @State private var localAIModelRefreshID = UUID()
    @State private var localAIAppLaunchMessage: String?
    @State private var localAIAppLaunchSucceeded: Bool = false
    @State private var skipNextLocalAIBackendChange: Bool = false
    @State private var permissionRefreshID = UUID()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(L10n.tabGeneral, systemImage: "gearshape") }

            languagesTab
                .tabItem { Label(L10n.tabLanguages, systemImage: "globe") }

            contextTab
                .tabItem { Label(L10n.tabPersonalization, systemImage: "person.text.rectangle") }

            GlossaryTabView(glossary: glossary)
                .tabItem { Label(L10n.tabGlossary, systemImage: "book") }

            writingTab
                .tabItem { Label("Writing", systemImage: "checkmark.seal") }

            usageTab
                .tabItem { Label(L10n.tabUsage, systemImage: "chart.bar") }

            aboutTab
                .tabItem { Label(L10n.tabAbout, systemImage: "info.circle") }
        }
        .frame(width: 660, height: 560)
        .padding(20)
        .onAppear {
            refreshLocalAIModelsIfUseful()
        }
        .onChange(of: settings.translationProvider) { _ in
            resetLocalAITestResult()
            refreshLocalAIModelsIfUseful(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshID = UUID()
        }
    }

    // MARK: - General

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    Text("AI Engine").font(.headline)
                    Picker("", selection: $settings.translationProvider) {
                        ForEach(TranslationProvider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.selectedTranslationProvider.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if settings.usesLocalAI {
                        localAISettings
                    } else {
                        geminiSettings
                    }
                }

                Divider()

                Group {
                    Text("Translation Style").font(.headline)
                    Picker("", selection: $settings.translationStyle) {
                        ForEach(TranslationStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Text(settings.selectedTranslationStyle.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Group {
                    Text("DeepL API Key (任意・即時プレビュー用)").font(.headline)
                    Text("登録すると⌘C×2した瞬間にDeepLの即時翻訳が出ます。月50万文字まで無料。Get a free key at [deepl.com/pro-api](https://www.deepl.com/pro-api).")
                        .font(.caption).foregroundColor(.secondary)
                    SecureField("DeepL key (空欄でもOK)", text: $settings.deeplApiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                Group {
                    Text("Behavior").font(.headline)
                    Picker("表示する結果", selection: $settings.providerDisplayMode) {
                        ForEach(ProviderDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.selectedProviderDisplayMode.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("📌 Stay open after action (popupを自動で閉じない)", isOn: $settings.stayOpen)
                    Toggle("🔒 Privacy mode (履歴に保存しない)", isOn: $settings.privacyMode)
                    Toggle("⚡ 翻訳キャッシュを使う (同じ文章は即時)", isOn: $settings.cacheEnabled)
                    Toggle("📝 Markdown / コード / URL を保持", isOn: $settings.preserveMarkdownAndCode)
                    Toggle("⏸️ Verso を一時停止 (ホットキー無効化)", isOn: $settings.paused)
                }

                Divider()

                Group {
                    Text("Hotkeys").font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("⌘C × 2  →  選択テキストを翻訳").font(.system(.body, design: .monospaced))
                        Text("⌥⇧C    →  画面領域 OCR 翻訳").font(.system(.body, design: .monospaced))
                        Text("⌘⇧H    →  History").font(.system(.body, design: .monospaced))
                        Text("⌘⇧V    →  クリップボード翻訳").font(.system(.body, design: .monospaced))
                        Text("⌘⇧T    →  翻訳ワークスペース").font(.system(.body, design: .monospaced))
                    }
                    .font(.system(size: 13)).foregroundColor(.secondary)
                }

                Divider()

                Group {
                    Text(L10n.sectionLanguage).font(.headline)
                    Picker("", selection: $settings.appLanguage) {
                        ForEach(L10n.Language.allCases, id: \.rawValue) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(L10n.t(
                        "Affects menu bar items, settings tabs, and major button labels. Refine button names (短く / 砕け…) stay in Japanese as conventional shortcuts.",
                        "メニューバー、設定タブ、主要ボタンに反映されます。Refineボタン (短く / 砕け…) は慣習として日本語のままです。"
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Divider()

                Group {
                    Text(L10n.sectionPermissions).font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: AccessibilityService.isTrusted()
                                ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(AccessibilityService.isTrusted() ? .green : .orange)
                            Text(AccessibilityService.isTrusted()
                                ? "Accessibility OK" : "Accessibility 未許可 — ホットキー効きません")
                            Spacer()
                            if !AccessibilityService.isTrusted() {
                                Button("Open Settings") {
                                    _ = AccessibilityService.checkAndPromptIfNeeded()
                                    permissionRefreshID = UUID()
                                }
                            }
                        }

                        HStack {
                            Image(systemName: ScreenCapturePermissionService.isTrusted()
                                ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(ScreenCapturePermissionService.isTrusted() ? .green : .orange)
                            Text(ScreenCapturePermissionService.isTrusted()
                                ? "Screen Recording OK" : "Screen Recording 未許可 — OCR翻訳に必要")
                            Spacer()
                            if !ScreenCapturePermissionService.isTrusted() {
                                Button("Request") {
                                    _ = ScreenCapturePermissionService.requestIfNeeded()
                                    permissionRefreshID = UUID()
                                }
                            }
                        }

                        Button {
                            permissionRefreshID = UUID()
                        } label: {
                            Label("Refresh Permissions", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                    }
                    .id(permissionRefreshID)
                    .font(.system(size: 13))
                }

                Spacer()
            }
            .padding()
        }
    }

    private var geminiSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gemini API Key").font(.subheadline).fontWeight(.semibold)
            Text("Get a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey).")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Group {
                    if showApiKey { TextField("AIza…", text: $settings.apiKey) }
                    else { SecureField("AIza…", text: $settings.apiKey) }
                }
                .textFieldStyle(.roundedBorder)
                Button(showApiKey ? "Hide" : "Show") { showApiKey.toggle() }
            }
            Text("APIキーが空欄、またはオフライン時は Local AI に自動切替します。")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Model").font(.subheadline).fontWeight(.semibold)
            Picker("", selection: $settings.model) {
                Text("Gemini 2.5 Flash-Lite — free, fast (1000 RPD)").tag("gemini-2.5-flash-lite")
                Text("Gemini 2.5 Flash — better quality (250 RPD free)").tag("gemini-2.5-flash")
                Text("Gemini 2.5 Pro — best, paid tier recommended").tag("gemini-2.5-pro")
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var localAISettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Backend", selection: $settings.localAIBackend) {
                ForEach(LocalAIBackend.allCases) { backend in
                    Text(backend.title).tag(backend.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: settings.localAIBackend) { _ in
                if skipNextLocalAIBackendChange {
                    skipNextLocalAIBackendChange = false
                    return
                }
                if settings.localAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || LocalAIBackend.allCases.map(\.defaultEndpoint).contains(settings.localAIEndpoint) {
                    settings.localAIEndpoint = settings.selectedLocalAIBackend.defaultEndpoint
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
                        LocalAIAppLauncher.buttonTitle(for: settings.selectedLocalAIBackend),
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

            TextField(settings.selectedLocalAIBackend.endpointHelp, text: $settings.localAIEndpoint)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: settings.localAIEndpoint) { _ in
                    resetLocalAIModelDiscovery()
                }

            TextField("Model name, e.g. huihui_ai/qwen3-abliterated:14b", text: $settings.localAIModel)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: settings.localAIModel) { _ in
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
                    || settings.localAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
                                if discovery.backend == settings.selectedLocalAIBackend
                                    && discovery.endpoint == settings.localAIEndpoint {
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
                                settings.localAIModel = model.name
                            } label: {
                                if model.name == settings.localAIModel {
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

                if let message = localAIModelListMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
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
                    || settings.localAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || settings.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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

            Text("Detect Local AI はOllama / LM Studio系のローカルサーバーを探します。Ollama は通常 `http://localhost:11434`、LM Studio は OpenAI Compatible の `/v1` endpoint を使います。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func refreshLocalAIModels() {
        let backend = settings.selectedLocalAIBackend
        let endpoint = settings.localAIEndpoint
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
                    let currentModel = settings.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let recommended = LocalAIModelInfo.recommendedReplacement(
                        from: models,
                        currentModel: currentModel
                    ) {
                        settings.localAIModel = recommended.name
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
                guard settings.usesLocalAI else {
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
        if settings.localAIBackend != discovery.backend.rawValue {
            skipNextLocalAIBackendChange = true
            settings.localAIBackend = discovery.backend.rawValue
        }
        settings.localAIEndpoint = discovery.endpoint
        discoveredLocalAIModels = discovery.models

        let currentModel = settings.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let recommended = LocalAIModelInfo.recommendedReplacement(
            from: discovery.models,
            currentModel: currentModel
        ) {
            settings.localAIModel = recommended.name
        }

        let selectedModel = settings.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
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
        settings.usesLocalAI
            && backend == settings.selectedLocalAIBackend
            && endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                == settings.localAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetLocalAIModelDiscovery() {
        localAIModelRefreshID = UUID()
        discoveredLocalAIModels = []
        discoveredLocalAIServers = []
        localAIModelListMessage = nil
        resetLocalAITestResult()
    }

    private func resetLocalAITestResult() {
        localAITestRequestID = UUID()
        isTestingLocalAI = false
        localAITestMessage = nil
        localAITestSucceeded = false
    }

    private func openLocalAIServerApp() {
        let result = LocalAIAppLauncher.openServerApp(for: settings.selectedLocalAIBackend)
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
        guard settings.usesLocalAI else { return }
        guard force || !isLoadingLocalAIModels else { return }
        guard !settings.localAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let currentModel = settings.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !discoveredLocalAIModels.isEmpty,
           discoveredLocalAIModels.contains(where: { $0.name == currentModel }) {
            return
        }

        refreshLocalAIModels()
    }

    private func testLocalAIConnection() {
        let backend = settings.selectedLocalAIBackend
        let endpoint = settings.localAIEndpoint
        let model = settings.localAIModel
        let requestID = UUID()

        localAITestRequestID = requestID
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
                    guard localAITestRequestID == requestID else { return }
                    guard currentLocalAITestRequestMatches(
                        backend: backend,
                        endpoint: endpoint,
                        model: model
                    ) else { return }
                    localAITestSucceeded = true
                    localAITestMessage = "接続OK: \(reply.prefix(40))"
                    isTestingLocalAI = false
                }
            } catch {
                await MainActor.run {
                    guard localAITestRequestID == requestID else { return }
                    guard currentLocalAITestRequestMatches(
                        backend: backend,
                        endpoint: endpoint,
                        model: model
                    ) else { return }
                    localAITestSucceeded = false
                    localAITestMessage = error.localizedDescription
                    isTestingLocalAI = false
                }
            }
        }
    }

    private func currentLocalAITestRequestMatches(
        backend: LocalAIBackend,
        endpoint: String,
        model: String
    ) -> Bool {
        currentLocalAIRequestMatches(backend: backend, endpoint: endpoint)
            && model.trimmingCharacters(in: .whitespacesAndNewlines)
                == settings.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Languages

    private var languagesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("デフォルトのターゲット言語")
                .font(.headline)
            Text("自動判定された入力言語に応じて、翻訳先言語を決めます。ポップアップ内で個別に上書きも可能。")
                .font(.caption).foregroundColor(.secondary)

            HStack {
                Text("入力が **英語** のとき → ").frame(width: 200, alignment: .leading)
                Picker("", selection: $settings.targetWhenEnglish) {
                    ForEach(LanguageDetector.availableTargets, id: \.short) {
                        Text("\($0.short)  \($0.fullName)").tag($0.short)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 220)
            }

            HStack {
                Text("入力が **その他** のとき → ").frame(width: 200, alignment: .leading)
                Picker("", selection: $settings.targetWhenOther) {
                    ForEach(LanguageDetector.availableTargets, id: \.short) {
                        Text("\($0.short)  \($0.fullName)").tag($0.short)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 220)
            }

            Divider()

            Text("対応言語の自動判定")
                .font(.headline)
            Text("入力言語は自動判定されます: 日本語(JA) / 英語(EN) / 中国語(ZH) / 韓国語(KO) / スペイン語(ES) / フランス語(FR) / ドイツ語(DE) / イタリア語(IT) / ポルトガル語(PT) / ロシア語(RU)")
                .font(.caption).foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Context

    private var contextTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Translator Context").font(.headline)
            Text("プロンプトに毎回注入されるあなた専用のコンテキスト。トーン、ロールプレイ、業界の前提を書く。固有名詞や具体的な訳語は Glossary タブへ。")
                .font(.caption).foregroundColor(.secondary)

            TextEditor(text: $settings.translatorContext)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Reset to default") {
                    isConfirmingResetContext = true
                }
                .controlSize(.small)
            }
        }
        .padding()
        .confirmationDialog(
            "Reset translator context?",
            isPresented: $isConfirmingResetContext
        ) {
            Button("Reset context", role: .destructive) {
                settings.translatorContext = AppSettings.defaultContext
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your current custom tone, terminology notes, and translation preferences.")
        }
    }

    // MARK: - Writing

    private var writingTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自分の英文ミス傾向").font(.headline)
                    Text("ポップアップの「添削」は、自分で書いた英文だけを直して、よくあるミスをここに蓄積します。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Clear", role: .destructive) {
                    isConfirmingClearWritingMistakes = true
                }
                .controlSize(.small)
                .disabled(writingMistakes.entries.isEmpty)
            }

            HStack(spacing: 14) {
                writingStat(title: "記録", value: "\(writingMistakes.entries.count)")
                writingStat(title: "傾向", value: "\(writingMistakes.summaries().count)")
            }

            if writingMistakes.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("まだ記録はありません")
                        .font(.headline)
                    Text("英文を選択して翻訳ポップアップを開き、「添削」を押すとここに蓄積されます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(writingMistakes.summaries()) { summary in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(summary.title)
                                    .font(.headline)
                                Text(summary.categoryLabel)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .cornerRadius(5)
                                Spacer()
                                Text("\(summary.count)回")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text(summary.sampleBefore)
                                    .foregroundColor(.red)
                                    .strikethrough()
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(summary.sampleAfter)
                                    .foregroundColor(.green)
                            }
                            .font(.callout)
                            .textSelection(.enabled)

                            if !summary.sampleExplanation.isEmpty {
                                Text(summary.sampleExplanation)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding()
        .confirmationDialog(
            "Clear writing mistake history?",
            isPresented: $isConfirmingClearWritingMistakes
        ) {
            Button("Clear writing mistakes", role: .destructive) {
                writingMistakes.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("添削で蓄積したミス傾向だけを削除します。翻訳履歴や用語集は残ります。")
        }
    }

    private func writingStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(width: 120, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Usage

    private var usageTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cloud API 使用状況").font(.headline)
            Text("Geminiで発生したトークン使用量とコスト概算。Local AIの翻訳は端末内で処理されるためAPIコストは発生しません。")
                .font(.caption).foregroundColor(.secondary)

            let today = usage.todayStats()
            let month = usage.monthStats()
            let total = usage.allTimeStats()

            VStack(spacing: 0) {
                statRow("Today",      calls: today.calls, tokens: today.tokens, cost: today.cost)
                Divider()
                statRow("This month", calls: month.calls, tokens: month.tokens, cost: month.cost)
                Divider()
                statRow("All time",   calls: total.calls, tokens: total.tokens, cost: total.cost)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )

            HStack {
                Spacer()
                Button("Clear usage history", role: .destructive) {
                    isConfirmingClearUsage = true
                }
                .controlSize(.small)
            }

            Spacer()
        }
        .padding()
        .confirmationDialog(
            "Clear usage history?",
            isPresented: $isConfirmingClearUsage
        ) {
            Button("Clear usage history", role: .destructive) {
                usage.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets cloud API usage estimates. It does not delete translation history or API keys.")
        }
    }

    private func statRow(_ label: String, calls: Int, tokens: Int, cost: Double) -> some View {
        HStack {
            Text(label).fontWeight(.medium).frame(width: 110, alignment: .leading)
            Text("\(calls) calls").frame(width: 90, alignment: .leading)
                .foregroundColor(.secondary)
            Text("\(tokens) tokens").frame(width: 130, alignment: .leading)
                .foregroundColor(.secondary)
            Text(String(format: "≈ $%.4f", cost)).frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundColor(cost > 0.5 ? .orange : .primary)
        }
        .font(.system(.body, design: .monospaced))
        .padding(.vertical, 6)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            AppIconMark(size: 72)
            Text("Verso").font(.title).bold()
            Text("Personal AI translation, on every page")
                .font(.callout).foregroundColor(.secondary)
            Text(appVersionText).foregroundColor(.secondary).padding(.top, 4)
            VStack(spacing: 4) {
                Text("⌘C×2  →  選択翻訳")
                Text("⌥⇧C   →  領域OCR翻訳")
                Text("⌘⇧V   →  クリップボード翻訳")
                Text("⌘⇧H   →  履歴")
            }.font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "v\(shortVersion)" : "v\(shortVersion) (\(build))"
    }
}

// MARK: - Glossary tab with import/export

struct GlossaryTabView: View {
    @ObservedObject var glossary: Glossary
    @State private var fileOperationMessage: String?
    @State private var fileOperationSucceeded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    exportGlossary()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
                .disabled(glossary.entries.isEmpty)
                Button {
                    importGlossary()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
            }
            if let fileOperationMessage {
                Label(fileOperationMessage, systemImage: fileOperationSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(fileOperationSucceeded ? .secondary : .red)
                    .lineLimit(2)
            }
            GlossaryView(glossary: glossary)
        }
    }

    private func exportGlossary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "verso-glossary.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(glossary.entries)
                try data.write(to: url, options: .atomic)
                setFileOperationMessage(
                    "\(glossary.entries.count) 件を \(url.lastPathComponent) に書き出しました。",
                    succeeded: true
                )
            } catch {
                setFileOperationMessage("Glossary の書き出しに失敗しました。", succeeded: false)
                NSAlert(error: error).runModal()
            }
        }
    }

    private func importGlossary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let imported = try JSONDecoder().decode([GlossaryEntry].self, from: data)
                guard !imported.isEmpty else {
                    setFileOperationMessage("取り込める Glossary エントリがありませんでした。", succeeded: false)
                    return
                }

                let alert = NSAlert()
                alert.messageText = "Glossary をインポート"
                alert.informativeText = "\(imported.count) 件のエントリを取り込みます。既存に追加 or 全置換、どちらにしますか？"
                alert.addButton(withTitle: "追加")
                alert.addButton(withTitle: "全置換")
                alert.addButton(withTitle: "キャンセル")
                let resp = alert.runModal()

                if resp == .alertFirstButtonReturn {
                    setImportResultMessage(glossary.importEntries(imported, replacingExisting: false))
                } else if resp == .alertSecondButtonReturn {
                    setImportResultMessage(glossary.importEntries(imported, replacingExisting: true))
                }
            } catch {
                setFileOperationMessage("Glossary の取り込みに失敗しました。", succeeded: false)
                NSAlert(error: error).runModal()
            }
        }
    }

    private func setImportResultMessage(_ result: GlossaryImportResult) {
        if result.skipped > 0 {
            setFileOperationMessage(
                "\(result.added) 件を取り込みました。\(result.skipped) 件は空欄または重複のためスキップしました。",
                succeeded: result.added > 0
            )
        } else {
            setFileOperationMessage("\(result.added) 件を取り込みました。", succeeded: true)
        }
    }

    private func setFileOperationMessage(_ message: String, succeeded: Bool) {
        fileOperationMessage = message
        fileOperationSucceeded = succeeded
    }
}
