import AppKit

public final class EditorWindowController: NSWindowController {
    private let canvas: EditorCanvasView
    private var style = AnnotationStyle.default
    public var onCopy: ((CGImage) -> Void)?
    public var onSave: ((CGImage) -> Void)?

    public init(image: CGImage) {
        let doc = EditorDocument(baseImage: image)
        self.canvas = EditorCanvasView(document: doc)

        let displayW = min(CGFloat(image.width), 1200)
        let displayH = displayW * CGFloat(image.height) / CGFloat(image.width)
        canvas.frame = NSRect(x: 0, y: 0, width: displayW, height: displayH)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: displayW + 24, height: displayH + 96),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Annotate"
        super.init(window: window)
        buildUI(canvasSize: NSSize(width: displayW, height: displayH))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(canvasSize: NSSize) {
        guard let content = window?.contentView else { return }

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 4
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        for tool in EditorTool.allCases {
            let b = NSButton(title: label(for: tool), target: self, action: #selector(selectTool(_:)))
            b.bezelStyle = .texturedRounded
            b.tag = EditorTool.allCases.firstIndex(of: tool)!
            toolbar.addArrangedSubview(b)
        }
        let colorWell = NSColorWell()
        colorWell.color = style.strokeColor.nsColor
        colorWell.target = self; colorWell.action = #selector(colorChanged(_:))
        toolbar.addArrangedSubview(colorWell)

        let scroll = NSScrollView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let actions = NSStackView()
        actions.orientation = .horizontal; actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyAction))
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveAction))
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneAction))
        [copyBtn, saveBtn, doneBtn].forEach { actions.addArrangedSubview($0) }

        content.addSubview(toolbar); content.addSubview(scroll); content.addSubview(actions)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            actions.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            actions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    private func label(for tool: EditorTool) -> String {
        switch tool {
        case .select: return "Select"; case .arrow: return "Arrow"; case .line: return "Line"
        case .rectangle: return "Rect"; case .filledRectangle: return "Fill"; case .ellipse: return "Oval"
        case .text: return "Text"; case .counter: return "1•"; case .blur: return "Blur"
        case .pixelate: return "Pixel"; case .crop: return "Crop"
        }
    }

    @objc private func selectTool(_ sender: NSButton) {
        canvas.tool = EditorTool.allCases[sender.tag]
    }
    @objc private func colorChanged(_ sender: NSColorWell) {
        style.strokeColor = RGBAColor(sender.color)
        style.fillColor = RGBAColor(sender.color.withAlphaComponent(0.25))
        canvas.style = style
    }
    @objc private func copyAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onCopy?(img)
    }
    @objc private func saveAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onSave?(img)
    }
    @objc private func doneAction() { window?.close() }
}
