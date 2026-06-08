import Foundation

/// Lightweight localization helper. Picks Japanese or English based on the
/// user-selected `appLanguage` setting (with system fallback).
///
/// Usage:
///   L10n.setLanguage(settings.appLanguage)        // call when settings change
///   text = L10n.t("Translate Clipboard", "クリップボードを翻訳")
///   text = L10n.menuTranslateClipboard
@MainActor
enum L10n {
    private(set) static var current: Language = .system

    enum Language: String, CaseIterable {
        case system, ja, en
        var displayName: String {
            switch self {
            case .system: return "Match system"
            case .ja: return "日本語"
            case .en: return "English"
            }
        }
    }

    static func setLanguage(_ raw: String) {
        current = Language(rawValue: raw) ?? .system
    }

    static var isJapanese: Bool {
        switch current {
        case .ja: return true
        case .en: return false
        case .system:
            return Locale.current.language.languageCode?.identifier == "ja"
        }
    }

    /// Pick string by language: en first, ja second.
    static func t(_ en: String, _ ja: String) -> String {
        isJapanese ? ja : en
    }

    // MARK: - Menu bar

    static var menuTranslateClipboard:    String { t("Translate Clipboard",            "クリップボードを翻訳") }
    static var menuTranslateRegion:       String { t("Translate Region…",              "範囲を選択して翻訳…") }
    static var menuTranslateWindow:       String { t("Translate Frontmost Window…",    "ウィンドウを翻訳…") }
    static var menuOpenWorkspace:         String { t("Open Translator…",               "翻訳ウィンドウを開く…") }
    static var menuHistory:               String { t("History…",                        "履歴…") }
    static var menuPause:                 String { t("Pause Verso",                     "Verso を一時停止") }
    static var menuResume:                String { t("Resume Verso",                    "Verso を再開") }
    static var menuCheckForUpdates:       String { t("Check for Updates…",              "アップデートを確認…") }
    static var menuSettings:              String { t("Settings…",                       "設定…") }
    static var menuShowWelcome:           String { t("Show Welcome Tour…",              "ようこそツアーを表示…") }
    static var menuCheckAccessibility:    String { t("Check Permissions",  "権限を確認") }
    static var menuQuit:                  String { t("Quit Verso",                      "Verso を終了") }

    // MARK: - Settings tabs

    static var tabGeneral:                String { t("General",            "一般") }
    static var tabLanguages:              String { t("Languages",          "言語") }
    static var tabPersonalization:        String { t("Personalization",    "コンテキスト") }
    static var tabGlossary:               String { t("Glossary",           "用語集") }
    static var tabUsage:                  String { t("Usage",              "使用状況") }
    static var tabAbout:                  String { t("About",              "アプリについて") }

    // MARK: - Settings General

    static var sectionApiKey:             String { t("Gemini API Key",     "Gemini APIキー") }
    static var sectionModel:              String { t("Model",              "モデル") }
    static var sectionDeepL:              String { t("DeepL API Key (optional, for instant preview)", "DeepL APIキー (任意・即時プレビュー用)") }
    static var sectionBehavior:           String { t("Behavior",           "動作") }
    static var sectionHotkeys:            String { t("Hotkeys",            "ホットキー") }
    static var sectionPermissions:        String { t("Permissions",        "権限") }
    static var sectionLanguage:           String { t("UI Language",        "UI 言語") }

    // MARK: - Popup

    static var popupTranslating:          String { t("translating…",       "翻訳中…") }
    static var popupCloseHint:            String { t("⤡ drag to resize  •  Esc to close",   "⤡ ドラッグで拡縮  •  Esc で閉じる") }
    static var popupPinnedHint:           String { t("📌 Conversation  •  Esc to close",   "📌 会話モード  •  Esc で閉じる") }
    static var btnInsert:                 String { t("Insert",             "挿入") }
    static var btnCopy:                   String { t("Copy",               "コピー") }
    static var btnClose:                  String { t("Close",              "閉じる") }
    static var btnShorter:                String { t("Shorter",            "短く") }
    static var btnCasual:                 String { t("Casual",             "砕け") }
    static var btnFormal:                 String { t("Formal",             "丁寧") }
    static var btnAlternative:            String { t("Alternative",        "別案") }
    static var btnFurigana:               String { t("Furigana",           "ふりがな") }
    static var btnExplain:                String { t("Explain",            "解説") }
    static var btnAddTerm:                String { t("Add Term",           "用語追加") }
    static var btnRetry:                  String { t("Retry",              "再試行") }
    static var btnUndo:                   String { t("Undo",               "戻す") }
    static var btnEdit:                   String { t("Edit",               "編集") }
    static var btnSaveAndLearn:           String { t("Save & Learn",       "保存して学習") }
    static var btnCancel:                 String { t("Cancel",             "キャンセル") }
    static var btnTranslate:              String { t("Translate",          "翻訳") }

    // MARK: - Workspace window

    static var workspaceTitle:            String { t("Verso — Translator Workspace", "Verso — 翻訳ワークスペース") }
    static var workspaceInputPlaceholder: String { t("Type or paste text to translate…", "翻訳したいテキストを入力 or ペースト…") }
    static var workspaceTranslateBtn:     String { t("Translate (⌘↵)",      "翻訳 (⌘↵)") }
    static var workspaceClearBtn:         String { t("Clear",              "クリア") }
}
