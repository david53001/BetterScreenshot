import TestKit
import CoreGraphics
@testable import EditorKit

private func baseImage(_ n: Int) -> CGImage {
    CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

let cropTests: [TestCase] = [
    TestCase("cropResizesBaseAndOffsetsAnnotations") { t in
        var doc = EditorDocument(baseImage: baseImage(100))
        doc.add(RectangleAnnotation(frame: CGRect(x: 40, y: 40, width: 10, height: 10), filled: false))
        guard let cropped = t.unwrap(doc.cropped(to: CGRect(x: 30, y: 30, width: 40, height: 40))) else { return }
        t.equal(cropped.baseImage.width, 40)
        t.equal(cropped.baseImage.height, 40)
        // Annotation shifts by (-30,-30): 40→10.
        t.equal(cropped.annotations[0].boundingBox(), CGRect(x: 10, y: 10, width: 10, height: 10))
    },
]
