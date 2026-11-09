import AppKit
import MaoShotCore

enum ToolbarAction { case undo, redo, save, copy, close }

/// Persisted tool preferences shared across captures.
enum ToolPrefs {
    static let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .black, .white]

    static var colorIndex: Int {
        get {
            let i = UserDefaults.standard.integer(forKey: "colorIndex")
            return palette.indices.contains(i) ? i : 0
        }
        set { UserDefaults.standard.set(newValue, forKey: "colorIndex") }
    }
}

final class ToolbarView: NSVisualEffectView {
    var onTool: ((Tool) -> Void)?
    var onColor: ((Int) -> Void)?
    var onAction: ((ToolbarAction) -> Void)?

    var selectedTool: Tool = .move { didSet { refresh() } }
    var selectedColorIndex: Int = 0 { didSet { refresh() } }

    private var toolButtons: [Tool: NSButton] = [:]
    private var colorButtons: [NSButton] = []

    private static let toolSpecs: [(Tool, String, String)] = [
        (.move, "arrow.up.and.down.and.arrow.left.and.right", "Select (V): move the area, or click a mark to move, resize or delete it"),
        (.pen, "scribble.variable", "Pen (P)"),
        (.line, "line.diagonal", "Line (L), hold ⇧ to snap"),
        (.arrow, "arrow.up.right", "Arrow (A), hold ⇧ to snap"),
        (.rect, "rectangle", "Rectangle (R)"),
        (.highlighter, "paintbrush.pointed.fill", "Highlighter (H)"),
        (.text, "textformat", "Text (T)"),
    ]

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)

        for (i, spec) in Self.toolSpecs.enumerated() {
            let b = iconButton(spec.1, tip: spec.2, action: #selector(toolTapped(_:)))
            b.tag = i
            toolButtons[spec.0] = b
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(separator())
        for (i, color) in ToolPrefs.palette.enumerated() {
            let b = NSButton(image: Self.swatch(color), target: self, action: #selector(colorTapped(_:)))
            b.isBordered = false
            b.tag = i
            b.wantsLayer = true
            b.layer?.cornerRadius = 11
            b.layer?.borderColor = NSColor.white.cgColor
            b.widthAnchor.constraint(equalToConstant: 22).isActive = true
            b.heightAnchor.constraint(equalToConstant: 22).isActive = true
            colorButtons.append(b)
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(iconButton("arrow.uturn.backward", tip: "Undo (⌘Z)", action: #selector(undoTapped)))
        stack.addArrangedSubview(iconButton("arrow.uturn.forward", tip: "Redo (⇧⌘Z)", action: #selector(redoTapped)))
        stack.addArrangedSubview(iconButton("square.and.arrow.down", tip: "Save… (⌘S)", action: #selector(saveTapped)))
        stack.addArrangedSubview(iconButton("doc.on.doc", tip: "Copy (Return or ⌘C)", action: #selector(copyTapped)))
        stack.addArrangedSubview(iconButton("xmark", tip: "Close (Esc)", action: #selector(closeTapped)))

        addSubview(stack)
        let size = stack.fittingSize
        setFrameSize(size)
        stack.frame = bounds
        stack.autoresizingMask = [.width, .height]
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Swallow clicks on the toolbar background so they don't start a new selection underneath.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    private func iconButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        let b: NSButton
        if let image {
            b = NSButton(image: image, target: self, action: action)
        } else {
            b = NSButton(title: String(tip.prefix(1)), target: self, action: action)
        }
        b.isBordered = false
        b.toolTip = tip
        b.contentTintColor = .white
        b.wantsLayer = true
        b.layer?.cornerRadius = 6
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return v
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
            color.setFill()
            let p = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            p.fill()
            NSColor.white.withAlphaComponent(0.6).setStroke()
            p.lineWidth = 1
            p.stroke()
            return true
        }
    }

    private func refresh() {
        for (tool, b) in toolButtons {
            b.layer?.backgroundColor = (tool == selectedTool
                ? NSColor.controlAccentColor.withAlphaComponent(0.9) : NSColor.clear).cgColor
        }
        for (i, b) in colorButtons.enumerated() {
            b.layer?.borderWidth = i == selectedColorIndex ? 2 : 0
        }
    }

    @objc private func toolTapped(_ sender: NSButton) { onTool?(Self.toolSpecs[sender.tag].0) }
    @objc private func colorTapped(_ sender: NSButton) { onColor?(sender.tag) }
    @objc private func undoTapped() { onAction?(.undo) }
    @objc private func redoTapped() { onAction?(.redo) }
    @objc private func saveTapped() { onAction?(.save) }
    @objc private func copyTapped() { onAction?(.copy) }
    @objc private func closeTapped() { onAction?(.close) }
}
