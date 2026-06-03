// Generates the BetterScreenshot app icon: a simple black-and-white camera on a
// dark macOS-style rounded-square (squircle), matching the reference style
// (dark squircle + white glyph). Pure AppKit drawing — no SF Symbol / window
// server dependency. Run with: swift tools/make-icon.swift <iconset-dir> [preview.png]
import AppKit
import Foundation

let darkFill = NSColor(calibratedWhite: 0.11, alpha: 1.0)   // ~#1c1c1c charcoal
let white = NSColor.white

func rr(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

/// Draws the icon at the given pixel size into the current graphics context.
func drawIcon(_ s: CGFloat) {
    // Squircle background (slight transparent margin so corners aren't clipped).
    let margin = s * 0.055
    let bg = NSRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    darkFill.setFill()
    rr(bg, bg.width * 0.2237).fill()

    // --- White camera glyph, centred ---
    let cx = s * 0.5
    let lensCY = s * 0.475          // lens / body vertical centre

    // Camera body.
    let bodyW = s * 0.60, bodyH = s * 0.40
    let body = NSRect(x: cx - bodyW / 2, y: lensCY - bodyH / 2, width: bodyW, height: bodyH)

    // Viewfinder hump on the top edge (overlaps body so it merges seamlessly).
    let humpW = s * 0.20, humpH = s * 0.085
    let hump = NSRect(x: cx - humpW / 2, y: body.maxY - s * 0.02, width: humpW, height: humpH)

    white.setFill()
    rr(hump, humpH * 0.35).fill()
    rr(body, s * 0.06).fill()

    // Flash window: small dark rounded square, top-left of the body.
    let flashSide = s * 0.055
    let flash = NSRect(x: body.minX + s * 0.055, y: body.maxY - s * 0.10,
                       width: flashSide, height: flashSide)
    darkFill.setFill()
    rr(flash, flashSide * 0.35).fill()

    // Lens: concentric circles -> dark outer ring, white ring, dark glass, white highlight.
    func disk(_ radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - radius, y: lensCY - radius,
                                    width: radius * 2, height: radius * 2)).fill()
    }
    let rl = s * 0.135
    disk(rl, darkFill)          // outer dark
    disk(rl * 0.78, white)      // white ring
    disk(rl * 0.46, darkFill)   // dark glass
    // tiny highlight, upper-right of the glass
    let hr = s * 0.022
    white.setFill()
    NSBezierPath(ovalIn: NSRect(x: cx + rl * 0.10, y: lensCY + rl * 0.12,
                                width: hr * 2, height: hr * 2)).fill()
}

func render(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    drawIcon(CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// --- CLI ---
let args = CommandLine.arguments
let iconsetDir = args.count > 1 ? args[1] : ""
let previewPath = args.count > 2 ? args[2] : ""

if !previewPath.isEmpty {
    writePNG(render(1024), to: previewPath)
    print("preview -> \(previewPath)")
}

if !iconsetDir.isEmpty {
    try? FileManager.default.createDirectory(atPath: iconsetDir,
        withIntermediateDirectories: true)
    let sizes: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, px) in sizes {
        writePNG(render(px), to: "\(iconsetDir)/\(name).png")
    }
    print("iconset -> \(iconsetDir) (\(sizes.count) images)")
}
