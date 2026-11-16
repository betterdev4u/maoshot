import AppKit
import XCTest
@testable import MaoShotCore

final class GeometryTests: XCTestCase {
    func testRectNormalizes() {
        let r = Geometry.rect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20))
        XCTAssertEqual(r, CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    func testResizeFlipsPastOppositeEdge() {
        let orig = CGRect(x: 100, y: 100, width: 100, height: 100)
        XCTAssertEqual(Geometry.resize(orig, handle: .right, to: CGPoint(x: 250, y: 0)),
                       CGRect(x: 100, y: 100, width: 150, height: 100))
        XCTAssertEqual(Geometry.resize(orig, handle: .right, to: CGPoint(x: 50, y: 0)),
                       CGRect(x: 50, y: 100, width: 50, height: 100))
        XCTAssertEqual(Geometry.resize(orig, handle: .topLeft, to: CGPoint(x: 90, y: 260)),
                       CGRect(x: 90, y: 100, width: 110, height: 160))
    }

    func testHandleHitTest() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertEqual(Geometry.handle(at: CGPoint(x: 101, y: 49), in: r), .topRight)
        XCTAssertEqual(Geometry.handle(at: CGPoint(x: 50, y: 2), in: r), .bottom)
        XCTAssertNil(Geometry.handle(at: CGPoint(x: 50, y: 25), in: r))
    }

    func testClampKeepsSizeInsideBounds() {
        let b = CGRect(x: 0, y: 0, width: 500, height: 300)
        XCTAssertEqual(Geometry.clamp(CGRect(x: 450, y: -20, width: 100, height: 50), into: b),
                       CGRect(x: 400, y: 0, width: 100, height: 50))
    }

    func testSnap45() {
        let p = Geometry.snap45(from: .zero, to: CGPoint(x: 100, y: 8))
        XCTAssertEqual(p.x, hypot(100, 8), accuracy: 0.001)
        XCTAssertEqual(p.y, 0, accuracy: 0.001)
    }

    func testToolbarPlacement() {
        let b = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let t = CGSize(width: 300, height: 40)
        // Room below → below, right-aligned.
        XCTAssertEqual(Geometry.toolbarOrigin(selection: CGRect(x: 400, y: 300, width: 400, height: 200), toolbarSize: t, bounds: b),
                       CGPoint(x: 500, y: 252))
        // Touches bottom → above.
        XCTAssertEqual(Geometry.toolbarOrigin(selection: CGRect(x: 400, y: 10, width: 400, height: 200), toolbarSize: t, bounds: b).y, 218)
        // Full screen → inside.
        XCTAssertEqual(Geometry.toolbarOrigin(selection: b, toolbarSize: t, bounds: b).y, 8)
    }
}

final class HistoryStoreTests: XCTestCase {
    func testKeepsOnlyNewestTen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("maoshot-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, limit: 10)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var urls: [URL] = []
        for i in 0..<13 {
            urls.append(try store.add(pngData: Data([UInt8(i)]), date: base.addingTimeInterval(Double(i))))
        }
        let items = store.items()
        XCTAssertEqual(items.count, 10)
        let names = items.map(\.lastPathComponent)
        XCTAssertEqual(names.first, urls.last?.lastPathComponent)
        XCTAssertFalse(names.contains(urls[0].lastPathComponent))
        XCTAssertEqual(store.date(of: items.first!), base.addingTimeInterval(12))
    }

    func testSameTimestampDoesNotOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("maoshot-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        let d = Date()
        try store.add(pngData: Data([1]), date: d)
        try store.add(pngData: Data([2]), date: d)
        XCTAssertEqual(store.items().count, 2)
    }
}

final class RendererTests: XCTestCase {
    private func solidImage(width: Int, height: Int, color: CGColor) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func pixel(_ img: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let rep = NSBitmapImageRep(cgImage: img)
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return (UInt8(c.redComponent * 255), UInt8(c.greenComponent * 255), UInt8(c.blueComponent * 255))
    }

