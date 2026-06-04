import Vision
import CoreGraphics

/// Vision wrapper for Capture Text. Synchronous — call it off the main thread
/// (Vision's perform() blocks). Feeds results to RecognitionResolver.
public enum TextRecognizer {
    public static func recognize(in image: CGImage) throws -> RecognitionResult {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true

        let qrRequest = VNDetectBarcodesRequest()
        qrRequest.symbologies = [.qr]

        try VNImageRequestHandler(cgImage: image).perform([textRequest, qrRequest])

        let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let qrs = (qrRequest.results ?? []).compactMap { $0.payloadStringValue }
        return RecognitionResolver.resolve(qrPayloads: qrs, textLines: lines)
    }
}
