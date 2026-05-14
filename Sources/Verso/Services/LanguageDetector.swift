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

    static func detect(
        _ text: String,
        defaultTargetForEnglish: String = "JA",
        defaultTargetForOther: String = "EN",
        forceTargetShort: String? = nil   // explicit user override from popup picker
    ) -> Pair {
        // 1. STRONG SCRIPT SIGNALS first — these are unambiguous and beat the NL recognizer
        //    (NL gets confused by mixed-language text, e.g. JA prose with embedded English code)
        let detected: LangInfo
        if let scriptHit = strongScriptSignal(text) {
            detected = scriptHit
        } else {
            // 2. Fall back to Apple NL framework for Latin-script languages
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(String(text.prefix(2000)))
            detected = (recognizer.dominantLanguage.flatMap { mapping[$0.rawValue] }) ?? fallback(text)
        }

        // 3. Pick target
        //   priority: explicit override > defaultTargetForEnglish > defaultTargetForOther
        let target: LangInfo
        if let force = forceTargetShort,
           let forced = mapping[force] ?? mapping[force.uppercased()] ?? mapping[force.lowercased()] {
            target = forced
        } else if detected.short == "EN" {
            target = mapping[defaultTargetForEnglish.lowercased()] ?? mapping[defaultTargetForEnglish.uppercased()] ?? japanese
        } else {
            target = mapping[defaultTargetForOther.lowercased()] ?? mapping[defaultTargetForOther.uppercased()] ?? english
        }
        // Avoid same-language no-op (e.g. JA → JA): fall back to English
        let finalTarget = (target.short == detected.short) ? english : target

        return Pair(
            sourceShort: detected.short,
            targetShort: finalTarget.short,
            sourceFull: detected.fullName,
            targetFull: finalTarget.fullName,
            deepLTarget: finalTarget.deepLTarget,
            deepLSource: detected.deepLSource
        )
    }

    /// All available target languages for the popup picker.
    static let availableTargets: [(short: String, fullName: String)] = [
        ("EN", "English"), ("JA", "Japanese"), ("ZH", "Chinese"),
        ("KO", "Korean"), ("ES", "Spanish"), ("FR", "French"),
        ("DE", "German"), ("IT", "Italian"), ("PT", "Portuguese"),
        ("RU", "Russian"),
    ]

    // MARK: - Internal

    private struct LangInfo {
        let short: String           // "JA"   — popup header
        let fullName: String        // "Japanese" — LLM prompt
        let deepLSource: String     // "EN"  — DeepL source_lang accepts NO region suffix
        let deepLTarget: String     // "EN-US" — DeepL target_lang accepts region suffix
    }

    private static let english   = LangInfo(short: "EN", fullName: "English",  deepLSource: "EN", deepLTarget: "EN-US")
    private static let japanese  = LangInfo(short: "JA", fullName: "Japanese", deepLSource: "JA", deepLTarget: "JA")
    private static let chinese   = LangInfo(short: "ZH", fullName: "Chinese",  deepLSource: "ZH", deepLTarget: "ZH")
    private static let korean    = LangInfo(short: "KO", fullName: "Korean",   deepLSource: "KO", deepLTarget: "KO")
    private static let spanish   = LangInfo(short: "ES", fullName: "Spanish",  deepLSource: "ES", deepLTarget: "ES")
    private static let french    = LangInfo(short: "FR", fullName: "French",   deepLSource: "FR", deepLTarget: "FR")
    private static let german    = LangInfo(short: "DE", fullName: "German",   deepLSource: "DE", deepLTarget: "DE")
    private static let italian   = LangInfo(short: "IT", fullName: "Italian",  deepLSource: "IT", deepLTarget: "IT")
    private static let portuguese = LangInfo(short: "PT", fullName: "Portuguese", deepLSource: "PT", deepLTarget: "PT-PT")
    private static let russian   = LangInfo(short: "RU", fullName: "Russian",  deepLSource: "RU", deepLTarget: "RU")

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

    /// Strong, unambiguous script signals: hiragana/katakana = always Japanese,
    /// hangul = always Korean. CJK ideographs alone are NOT enough (could be Chinese).
    private static func strongScriptSignal(_ text: String) -> LangInfo? {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // Hiragana (0x3040–0x309F) or Katakana (0x30A0–0x30FF) → definitely Japanese
            if (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v) {
                return japanese
            }
            // Hangul Syllables → definitely Korean
            if (0xAC00...0xD7AF).contains(v) {
                return korean
            }
        }
        return nil
    }

    /// Last-resort fallback (after both strong signals + NL recognizer). Treats CJK
    /// ideographs as Chinese, otherwise English.
    private static func fallback(_ text: String) -> LangInfo {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) {
                return chinese
            }
        }
        return english
    }
}
