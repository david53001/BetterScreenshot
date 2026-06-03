import TestKit
import CoreGraphics
@testable import EditorKit

private func pixelAt(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let i = (y * w + x) * 4
    return [buf[i], buf[i+1], buf[i+2], buf[i+3]]
}

private func whiteBase(_ n: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
    return ctx.makeImage()!
}

let documentRendererTests: [TestCase] = [
    TestCase("rendersFilledRectAtTopLeftCoordsInRed") { t in
        var doc = EditorDocument(baseImage: whiteBase(100))
        var style = AnnotationStyle.default
        style.strokeColor = RGBAColor(r: 1, g: 0, b: 0, a: 1)
        // Top-left rect covering x:20..60, y:20..60.
        doc.add(FilledRectangleAnnotation(frame: CGRect(x: 20, y: 20, width: 40, height: 40), style: style))

        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        t.equal(out.width, 100)
        t.equal(out.height, 100)

        let inside = pixelAt(out, 40, 40)   // center of the rect → red
        t.isTrue(inside[0] > 200)
        t.isTrue(inside[1] < 60)

        let corner = pixelAt(out, 5, 5)     // top-left empty → white
        t.isTrue(corner[0] > 200)
        t.isTrue(corner[1] > 200)
        t.isTrue(corner[2] > 200)
    },
]
