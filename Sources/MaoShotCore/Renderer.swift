import AppKit

public enum Renderer {
    /// Crop `screenImage` to `selection` (points, non-flipped, in a view of `screenSize`) and burn in annotations.
    /// Output is at full pixel resolution of the captured screen.
    public static func render(screenImage: CGImage, screenSize: CGSize, selection: CGRect, annotations: [Annotation]) -> CGImage? {
        guard screenSize.width > 0 else { return nil }
        let scale = CGFloat(screenImage.width) / screenSize.width
        let sel = Geometry.pixelAligned(selection, scale: scale)
        let w = Int((sel.width * scale).rounded())
        let h = Int((sel.height * scale).rounded())
        guard w > 0, h > 0,
              let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.interpolationQuality = .none
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -sel.minX, y: -sel.minY)
        ctx.draw(screenImage, in: CGRect(origin: .zero, size: screenSize))

        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for a in annotations { a.draw() }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// PNG data. When `pointSize` is given the PNG carries matching DPI (e.g. 144 for Retina), like macOS screenshots.
    public static func pngData(_ image: CGImage, pointSize: CGSize? = nil) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        if let s = pointSize, s.width > 0, s.height > 0 { rep.size = s }
        return rep.representation(using: .png, properties: [:])
    }
}
