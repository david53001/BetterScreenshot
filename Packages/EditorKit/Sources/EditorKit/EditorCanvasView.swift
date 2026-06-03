import AppKit

public final class EditorCanvasView: NSView {
    public private(set) var document: EditorDocument
    public var tool: EditorTool = .select
    public var style = AnnotationStyle.default { didSet { needsDisplay = true } }
    public var onTextRequested: ((CGPoint) -> Void)?   // Task 11 wires inline editing

    private var selectedID: UUID?
    private var dragStartImagePoint: CGPoint?
    private var inProgress: (any Annotation)?

    // MARK: - Task 14: Resize handles
    // Handle index: 0=TL 1=TC 2=TR 3=ML 4=MR 5=BL 6=BC 7=BR
    private var activeHandleIndex: Int? = nil
    private var handleOriginalFrame: CGRect = .zero
    private let handleSize: CGFloat = 8

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

    // MARK: - Resize handle geometry (view coords)
    private func handleRects(for viewRect: NSRect) -> [NSRect] {
        let s = handleSize
        let hs = s / 2
        let minX = viewRect.minX, midX = viewRect.midX, maxX = viewRect.maxX
        let minY = viewRect.minY, midY = viewRect.midY, maxY = viewRect.maxY
        return [
            NSRect(x: minX - hs, y: minY - hs, width: s, height: s), // 0 TL
            NSRect(x: midX - hs, y: minY - hs, width: s, height: s), // 1 TC
            NSRect(x: maxX - hs, y: minY - hs, width: s, height: s), // 2 TR
            NSRect(x: minX - hs, y: midY - hs, width: s, height: s), // 3 ML
            NSRect(x: maxX - hs, y: midY - hs, width: s, height: s), // 4 MR
            NSRect(x: minX - hs, y: maxY - hs, width: s, height: s), // 5 BL
            NSRect(x: midX - hs, y: maxY - hs, width: s, height: s), // 6 BC
            NSRect(x: maxX - hs, y: maxY - hs, width: s, height: s), // 7 BR
        ]
    }

    /// Returns the index (0-7) of the handle hit at viewPoint, or nil.
    private func hitHandle(at viewPoint: NSPoint, viewRect: NSRect) -> Int? {
        let rects = handleRects(for: viewRect)
        for (i, r) in rects.enumerated() {
            if r.insetBy(dx: -2, dy: -2).contains(viewPoint) { return i }
        }
        return nil
    }

    /// Compute a resized frame by dragging handle `idx` from `original` by `delta` (image coords).
    private func resizedFrame(original: CGRect, handleIdx: Int, delta: CGVector) -> CGRect {
        var minX = original.minX, minY = original.minY
        var maxX = original.maxX, maxY = original.maxY
        // TL=0, TC=1, TR=2, ML=3, MR=4, BL=5, BC=6, BR=7
        let movesLeft  = [0, 3, 5].contains(handleIdx)
        let movesRight = [2, 4, 7].contains(handleIdx)
        let movesTop   = [0, 1, 2].contains(handleIdx)
        let movesBot   = [5, 6, 7].contains(handleIdx)
        if movesLeft  { minX += delta.dx }
        if movesRight { maxX += delta.dx }
        if movesTop   { minY += delta.dy }
        if movesBot   { maxY += delta.dy }
        // Keep at least 4px
        if maxX - minX < 4 { if movesLeft { minX = maxX - 4 } else { maxX = minX + 4 } }
        if maxY - minY < 4 { if movesTop  { minY = maxY - 4 } else { maxY = minY + 4 } }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// True when the selected annotation is a rect-based type that exposes a mutable frame.
    private func selectedViewRect() -> NSRect? {
        guard let id = selectedID, let i = document.index(of: id) else { return nil }
        let a = document.annotations[i]
        guard a is RectangleAnnotation || a is FilledRectangleAnnotation
           || a is EllipseAnnotation   || a is BlurAnnotation
           || a is PixelateAnnotation  else { return nil }
        let bb = a.boundingBox()
        return NSRect(x: bb.minX / scale, y: bb.minY / scale,
                      width: bb.width / scale, height: bb.height / scale)
    }

    /// Replace the frame on a rect-based annotation by building a copy with the new frame.
    private func replaceFrame(_ newImageFrame: CGRect) {
        guard let id = selectedID, let i = document.index(of: id) else { return }
        let a = document.annotations[i]
        let updated: (any Annotation)?
        switch a {
        case let r as RectangleAnnotation:
            var c = r; c.frame = newImageFrame; updated = c
        case let f as FilledRectangleAnnotation:
            var c = f; c.frame = newImageFrame; updated = c
        case let e as EllipseAnnotation:
            var c = e; c.frame = newImageFrame; updated = c
        case let b as BlurAnnotation:
            var c = b; c.frame = newImageFrame; updated = c
        case let p as PixelateAnnotation:
            var c = p; c.frame = newImageFrame; updated = c
        default:
            updated = nil
        }
        if let u = updated { document.replace(id: id, with: u) }
    }

    // MARK: - Rendering
    public override func draw(_ dirtyRect: NSRect) {
        guard let flat = DocumentRenderer.render(document) else { return }
        NSImage(cgImage: flat, size: bounds.size).draw(in: bounds)
        // Selection outline + resize handles.
        if let id = selectedID, let i = document.index(of: id) {
            let bb = document.annotations[i].boundingBox()
            let viewRect = NSRect(x: bb.minX / scale, y: bb.minY / scale,
                                  width: bb.width / scale, height: bb.height / scale)
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: viewRect.insetBy(dx: -2, dy: -2))
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()

            // Draw resize handles for rect-based shapes.
            if selectedViewRect() != nil {
                NSColor.white.setFill()
                NSColor.systemBlue.setStroke()
                for r in handleRects(for: viewRect) {
                    let path = NSBezierPath(rect: r)
                    path.fill(); path.lineWidth = 1; path.stroke()
                }
            }
        }
    }

    // MARK: - Mouse
    public override func mouseDown(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let p = imagePoint(viewPt)
        dragStartImagePoint = p
        activeHandleIndex = nil

        switch tool {
        case .select:
            // Check handle hit first.
            if let vr = selectedViewRect(), let hi = hitHandle(at: viewPt, viewRect: vr) {
                activeHandleIndex = hi
                handleOriginalFrame = document.annotations[document.index(of: selectedID!)!].boundingBox()
            } else {
                selectedID = document.topmostHit(at: p)
            }
            needsDisplay = true
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
            if let hi = activeHandleIndex {
                // Resize via handle.
                let delta = CGVector(dx: p.x - start.x, dy: p.y - start.y)
                let newFrame = resizedFrame(original: handleOriginalFrame, handleIdx: hi, delta: delta)
                replaceFrame(newFrame)
            } else if let id = selectedID {
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
        if activeHandleIndex != nil {
            // Resize complete — update the stored original frame for next drag.
            if let id = selectedID, let i = document.index(of: id) {
                handleOriginalFrame = document.annotations[i].boundingBox()
            }
            activeHandleIndex = nil
        } else {
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
