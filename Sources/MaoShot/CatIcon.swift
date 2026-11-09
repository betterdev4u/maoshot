import AppKit

/// MaoShot artwork (猫 māo = cat): a cat face framed by screenshot crop corners.
enum CatIcon {
    // MARK: - Shared cat geometry (unit space 0…1, y up)

    /// Head + ears silhouette pieces in a unit square. Filled one by one: as a single path the
    /// overlapping, oppositely wound pieces would cancel out where they meet.
    private static func headPieces(in r: CGRect) -> [NSBezierPath] {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        // Face: a wide rounded oval.
        var pieces = [NSBezierPath(ovalIn: CGRect(x: r.minX + 0.08 * r.width, y: r.minY + 0.06 * r.height,
                                                  width: 0.84 * r.width, height: 0.70 * r.height))]
        // Ears.
        for (base1, tip, base2) in [(p(0.12, 0.52), p(0.20, 0.97), p(0.46, 0.70)),
                                    (p(0.88, 0.52), p(0.80, 0.97), p(0.54, 0.70))] {
            let ear = NSBezierPath()
            ear.move(to: base1)
            ear.line(to: tip)
            ear.line(to: base2)
            ear.close()
            ear.lineJoinStyle = .round
            pieces.append(ear)
        }
        return pieces
    }

    /// Fill the silhouette as one composited shape (so a shadow is cast once, not per piece).
    private static func fillHead(in r: CGRect) {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for piece in headPieces(in: r) { piece.fill() }
        ctx.endTransparencyLayer()
    }

    // MARK: - Menu bar (template, 18pt)

    static func menuBarImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            // Crop corners.
            let c = NSBezierPath()
            c.lineWidth = 1.4
            c.lineCapStyle = .round
            let inset = rect.insetBy(dx: 1, dy: 1), arm: CGFloat = 4
            for (x, y, dx, dy) in [(inset.minX, inset.minY, 1.0, 1.0), (inset.maxX, inset.minY, -1.0, 1.0),
                                   (inset.minX, inset.maxY, 1.0, -1.0), (inset.maxX, inset.maxY, -1.0, -1.0)] {
                c.move(to: CGPoint(x: x + dx * arm, y: y))
                c.line(to: CGPoint(x: x, y: y))
                c.line(to: CGPoint(x: x, y: y + dy * arm))
            }
            c.stroke()
            // Cat head, filled, with eyes knocked out.
            fillHead(in: CGRect(x: 4, y: 3.5, width: 10, height: 10))
            NSGraphicsContext.current?.compositingOperation = .clear
            for ex in [7.0, 11.0] {
                NSBezierPath(ovalIn: CGRect(x: ex - 0.9, y: 7.1, width: 1.8, height: 2.1)).fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "MaoShot"
        return img
    }

    // MARK: - App icon

    /// Full-colour app icon at `size` px (square). Follows the macOS icon grid (824/1024 content).
    static func appIcon(size: CGFloat) -> NSBitmapImageRep {
        let px = Int(size)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = size / 1024
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: s, y: s)

        // Background squircle with warm gradient + drop shadow.
        let bg = CGRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = NSBezierPath(roundedRect: bg, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor(srgbRed: 1, green: 0.55, blue: 0.3, alpha: 1).setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [NSColor(srgbRed: 1.00, green: 0.78, blue: 0.42, alpha: 1),
                            NSColor(srgbRed: 1.00, green: 0.47, blue: 0.30, alpha: 1)])!
            .draw(in: squircle, angle: -90)

        // Crop corners (screenshot frame).
        let corners = NSBezierPath()
        corners.lineWidth = 34
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        let f = bg.insetBy(dx: 92, dy: 92), arm: CGFloat = 120
        for (x, y, dx, dy) in [(f.minX, f.minY, 1.0, 1.0), (f.maxX, f.minY, -1.0, 1.0),
                               (f.minX, f.maxY, 1.0, -1.0), (f.maxX, f.maxY, -1.0, -1.0)] {
            corners.move(to: CGPoint(x: x + dx * arm, y: y))
            corners.line(to: CGPoint(x: x, y: y))
            corners.line(to: CGPoint(x: x, y: y + dy * arm))
        }
        NSColor.white.withAlphaComponent(0.92).setStroke()
        corners.stroke()

