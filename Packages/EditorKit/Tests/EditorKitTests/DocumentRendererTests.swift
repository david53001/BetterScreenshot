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

/// A base whose TOP half (image rows 0…) is red and BOTTOM half is blue, so a
/// vertical flip is detectable — a solid/symmetric base cannot reveal one.
private func topRedBottomBlueBase(_ n: Int) -> CGImage {
    let bytesPerRow = n * 4
    var buf = [UInt8](repeating: 0, count: n * bytesPerRow)
    for y in 0..<n {
        for x in 0..<n {
            let i = y * bytesPerRow + x * 4
            if y < n / 2 { buf[i] = 255; buf[i + 3] = 255 }       // top → red
            else         { buf[i + 2] = 255; buf[i + 3] = 255 }   // bottom → blue
        }
    }
    return CGContext(data: &buf, width: n, height: n, bitsPerComponent: 8,
        bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
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
    TestCase("rendersInProgressPreviewOnTop") { t in
        let doc = EditorDocument(baseImage: whiteBase(100))
        var style = AnnotationStyle.default
        style.strokeColor = RGBAColor(r: 1, g: 0, b: 0, a: 1)
        let preview = FilledRectangleAnnotation(
            frame: CGRect(x: 20, y: 20, width: 40, height: 40), style: style)

        // No preview → center stays white (the live shape is not committed).
        guard let plain = t.unwrap(DocumentRenderer.render(doc)) else { return }
        let plainCenter = pixelAt(plain, 40, 40)
        t.isTrue(plainCenter[0] > 200 && plainCenter[1] > 200 && plainCenter[2] > 200,
                 "no-preview center should be white")

        // With preview → center is painted red, on top of the flattened doc.
        guard let withPreview = t.unwrap(DocumentRenderer.render(doc, preview: preview)) else { return }
        let c = pixelAt(withPreview, 40, 40)
        t.isTrue(c[0] > 200, "preview center red channel high")
        t.isTrue(c[1] < 60,  "preview center green channel low")
    },
    TestCase("arrowShaftDoesNotBleedPastArrowhead") { t in
        // A thick arrow pointing right. The round line cap used to poke ~lineWidth/2
        // past the arrowhead tip; the shaft must now stop at the head's base so
        // nothing protrudes beyond the tip.
        var doc = EditorDocument(baseImage: whiteBase(100))
        var style = AnnotationStyle.default
        style.strokeColor = RGBAColor(r: 1, g: 0, b: 0, a: 1)
        style.lineWidth = 12
        doc.add(ArrowAnnotation(start: CGPoint(x: 20, y: 50),
                                end: CGPoint(x: 80, y: 50), style: style))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }

        // 4px past the tip — must be background white (no round-cap bleed).
        let past = pixelAt(out, 84, 50)
        t.isTrue(past[0] > 200 && past[1] > 200 && past[2] > 200,
                 "no stroke should bleed past the arrow tip")

        // The arrowhead itself is still filled near the tip → red.
        let head = pixelAt(out, 76, 50)
        t.isTrue(head[0] > 200 && head[1] < 80, "arrowhead is still filled near the tip")

        // The shaft is still drawn at its midpoint → red.
        let shaft = pixelAt(out, 35, 50)
        t.isTrue(shaft[0] > 200 && shaft[1] < 80, "shaft is still drawn")
    },
    TestCase("preservesBaseImageOrientation") { t in
        // Base is red on top, blue on bottom. The flattened output must keep
        // that orientation — i.e. not be rendered upside-down.
        let doc = EditorDocument(baseImage: topRedBottomBlueBase(80))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }

        let top = pixelAt(out, 40, 5)        // near the top → red
        t.isTrue(top[0] > 200 && top[2] < 60, "top of rendered image should stay red")

        let bottom = pixelAt(out, 40, 75)    // near the bottom → blue
        t.isTrue(bottom[2] > 200 && bottom[0] < 60, "bottom of rendered image should stay blue")
    },
]
