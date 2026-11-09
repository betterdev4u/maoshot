import AppKit
import Darwin
import ScreenCaptureKit
import Security

/// Append-only log at ~/Library/Logs/MaoShot.log plus a full troubleshooting report.
enum DiagLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MaoShot.log")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Keep the log small: past 512 KB, keep only the newest half.
    static func trimIfNeeded(maxBytes: Int = 512 * 1024) {
        guard let data = try? Data(contentsOf: url), data.count > maxBytes else { return }
        try? data.suffix(maxBytes / 2).write(to: url, options: .atomic)
    }

    // MARK: - Report

    /// Everything relevant to "why won't Screen Recording permission stick?".
    /// `liveTest` performs a real ScreenCaptureKit call (may trigger the system prompt).
    @MainActor
    static func report(liveTest: Bool, hotKeyRegistered: Bool?) async -> String {
        var lines: [String] = []
        func add(_ k: String, _ v: Any) { lines.append("\(k): \(v)") }

        let info = Bundle.main.infoDictionary ?? [:]
        lines.append("=== MaoShot diagnostics \(ISO8601DateFormatter().string(from: Date())) ===")
        add("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
        add("bundle path", Bundle.main.bundlePath)
        add("bundle id", Bundle.main.bundleIdentifier ?? "(none — not running from an .app bundle)")
        add("version", "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))")

        // Launch context: LaunchServices launches have launchd (pid 1) as parent.
        let pid = getpid(), ppid = getppid()
        add("pid / parent", "\(pid) / \(ppid) \(processPath(ppid) ?? "?")")
        add("launched via", ppid == 1 ? "LaunchServices (Finder/Spotlight/open) ✓"
                                      : "directly by parent process — macOS may check the PARENT's permission ⚠︎")

        // Code signature (what TCC matches the permission against).
        lines.append(contentsOf: signatureLines())

        // Other copies with the same bundle id confuse permission matching.
        let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        add("copies registered with this bundle id", copies.count)
        for c in copies {
            let mark = c.standardizedFileURL.path == URL(fileURLWithPath: Bundle.main.bundlePath).standardizedFileURL.path ? "  ← this one" : ""
            lines.append("  - \(c.path)\(mark)")
        }

        add("CGPreflightScreenCaptureAccess", CGPreflightScreenCaptureAccess())
        if let hk = hotKeyRegistered { add("hotkey \(Shortcut.current.id) registered", hk) }

        if liveTest {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                add("live capture test", "OK — \(content.displays.count) display(s) visible ✓")
            } catch {
                let ns = error as NSError
                add("live capture test", "FAILED — \(ns.domain) code \(ns.code): \(ns.localizedDescription)")
            }
        }

        lines.append(contentsOf: verdict(lines: lines))
        return lines.joined(separator: "\n")
    }

    private static func verdict(lines: [String]) -> [String] {
        let text = lines.joined(separator: "\n")
        var hints: [String] = []
        if text.contains("live capture test: OK") {
            hints.append("Capture works. If the shortcut does nothing, check the hotkey line above.")
        } else {
            if text.contains("directly by parent process") {
                hints.append("Launched by another process. Quit and open MaoShot from Finder or Spotlight instead.")
            }
            if text.contains("copies registered with this bundle id: ") && !text.contains("copies registered with this bundle id: 1") {
                hints.append("More than one MaoShot.app is installed. Delete the extra copies so the permission matches the one you run.")
            }
            if text.contains("CGPreflightScreenCaptureAccess: false") {
                hints.append("macOS doesn't allow this build to capture. If MaoShot is already on in Screen & System Audio Recording, "
                             + "use Troubleshoot → Reset Screen Recording Permission…, then turn it on again.")
            }
        }
        return hints.isEmpty ? [] : ["--- hints ---"] + hints.map { "• " + $0 }
    }

    /// Hash identifying this exact build's code signature.
    static func currentCdhash() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var infoCF: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any], let data = info[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private static func processPath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    private static func signatureLines() -> [String] {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return ["signature: (unavailable)"] }
        var staticCode: SecStaticCode?
        SecCodeCopyStaticCode(code, [], &staticCode)
        var out: [String] = []

        var infoCF: CFDictionary?
        if let staticCode, SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
           let info = infoCF as? [String: Any] {
            let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
            let adhoc = flags & 0x2 != 0 // kSecCodeSignatureAdhoc
            let cdhash = (info[kSecCodeInfoUnique as String] as? Data)?.map { String(format: "%02x", $0) }.joined() ?? "?"
            let certs = (info[kSecCodeInfoCertificates as String] as? [SecCertificate]) ?? []
            let signer = certs.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
            out.append("signed as: \(adhoc ? "ad-hoc (permission resets on every rebuild)" : (signer ?? "certificate"))")
            out.append("team id: \(info[kSecCodeInfoTeamIdentifier as String] ?? "(none)")")
            out.append("cdhash: \(cdhash)")
        }
        var req: SecRequirement?
        if let staticCode, SecCodeCopyDesignatedRequirement(staticCode, [], &req) == errSecSuccess, let req {
            var s: CFString?
            SecRequirementCopyString(req, [], &s)
            out.append("designated requirement: \(s as String? ?? "?")")
        }
        let valid = SecCodeCheckValidity(code, [], nil)
        out.append("signature valid: \(valid == errSecSuccess ? "yes" : "NO (OSStatus \(valid))")")
        return out
    }
}
