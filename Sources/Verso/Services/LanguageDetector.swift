import Foundation
import NaturalLanguage

/// Source-language detection + mapping to display / DeepL / Gemini names.
/// Falls back to JA-EN heuristic when NL detection is uncertain.
enum LanguageDetector {

    /// Result of detection: (sourceCode, targetCode, sourceFullName, targetFullName)
    /// - codes are short uppercase tokens for the popup header (e.g. "JA")
    /// - names are full English language names for the LLM prompt (e.g. "Japanese")
    struct Pair {
        let sourceShort: String
        let targetShort: String
        let sourceFull: String
        let targetFull: String
        /// DeepL target_lang code (e.g. "EN-US", "JA", "ZH", "KO", "ES", "FR")
        let deepLTarget: String
        /// DeepL source_lang code (optional — DeepL auto-detects)
        let deepLSource: String?
    }

    static func detect(_ text: String, defaultTargetForEnglish: String = "JA") -> Pair {
        // 1. Try Apple NL framework
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))   // sample first 2K chars
        let dominant = recognizer.dominantLanguage

        // 2. Map to our internal model
        let detected = (dominant.flatMap { mapping[$0.rawValue] }) ?? fallback(text)

        // 3. Pick target
        // - If source is English → target is user's preferred (default Japanese)
        // - Otherwise → target is English
        let target: LangInfo
        if detected.short == "EN" {
            target = mapping[defaultTargetForEnglish.lowercased()] ?? japanese
        } else {
            target = english
        }

        return Pair(
            sourceShort: detected.short,
            targetShort: target.short,
            sourceFull: detected.fullName,
            targetFull: target.fullName,
            deepLTarget: target.deepL,
            deepLSource: detected.deepL
        )
    }

    // MARK: - Internal

    private struct LangInfo {
        let short: String       // "JA"
        let fullName: String    // "Japanese"
        let deepL: String       // "JA"
    }

    private static let english   = LangInfo(short: "EN", fullName: "English",  deepL: "EN-US")
    private static let japanese  = LangInfo(short: "JA", fullName: "Japanese", deepL: "JA")
    private static let chinese   = LangInfo(short: "ZH", fullName: "Chinese",  deepL: "ZH")
    private static let korean    = LangInfo(short: "KO", fullName: "Korean",   deepL: "KO")
    private static let spanish   = LangInfo(short: "ES", fullName: "Spanish",  deepL: "ES")
    private static let french    = LangInfo(short: "FR", fullName: "French",   deepL: "FR")
    private static let german    = LangInfo(short: "DE", fullName: "German",   deepL: "DE")
    private static let italian   = LangInfo(short: "IT", fullName: "Italian",  deepL: "IT")
    private static let portuguese = LangInfo(short: "PT", fullName: "Portuguese", deepL: "PT-PT")
    private static let russian   = LangInfo(short: "RU", fullName: "Russian",  deepL: "RU")

    private static let mapping: [String: LangInfo] = [
        // NLLanguage raw values
        "en": english, "ja": japanese, "zh-Hans": chinese, "zh-Hant": chinese, "zh": chinese,
        "ko": korean, "es": spanish, "fr": french, "de": german, "it": italian,
        "pt": portuguese, "ru": russian,
        // Convenience (UPPER, for explicit settings)
        "EN": english, "JA": japanese, "ZH": chinese, "KO": korean,
        "ES": spanish, "FR": french, "DE": german, "IT": italian,
        "PT": portuguese, "RU": russian,
    ]

    /// Heuristic fallback when NL framework returns nothing
    private static func fallback(_ text: String) -> LangInfo {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v)   // Hiragana
                || (0x30A0...0x30FF).contains(v) // Katakana
            {
                return japanese
            }
        }
        // CJK ideographs without kana → could be Chinese
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) {
                return chinese
            }
        }
        // Hangul
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0xAC00...0xD7AF).contains(v) {
                return korean
            }
        }
        return english
    }
}
