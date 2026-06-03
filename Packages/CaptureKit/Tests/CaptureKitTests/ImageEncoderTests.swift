import TestKit
import CoreGraphics
@testable import CaptureKit

private func makeEncoderImage() -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return ctx.makeImage()!
}

let imageEncoderTests: [TestCase] = [
    TestCase("encodesPNGWithCorrectSignature") { t in
        guard let data = t.unwrap(ImageEncoder.encode(makeEncoderImage(), as: .png)) else { return }
        // PNG magic: 89 50 4E 47
        t.equal(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    },
    TestCase("encodesJPEGWithCorrectSignature") { t in
        guard let data = t.unwrap(ImageEncoder.encode(makeEncoderImage(), as: .jpg(quality: 0.8))) else { return }
        // JPEG magic: FF D8
        t.equal(Array(data.prefix(2)), [0xFF, 0xD8])
    },
]
