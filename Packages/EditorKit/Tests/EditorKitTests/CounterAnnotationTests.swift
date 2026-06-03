import TestKit
import CoreGraphics
@testable import EditorKit

let counterAnnotationTests: [TestCase] = [
    TestCase("boundingBoxIsSquareAtOrigin") { t in
        let c = CounterAnnotation(number: 3, origin: CGPoint(x: 50, y: 60))
        let bb = c.boundingBox()
        t.approxEqual(Double(bb.minX), 50, tol: 0.001)
        t.approxEqual(Double(bb.minY), 60, tol: 0.001)
        t.approxEqual(Double(bb.width), Double(bb.height), tol: 0.001)
    },
    TestCase("nextCounterNumberCountsCountersOnly") { t in
        let base = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        var doc = EditorDocument(baseImage: base)
        doc.add(RectangleAnnotation(frame: .zero, filled: false))
        doc.add(CounterAnnotation(number: 1, origin: .zero))
        t.equal(doc.nextCounterNumber(), 2)
    },
]
