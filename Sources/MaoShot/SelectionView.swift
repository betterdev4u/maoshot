import AppKit
import MaoShotCore

enum FinishAction { case copy, save, cancel }

@MainActor
protocol SelectionViewDelegate: AnyObject {
    func selectionViewDidBeginSelection(_ view: SelectionView)
    func selectionView(_ view: SelectionView, finishWith action: FinishAction)
}

/// Full-screen view showing the frozen screenshot. Handles region selection, markup, editing marks and shortcuts.
final class SelectionView: NSView, NSTextFieldDelegate {
    let screenImage: CGImage
    weak var delegate: SelectionViewDelegate?

    private(set) var selection: CGRect? {
        didSet { needsDisplay = true; layoutToolbar() }
    }
    private(set) var annotations: [Annotation] = []

    /// Index of the mark picked with the Move tool (for drag / resize / delete / recolor).
    private var selectedMark: Int? { didSet { needsDisplay = true } }

    // Snapshot-based history: covers add, move, resize, recolor and delete alike.
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    /// Snapshot taken at mouseDown on a mark; committed to undo only once the mark actually changes.
    private var pendingSnapshot: [Annotation]?

    private enum Drag {
        case none
        case selecting(CGPoint)
        case moving(CGPoint, CGRect)
        case resizing(Handle, CGRect)
        case drawing(CGPoint)
        case movingMark(Int, CGPoint, Annotation)
        case resizingMark(Int, Handle, CGRect, Annotation)
    }

    private let displayImage: NSImage
    private let toolbar = ToolbarView()
    private var drag: Drag = .none
    private var current: Annotation?
    private var penPoints: [CGPoint] = []
    private var textField: NSTextField?
    private var mouseInside = false

    private var tool: Tool = .move {
        didSet {
            toolbar.selectedTool = tool
            if tool != .move { selectedMark = nil }
            updateCursor()
        }
    }
    private var colorIndex: Int = ToolPrefs.colorIndex {
        didSet { ToolPrefs.colorIndex = colorIndex; toolbar.selectedColorIndex = colorIndex }
    }
    private var color: NSColor { ToolPrefs.palette[colorIndex] }
    private let textSize: CGFloat = 22

    private var pixelScale: CGFloat { CGFloat(screenImage.width) / max(bounds.width, 1) }

