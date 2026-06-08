import Foundation
import Combine

enum TranslationStyle: String, CaseIterable, Identifiable {
    case balanced
    case directBusiness
    case casual
    case polished
    case literal
    case mbaEnglish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .directBusiness: return "Direct Business"
        case .casual: return "Casual"
        case .polished: return "Polished"
        case .literal: return "Literal"
        case .mbaEnglish: return "MBA English"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced:
            return "自然さと正確さのバランスを優先"
        case .directBusiness:
            return "短く、直接的で、仕事でそのまま使いやすい表現"
        case .casual:
            return "チャット向けに軽く、口語寄り"
        case .polished:
            return "外向きの文書・メール向けに丁寧で整った表現"
        case .literal:
            return "意味の取りこぼしを避けるため、原文構造を強めに保持"
        case .mbaEnglish:
            return "MBA・ビジネススクール文脈で使いやすい簡潔な英語"
        }
    }

    var prompt: String {
        switch self {
        case .balanced:
            return """
            ## ACTIVE STYLE
            Balanced: prioritize accurate meaning and natural phrasing. Keep the output concise, but do not flatten nuance.
            """
        case .directBusiness:
            return """
            ## ACTIVE STYLE
            Direct Business: make the output concise, clear, and action-oriented. Prefer active voice. Remove unnecessary politeness, hedging, filler, and repeated phrasing while preserving intent.
            """
        case .casual:
            return """
            ## ACTIVE STYLE
            Casual: write like a practical chat message. Keep it friendly and short. Avoid stiff business wording unless the source clearly requires it.
            """
        case .polished:
            return """
            ## ACTIVE STYLE
            Polished: write for external-facing email or documents. Keep it professional, smooth, and respectful without adding new facts.
            """
        case .literal:
            return """
            ## ACTIVE STYLE
            Literal: stay close to the source structure and terminology. Prioritize traceability over elegance, but still output valid natural language.
            """
        case .mbaEnglish:
            return """
            ## ACTIVE STYLE
            MBA English: when translating into English, use concise business-school English suitable for class discussion, essays, cases, and executive summaries. Prefer precise verbs, plain structure, and defensible wording. When translating into Japanese, keep management and MBA concepts clear and natural.
            """
        }
    }
}

enum TranslationProvider: String, CaseIterable, Identifiable {
    case gemini
    case localAI

    static let defaultProvider: TranslationProvider = .localAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gemini: return "Gemini"
        case .localAI: return "Local AI"
        }
    }

    var subtitle: String {
        switch self {
        case .gemini:
            return "クラウドのGeminiで高速・高品質に翻訳"
        case .localAI:
            return "Ollama / LM Studio など手元のAIで、ネットなしでも翻訳"
        }
    }

    var icon: String {
        switch self {
        case .gemini: return "sparkles"
        case .localAI: return "desktopcomputer"
        }
    }
}

enum LocalAIBackend: String, CaseIterable, Identifiable {
    case ollama
    case openAICompatible

