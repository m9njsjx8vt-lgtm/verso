import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    // MARK: - API keys

    @Published var apiKey: String {
        didSet { SecretsStore.set(apiKey, forKey: "geminiApiKey") }
    }

    @Published var deeplApiKey: String {
        didSet { SecretsStore.set(deeplApiKey, forKey: "deeplApiKey") }
    }

    // MARK: - Translator behavior

    @Published var translatorContext: String {
        didSet { UserDefaults.standard.set(translatorContext, forKey: "translatorContext") }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
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

    init() {
        let d = UserDefaults.standard
        self.apiKey = SecretsStore.get("geminiApiKey") ?? ""
        self.deeplApiKey = SecretsStore.get("deeplApiKey") ?? ""
        self.translatorContext = d.string(forKey: "translatorContext") ?? Self.defaultContext
        self.model = d.string(forKey: "model") ?? "gemini-2.5-flash-lite"
        self.targetWhenEnglish = d.string(forKey: "targetWhenEnglish") ?? "JA"
        self.targetWhenOther = d.string(forKey: "targetWhenOther") ?? "EN"
        self.preserveMarkdownAndCode = d.object(forKey: "preserveMarkdownAndCode") as? Bool ?? true
        self.paused = d.bool(forKey: "paused")
        self.privacyMode = d.bool(forKey: "privacyMode")
        self.stayOpen = d.bool(forKey: "stayOpen")
        self.cacheEnabled = d.object(forKey: "cacheEnabled") as? Bool ?? true
        self.appLanguage = d.string(forKey: "appLanguage") ?? "system"
        L10n.setLanguage(self.appLanguage)
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