    init(frame: NSRect, image: CGImage) {
        screenImage = image
        displayImage = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
        toolbar.isHidden = true
        toolbar.selectedTool = tool
        toolbar.selectedColorIndex = colorIndex
        toolbar.onTool = { [weak self] t in self?.selectTool(t) }
        toolbar.onColor = { [weak self] i in self?.chooseColor(i) }
        toolbar.onAction = { [weak self] a in
            guard let self else { return }
            switch a {
            case .undo: self.undo()
            case .redo: self.redo()
            case .save: self.finish(.save)
            case .copy: self.finish(.copy)
            case .close: self.finish(.cancel)
            }
        }
        addSubview(toolbar)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Public

    func reset() {
        cancelText()
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        selectedMark = nil
        current = nil
        drag = .none
        selection = nil
    }

    func renderResult() -> (image: CGImage, pointSize: CGSize)? {
        guard let sel = selection else { return nil }
        let aligned = Geometry.pixelAligned(sel, scale: pixelScale)
        guard let img = Renderer.render(screenImage: screenImage, screenSize: bounds.size,
                                        selection: aligned, annotations: annotations) else { return nil }
        return (img, aligned.size)
    }

    /// Used by the offline UI snapshot (`--render-demo`).
    func setDemoState(selection: CGRect, annotations: [Annotation], tool: Tool, selectedMark: Int? = nil) {
        self.annotations = annotations
        self.selection = selection
        self.tool = tool
        self.selectedMark = selectedMark
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        displayImage.draw(in: dirtyRect, from: dirtyRect, operation: .copy, fraction: 1)

        let dim = NSColor.black.withAlphaComponent(0.45)
        guard let sel = selection else {
            dim.setFill()
            bounds.fill(using: .sourceOver)
            if mouseInside { drawHint() }
            return
        }

        let mask = NSBezierPath(rect: bounds)
        mask.append(NSBezierPath(rect: sel))
        mask.windingRule = .evenOdd
        dim.setFill()
        mask.fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: sel).addClip()
        for a in annotations { a.draw() }
        current?.draw()
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()
        border.setLineDash([4, 4], count: 2, phase: 0)
        NSColor.black.withAlphaComponent(0.6).setStroke()
        border.stroke()

        if case .drawing = drag {} else {
            for (_, p) in Geometry.handlePoints(for: sel) {
                let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: r).fill()
                NSColor.controlAccentColor.setStroke()
                NSBezierPath(ovalIn: r).stroke()
            }
        }
        drawMarkSelection()
        drawSizeLabel(sel)
    }

    /// Frame + square handles around the picked mark.
    private func drawMarkSelection() {
        guard let i = selectedMark, annotations.indices.contains(i) else { return }
        let r = markFrame(annotations[i])
        let frame = NSBezierPath(rect: r)
        frame.lineWidth = 1
        frame.setLineDash([3, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        frame.stroke()
        for (_, p) in Geometry.handlePoints(for: r) {
            let h = NSBezierPath(rect: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            NSColor.white.setFill()
            h.fill()
            NSColor.controlAccentColor.setStroke()
            h.lineWidth = 1
            h.stroke()
        }
    }

    /// Mark bounds padded a little so handles of thin marks (a horizontal line) don't collapse onto each other.
    private func markFrame(_ a: Annotation) -> CGRect {
        let b = a.bounds
        let padX: CGFloat = b.width < 16 ? (16 - b.width) / 2 + 4 : 4
        let padY: CGFloat = b.height < 16 ? (16 - b.height) / 2 + 4 : 4
        return b.insetBy(dx: -padX, dy: -padY)
    }

    private func drawSizeLabel(_ sel: CGRect) {
        let w = Int((sel.width * pixelScale).rounded()), h = Int((sel.height * pixelScale).rounded())
        let text = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let ts = text.size(withAttributes: attrs)
        var r = CGRect(x: sel.minX, y: sel.maxY + 5, width: ts.width + 12, height: ts.height + 4)
        if r.maxY > bounds.maxY { r.origin = CGPoint(x: sel.minX + 5, y: sel.maxY - r.height - 5) }
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: r.minX + 6, y: r.minY + 2), withAttributes: attrs)
    }

    private func drawHint() {
        let text = "Drag to select an area   ·   Esc to cancel" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let ts = text.size(withAttributes: attrs)
        let r = CGRect(x: bounds.midX - ts.width / 2 - 14, y: bounds.maxY - 90, width: ts.width + 28, height: ts.height + 12)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        text.draw(at: CGPoint(x: r.minX + 14, y: r.minY + 6), withAttributes: attrs)
    }

    private func layoutToolbar() {
        var dragging = false
        switch drag {
        case .selecting, .moving, .resizing: dragging = true
        default: break
        }
        guard let sel = selection, !dragging else { toolbar.isHidden = true; return }
        toolbar.setFrameOrigin(Geometry.toolbarOrigin(selection: sel, toolbarSize: toolbar.frame.size, bounds: bounds))
        toolbar.isHidden = false
    }

    // MARK: - Mouse

    private func point(_ e: NSEvent) -> CGPoint {
        Geometry.clamp(convert(e.locationInWindow, from: nil), into: bounds)
    }

    /// Topmost mark under `p`, inside the selection.
    private func markIndex(at p: CGPoint) -> Int? {
        guard let sel = selection, sel.contains(p) else { return nil }
        return annotations.indices.reversed().first { annotations[$0].hitTest(p) }
    }

    private func selectedMarkHandle(at p: CGPoint) -> Handle? {
        guard tool == .move, let i = selectedMark, annotations.indices.contains(i) else { return nil }
        return Geometry.handle(at: p, in: markFrame(annotations[i]), tolerance: 6)
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeKey()
        if textField != nil {
            commitText()
            return
        }
        window?.makeFirstResponder(self)
        let p = point(e)

        guard let sel = selection else {
            drag = .selecting(p)
            delegate?.selectionViewDidBeginSelection(self)
            return
        }

        // 1. Handles of the picked mark.
        if let h = selectedMarkHandle(at: p), let i = selectedMark {
            pendingSnapshot = annotations
            drag = .resizingMark(i, h, markFrame(annotations[i]), annotations[i])
            return
        }
        // 2. Region handles.
        if let h = Geometry.handle(at: p, in: sel) {
            drag = .resizing(h, sel)
            layoutToolbar()
            return
        }
        switch tool {
        case .move:
            // 3. Pick a mark (double-click on empty area still copies).
            if let i = markIndex(at: p) {
                selectedMark = i
                pendingSnapshot = annotations
                drag = .movingMark(i, p, annotations[i])
                NSCursor.closedHand.set()
                return
            }
            selectedMark = nil
            if e.clickCount == 2, sel.contains(p) {
                finish(.copy)
                return
            }
            if sel.contains(p) {
                drag = .moving(p, sel)
                NSCursor.closedHand.set()
            } else {
                drag = .selecting(p)
                selection = nil
                delegate?.selectionViewDidBeginSelection(self)
            }
        case .text:
            if sel.contains(p) { beginText(at: p) }
        case .pen, .highlighter, .line, .arrow, .rect:
            guard sel.contains(p) else { return }
            drag = .drawing(p)
            penPoints = [p]
            current = makeAnnotation(start: p, end: p, shift: false)
            needsDisplay = true
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = point(e)
        switch drag {
        case .none:
            break
        case .selecting(let start):
            selection = Geometry.rect(from: start, to: p)
        case .moving(let start, let orig):
            selection = Geometry.clamp(orig.offsetBy(dx: p.x - start.x, dy: p.y - start.y), into: bounds)
        case .resizing(let h, let orig):
            selection = Geometry.resize(orig, handle: h, to: p)
        case .drawing(let start):
            penPoints.append(p)
            current = makeAnnotation(start: start, end: p, shift: e.modifierFlags.contains(.shift))
            needsDisplay = true
        case .movingMark(let i, let start, let orig):
            commitPendingSnapshot()
            annotations[i] = orig.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            needsDisplay = true
        case .resizingMark(let i, let h, let frame, let orig):
            commitPendingSnapshot()
            var newFrame = Geometry.resize(frame, handle: h, to: p)
            if e.modifierFlags.contains(.shift), frame.width > 0, frame.height > 0 {
                newFrame = Self.keepAspect(newFrame, of: frame, handle: h)
            }
            // markFrame pads the real bounds; map frame→frame so the padding stays constant.
            let pad = CGSize(width: (frame.width - orig.bounds.width) / 2, height: (frame.height - orig.bounds.height) / 2)
            let target = newFrame.insetBy(dx: min(pad.width, newFrame.width / 2), dy: min(pad.height, newFrame.height / 2))
            annotations[i] = orig.transformed(from: orig.bounds, to: target)
            needsDisplay = true
        }
    }

    /// Shift-resize keeps proportions (anchored at the opposite corner).
    private static func keepAspect(_ r: CGRect, of orig: CGRect, handle: Handle) -> CGRect {
        let k = max(r.width / orig.width, r.height / orig.height)
        let size = CGSize(width: orig.width * k, height: orig.height * k)
        var o = r.origin
        switch handle {
        case .topLeft, .left, .bottomLeft: o.x = r.maxX - size.width
        default: break
        }
        switch handle {
        case .bottomLeft, .bottom, .bottomRight: o.y = r.maxY - size.height
        default: break
        }
        return CGRect(origin: o, size: size)
    }

    override func mouseUp(with e: NSEvent) {
        switch drag {
        case .selecting, .resizing:
            if let s = selection, s.width < 3 || s.height < 3 { selection = nil }
        case .drawing:
            if let c = current, !isDegenerate(c) { addAnnotation(c) }
            current = nil
        default:
            break
        }
        pendingSnapshot = nil
        drag = .none
        layoutToolbar()
        needsDisplay = true
        updateCursor(at: point(e))
    }

    override func mouseMoved(with e: NSEvent) {
        mouseInside = true
        updateCursor(at: point(e))
        if selection == nil { needsDisplay = true }
    }

    override func mouseEntered(with event: NSEvent) { mouseInside = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { mouseInside = false; needsDisplay = true }

    private func updateCursor() {
        guard let w = window else { return }
        updateCursor(at: convert(w.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func setResizeCursor(_ h: Handle) {
        if h.isHorizontalEdge { NSCursor.resizeLeftRight.set() }
        else if h.isVerticalEdge { NSCursor.resizeUpDown.set() }
        else { NSCursor.crosshair.set() }
    }

    private func updateCursor(at p: CGPoint) {
        if !toolbar.isHidden, toolbar.frame.contains(p) { NSCursor.arrow.set(); return }
        guard let sel = selection else { NSCursor.crosshair.set(); return }
        if let h = selectedMarkHandle(at: p) { setResizeCursor(h); return }
        if let h = Geometry.handle(at: p, in: sel) { setResizeCursor(h); return }
        guard sel.contains(p) else { NSCursor.crosshair.set(); return }
        switch tool {
        case .move: (markIndex(at: p) != nil ? NSCursor.pointingHand : NSCursor.openHand).set()
        case .text: NSCursor.iBeam.set()
        default: NSCursor.crosshair.set()
        }
    }

    // MARK: - Annotations & history

    private func makeAnnotation(start: CGPoint, end: CGPoint, shift: Bool) -> Annotation? {
        switch tool {
        case .pen:
            return Annotation(shape: .pen(penPoints), color: color, lineWidth: 3)
        case .highlighter:
            return Annotation(shape: .highlighter(penPoints), color: color, lineWidth: 18)
        case .line:
            return Annotation(shape: .line(start, shift ? Geometry.snap45(from: start, to: end) : end), color: color, lineWidth: 3)
        case .arrow:
            return Annotation(shape: .arrow(start, shift ? Geometry.snap45(from: start, to: end) : end), color: color, lineWidth: 3)
        case .rect:
            return Annotation(shape: .rect(Geometry.rect(from: start, to: end)), color: color, lineWidth: 3)
        case .move, .text:
            return nil
        }
    }

    private func isDegenerate(_ a: Annotation) -> Bool {
        switch a.shape {
        case .line(let p, let q), .arrow(let p, let q): return hypot(q.x - p.x, q.y - p.y) < 3
        case .rect(let r): return r.width < 3 || r.height < 3
        default: return false
        }
    }

    private func checkpoint() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    private func commitPendingSnapshot() {
        guard let snap = pendingSnapshot else { return }
        pendingSnapshot = nil
        undoStack.append(snap)
        redoStack.removeAll()
    }

    private func addAnnotation(_ a: Annotation) {
        checkpoint()
        annotations.append(a)
    }

    private func deleteSelectedMark() {
        guard let i = selectedMark, annotations.indices.contains(i) else { return }
        checkpoint()
        annotations.remove(at: i)
        selectedMark = nil
    }

    private func chooseColor(_ i: Int) {
        colorIndex = i
        // Recolor the picked mark too.
        if let m = selectedMark, annotations.indices.contains(m) {
            checkpoint()
            annotations[m].color = ToolPrefs.palette[i]
            needsDisplay = true
        }
        if let tf = textField {
            tf.textColor = color
            (tf.currentEditor() as? NSTextView)?.insertionPointColor = color
        }
    }

    private func selectTool(_ t: Tool) {
        commitText()
        tool = t
        window?.makeFirstResponder(self)
    }

    private func undo() {
        if textField != nil { cancelText(); return }
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
        selectedMark = nil
        needsDisplay = true
    }

    private func redo() {
        guard textField == nil, let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedMark = nil
        needsDisplay = true
    }

    // MARK: - Text

    private func beginText(at p: CGPoint) {
        guard let sel = selection else { return }
        let font = Annotation.font(size: textSize)
        let h = ceil(font.ascender - font.descender + font.leading) + 4
        let x = p.x - 2
        let tf = NSTextField(frame: CGRect(x: x, y: p.y - h / 2, width: max(60, sel.maxX - x), height: h))
        tf.font = font
        tf.textColor = color
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.cell?.isScrollable = true
        tf.cell?.wraps = false
        tf.delegate = self
        tf.target = self
        tf.action = #selector(textEntered(_:))
        addSubview(tf)
        textField = tf
        window?.makeFirstResponder(tf)
        (tf.currentEditor() as? NSTextView)?.insertionPointColor = color
    }

    @objc private func textEntered(_ sender: NSTextField) { commitText() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelText()
            return true
        }
        return false
    }

    private func commitText() {
        guard let tf = textField else { return }
        textField = nil
        let s = tf.stringValue
        if !s.trimmingCharacters(in: .whitespaces).isEmpty {
            let textColor = tf.textColor ?? color
            let ts = (s as NSString).size(withAttributes: Annotation.textAttributes(color: textColor, size: textSize))
            let origin = CGPoint(x: tf.frame.minX + 2, y: tf.frame.midY - ts.height / 2)
            addAnnotation(Annotation(shape: .text(s, origin, textSize), color: textColor))
        }
        tf.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelText() {
        guard let tf = textField else { return }
        textField = nil
        tf.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    // MARK: - Keyboard

    private func finish(_ action: FinishAction) {
        commitText()
        if action != .cancel, selection == nil { return }
        selectedMark = nil
        delegate?.selectionView(self, finishWith: action)
    }

    override func keyDown(with e: NSEvent) {
        if !handleKey(e) { super.keyDown(with: e) }
    }

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard textField == nil, window?.isKeyWindow == true, e.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: e)
        }
        return handleKey(e)
    }

    override func cancelOperation(_ sender: Any?) { finish(.cancel) }

    private func handleKey(_ e: NSEvent) -> Bool {
        switch Int(e.keyCode) {
        case 53: // Esc: deselect a picked mark first, otherwise close
            if selectedMark != nil { selectedMark = nil } else { finish(.cancel) }
            return true
        case 36, 76: finish(.copy); return true // Return / Enter
        case 51, 117: deleteSelectedMark(); return true // Delete / Forward-delete
        case 123, 124, 125, 126: // arrows nudge the picked mark (⇧ = 10pt)
            guard let i = selectedMark, annotations.indices.contains(i) else { return false }
            let step: CGFloat = e.modifierFlags.contains(.shift) ? 10 : 1
            let d: (CGFloat, CGFloat) = [123: (-step, 0), 124: (step, 0), 125: (0, -step), 126: (0, step)][Int(e.keyCode)]!
            checkpoint()
            annotations[i] = annotations[i].offsetBy(dx: d.0, dy: d.1)
            needsDisplay = true
            return true
        default: break
        }
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if e.modifierFlags.contains(.command) {
            switch ch {
            case "c": finish(.copy)
            case "s": finish(.save)
            case "z": if e.modifierFlags.contains(.shift) { redo() } else { undo() }
            case "y": redo()
            default: return false
            }
            return true
        }
        guard selection != nil else { return false }
        let map: [String: Tool] = ["v": .move, "m": .move, "p": .pen, "l": .line, "a": .arrow,
                                   "r": .rect, "h": .highlighter, "t": .text]
        guard let t = map[ch] else { return false }
        selectTool(t)
        return true
    }
}
