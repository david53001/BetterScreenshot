import TestKit
import AppKit
import CoreImage
@testable import CaptureKit

// Headless renderers — same technique as the verified 2026-06-04 probe.
private func renderTextImage(_ text: String,
                             size: CGSize = CGSize(width: 600, height: 120)) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor.white)
    ctx.fill(CGRect(origin: .zero, size: size))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    (text as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: [
        .font: NSFont.systemFont(ofSize: 36, weight: .medium),
        .foregroundColor: NSColor.black])
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

private func renderQRImage(_ payload: String) -> CGImage {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(payload.data(using: .utf8)!, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    return CIContext().createCGImage(output, from: output.extent)!
}

private func composite(_ left: CGImage, _ right: CGImage) -> CGImage {
    let w = left.width + right.width, h = max(left.height, right.height)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor.white)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(left, in: CGRect(x: 0, y: 0, width: left.width, height: left.height))
    ctx.draw(right, in: CGRect(x: left.width, y: 0, width: right.width, height: right.height))
    return ctx.makeImage()!
}

let textRecognizerTests: [TestCase] = [
    TestCase("recognizesRenderedText") { t in
        let result = try? TextRecognizer.recognize(
            in: renderTextImage("Hello BetterScreenshot 12345"))
        guard case .text(let s)? = result else {
            t.fail("expected .text, got \(String(describing: result))"); return
        }
        t.isTrue(s.contains("BetterScreenshot"), "recognized: \(s)")
        t.isTrue(s.contains("12345"), "recognized: \(s)")
    },
    TestCase("decodesQRPayload") { t in
        let result = try? TextRecognizer.recognize(
            in: renderQRImage("https://github.com/david53001/BetterScreenshot"))
        t.equal(result, RecognitionResult.qr("https://github.com/david53001/BetterScreenshot"))
    },
    TestCase("qrBeatsTextInMixedImage") { t in
        let mixed = composite(renderTextImage("plain words"), renderQRImage("qr-payload"))
        t.equal(try? TextRecognizer.recognize(in: mixed), RecognitionResult.qr("qr-payload"))
    },
    TestCase("blankImageIsNone") { t in
        t.equal(try? TextRecognizer.recognize(in: renderTextImage("")),
                RecognitionResult.none)
    },
]
