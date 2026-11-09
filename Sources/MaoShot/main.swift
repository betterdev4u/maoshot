import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared

    if let i = CommandLine.arguments.firstIndex(of: "--render-demo"), CommandLine.arguments.count > i + 1 {
        // Offline UI snapshot for development: no screen permission needed.
        DemoRenderer.run(outputDirectory: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    }

    if let i = CommandLine.arguments.firstIndex(of: "--make-iconset"), CommandLine.arguments.count > i + 1 {
        // Dev: regenerate Resources/AppIcon.icns via build.sh / iconutil.
        try! CatIcon.writeIconset(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    }

    if CommandLine.arguments.contains("--check-permission") {
        // Helper for PermissionGuide: a fresh process sees the current grant; exit 0 = allowed.
        exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
    }

    if CommandLine.arguments.contains("--diagnose") {
        // Prints the report for the binary as launched from a shell (no live capture → no prompt).
        Task { @MainActor in
            print(await DiagLog.report(liveTest: CommandLine.arguments.contains("--live"), hotKeyRegistered: nil))
            exit(0)
        }
        RunLoop.main.run()
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
