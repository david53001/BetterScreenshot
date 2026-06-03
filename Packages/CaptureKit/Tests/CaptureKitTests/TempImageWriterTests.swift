import TestKit
import CoreGraphics
import Foundation
@testable import CaptureKit

private func makeImage() -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    return ctx.makeImage()!
}

let tempImageWriterTests: [TestCase] = [
    TestCase("writesPNGToTempAndFileExists") { t in
        guard let url = TempImageWriter.writePNG(makeImage(), fileName: "DragTest.png") else {
            t.isTrue(false)
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        t.isTrue(FileManager.default.fileExists(atPath: url.path))
        t.equal(url.pathExtension, "png")
        guard let data = try? Data(contentsOf: url) else {
            t.isTrue(false)
            return
        }
        t.equal(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    },
]
