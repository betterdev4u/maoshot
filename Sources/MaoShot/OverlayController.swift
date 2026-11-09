import AppKit

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One frozen overlay window per display; only one display holds the active selection at a time.
@MainActor
final class OverlayController: SelectionViewDelegate {
    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    var onFinish: ((FinishAction, SelectionView) -> Void)?

    init(captures: [CapturedScreen]) {
        for c in captures {
            let w = OverlayWindow(screen: c.screen)
            let v = SelectionView(frame: CGRect(origin: .zero, size: c.screen.frame.size), image: c.image)
            v.delegate = self
            w.contentView = v
            windows.append(w)
            views.append(v)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        for w in windows { w.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        let i = windows.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        guard windows.indices.contains(i) else { return }
        windows[i].makeKeyAndOrderFront(nil)
        windows[i].makeFirstResponder(views[i])
        NSCursor.crosshair.set()
    }

    func close() {
        for w in windows {
            w.orderOut(nil)
            w.close()
        }
        windows.removeAll()
        views.removeAll()
    }

    func selectionViewDidBeginSelection(_ view: SelectionView) {
        for v in views where v !== view { v.reset() }
    }

    func selectionView(_ view: SelectionView, finishWith action: FinishAction) {
        onFinish?(action, view)
    }
}