    func testCropsAtRetinaResolutionAndBurnsInAnnotations() throws {
        // 200x100 pt screen at 2x = 400x200 px, white.
        let screen = solidImage(width: 400, height: 200, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let sel = CGRect(x: 50, y: 20, width: 100, height: 60)
        let red = Annotation(shape: .rect(CGRect(x: 60, y: 30, width: 50, height: 30)), color: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), lineWidth: 4)
        let out = try XCTUnwrap(Renderer.render(screenImage: screen, screenSize: CGSize(width: 200, height: 100),
                                                selection: sel, annotations: [red]))
        XCTAssertEqual(out.width, 200)
        XCTAssertEqual(out.height, 120)
        // Rect's left edge is at x = (60-50)*2 = 20px; colorAt uses top-left origin.
        // Rect spans y 30..60 pt → in output (sel minY 20) 10..40 pt → top-origin px rows (60-40)*2=40 .. (60-10)*2=100.
        let (r, g, b) = pixel(out, x: 20, y: 70)
        XCTAssertGreaterThan(r, 200); XCTAssertLessThan(g, 60); XCTAssertLessThan(b, 60)
        // Untouched area stays white.
        let (r2, g2, b2) = pixel(out, x: 150, y: 10)
        XCTAssertTrue([r2, g2, b2].allSatisfy { $0 >= 252 })
    }

    func testPNGCarriesRetinaPointSize() throws {
        let img = solidImage(width: 40, height: 20, color: CGColor(gray: 0.5, alpha: 1))
        let data = try XCTUnwrap(Renderer.pngData(img, pointSize: CGSize(width: 20, height: 10)))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 40)
        XCTAssertEqual(rep.size.width, 20, accuracy: 0.5)
    }
}

final class AnnotationEditingTests: XCTestCase {
    func testMoveAndResizeArrow() {
        let a = Annotation(shape: .arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)), color: .red)
        XCTAssertEqual(a.bounds, CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(a.offsetBy(dx: 10, dy: 5).bounds, CGRect(x: 10, y: 5, width: 100, height: 50))
        let scaled = a.transformed(from: a.bounds, to: CGRect(x: 0, y: 0, width: 200, height: 100))
        guard case .arrow(_, let q) = scaled.shape else { return XCTFail() }
        XCTAssertEqual(q, CGPoint(x: 200, y: 100))
    }

    func testHorizontalLineResizeDoesNotDivideByZero() {
        let a = Annotation(shape: .line(CGPoint(x: 0, y: 10), CGPoint(x: 100, y: 10)), color: .red)
        let b = a.transformed(from: a.bounds, to: CGRect(x: 0, y: 30, width: 50, height: 0))
        XCTAssertEqual(b.bounds, CGRect(x: 0, y: 30, width: 50, height: 0))
    }

    func testHitTest() {
        let line = Annotation(shape: .line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)), color: .red, lineWidth: 3)
        XCTAssertTrue(line.hitTest(CGPoint(x: 50, y: 5)))
        XCTAssertFalse(line.hitTest(CGPoint(x: 50, y: 20)))
        let rect = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)), color: .red)
        XCTAssertTrue(rect.hitTest(CGPoint(x: 1, y: 50)))   // on border
        XCTAssertFalse(rect.hitTest(CGPoint(x: 50, y: 50))) // inside is click-through
    }

    func testTextScalesFont() {
        let t = Annotation(shape: .text("Hi", .zero, 20), color: .red)
        let b = t.bounds
        let big = t.transformed(from: b, to: CGRect(x: 5, y: 5, width: b.width * 2, height: b.height * 2))
        guard case .text(_, let o, let size) = big.shape else { return XCTFail() }
        XCTAssertEqual(size, 40, accuracy: 0.01)
        XCTAssertEqual(o, CGPoint(x: 5, y: 5))
    }

    func testMarkerThicknessKeepsCentreLine() {
        let m = Annotation(shape: .marker(CGRect(x: 10, y: 90, width: 100, height: 20)), color: .yellow, lineWidth: 20)
        let thick = m.withSize(index: 4)
        XCTAssertEqual(thick.bounds.midY, 100, accuracy: 0.001)
        XCTAssertEqual(thick.bounds.width, 100, accuracy: 0.001)
        XCTAssertGreaterThan(thick.bounds.height, 20)
        XCTAssertLessThan(m.withSize(index: 0).bounds.height, 20)
        XCTAssertTrue(m.hitTest(CGPoint(x: 50, y: 100)))
    }

    func testSizeLevelsScaleStrokeFromNormal() {
        let line = Annotation(shape: .line(.zero, CGPoint(x: 10, y: 0)), color: .red)
        XCTAssertEqual(line.withSize(index: Annotation.defaultSizeIndex).lineWidth, 3)
        XCTAssertLessThan(line.withSize(index: 0).lineWidth, 3)
        XCTAssertGreaterThan(line.withSize(index: 4).lineWidth, 3)
    }
}
