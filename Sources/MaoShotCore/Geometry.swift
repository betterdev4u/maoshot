import CoreGraphics
import Foundation

/// Resize handles of a selection rectangle. Coordinates are non-flipped (y grows upward), so "top" is maxY.
public enum Handle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    public var isHorizontalEdge: Bool { self == .left || self == .right }
    public var isVerticalEdge: Bool { self == .top || self == .bottom }
}

public enum Geometry {
    /// Normalized rect spanning two points.
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public static func handlePoints(for r: CGRect) -> [(Handle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.top, CGPoint(x: r.midX, y: r.maxY)),
            (.topRight, CGPoint(x: r.maxX, y: r.maxY)),
            (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.minY)),
            (.bottom, CGPoint(x: r.midX, y: r.minY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.minY)),
            (.left, CGPoint(x: r.minX, y: r.midY)),
        ]
    }

    public static func handle(at p: CGPoint, in r: CGRect, tolerance: CGFloat = 7) -> Handle? {
        for (h, hp) in handlePoints(for: r) where abs(hp.x - p.x) <= tolerance && abs(hp.y - p.y) <= tolerance {
            return h
        }
        return nil
    }

    /// Resize `original` by dragging `handle` to `p`. Dragging past the opposite edge flips naturally.
    public static func resize(_ original: CGRect, handle: Handle, to p: CGPoint) -> CGRect {
        var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
        switch handle {
        case .topLeft: minX = p.x; maxY = p.y
        case .top: maxY = p.y
        case .topRight: maxX = p.x; maxY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; minY = p.y
        case .bottom: minY = p.y
        case .bottomLeft: minX = p.x; minY = p.y
        case .left: minX = p.x
        }
        return rect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
    }

    /// Shift `r` (keeping its size) so it lies inside `bounds`.
    public static func clamp(_ r: CGRect, into bounds: CGRect) -> CGRect {
        var o = r.origin
        o.x = min(max(o.x, bounds.minX), bounds.maxX - r.width)
        o.y = min(max(o.y, bounds.minY), bounds.maxY - r.height)
        return CGRect(origin: o, size: r.size)
    }

    public static func clamp(_ p: CGPoint, into bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    public static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Snap the segment a→b to the nearest 45° angle.
    public static func snap45(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        let len = hypot(dx, dy)
        return CGPoint(x: a.x + cos(angle) * len, y: a.y + sin(angle) * len)
    }

    /// Snap a rect (in points) to the pixel grid for the given backing scale.
    public static func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        let x0 = (r.minX * scale).rounded() / scale
        let y0 = (r.minY * scale).rounded() / scale
        let x1 = (r.maxX * scale).rounded() / scale
        let y1 = (r.maxY * scale).rounded() / scale
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Where to put the toolbar: below the selection (right-aligned), else above, else inside the bottom edge.
    public static func toolbarOrigin(selection s: CGRect, toolbarSize t: CGSize, bounds b: CGRect, gap: CGFloat = 8) -> CGPoint {
        var x = s.maxX - t.width
        x = min(max(x, b.minX + gap), b.maxX - t.width - gap)
        var y = s.minY - gap - t.height
        if y < b.minY + gap {
            y = s.maxY + gap
            if y + t.height > b.maxY - gap {
                y = s.minY + gap
            }
        }
        return CGPoint(x: x, y: y)
    }
}
