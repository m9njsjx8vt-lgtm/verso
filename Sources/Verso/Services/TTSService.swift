import AVFoundation

/// Text-to-speech for translation playback. Picks a voice based on the target language.
@MainActor
final class TTSService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, languageShort: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: languageShort)
        utterance.rate = 0.5  // a touch slower than default for clarity
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    private func voice(for short: String) -> AVSpeechSynthesisVoice? {
        let code: String
        switch short {
        case "JA": code = "ja-JP"
        case "EN": code = "en-US"
        case "ZH": code = "zh-CN"
        case "KO": code = "ko-KR"
        case "ES": code = "es-ES"
        case "FR": code = "fr-FR"
        case "DE": code = "de-DE"
        case "IT": code = "it-IT"
        case "PT": code = "pt-PT"
        case "RU": code = "ru-RU"
        default:   code = "en-US"
        }
        return AVSpeechSynthesisVoice(language: code)
    }
}
