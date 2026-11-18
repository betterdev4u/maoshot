import AppKit
import MaoShotCore

/// Renders the overlay UI and the final output against a synthetic "screen", so the drawing code
/// can be checked without Screen Recording permission. `MaoShot --render-demo <dir>`
@MainActor
enum DemoRenderer {
    static func run(outputDirectory dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 1200, height: 750)
        let scale: CGFloat = 2
        guard let screen = fakeScreen(size: size, scale: scale) else { return }

        let view = SelectionView(frame: CGRect(origin: .zero, size: size), image: screen)
        let sel = CGRect(x: 180, y: 220, width: 640, height: 380)
        let ann: [Annotation] = [
            Annotation(shape: .rect(CGRect(x: 220, y: 450, width: 260, height: 110)), color: .systemRed),
            Annotation(shape: .arrow(CGPoint(x: 700, y: 300), CGPoint(x: 500, y: 440)), color: .systemRed),
            Annotation(shape: .marker(CGRect(x: 234, y: 379, width: 316, height: 20)), color: .systemYellow, lineWidth: 20),
            Annotation(shape: .pen((0..<40).map { CGPoint(x: 560 + CGFloat($0) * 5, y: 520 + sin(CGFloat($0) / 3) * 20) }), color: .systemBlue),
            Annotation(shape: .line(CGPoint(x: 230, y: 260), CGPoint(x: 460, y: 260)), color: .systemGreen),
            Annotation(shape: .text("Click here →", CGPoint(x: 560, y: 260), 22), color: .systemRed),
        ]
        view.setDemoState(selection: sel, annotations: ann, tool: .move, selectedMark: 0)

        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("overlay.png"))
        }
        if let out = view.renderResult(), let png = Renderer.pngData(out.image, pointSize: out.pointSize) {
            try? png.write(to: dir.appendingPathComponent("result.png"))
            print("result: \(out.image.width)x\(out.image.height) px")
        }
        // Feature shots: straight highlighter vs brush, and the thickness levels.
        let wobble = (0..<30).map { CGPoint(x: 234 + CGFloat($0) * 9, y: 319 + sin(CGFloat($0) * 1.3) * 3.5) }
        let label: (String, CGFloat, CGFloat) -> Annotation = {
            Annotation(shape: .text($0, CGPoint(x: $1, y: $2), 15), color: .black)
        }
        let highlight: [Annotation] = [
            Annotation(shape: .marker(CGRect(x: 234, y: 379, width: 316, height: 20)), color: .systemYellow, lineWidth: 20),
            Annotation(shape: .highlighter(wobble), color: .systemYellow, lineWidth: 18),
            label("Highlighter: stays straight", 640, 382),
            label("Brush: freehand", 640, 312),
        ]
        renderShot(named: "highlighter.png", screen: screen, size: size, selection: CGRect(x: 200, y: 290, width: 720, height: 140), annotations: highlight, to: dir)
        var thickness: [Annotation] = []
        for (i, name) in Annotation.sizeNames.enumerated() {
            let y = 580 - CGFloat(i) * 62
            let line = Annotation(shape: .line(CGPoint(x: 620, y: y), CGPoint(x: 780, y: y)), color: .systemRed)
            thickness.append(line.withSize(index: i))
            thickness.append(label(name, 800, y - 9))
        }
        renderShot(named: "thickness.png", screen: screen, size: size, selection: CGRect(x: 600, y: 280, width: 340, height: 340), annotations: thickness, to: dir)

        // Menu bar icon at 8x for inspection.
        let mb = CatIcon.menuBarImage()
        let big = NSImage(size: NSSize(width: 144, height: 144), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            mb.draw(in: r)
            return true
        }
        if let tiff = big.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("menubar.png"))
        }
        print("wrote \(dir.path)/overlay.png, result.png, menubar.png")
    }

    private static func renderShot(named name: String, screen: CGImage, size: CGSize, selection: CGRect,
                                   annotations: [Annotation], to dir: URL) {
        let v = SelectionView(frame: CGRect(origin: .zero, size: size), image: screen)
        v.setDemoState(selection: selection, annotations: annotations, tool: .move)
        if let out = v.renderResult(), let png = Renderer.pngData(out.image, pointSize: out.pointSize) {
            try? png.write(to: dir.appendingPathComponent(name))
        }
    }

    private static func fakeScreen(size: CGSize, scale: CGFloat) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: CGRect(origin: .zero, size: size), angle: 35)
        NSColor.white.setFill()
        let win = CGRect(x: 150, y: 150, width: 800, height: 480)
        NSBezierPath(roundedRect: win, xRadius: 12, yRadius: 12).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.darkGray]
        for (i, line) in ["Quarterly report", "Revenue grew 12% quarter over quarter.",
                          "Important: submit numbers by Friday.", "Contact the team for questions."].enumerated() {
            (line as NSString).draw(at: CGPoint(x: 240, y: 520 - CGFloat(i) * 70), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
