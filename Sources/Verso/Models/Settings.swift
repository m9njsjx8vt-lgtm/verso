import Foundation
import Combine

final class AppSettings: ObservableObject {
    @Published var apiKey: String {
        didSet { KeychainService.set(apiKey, forKey: "geminiApiKey") }
    }

    @Published var translatorContext: String {
        didSet { UserDefaults.standard.set(translatorContext, forKey: "translatorContext") }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }

    init() {
        self.apiKey = KeychainService.get(forKey: "geminiApiKey") ?? ""
        self.translatorContext = UserDefaults.standard.string(forKey: "translatorContext")
            ?? Self.defaultContext
        self.model = UserDefaults.standard.string(forKey: "model")
            ?? "gemini-2.5-flash-lite"
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
