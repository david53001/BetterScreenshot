import AppKit

public final class EditorCanvasView: NSView {
    public private(set) var document: EditorDocument
    public var tool: EditorTool = .select
    public var style = AnnotationStyle.default { didSet { needsDisplay = true } }
    public var onTextRequested: ((CGPoint) -> Void)?   // Task 11 wires inline editing

    // MARK: - Selection (supports multiple objects)
    private var selectedIDs: Set<UUID> = []
    /// The single selected annotation, or nil when zero or several are selected
    /// (resize handles only make sense for exactly one).
    private var soleSelectedID: UUID? { selectedIDs.count == 1 ? selectedIDs.first : nil }
    private var dragStartImagePoint: CGPoint?
    private var inProgress: (any Annotation)?
    /// Live drag rectangle (image coords) for region tools (blur/pixelate/crop),
    /// which have no committable preview shape — shown as a dashed marquee.
    private var regionMarquee: CGRect?
    /// Live rubber-band rectangle (image coords) for the select tool's marquee.
    private var marqueeRect: CGRect?

    // MARK: - Task 14: Resize handles
    // Handle index: 0=TL 1=TC 2=TR 3=ML 4=MR 5=BL 6=BC 7=BR
    private var activeHandleIndex: Int? = nil
    private var handleOriginalFrame: CGRect = .zero
    private let handleSize: CGFloat = 8

    // MARK: - Undo / redo history (document snapshots)
    // EditorDocument is a value type, so a snapshot is just a copy of the struct.
    private var undoStack: [EditorDocument] = []
    private var redoStack: [EditorDocument] = []
    /// Pre-drag snapshot, pushed on mouseUp only if the drag actually mutated.
    private var pendingDragSnapshot: EditorDocument?
    private var didDragMutate = false

    /// Fired after any change affecting the dimensions readout, selection, or
    /// undo/redo availability, so the window chrome can refresh itself.
    public var onStateChange: (() -> Void)?

