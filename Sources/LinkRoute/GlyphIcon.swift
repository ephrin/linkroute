import AppKit

/// Icons drawn from a single text character, so any font glyph or emoji can be the icon.
enum GlyphIcon {
    /// First character of `s`, or the default arrow.
    static func glyph(_ s: String) -> String {
        s.first.map(String.init) ?? "⇢"
    }

    /// Template image for the menu bar: macOS tints it for light, dark and highlighted states.
    static func statusImage(_ s: String) -> NSImage {
        let text = NSAttributedString(string: glyph(s), attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        let size = text.size()
        let box = NSSize(width: max(18, ceil(size.width) + 2), height: 18)
        let image = NSImage(size: box, flipped: false) { rect in
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Square app icon: white glyph on a rounded gradient tile, as PNG data.
    static func appIconPNG(glyph s: String, pixels: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw NSError(domain: "linkroute", code: 1, userInfo: [NSLocalizedDescriptionKey: "bitmap"])
        }
        let px = CGFloat(pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        // macOS icon grid: the tile fills about 80% of the canvas.
        let inset = px * 0.1
        let tile = NSRect(x: inset, y: inset, width: px - 2 * inset, height: px - 2 * inset)
        let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
        NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.42, blue: 0.98, alpha: 1),
                   ending: NSColor(srgbRed: 0.20, green: 0.16, blue: 0.62, alpha: 1))?.draw(in: path, angle: -90)

        let text = NSAttributedString(string: glyph(s), attributes: [
            .font: NSFont.systemFont(ofSize: tile.width * 0.72, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2))

        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "linkroute", code: 2, userInfo: [NSLocalizedDescriptionKey: "png"])
        }
        return png
    }

    /// Write a `.iconset` folder for `iconutil -c icns`.
    static func exportIconset(glyph: String, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            try appIconPNG(glyph: glyph, pixels: base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
            try appIconPNG(glyph: glyph, pixels: base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
    }
}
