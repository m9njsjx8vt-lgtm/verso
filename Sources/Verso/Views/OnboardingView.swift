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
    @State private var localAIAppLaunchMessage: String?
    @State private var localAIAppLaunchSucceeded: Bool = false

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
                && !isLoadingLocalAIModels
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
            Image(systemName: "character.bubble")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
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
                if localEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || LocalAIBackend.allCases.map(\.defaultEndpoint).contains(localEndpointDraft) {
                    localEndpointDraft = selectedLocalBackend.defaultEndpoint
                }
                discoveredLocalAIModels = []
                localAIModelListMessage = nil
                localAITestMessage = nil
                localAITestSucceeded = false
                localAIAppLaunchMessage = nil
                localAIAppLaunchSucceeded = false
            }

            HStack(spacing: 8) {
                Button {
                    let result = LocalAIAppLauncher.openServerApp(for: selectedLocalBackend)
                    localAIAppLaunchSucceeded = result.succeeded
                    localAIAppLaunchMessage = result.message
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

            TextField("Model name", text: $localModelDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

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

                if isLoadingLocalAIModels {
                    ProgressView()
                        .controlSize(.small)
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

        isLoadingLocalAIModels = true
        localAIModelListMessage = nil
        discoveredLocalAIModels = []

        Task {
            do {
                let models = try await LocalAIClient().listModels(
                    backend: backend,
                    endpoint: endpoint
                )
                await MainActor.run {
                    discoveredLocalAIModels = models
                    let currentModel = localModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if models.isEmpty {
                        localAIModelListMessage = "モデルが見つかりません"
                    } else if let recommended = LocalAIModelInfo.recommendedReplacement(
                        from: models,
                        currentModel: currentModel
                    ) {
                        localModelDraft = recommended.name
                        localAIModelListMessage = "\(models.count) models found · \(recommended.name) を選択"
                    } else {
                        localAIModelListMessage = "\(models.count) models found"
                    }
                    isLoadingLocalAIModels = false
                }
            } catch {
                await MainActor.run {
                    localAIModelListMessage = error.localizedDescription
                    isLoadingLocalAIModels = false
                }
            }
        }
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
        guard let size = model.sizeBytes, size > 0 else {
            return model.name
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return "\(model.name)  ·  \(formatter.string(fromByteCount: size))"
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
