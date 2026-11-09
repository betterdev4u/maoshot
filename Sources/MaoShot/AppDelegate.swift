import AppKit
import ServiceManagement
import MaoShotCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var overlay: OverlayController?
    private var capturing = false
    private let recorder = ShortcutRecorder()
    private let history = HistoryStore(directory: HistoryStore.defaultDirectory, limit: 10)

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagLog.trimIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = CatIcon.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        registerHotKey()
        let registered = hotKey != nil
        Task { @MainActor in
            DiagLog.write("launch\n" + (await DiagLog.report(liveTest: false, hotKeyRegistered: registered)))
        }
        PermissionGuide.handleLaunch()
    }

    // MARK: - Hotkey

    private func registerHotKey() {
        hotKey = nil
        let s = Shortcut.current
        hotKey = HotKey(keyCode: s.keyCode, modifiers: s.carbonModifiers) { [weak self] in
            self?.startCapture()
        }
        if hotKey == nil {
            DiagLog.write("hotkey \(s.id) unavailable (used by another app)")
        }
    }

    // MARK: - Capture

    @objc private func captureFromMenu() {
        // Let the menu finish closing so it isn't in the shot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.startCapture() }
    }

    func startCapture() {
        guard overlay == nil, !capturing else { return }
        // Don't gate on CGPreflightScreenCaptureAccess(): it can report false after the user has
        // granted access (until relaunch). Just try; ScreenCaptureKit throws if access is really missing.
        capturing = true
        Task { @MainActor in
            defer { capturing = false }
            do {
                let captures = try await ScreenCapturer.captureAll()
                guard !captures.isEmpty else { return }
                let controller = OverlayController(captures: captures)
                controller.onFinish = { action, view in self.finish(action, view: view) }
                overlay = controller
                controller.show()
            } catch {
                let code = (error as NSError).code
                DiagLog.write("capture failed preflight=\(ScreenCapturer.hasPermission) error=\(error)")
                if code == ScreenCapturer.deniedErrorCode || !ScreenCapturer.hasPermission {
                    PermissionGuide.shared.show(reason: "macOS blocked the capture. Screen Recording access is off.")
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    private func finish(_ action: FinishAction, view: SelectionView) {
        let result = view.renderResult()
        overlay?.close()
        overlay = nil

        guard let result, let png = Renderer.pngData(result.image, pointSize: result.pointSize) else {
            NSApp.hide(nil)
            return
        }
        // Every captured region goes to history — even if it was never copied or saved.
        _ = try? history.add(pngData: png)

        switch action {
        case .copy:
            copyToClipboard(png)
            NSApp.hide(nil)
        case .save:
            saveWithPanel(png)
        case .cancel:
            NSApp.hide(nil)
        }
    }

    private func copyToClipboard(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    private func saveWithPanel(_ png: Data, date: Date = Date()) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot \(Self.fileStamp.string(from: date)).png"
        panel.directoryURL = UserDefaults.standard.url(forKey: "saveDirectory")
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.level = .modalPanel
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try png.write(to: url, options: .atomic)
                UserDefaults.standard.set(url.deletingLastPathComponent(), forKey: "saveDirectory")
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        NSApp.hide(nil)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Shortcut.current

        let capture = NSMenuItem(title: "Take Screenshot", action: #selector(captureFromMenu), keyEquivalent: s.keyEquivalent)
        capture.keyEquivalentModifierMask = s.modifierMask
        capture.target = self
        menu.addItem(capture)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem.sectionHeader(title: "Recent"))
        let items = history.items()
        if items.isEmpty {
            let empty = NSMenuItem(title: "No screenshots yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        let timeFmt = DateFormatter()
        timeFmt.doesRelativeDateFormatting = true
        timeFmt.dateStyle = .short
        timeFmt.timeStyle = .medium
        for url in items {
            let title = history.date(of: url).map { timeFmt.string(from: $0) } ?? url.lastPathComponent
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if let img = NSImage(contentsOf: url) { item.image = Self.thumbnail(img) }
            let sub = NSMenu()
            for (t, sel) in [("Copy to Clipboard", #selector(copyHistoryItem(_:))),
                             ("Save…", #selector(saveHistoryItem(_:))),
                             ("Open", #selector(openHistoryItem(_:))),
                             ("Show in Finder", #selector(revealHistoryItem(_:)))] {
                let mi = NSMenuItem(title: t, action: sel, keyEquivalent: "")
                mi.target = self
                mi.representedObject = url
                sub.addItem(mi)
            }
            item.submenu = sub
            menu.addItem(item)
        }
        if !items.isEmpty {
            let open = NSMenuItem(title: "Open History Folder", action: #selector(openHistoryFolder), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
        menu.addItem(.separator())

        let shortcutItem = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        let shortcutMenu = NSMenu()
        for p in Shortcut.presets + [Shortcut.savedCustom].compactMap({ $0 }) {
            let mi = NSMenuItem(title: p.title, action: #selector(chooseShortcut(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = p.id
            mi.state = p.id == s.id ? .on : .off
            shortcutMenu.addItem(mi)
        }
        shortcutMenu.addItem(.separator())
        let record = NSMenuItem(title: "Custom Shortcut…", action: #selector(recordShortcut), keyEquivalent: "")
        record.target = self
        shortcutMenu.addItem(record)
        if hotKey == nil {
            let warn = NSMenuItem(title: "⚠︎ This shortcut is used by another app. Pick another.", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            shortcutMenu.addItem(warn)
        }
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if !ScreenCapturer.hasPermission {
            let perm = NSMenuItem(title: "Allow Screen Recording…", action: #selector(permissionFromMenu), keyEquivalent: "")
            perm.target = self
            menu.addItem(perm)
        }

        let trouble = NSMenuItem(title: "Troubleshoot", action: nil, keyEquivalent: "")
        let troubleMenu = NSMenu()
        for (t, sel) in [("Screen Recording Setup…", #selector(permissionFromMenu)),
                         ("Reset Screen Recording Permission…", #selector(resetPermission)),
                         ("Copy Diagnostics Report", #selector(runDiagnostics)),
                         ("Show Log", #selector(openLogFile)),
                         ("Restart MaoShot", #selector(restartFromMenu))] {
            let mi = NSMenuItem(title: t, action: sel, keyEquivalent: "")
            mi.target = self
            troubleMenu.addItem(mi)
        }
        trouble.submenu = troubleMenu
        menu.addItem(trouble)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About MaoShot", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit MaoShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private static func thumbnail(_ img: NSImage) -> NSImage {
        let h: CGFloat = 36
        let w = min(120, max(h, img.size.width * h / max(img.size.height, 1)))
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
            img.draw(in: r, from: .zero, operation: .copy, fraction: 1)
            return true
        }
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, let data = try? Data(contentsOf: url) else { return }
        copyToClipboard(data)
    }

    @objc private func saveHistoryItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, let data = try? Data(contentsOf: url) else { return }
        saveWithPanel(data, date: history.date(of: url) ?? Date())
    }

    @objc private func openHistoryItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealHistoryItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openHistoryFolder() {
        try? FileManager.default.createDirectory(at: history.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(history.directory)
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear recent screenshots?"
        alert.informativeText = "The last \(history.limit) captures kept by MaoShot will be deleted. Files you saved are not affected."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { history.clear() }
    }

    @objc private func chooseShortcut(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let s = (Shortcut.presets + [Shortcut.savedCustom].compactMap { $0 }).first(where: { $0.id == id }) else { return }
        Shortcut.select(s)
        registerHotKey()
    }

    @objc private func recordShortcut() {
        let previous = Shortcut.current
        hotKey = nil // free the current combo so it can be recorded too
        recorder.record(current: previous) { [weak self] new in
            guard let self else { return }
            guard let new else { self.registerHotKey(); return }
            guard let hk = HotKey(keyCode: new.keyCode, modifiers: new.carbonModifiers, handler: { [weak self] in
                self?.startCapture()
            }) else {
                self.registerHotKey()
                self.alert("\(new.title) is already used by another app", "Pick a different combination.")
                return
            }
            self.hotKey = hk
            Shortcut.select(new)
            DiagLog.write("hotkey set to custom \(new.title)")
            if new.clashesWithSystemScreenshot {
                self.alert("macOS also uses \(new.title)",
                           "Turn off macOS's own shortcut in System Settings → Keyboard → Keyboard Shortcuts → Screenshots, "
                           + "otherwise macOS takes it first.")
            }
        }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func runDiagnostics() {
        let registered = hotKey != nil
        Task { @MainActor in
            let report = await DiagLog.report(liveTest: true, hotKeyRegistered: registered)
            DiagLog.write("diagnostics\n" + report)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Diagnostics report copied to clipboard"
            alert.informativeText = report
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show Log")
            if alert.runModal() == .alertSecondButtonReturn { openLogFile() }
        }
    }

    @objc private func openLogFile() {
        if !FileManager.default.fileExists(atPath: DiagLog.url.path) { DiagLog.write("log created") }
        NSWorkspace.shared.open(DiagLog.url)
    }

    @objc private func restartFromMenu() { AppRelaunch.relaunch() }

    @objc private func resetPermission() { PermissionGuide.confirmReset() }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Select, mark up, copy. A tiny screenshot tool for macOS.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    @objc private func permissionFromMenu() { PermissionGuide.shared.show() }
}
