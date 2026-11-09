import AppKit

/// Restart the app: macOS applies a newly granted Screen Recording permission only to a fresh process.
enum AppRelaunch {
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Screen Recording setup window.
///
/// Rules learned the hard way:
/// - macOS shows its own permission prompt only once per app. Asking repeatedly gets silently refused,
///   so MaoShot asks once and otherwise guides the user to System Settings (drag the app in if it's not listed).
/// - A running process never sees a new grant. A fresh helper process is polled, and MaoShot restarts itself.
/// - Resetting the permission is only done when the user asks for it (stale entry after an update).
@MainActor
final class PermissionGuide: NSObject, NSWindowDelegate {
    static let shared = PermissionGuide()

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private var window: NSWindow?
    private var timer: Timer?
    private var checking = false
    private let statusLabel = NSTextField(labelWithString: "")

    // MARK: - Launch

    private static let grantedBuildKey = "grantedBuild"
    private static let resetPendingKey = "permissionResetPending"

    /// Signature hash of the build that last had access, to recognise an update that lost it.
    private static var grantedBuild: String? {
        get { UserDefaults.standard.string(forKey: grantedBuildKey) }
        set { UserDefaults.standard.set(newValue, forKey: grantedBuildKey) }
    }

    private static var resetPending: Bool {
        get { UserDefaults.standard.bool(forKey: resetPendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: resetPendingKey) }
    }

    static func handleLaunch() {
        if ScreenCapturer.hasPermission {
            grantedBuild = DiagLog.currentCdhash()
            resetPending = false
            return
        }
        let updated = grantedBuild != nil && grantedBuild != DiagLog.currentCdhash()
        if resetPending {
            resetPending = false
            DiagLog.write("permission: first launch after reset, asking macOS")
            ScreenCapturer.requestPermission()
            shared.show(reason: "Turn MaoShot on in System Settings.")
            shared.openSettings()
        } else if updated {
            DiagLog.write("permission: build changed since last grant")
            shared.show(reason: "MaoShot was updated. If its switch is already on, click Reset Permission.")
        } else {
            ScreenCapturer.requestPermission()
            shared.show()
        }
    }

    // MARK: - Actions

    /// Clears MaoShot's own (stale) Screen Recording entry and restarts, so the fresh process can ask again.
    static func resetAndRelaunch() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "com.maoshot.app"]
        try? reset.run()
        reset.waitUntilExit()
        DiagLog.write("permission: tccutil reset exit=\(reset.terminationStatus), restarting")
        resetPending = true
        AppRelaunch.relaunch()
    }

    static func confirmReset() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Reset Screen Recording permission?"
        alert.informativeText = "Use this when MaoShot is switched on in System Settings but still can't capture "
            + "(common after installing a new version). MaoShot will restart, then turn it on again."
        alert.addButton(withTitle: "Reset and Restart")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { resetAndRelaunch() }
    }

    func openSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    // MARK: - Window

    func show(reason: String? = nil) {
        if window == nil { buildWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        statusLabel.stringValue = reason ?? "Waiting for access…"
        startPolling()
    }

    private func buildWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "MaoShot"
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = NSTextField(labelWithString: "Allow MaoShot to capture your screen")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: """
        1. Click Open System Settings.
        2. Turn on MaoShot under Screen & System Audio Recording.
           Not in the list? Click Show in Finder and drag MaoShot into the list.
        MaoShot restarts by itself once access is on.
        """)
        body.font = .systemFont(ofSize: 13)
        body.preferredMaxLayoutWidth = 410

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        let open = NSButton(title: "Open System Settings", target: self, action: #selector(openSettingsTapped))
        open.keyEquivalent = "\r"
        let finder = NSButton(title: "Show in Finder", target: self, action: #selector(showInFinder))
        let reset = NSButton(title: "Reset Permission…", target: self, action: #selector(resetTapped))
        let quit = NSButton(title: "Quit", target: self, action: #selector(quit))
        let buttons = NSStackView(views: [quit, reset, NSView(), finder, open])
        buttons.orientation = .horizontal
        buttons.distribution = .fill

        let text = NSStackView(views: [title, body, statusLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 8

        let top = NSStackView(views: [icon, text])
        top.orientation = .horizontal
        top.alignment = .top
        top.spacing = 14

        let root = NSStackView(views: [top, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
        ])
        w.contentView = content
        window = w
    }

    @objc private func openSettingsTapped() { openSettings() }

    @objc private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func resetTapped() { Self.confirmReset() }
    @objc private func quit() { NSApp.terminate(nil) }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling via a fresh process

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard !checking, let exe = Bundle.main.executablePath else { return }
        checking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = ["--check-permission"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            var granted = false
            if (try? p.run()) != nil {
                p.waitUntilExit()
                granted = p.terminationStatus == 0
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.checking = false
                    guard granted, self.timer != nil else { return }
                    self.timer?.invalidate()
                    self.timer = nil
                    self.statusLabel.stringValue = "✓ Access granted. Restarting MaoShot…"
                    DiagLog.write("permission: granted, restarting")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { AppRelaunch.relaunch() }
                }
            }
        }
    }
}
