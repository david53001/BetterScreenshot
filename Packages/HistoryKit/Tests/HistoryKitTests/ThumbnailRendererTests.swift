import TestKit
import Foundation
import CoreGraphics
import ImageIO
@testable import HistoryKit

/// A small solid-color PNG for thumbnail/store tests (shared with HistoryStoreTests).
func makePNGData(width: Int = 1600, height: Int = 1000) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let img = ctx.makeImage()!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out as CFMutableData,
                                                "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

let thumbnailRendererTests: [TestCase] = [
    TestCase("capsLongestSideAt400") { t in
        let png = makePNGData(width: 1600, height: 1000)
        guard let thumb = t.unwrap(ThumbnailRenderer.jpegThumbnail(from: png)) else { return }
        guard let size = t.unwrap(ThumbnailRenderer.pixelSize(of: thumb)) else { return }
        t.equal(Int(size.width), 400)
        t.equal(Int(size.height), 250)
    },
    TestCase("smallImagesAreNotUpscaledBeyondCap") { t in
        let png = makePNGData(width: 200, height: 100)
        guard let thumb = t.unwrap(ThumbnailRenderer.jpegThumbnail(from: png)) else { return }
        guard let size = t.unwrap(ThumbnailRenderer.pixelSize(of: thumb)) else { return }
        t.isTrue(size.width <= 400 && size.height <= 400)
    },
    TestCase("outputIsJPEG") { t in
        let png = makePNGData(width: 100, height: 100)
        guard let thumb = t.unwrap(ThumbnailRenderer.jpegThumbnail(from: png)) else { return }
        t.equal(Array(thumb.prefix(2)), [0xFF, 0xD8])
    },
    TestCase("garbageDataReturnsNil") { t in
        t.isNil(ThumbnailRenderer.jpegThumbnail(from: Data([0x00, 0x01, 0x02])))
    },
]
