import AppKit

/// The annotation editor window. Redesigned chrome: a floating frosted-glass
/// tool pill, an inspector that adapts to the active tool, a quiet bottom
/// action bar, and undo/redo in the title bar — over a centred neutral canvas.
public final class EditorWindowController: NSWindowController {
    private let canvas: EditorCanvasView
    private var style = AnnotationStyle.default
    public var onCopy: ((CGImage) -> Void)?
    public var onSave: ((CGImage) -> Void)?
    public var onPin: ((CGImage) -> Void)?

    // Chrome references kept for live updates.
    private var toolButtons: [EditorTool: IconToolButton] = [:]
    private let inspectorEffect = NSVisualEffectView()
    private let inspectorStack = NSStackView()
    private let dimsLabel = NSTextField(labelWithString: "")
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private var swatchButtons: [SwatchButton] = []
    private let customColorWell = NSColorWell()
    private var selectionDependentButtons: [NSButton] = []
    private var scrollView = NSScrollView()
    private let maxDisplayW: CGFloat = 1200

    // Inspector preset palette.
    private let presetColors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1), // red
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1), // orange
        NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1), // yellow
        NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1), // green
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1), // blue
        NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1), // purple
        NSColor.white,
        NSColor.black,
    ]

    // Tool → (SF Symbol, tooltip). Order also defines toolbar grouping below.
    private static let toolInfo: [EditorTool: (symbol: String, tip: String)] = [
        .select: ("cursorarrow", "Select"),
        .arrow: ("arrow.up.right", "Arrow"),
        .line: ("line.diagonal", "Line"),
        .rectangle: ("rectangle", "Rectangle"),
        .filledRectangle: ("rectangle.fill", "Filled Rectangle"),
        .ellipse: ("circle", "Ellipse"),
        .text: ("textformat", "Text"),
        .counter: ("1.circle.fill", "Counter"),
        .blur: ("drop.fill", "Blur"),
        .pixelate: ("square.grid.3x3.fill", "Pixelate"),
        .crop: ("crop", "Crop"),
    ]
    private let toolGroups: [[EditorTool]] = [
        [.select],
        [.arrow, .line, .rectangle, .filledRectangle, .ellipse],
        [.text, .counter],
        [.blur, .pixelate],
        [.crop],
    ]

    private lazy var backdrop = NSColor(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.90, alpha: 1)
    }

    public init(image: CGImage) {
        let doc = EditorDocument(baseImage: image)
        self.canvas = EditorCanvasView(document: doc)

        let displayW = min(CGFloat(image.width), 1200)
        let displayH = displayW * CGFloat(image.height) / CGFloat(image.width)
        canvas.frame = NSRect(x: 0, y: 0, width: displayW, height: displayH)

        let contentW = max(displayW, 600)
        let contentH = min(displayH, 620) + 112 /*top chrome*/ + 56 /*action bar*/
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Annotate"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 600, height: 440)
        super.init(window: window)

        window.backgroundColor = backdrop
        buildUI()
        // Delete / [ / ] are handled in the canvas's keyDown — make it the
        // first responder up front instead of requiring a click first.
        window.initialFirstResponder = canvas
        canvas.onStateChange = { [weak self] in self?.refreshChrome() }
        selectTool(.arrow)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Scroll view + centred canvas over the neutral backdrop.
        let clip = CenteringClipView()
        clip.drawsBackground = true
        clip.backgroundColor = backdrop
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backdrop
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 104, left: 24, bottom: 24, right: 24)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = buildToolbar()
        buildInspector()
        let actionBar = buildActionBar()
        buildTitlebarHistory()

        content.addSubview(scrollView)
        content.addSubview(actionBar)
        content.addSubview(toolbar)
        content.addSubview(inspectorEffect)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionBar.topAnchor),

            actionBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            actionBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            actionBar.heightAnchor.constraint(equalToConstant: 56),

            toolbar.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),

            inspectorEffect.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            inspectorEffect.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            inspectorEffect.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func darkPill(cornerRadius: CGFloat) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.appearance = NSAppearance(named: .vibrantDark)
        v.material = .hudWindow
        v.blendingMode = .withinWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = true
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        return v
    }

    private func buildToolbar() -> NSVisualEffectView {
        let pill = darkPill(cornerRadius: 15)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 3
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        for (gi, group) in toolGroups.enumerated() {
            if gi > 0 { row.addArrangedSubview(makeSeparator()) }
            for tool in group {
                let info = Self.toolInfo[tool]!
                let b = IconToolButton(tool: tool, symbol: info.symbol, tip: info.tip,
                                       target: self, action: #selector(toolButtonClicked(_:)))
                toolButtons[tool] = b
                row.addArrangedSubview(b)
            }
        }

        pill.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
        ])
        return pill
    }

    private func makeSeparator() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 1),
            v.heightAnchor.constraint(equalToConstant: 22),
        ])
        return v
    }

    private func buildInspector() {
        let pill = inspectorEffect
        pill.appearance = NSAppearance(named: .vibrantDark)
        pill.material = .hudWindow
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.layer?.cornerRadius = 12
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor(white: 1, alpha: 0.09).cgColor

        inspectorStack.orientation = .horizontal
        inspectorStack.spacing = 12
        inspectorStack.alignment = .centerY
        inspectorStack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(inspectorStack)
        NSLayoutConstraint.activate([
            inspectorStack.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            inspectorStack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            inspectorStack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
        ])
    }

    private func buildActionBar() -> NSView {
        let bar = NSVisualEffectView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active

        // Top hairline.
        let hairline = NSView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bar.addSubview(hairline)

        dimsLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        dimsLabel.textColor = .secondaryLabelColor
        dimsLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(dimsLabel)

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneAction))
        doneBtn.isBordered = false
        doneBtn.attributedTitle = NSAttributedString(string: "Done",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                         .font: NSFont.systemFont(ofSize: 13)])
        doneBtn.keyEquivalent = "w"; doneBtn.keyEquivalentModifierMask = [.command]

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveBtn.bezelStyle = .rounded
        saveBtn.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
        saveBtn.imagePosition = .imageLeading
        saveBtn.keyEquivalent = "s"; saveBtn.keyEquivalentModifierMask = [.command]

        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyAction))
        copyBtn.bezelStyle = .rounded
        copyBtn.bezelColor = .controlAccentColor
        copyBtn.contentTintColor = .white
        copyBtn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyBtn.imagePosition = .imageLeading
        copyBtn.attributedTitle = NSAttributedString(string: "Copy",
            attributes: [.foregroundColor: NSColor.white,
                         .font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        copyBtn.keyEquivalent = "c"; copyBtn.keyEquivalentModifierMask = [.command, .shift]

        let pinBtn = NSButton(title: "Pin", target: self, action: #selector(pinAction))
        pinBtn.bezelStyle = .rounded
        pinBtn.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")
        pinBtn.imagePosition = .imageLeading
        pinBtn.toolTip = "Pin to screen"

        let actions = NSStackView(views: [doneBtn, pinBtn, saveBtn, copyBtn])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(actions)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: bar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            dimsLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 18),
            dimsLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            actions.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            actions.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func buildTitlebarHistory() {
        configureHistoryButton(undoButton, symbol: "arrow.uturn.backward",
                               tip: "Undo", action: #selector(undoAction))
        configureHistoryButton(redoButton, symbol: "arrow.uturn.forward",
                               tip: "Redo", action: #selector(redoAction))
        let stack = NSStackView(views: [undoButton, redoButton])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 10)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = stack
        window?.addTitlebarAccessoryViewController(accessory)
    }

    private func configureHistoryButton(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isBordered = false
        b.bezelStyle = .shadowlessSquare
        b.imagePosition = .imageOnly
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.target = self
        b.action = action
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 26),
            b.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    // MARK: - Inspector (adaptive)

    private func rebuildInspector(for tool: EditorTool) {
        inspectorStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        swatchButtons.removeAll()
        selectionDependentButtons.removeAll()

        switch tool {
        case .select:
            inspectorStack.addArrangedSubview(makeLabel("Object"))
            inspectorStack.addArrangedSubview(makeObjectActions())
        case .arrow, .line, .rectangle, .ellipse:
            inspectorStack.addArrangedSubview(makeLabel(Self.toolInfo[tool]!.tip))
            inspectorStack.addArrangedSubview(makeColorRow())
            inspectorStack.addArrangedSubview(makeDivider())
            inspectorStack.addArrangedSubview(makeWeightSegment())
        case .filledRectangle:
            inspectorStack.addArrangedSubview(makeLabel("Filled"))
            inspectorStack.addArrangedSubview(makeColorRow())
        case .text:
            inspectorStack.addArrangedSubview(makeLabel("Text"))
            inspectorStack.addArrangedSubview(makeColorRow())
            inspectorStack.addArrangedSubview(makeDivider())
            inspectorStack.addArrangedSubview(makeSizeSegment())
        case .counter:
            inspectorStack.addArrangedSubview(makeLabel("Counter"))
            inspectorStack.addArrangedSubview(makeColorRow())
        case .blur, .pixelate:
            inspectorStack.addArrangedSubview(makeLabel("Redact"))
            inspectorStack.addArrangedSubview(makeRedactSegment(current: tool))
        case .crop:
            inspectorStack.addArrangedSubview(makeLabel("Crop"))
            inspectorStack.addArrangedSubview(makeHint("Drag the area to keep"))
        }
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text.uppercased())
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = NSColor(white: 1, alpha: 0.45)
        return l
    }

    private func makeHint(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        l.textColor = NSColor(white: 1, alpha: 0.62)
        return l
    }

    private func makeDivider() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 1),
            v.heightAnchor.constraint(equalToConstant: 20),
        ])
        return v
    }

    private func makeColorRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        for color in presetColors {
            let sw = SwatchButton(color: color, target: self, action: #selector(swatchClicked(_:)))
            sw.isSelectedSwatch = colorsMatch(color, style.strokeColor.nsColor)
            swatchButtons.append(sw)
            row.addArrangedSubview(sw)
        }
        customColorWell.target = self
        customColorWell.action = #selector(customColorChanged(_:))
        customColorWell.color = style.strokeColor.nsColor
        customColorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            customColorWell.widthAnchor.constraint(equalToConstant: 28),
            customColorWell.heightAnchor.constraint(equalToConstant: 22),
        ])
        row.addArrangedSubview(customColorWell)
        return row
    }

    private func makeWeightSegment() -> NSSegmentedControl {
        let seg = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne,
                                     target: self, action: #selector(weightChanged(_:)))
        seg.segmentStyle = .rounded
        let widths: [CGFloat] = [2, 4, 7]
        seg.selectedSegment = widths.firstIndex(of: style.lineWidth) ?? 1
        return seg
    }

    private func makeSizeSegment() -> NSSegmentedControl {
        let seg = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne,
                                     target: self, action: #selector(sizeChanged(_:)))
        seg.segmentStyle = .rounded
        let sizes: [CGFloat] = [18, 24, 36]
        seg.selectedSegment = sizes.firstIndex(of: style.fontSize) ?? 1
        return seg
    }

    private func makeRedactSegment(current: EditorTool) -> NSSegmentedControl {
        let seg = NSSegmentedControl(labels: ["Blur", "Pixelate"], trackingMode: .selectOne,
                                     target: self, action: #selector(redactChanged(_:)))
        seg.segmentStyle = .rounded
        seg.selectedSegment = current == .pixelate ? 1 : 0
        return seg
    }

    private func makeObjectActions() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        func button(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: " " + title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            b.imagePosition = .imageLeading
            b.contentTintColor = NSColor(white: 1, alpha: 0.85)
            selectionDependentButtons.append(b)
            return b
        }
        row.addArrangedSubview(button("Front", "square.3.layers.3d.top.filled", #selector(bringFront)))
        row.addArrangedSubview(button("Back", "square.3.layers.3d.bottom.filled", #selector(sendBack)))
        row.addArrangedSubview(button("Delete", "trash", #selector(deleteObject)))
        return row
    }

    // MARK: - Tool selection

    private func selectTool(_ tool: EditorTool) {
        canvas.tool = tool
        for (t, b) in toolButtons { b.isSelectedTool = (t == tool) }
        rebuildInspector(for: tool)
        refreshChrome()
    }

    @objc private func toolButtonClicked(_ sender: IconToolButton) { selectTool(sender.tool) }

    // MARK: - Inspector actions

    @objc private func swatchClicked(_ sender: SwatchButton) {
        applyStrokeColor(sender.swatchColor)
        for sw in swatchButtons { sw.isSelectedSwatch = (sw === sender) }
        customColorWell.color = sender.swatchColor
    }

    @objc private func customColorChanged(_ sender: NSColorWell) {
        applyStrokeColor(sender.color)
        for sw in swatchButtons { sw.isSelectedSwatch = colorsMatch(sw.swatchColor, sender.color) }
    }

    private func applyStrokeColor(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        style.strokeColor = RGBAColor(c)
        style.fillColor = RGBAColor(c.withAlphaComponent(0.25))
        canvas.style = style
    }

    @objc private func weightChanged(_ sender: NSSegmentedControl) {
        let widths: [CGFloat] = [2, 4, 7]
        style.lineWidth = widths[max(0, sender.selectedSegment)]
        canvas.style = style
    }

    @objc private func sizeChanged(_ sender: NSSegmentedControl) {
        let sizes: [CGFloat] = [18, 24, 36]
        style.fontSize = sizes[max(0, sender.selectedSegment)]
        canvas.style = style
    }

    @objc private func redactChanged(_ sender: NSSegmentedControl) {
        selectTool(sender.selectedSegment == 1 ? .pixelate : .blur)
    }

    @objc private func bringFront() { canvas.bringSelectedToFront() }
    @objc private func sendBack() { canvas.sendSelectedToBack() }
    @objc private func deleteObject() { canvas.deleteSelected() }

    // MARK: - History + export

    @objc private func undoAction() { canvas.undo() }
    @objc private func redoAction() { canvas.redo() }

    @objc private func copyAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onCopy?(img)
    }
    @objc private func saveAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onSave?(img)
    }
    @objc private func pinAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onPin?(img)
    }
    @objc private func doneAction() { window?.close() }

    // MARK: - Chrome refresh

    private func refreshChrome() {
        let size = canvas.currentDocument().size
        dimsLabel.stringValue = "\(Int(size.width)) × \(Int(size.height)) px"
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
        let hasSel = canvas.hasSelection
        selectionDependentButtons.forEach { $0.isEnabled = hasSel }
        fitCanvas()
    }

    /// Keep the canvas displayed at a consistent fit-to-width scale (re-applied
    /// after crop/undo changes the document's pixel size).
    private func fitCanvas() {
        let s = canvas.currentDocument().size
        guard s.width > 0 else { return }
        let w = min(s.width, maxDisplayW)
        let h = w * s.height / s.width
        if canvas.frame.size != NSSize(width: w, height: h) {
            canvas.frame = NSRect(x: 0, y: 0, width: w, height: h)
        }
    }

    // MARK: - Helpers

    private func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        let t: CGFloat = 0.02
        return abs(x.redComponent - y.redComponent) < t
            && abs(x.greenComponent - y.greenComponent) < t
            && abs(x.blueComponent - y.blueComponent) < t
            && abs(x.alphaComponent - y.alphaComponent) < t
    }
}