    static let defaultModel = "huihui_ai/qwen3-abliterated:14b"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama: return "Ollama"
        case .openAICompatible: return "OpenAI Compatible"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .openAICompatible: return "http://localhost:1234/v1"
        }
    }

    var endpointHelp: String {
        switch self {
        case .ollama:
            return "例: http://localhost:11434"
        case .openAICompatible:
            return "例: http://localhost:1234/v1 または http://localhost:8080/v1"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    // MARK: - API keys

    @Published var apiKey: String {
        didSet { SecretsStore.set(apiKey, forKey: "geminiApiKey") }
    }

    @Published var deeplApiKey: String {
        didSet { SecretsStore.set(deeplApiKey, forKey: "deeplApiKey") }
    }

    // MARK: - AI engine

    @Published var translationProvider: String {
        didSet { UserDefaults.standard.set(translationProvider, forKey: "translationProvider") }
    }

    @Published var localAIBackend: String {
        didSet {
            UserDefaults.standard.set(localAIBackend, forKey: "localAIBackend")
            let backend = selectedLocalAIBackend
            if localAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                localAIEndpoint = backend.defaultEndpoint
            }
        }
    }

    @Published var localAIEndpoint: String {
        didSet { UserDefaults.standard.set(localAIEndpoint, forKey: "localAIEndpoint") }
    }

    @Published var localAIModel: String {
        didSet { UserDefaults.standard.set(localAIModel, forKey: "localAIModel") }
    }

    // MARK: - Translator behavior

    @Published var translatorContext: String {
        didSet { UserDefaults.standard.set(translatorContext, forKey: "translatorContext") }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }

    @Published var translationStyle: String {
        didSet { UserDefaults.standard.set(translationStyle, forKey: "translationStyle") }
    }

    /// What target to use when source is detected as English.
    @Published var targetWhenEnglish: String {
        didSet { UserDefaults.standard.set(targetWhenEnglish, forKey: "targetWhenEnglish") }
    }

    /// What target to use when source is anything other than English.
    @Published var targetWhenOther: String {
        didSet { UserDefaults.standard.set(targetWhenOther, forKey: "targetWhenOther") }
    }

    /// Preserve Markdown / code / URLs / paths verbatim during translation.
    @Published var preserveMarkdownAndCode: Bool {
        didSet { UserDefaults.standard.set(preserveMarkdownAndCode, forKey: "preserveMarkdownAndCode") }
    }

    // MARK: - Operational toggles

    /// Hotkey detection paused entirely. ⌘C×2 and ⌥⇧C ignored.
    @Published var paused: Bool {
        didSet { UserDefaults.standard.set(paused, forKey: "paused") }
    }

    /// Don't record translations to history.
    @Published var privacyMode: Bool {
        didSet { UserDefaults.standard.set(privacyMode, forKey: "privacyMode") }
    }

    /// Pin popup open (don't auto-dismiss on focus loss). Lighter conversation mode.
    @Published var stayOpen: Bool {
        didSet { UserDefaults.standard.set(stayOpen, forKey: "stayOpen") }
    }

    /// Use the in-memory cache to skip API calls for repeated text.
    @Published var cacheEnabled: Bool {
        didSet { UserDefaults.standard.set(cacheEnabled, forKey: "cacheEnabled") }
    }

    /// UI language: "system" / "ja" / "en"
    @Published var appLanguage: String {
        didSet {
            UserDefaults.standard.set(appLanguage, forKey: "appLanguage")
            L10n.setLanguage(appLanguage)
            NotificationCenter.default.post(name: .versoLanguageChanged, object: nil)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init() {
        let d = UserDefaults.standard
        let storedApiKey = SecretsStore.get("geminiApiKey") ?? ""
        self.apiKey = storedApiKey
        self.deeplApiKey = SecretsStore.get("deeplApiKey") ?? ""
        let savedProvider = d.string(forKey: "translationProvider") ?? TranslationProvider.defaultProvider.rawValue
        self.translationProvider = TranslationProvider(rawValue: savedProvider)?.rawValue
            ?? TranslationProvider.defaultProvider.rawValue
        let savedBackend = d.string(forKey: "localAIBackend") ?? LocalAIBackend.ollama.rawValue
        let resolvedBackend = LocalAIBackend(rawValue: savedBackend) ?? .ollama
        self.localAIBackend = resolvedBackend.rawValue
        let backend = resolvedBackend
        self.localAIEndpoint = d.string(forKey: "localAIEndpoint") ?? backend.defaultEndpoint
        self.localAIModel = d.string(forKey: "localAIModel") ?? LocalAIBackend.defaultModel
        self.translatorContext = d.string(forKey: "translatorContext") ?? Self.defaultContext
        self.model = d.string(forKey: "model") ?? "gemini-2.5-flash-lite"
        let savedStyle = d.string(forKey: "translationStyle") ?? TranslationStyle.directBusiness.rawValue
        self.translationStyle = TranslationStyle(rawValue: savedStyle)?.rawValue
            ?? TranslationStyle.directBusiness.rawValue
        self.targetWhenEnglish = d.string(forKey: "targetWhenEnglish") ?? "JA"
        self.targetWhenOther = d.string(forKey: "targetWhenOther") ?? "EN"
        self.preserveMarkdownAndCode = d.object(forKey: "preserveMarkdownAndCode") as? Bool ?? true
        self.paused = d.bool(forKey: "paused")
        self.privacyMode = d.bool(forKey: "privacyMode")
        self.stayOpen = d.bool(forKey: "stayOpen")
        self.cacheEnabled = d.object(forKey: "cacheEnabled") as? Bool ?? true
        self.appLanguage = d.string(forKey: "appLanguage") ?? "system"
        self.hasCompletedOnboarding = d.object(forKey: "hasCompletedOnboarding") as? Bool ?? !storedApiKey.isEmpty
        L10n.setLanguage(self.appLanguage)
    }

    var selectedTranslationProvider: TranslationProvider {
        TranslationProvider(rawValue: translationProvider) ?? TranslationProvider.defaultProvider
    }

    var selectedLocalAIBackend: LocalAIBackend {
        LocalAIBackend(rawValue: localAIBackend) ?? .ollama
    }

    var usesLocalAI: Bool {
        selectedTranslationProvider == .localAI
    }

    var primaryProviderTitle: String {
        selectedTranslationProvider.title
    }

    var primaryProviderIcon: String {
        selectedTranslationProvider.icon
    }

    var activeModelKey: String {
        modelKey(useLocalAI: usesLocalAI)
    }

    var localAIActiveModelKey: String {
        [
            "local",
            selectedLocalAIBackend.rawValue,
            localAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        ].joined(separator: ":")
    }

    func providerTitle(useLocalAI: Bool) -> String {
        useLocalAI ? TranslationProvider.localAI.title : selectedTranslationProvider.title
    }

    func providerIcon(useLocalAI: Bool) -> String {
        useLocalAI ? TranslationProvider.localAI.icon : selectedTranslationProvider.icon
    }

    func modelKey(useLocalAI: Bool) -> String {
        useLocalAI ? localAIActiveModelKey : model
    }

    var selectedTranslationStyle: TranslationStyle {
        TranslationStyle(rawValue: translationStyle) ?? .directBusiness
    }

    func promptContext(additionalBlocks: [String?] = []) -> String {
        ([translatorContext, selectedTranslationStyle.prompt] + additionalBlocks)
            .compactMap { value in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty
                else { return nil }
                return value
            }
            .joined(separator: "\n\n")
    }

    static let defaultContext: String = """
    # 翻訳コンテキスト

    自由に編集してください。ここに書いた内容が毎回プロンプトに混ざります。

    ## トーン

    - 日本語→英語: 簡潔・直接的なビジネス英語。能動態。冗長な敬語を削ぐ。
    - 英語→日本語: 自然で短い日本語。ビジネスは「です・ます」、カジュアルな文脈は口語。

    ## 固有名詞（そのまま保持）

    （社名、プロジェクト名、人名などをここに）

    ## 業界用語

    （特殊な訳語マッピングをここに）

    ## やってほしくないこと

    - 訳注・括弧書きの解説を追加しない
    - 原文にない情報を補完しない
    - 翻訳以外のコメント・前置きを出力しない
    """
}