    public var hasSelection: Bool { !selectedIDs.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    private func snapshot() {
        undoStack.append(document)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

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
        guard let id = soleSelectedID, let i = document.index(of: id) else { return nil }
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
        guard let id = soleSelectedID, let i = document.index(of: id) else { return }
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
        // The in-progress shape is drawn on top of the flattened doc so the
        // user sees the annotation live as they drag (e.g. a rectangle growing).
        guard let flat = DocumentRenderer.render(document, preview: inProgress) else { return }
        NSImage(cgImage: flat, size: bounds.size).draw(in: bounds)

        // Live marquee for region tools (blur/pixelate/crop) that have no shape preview.
        if let m = regionMarquee {
            let vr = NSRect(x: m.minX / scale, y: m.minY / scale,
                            width: m.width / scale, height: m.height / scale)
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: vr)
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }

        // Live rubber-band marquee for the select tool.
        if let m = marqueeRect {
            let vr = NSRect(x: m.minX / scale, y: m.minY / scale,
                            width: m.width / scale, height: m.height / scale)
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: vr).fill()
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: vr)
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }

        // Selection outline(s) — one dashed box per selected annotation.
        for id in selectedIDs {
            guard let i = document.index(of: id) else { continue }
            let bb = document.annotations[i].boundingBox()
            let viewRect = NSRect(x: bb.minX / scale, y: bb.minY / scale,
                                  width: bb.width / scale, height: bb.height / scale)
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: viewRect.insetBy(dx: -2, dy: -2))
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }

        // Resize handles only for a single rect-based selection.
        if let vr = selectedViewRect() {
            NSColor.white.setFill()
            NSColor.systemBlue.setStroke()
            for r in handleRects(for: vr) {
                let path = NSBezierPath(rect: r)
                path.fill(); path.lineWidth = 1; path.stroke()
            }
        }
    }

    // MARK: - Mouse
    public override func mouseDown(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let p = imagePoint(viewPt)
        dragStartImagePoint = p
        activeHandleIndex = nil
        regionMarquee = nil
        marqueeRect = nil

        switch tool {
        case .select:
            // Resize handle (single selection) first, then an object hit, then
            // an empty-space drag starts a rubber-band marquee.
            if let vr = selectedViewRect(), let hi = hitHandle(at: viewPt, viewRect: vr) {
                activeHandleIndex = hi
                handleOriginalFrame = document.annotations[document.index(of: soleSelectedID!)!].boundingBox()
                pendingDragSnapshot = document; didDragMutate = false
            } else if let hit = document.topmostHit(at: p) {
                // Clicking an object outside the current selection selects just
                // it; clicking one already selected keeps the group (drag = move).
                if !selectedIDs.contains(hit) { selectedIDs = [hit] }
                pendingDragSnapshot = document; didDragMutate = false
            } else {
                selectedIDs = []
                marqueeRect = CGRect(origin: p, size: .zero)
            }
            onStateChange?(); needsDisplay = true
        case .text:
            onTextRequested?(p)
        case .counter:
            snapshot()
            document.add(CounterAnnotation(number: document.nextCounterNumber(),
                                           origin: p, style: style))
            onStateChange?(); needsDisplay = true
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
                replaceFrame(newFrame); didDragMutate = true
            } else if marqueeRect != nil {
                marqueeRect = rect(start, p)
            } else if !selectedIDs.isEmpty {
                // Move the whole selection together.
                let delta = CGVector(dx: p.x - start.x, dy: p.y - start.y)
                for id in selectedIDs { document.move(id: id, by: delta) }
                dragStartImagePoint = p; didDragMutate = true
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
        case .blur, .pixelate, .crop:
            regionMarquee = rect(start, p)
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
            if let id = soleSelectedID, let i = document.index(of: id) {
                handleOriginalFrame = document.annotations[i].boundingBox()
            }
            activeHandleIndex = nil
        } else {
            switch tool {
            case .select:
                // Resolve a marquee drag into the set of enclosed objects.
                if let m = marqueeRect {
                    selectedIDs = Set(document.ids(intersecting: m))
                    marqueeRect = nil
                }
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
                if let a = inProgress { inProgress = nil; insert(a) }  // insert() snapshots
            }
        }
        // Commit a single undo step for a completed move/resize drag.
        if didDragMutate, let snap = pendingDragSnapshot {
            undoStack.append(snap)
            if undoStack.count > 50 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        pendingDragSnapshot = nil; didDragMutate = false
        dragStartImagePoint = nil; regionMarquee = nil; marqueeRect = nil
        onStateChange?(); needsDisplay = true
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Keyboard (undo/redo, delete, z-order)
    public override var acceptsFirstResponder: Bool { true }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleUndoRedo(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        if handleUndoRedo(event) { return }
        guard !selectedIDs.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 51, 117: deleteSelected()                                  // Delete / Fwd-Delete
        default:
            if event.charactersIgnoringModifiers == "]" { bringSelectedToFront() }
            else if event.charactersIgnoringModifiers == "[" { sendSelectedToBack() }
            else { super.keyDown(with: event) }
        }
    }

    /// ⌘/⌃Z = undo, ⌘/⌃⇧Z or ⌘/⌃Y = redo. Returns true when consumed.
    private func handleUndoRedo(_ event: NSEvent) -> Bool {
        if activeField != nil { return false }   // let the text editor own ⌘Z while typing
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) || mods.contains(.control) else { return false }
        switch event.keyCode {
        case 6:  mods.contains(.shift) ? redo() : undo(); return true    // Z / ⇧Z
        case 16: redo(); return true                                     // Y
        default: return false
        }
    }

    // MARK: - Mutation entry points for the window controller / inline editor
    public func insert(_ annotation: any Annotation) {
        snapshot(); document.add(annotation); selectedIDs = [annotation.id]
        onStateChange?(); needsDisplay = true
    }
    public func applyCrop(to imageRect: CGRect) {
        guard let cropped = document.cropped(to: imageRect) else { return }
        snapshot()
        document = cropped
        frame = NSRect(origin: .zero, size: document.size)
        selectedIDs = []; onStateChange?(); needsDisplay = true
    }
    public func currentDocument() -> EditorDocument { document }

    // MARK: - Undo / redo + object actions (driven by the window chrome)
    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document); document = prev
        selectedIDs = []; onStateChange?(); needsDisplay = true
    }
    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document); document = next
        selectedIDs = []; onStateChange?(); needsDisplay = true
    }
    public func deleteSelected() {
        guard !selectedIDs.isEmpty else { return }
        snapshot()
        for id in selectedIDs { document.remove(id: id) }
        selectedIDs = []
        onStateChange?(); needsDisplay = true
    }
    public func bringSelectedToFront() {
        guard !selectedIDs.isEmpty else { return }
        snapshot()
        // Walk in document order so the selected objects keep their relative stacking.
        for id in document.annotations.map(\.id) where selectedIDs.contains(id) {
            document.bringToFront(id: id)
        }
        onStateChange?(); needsDisplay = true
    }
    public func sendSelectedToBack() {
        guard !selectedIDs.isEmpty else { return }
        snapshot()
        for id in document.annotations.map(\.id).reversed() where selectedIDs.contains(id) {
            document.sendToBack(id: id)
        }
        onStateChange?(); needsDisplay = true
    }

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
