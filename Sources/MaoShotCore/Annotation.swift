import AppKit

public enum Tool: String, CaseIterable, Sendable {
    case move, pen, line, arrow, rect, highlighter, marker, text
}

/// A single markup element. Coordinates are in screen-view points (non-flipped), independent of the selection,
/// so moving the selection keeps annotations pinned to the screen content.
public struct Annotation {
    public enum Shape {
        case pen([CGPoint])
        case highlighter([CGPoint])
        /// Straight text highlighter: a translucent bar.
        case marker(CGRect)
        case line(CGPoint, CGPoint)
        case arrow(CGPoint, CGPoint)
        case rect(CGRect)
        /// text, bottom-left origin, font size
        case text(String, CGPoint, CGFloat)
    }

    public var shape: Shape
    public var color: NSColor
    public var lineWidth: CGFloat

    public init(shape: Shape, color: NSColor, lineWidth: CGFloat = 3) {
        self.shape = shape
        self.color = color
        self.lineWidth = lineWidth
    }

    /// Stroke thickness levels shared by all tools, from thin to extra thick. Index 2 is the default.
    public static let sizeScales: [CGFloat] = [0.5, 0.75, 1, 1.6, 2.6]
    public static let sizeNames = ["Thin", "Light", "Normal", "Thick", "Extra Thick"]
    public static let defaultSizeIndex = 2

    /// Normal-size thickness for each tool (bar height for the marker).
    public static func baseWidth(_ tool: Tool) -> CGFloat {
        switch tool {
        case .highlighter: return 18
        case .marker: return 20
        default: return 3
        }
    }

    public var isText: Bool { if case .text = shape { return true } else { return false } }

    /// This mark at another thickness level. Text is left alone.
    public func withSize(index: Int) -> Annotation {
        let k = Self.sizeScales[min(max(index, 0), Self.sizeScales.count - 1)]
        var c = self
        switch shape {
        case .marker(let r):
            let h = Self.baseWidth(.marker) * k
            c.shape = .marker(CGRect(x: r.minX, y: r.midY - h / 2, width: r.width, height: h))
            c.lineWidth = h
        case .highlighter: c.lineWidth = Self.baseWidth(.highlighter) * k
        case .text: break
        default: c.lineWidth = Self.baseWidth(.pen) * k
        }
        return c
    }

    public static func font(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    public static func textAttributes(color: NSColor, size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: font(size: size), .foregroundColor: color]
    }

    // MARK: - Editing

    /// Geometric bounds (without stroke width). Used for selection handles and resizing.
    public var bounds: CGRect {
        switch shape {
        case .pen(let pts), .highlighter(let pts):
            return Self.boundingRect(pts)
        case .line(let a, let b), .arrow(let a, let b):
            return Geometry.rect(from: a, to: b)
        case .rect(let r), .marker(let r):
            return r
        case .text(let s, let origin, let size):
            let ts = (s as NSString).size(withAttributes: Self.textAttributes(color: color, size: size))
            return CGRect(origin: origin, size: ts)
        }
    }

