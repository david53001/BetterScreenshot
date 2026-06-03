import AppKit

public final class EditorCanvasView: NSView {
    public private(set) var document: EditorDocument
    public var tool: EditorTool = .select
    public var style = AnnotationStyle.default { didSet { needsDisplay = true } }
    public var onTextRequested: ((CGPoint) -> Void)?   // Task 11 wires inline editing

    private var selectedID: UUID?
    private var dragStartImagePoint: CGPoint?
    private var inProgress: (any Annotation)?

    public init(document: EditorDocument) {
        self.document = document
        super.init(frame: NSRect(origin: .zero, size: document.size))
        self.onTextRequested = { [weak self] p in self?.beginTextEditing(atImagePoint: p) }
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    // MARK: - Coordinate mapping (view ↔ image)
    private var scale: CGFloat { document.size.width / max(bounds.width, 1) }
    private func imagePoint(_ viewPoint: NSPoint) -> CGPoint {
        CGPoint(x: viewPoint.x * scale, y: viewPoint.y * scale)
    }

    // MARK: - Rendering
    public override func draw(_ dirtyRect: NSRect) {
        guard let flat = DocumentRenderer.render(document) else { return }
        NSImage(cgImage: flat, size: bounds.size).draw(in: bounds)
        // Selection outline.
        if let id = selectedID, let i = document.index(of: id) {
            let bb = document.annotations[i].boundingBox()
            let viewRect = NSRect(x: bb.minX / scale, y: bb.minY / scale,
                                  width: bb.width / scale, height: bb.height / scale)
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: viewRect.insetBy(dx: -2, dy: -2))
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }
    }

    // MARK: - Mouse
    public override func mouseDown(with event: NSEvent) {
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        dragStartImagePoint = p
        switch tool {
        case .select:
            selectedID = document.topmostHit(at: p); needsDisplay = true
        case .text:
            onTextRequested?(p)
        case .counter:
            document.add(CounterAnnotation(number: document.nextCounterNumber(),
                                           origin: p, style: style)); needsDisplay = true
        default:
            inProgress = nil // shape creation happens on drag
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartImagePoint else { return }
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        switch tool {
        case .select:
            if let id = selectedID {
                document.move(id: id, by: CGVector(dx: (p.x - start.x), dy: (p.y - start.y)))
                dragStartImagePoint = p
            }
        case .arrow:
            inProgress = ArrowAnnotation(start: start, end: p, style: style)
        case .line:
            inProgress = LineAnnotation(start: start, end: p, style: style)
        case .rectangle:
            inProgress = RectangleAnnotation(frame: rect(start, p), filled: false, style: style)
        case .filledRectangle:
            inProgress = FilledRectangleAnnotation(frame: rect(start, p), style: style)
        case .ellipse:
            inProgress = EllipseAnnotation(frame: rect(start, p), style: style)
        default: break
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        let start = dragStartImagePoint ?? p
        let r = rect(start, p)
        switch tool {
        case .blur:
            if r.width >= 2, r.height >= 2,
               let patch = Redactor.blur(document.baseImage, region: r, radius: 12) {
                insert(BlurAnnotation(frame: r, patch: patch))
            }
        case .pixelate:
            if r.width >= 2, r.height >= 2,
               let patch = Redactor.pixelate(document.baseImage, region: r, blockSize: 12) {
                insert(PixelateAnnotation(frame: r, patch: patch))
            }
        case .crop:
            if r.width >= 4, r.height >= 4 { applyCrop(to: r) }
        default:
            if let a = inProgress { document.add(a); selectedID = a.id; inProgress = nil }
        }
        dragStartImagePoint = nil; needsDisplay = true
    }

    // Live preview of the in-progress shape on top of the flattened doc.
    public override func updateLayer() {}
    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Keyboard (delete, z-order)
    public override var acceptsFirstResponder: Bool { true }
    public override func keyDown(with event: NSEvent) {
        guard let id = selectedID else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 51, 117: document.remove(id: id); selectedID = nil   // Delete / Fwd-Delete
        default:
            if event.charactersIgnoringModifiers == "]" { document.bringToFront(id: id) }
            else if event.charactersIgnoringModifiers == "[" { document.sendToBack(id: id) }
            else { super.keyDown(with: event); return }
        }
        needsDisplay = true
    }

    // MARK: - Mutation entry points for the window controller / inline editor
    public func insert(_ annotation: any Annotation) {
        document.add(annotation); selectedID = annotation.id; needsDisplay = true
    }
    public func applyCrop(to imageRect: CGRect) {
        if let cropped = document.cropped(to: imageRect) {
            document = cropped
            frame = NSRect(origin: .zero, size: document.size)
            selectedID = nil; needsDisplay = true
        }
    }
    public func currentDocument() -> EditorDocument { document }

    // MARK: - Inline text editing (Task 11)
    private var activeField: NSTextField?

    private func beginTextEditing(atImagePoint p: CGPoint) {
        let viewPoint = NSPoint(x: p.x / scale, y: p.y / scale)
        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y, width: 200, height: 28))
        field.font = .systemFont(ofSize: style.fontSize / scale, weight: .semibold)
        field.textColor = style.strokeColor.nsColor
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitText(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeField = field
        textImageOrigin = p
    }
    private var textImageOrigin: CGPoint = .zero

    @objc private func commitText(_ sender: NSTextField) {
        let text = sender.stringValue
        sender.removeFromSuperview(); activeField = nil
        guard !text.isEmpty else { needsDisplay = true; return }
        insert(TextAnnotation(text: text, origin: textImageOrigin, style: style))
    }
}
