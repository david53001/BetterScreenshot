import AppKit
import CoreGraphics

public enum DocumentRenderer {
    /// Flattens the document into a CGImage. Used for both export and the canvas.
    public static func render(_ doc: EditorDocument) -> CGImage? {
        let w = doc.baseImage.width, h = doc.baseImage.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Flipped NSGraphicsContext → AppKit drawing uses top-left origin (incl. text, images).
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        NSImage(cgImage: doc.baseImage, size: NSSize(width: w, height: h))
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        for a in doc.annotations { a.draw() }

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