    /// Whether a click at `p` should pick this mark.
    public func hitTest(_ p: CGPoint, tolerance: CGFloat = 6) -> Bool {
        let reach = lineWidth / 2 + tolerance
        switch shape {
        case .pen(let pts), .highlighter(let pts):
            if pts.count == 1 { return hypot(p.x - pts[0].x, p.y - pts[0].y) <= reach }
            return zip(pts, pts.dropFirst()).contains { Geometry.distance(from: p, toSegment: $0, $1) <= reach }
        case .line(let a, let b), .arrow(let a, let b):
            return Geometry.distance(from: p, toSegment: a, b) <= reach
        case .rect(let r):
            // Only the stroked border, so clicks inside still reach marks underneath.
            return r.insetBy(dx: -reach, dy: -reach).contains(p) && !r.insetBy(dx: reach, dy: reach).contains(p)
        case .marker(let r):
            return r.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    /// Map this mark from bounds `a` onto bounds `b` (move = same size, resize = scale).
    public func transformed(from a: CGRect, to b: CGRect) -> Annotation {
        func map(_ p: CGPoint) -> CGPoint {
            let x = a.width < 0.5 ? p.x - a.minX + b.minX : b.minX + (p.x - a.minX) * b.width / a.width
            let y = a.height < 0.5 ? p.y - a.minY + b.minY : b.minY + (p.y - a.minY) * b.height / a.height
            return CGPoint(x: x, y: y)
        }
        var c = self
        switch shape {
        case .pen(let pts): c.shape = .pen(pts.map(map))
        case .highlighter(let pts): c.shape = .highlighter(pts.map(map))
        case .line(let p, let q): c.shape = .line(map(p), map(q))
        case .arrow(let p, let q): c.shape = .arrow(map(p), map(q))
        case .rect(let r): c.shape = .rect(Geometry.rect(from: map(r.origin), to: map(CGPoint(x: r.maxX, y: r.maxY))))
        case .marker(let r): c.shape = .marker(Geometry.rect(from: map(r.origin), to: map(CGPoint(x: r.maxX, y: r.maxY))))
        case .text(let s, _, let size):
            // Text scales uniformly by whichever dimension changed more.
            let kw = a.width > 0 ? b.width / a.width : 1
            let kh = a.height > 0 ? b.height / a.height : 1
            let k = abs(kh - 1) >= abs(kw - 1) ? kh : kw
            c.shape = .text(s, b.origin, min(300, max(8, size * k)))
        }
        return c
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Annotation {
        let r = bounds
        return transformed(from: r, to: r.offsetBy(dx: dx, dy: dy))
    }

    static func boundingRect(_ pts: [CGPoint]) -> CGRect {
        guard let f = pts.first else { return .zero }
        var r = CGRect(origin: f, size: .zero)
        for p in pts.dropFirst() { r = r.union(CGRect(origin: p, size: .zero)) }
        return r
    }

    /// Draws into the current NSGraphicsContext.
    public func draw() {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        switch shape {
        case .pen(let pts):
            color.setStroke()
            Self.polyline(pts, width: lineWidth).stroke()

        case .highlighter(let pts):
            NSGraphicsContext.current?.compositingOperation = .multiply
            color.withAlphaComponent(0.5).setStroke()
            let path = Self.polyline(pts, width: lineWidth)
            path.lineCapStyle = .square
            path.stroke()

        case .marker(let r):
            NSGraphicsContext.current?.compositingOperation = .multiply
            color.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()

        case .line(let a, let b):
            color.setStroke()
            Self.polyline([a, b], width: lineWidth).stroke()

        case .arrow(let a, let b):
            color.setStroke()
            color.setFill()
            let head = max(12, lineWidth * 4.5)
            let angle = atan2(b.y - a.y, b.x - a.x)
            let len = hypot(b.x - a.x, b.y - a.y)
            let shaftEnd = len > head
                ? CGPoint(x: b.x - cos(angle) * head * 0.7, y: b.y - sin(angle) * head * 0.7)
                : a
            Self.polyline([a, shaftEnd], width: lineWidth).stroke()
            let spread: CGFloat = 0.42
            let tri = NSBezierPath()
            tri.move(to: b)
            tri.line(to: CGPoint(x: b.x - cos(angle - spread) * head, y: b.y - sin(angle - spread) * head))
            tri.line(to: CGPoint(x: b.x - cos(angle + spread) * head, y: b.y - sin(angle + spread) * head))
            tri.close()
            tri.lineJoinStyle = .round
            tri.lineWidth = 1
            tri.fill()
            tri.stroke()

        case .rect(let r):
            color.setStroke()
            let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            path.lineWidth = lineWidth
            path.lineJoinStyle = .round
            path.stroke()

        case .text(let s, let origin, let size):
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            (s as NSString).draw(at: origin, withAttributes: Self.textAttributes(color: color, size: size))
        }
    }

    static func polyline(_ pts: [CGPoint], width: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 {
            path.line(to: first) // a dot
        } else {
            for p in pts.dropFirst() { path.line(to: p) }
        }
        return path
    }
}
