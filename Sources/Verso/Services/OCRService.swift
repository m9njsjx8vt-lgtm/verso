@preconcurrency import Vision
import AppKit

enum OCRError: LocalizedError {
    case noText
    case visionFailure(Error)

    var errorDescription: String? {
        switch self {
        case .noText: return "テキストが検出されませんでした。"
        case .visionFailure(let err): return "OCRエラー: \(err.localizedDescription)"
        }
    }
}

enum OCRService {
    /// Recognize text in `cgImage` using macOS Vision (Japanese + English).
    static func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.visionFailure(error))
                    return
                }
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: OCRError.noText)
                } else {
                    continuation.resume(returning: text)
                }
            }
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.visionFailure(error))
                }
            }
        }
    }
}