        // Cat head.
        let headRect = CGRect(x: 262, y: 236, width: 500, height: 500)
        NSGraphicsContext.saveGraphicsState()
        let soft = NSShadow()
        soft.shadowColor = NSColor(srgbRed: 0.55, green: 0.2, blue: 0.05, alpha: 0.35)
        soft.shadowBlurRadius = 18
        soft.shadowOffset = NSSize(width: 0, height: -8)
        soft.set()
        NSColor(srgbRed: 1.0, green: 0.98, blue: 0.95, alpha: 1).setFill()
        fillHead(in: headRect)
        NSGraphicsContext.restoreGraphicsState()

        func hp(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: headRect.minX + x * headRect.width, y: headRect.minY + y * headRect.height)
        }
        // Inner ears.
        NSColor(srgbRed: 1.0, green: 0.70, blue: 0.74, alpha: 1).setFill()
        for (a, b, c) in [(hp(0.18, 0.62), hp(0.22, 0.88), hp(0.38, 0.70)),
                          (hp(0.82, 0.62), hp(0.78, 0.88), hp(0.62, 0.70))] {
            let ear = NSBezierPath()
            ear.move(to: a); ear.line(to: b); ear.line(to: c); ear.close()
            ear.fill()
        }
        // Eyes.
        let ink = NSColor(srgbRed: 0.22, green: 0.16, blue: 0.14, alpha: 1)
        for ex in [0.33, 0.67] {
            ink.setFill()
            let c = hp(ex, 0.42)
            NSBezierPath(ovalIn: CGRect(x: c.x - 30, y: c.y - 38, width: 60, height: 76)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - 4, y: c.y + 8, width: 20, height: 20)).fill()
        }
        // Nose + mouth.
        let n = hp(0.5, 0.30)
        let nose = NSBezierPath()
        nose.move(to: CGPoint(x: n.x - 20, y: n.y + 10))
        nose.line(to: CGPoint(x: n.x + 20, y: n.y + 10))
        nose.line(to: CGPoint(x: n.x, y: n.y - 12))
        nose.close()
        NSColor(srgbRed: 1.0, green: 0.48, blue: 0.55, alpha: 1).setFill()
        nose.fill()
        let mouth = NSBezierPath()
        mouth.lineWidth = 9
        mouth.lineCapStyle = .round
        mouth.move(to: CGPoint(x: n.x, y: n.y - 12))
        mouth.curve(to: CGPoint(x: n.x - 40, y: n.y - 30), controlPoint1: CGPoint(x: n.x, y: n.y - 36),
                    controlPoint2: CGPoint(x: n.x - 26, y: n.y - 40))
        mouth.move(to: CGPoint(x: n.x, y: n.y - 12))
        mouth.curve(to: CGPoint(x: n.x + 40, y: n.y - 30), controlPoint1: CGPoint(x: n.x, y: n.y - 36),
                    controlPoint2: CGPoint(x: n.x + 26, y: n.y - 40))
        ink.setStroke()
        mouth.stroke()
        // Whiskers.
        let whiskers = NSBezierPath()
        whiskers.lineWidth = 7
        whiskers.lineCapStyle = .round
        for side in [-1.0, 1.0] {
            for (dy, slope) in [(0.0, 10.0), (-26.0, -8.0)] {
                let start = CGPoint(x: n.x + side * 70, y: n.y + dy)
                whiskers.move(to: start)
                whiskers.line(to: CGPoint(x: start.x + side * 120, y: start.y + slope))
            }
        }
        ink.withAlphaComponent(0.55).setStroke()
        whiskers.stroke()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Writes an .iconset folder (all macOS sizes) for `iconutil -c icns`.
    static func writeIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                let data = appIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
                try data.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
