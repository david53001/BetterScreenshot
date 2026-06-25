import CoreGraphics
import AppKit

public struct RGBAColor: Equatable, Codable {
    public var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    public var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    public init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        self.init(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
    }
}
