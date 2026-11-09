import AppKit
import ScreenCaptureKit

struct CapturedScreen {
    let screen: NSScreen
    let image: CGImage
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum ScreenCapturer {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// SCStreamError.userDeclined: macOS refused capture (no permission, or a stale entry).
    static let deniedErrorCode = -3801

    /// Ask macOS once. A real ScreenCaptureKit call is what adds MaoShot to the Settings list and shows
    /// the system prompt (the first time only; later calls are silently refused).
    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                DiagLog.write("permission request: allowed")
            } catch {
                DiagLog.write("permission request: \((error as NSError).code) \(error.localizedDescription)")
            }
        }
    }

    /// Freeze every display at full Retina resolution (cursor hidden).
    @MainActor
    static func captureAll() async throws -> [CapturedScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [CapturedScreen] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(CapturedScreen(screen: screen, image: image))
        }
        return result
    }
}
