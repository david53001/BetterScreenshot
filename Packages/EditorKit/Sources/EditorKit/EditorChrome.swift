import AppKit

// Custom AppKit views backing the redesigned annotation editor chrome:
// the floating glass tool-pill buttons, the inspector colour swatches, and a
// clip view that centres the canvas inside its scroll view. All are manual /
// visually verified (no unit tests), matching the project's UI testing norm.

/// A single icon tool in the floating toolbar pill. Draws its own rounded
/// hover / selected background and tints an SF Symbol template image.
final class IconToolButton: NSButton {
    let tool: EditorTool
    var isSelectedTool = false { didSet { updateTint(); needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(tool: EditorTool, symbol: String, tip: String, target: AnyObject?, action: Selector) {
        self.tool = tool
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        bezelStyle = .shadowlessSquare
        imagePosition = .imageOnly
        focusRingType = .none
        title = ""
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(cfg)
        image?.isTemplate = true
        toolTip = tip
        self.target = target
        self.action = action
        updateTint()
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 38),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateTint() {
        contentTintColor = isSelectedTool ? .white : NSColor(white: 1, alpha: 0.82)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor? = isSelectedTool ? .controlAccentColor
                         : (hovering ? NSColor(white: 1, alpha: 0.13) : nil)
        if let bg {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
            bg.setFill(); path.fill()
        }
        super.draw(dirtyRect)
    }
}

/// A round colour swatch in the inspector, with a selection ring.
final class SwatchButton: NSButton {
    let swatchColor: NSColor
    var isSelectedSwatch = false { didSet { needsDisplay = true } }

    init(color: NSColor, target: AnyObject?, action: Selector) {
        self.swatchColor = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        bezelStyle = .shadowlessSquare
        focusRingType = .none
        title = ""
        self.target = target
        self.action = action
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 16
        let circle = NSRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        swatchColor.setFill(); NSBezierPath(ovalIn: circle).fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let outline = NSBezierPath(ovalIn: circle); outline.lineWidth = 1; outline.stroke()
        if isSelectedSwatch {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2; ring.stroke()
        }
    }
}

/// Keeps the document view centred when it is smaller than the visible area,
/// so the screenshot floats in the middle of the neutral backdrop.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width {
            rect.origin.x = (doc.frame.width - rect.width) / 2
        }
        if rect.height > doc.frame.height {
            rect.origin.y = (doc.frame.height - rect.height) / 2
        }
        return rect
    }
}
