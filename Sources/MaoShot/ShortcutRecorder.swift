import AppKit
import Carbon.HIToolbox

/// Small window that records the next key combination as the capture shortcut.
@MainActor
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var monitor: Any?
    private let keysLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private var onDone: ((Shortcut?) -> Void)?

    /// Calls `done` with the recorded shortcut, or nil if cancelled.
    func record(current: Shortcut, done: @escaping (Shortcut?) -> Void) {
        onDone = done
        if window == nil { buildWindow() }
        keysLabel.stringValue = current.title.components(separatedBy: "  ")[0]
        keysLabel.textColor = .tertiaryLabelColor
        setHint("Press the new shortcut. Esc cancels.")

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func handle(_ e: NSEvent) {
        if e.type == .flagsChanged {
            // Live preview of held modifiers.
            let f = e.modifierFlags
            var s = ""
            if f.contains(.control) { s += "⌃" }
            if f.contains(.option) { s += "⌥" }
            if f.contains(.shift) { s += "⇧" }
            if f.contains(.command) { s += "⌘" }
            keysLabel.stringValue = s
            keysLabel.textColor = .labelColor
            return
        }
        if Int(e.keyCode) == kVK_Escape, e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            finish(nil)
            return
        }
        guard let s = Shortcut.from(event: e) else {
            NSSound.beep()
            setHint("Add ⌘, ⌥ or ⌃ (function keys F1–F20 work alone).")
            return
        }
        keysLabel.stringValue = s.title
        keysLabel.textColor = .controlAccentColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.finish(s) }
    }

    private func setHint(_ s: String) { hintLabel.stringValue = s }

    private func finish(_ s: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let done = onDone
        onDone = nil
        window?.orderOut(nil)
        done?(s)
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }

    private func buildWindow() {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Set Shortcut"
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        keysLabel.font = .systemFont(ofSize: 30, weight: .medium)
        keysLabel.alignment = .center
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))

        let stack = NSStackView(views: [keysLabel, hintLabel, cancel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        keysLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        window = w
    }

    @objc private func cancelTapped() { finish(nil) }
}
