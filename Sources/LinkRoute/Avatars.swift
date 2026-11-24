import AppKit
import LinkRouteCore

/// Profile pictures as Chrome shows them: the account picture when the profile uses one,
/// otherwise a monogram in the profile's own colors.
@MainActor
enum Avatars {
    /// Round avatar of `size` points.
    static func image(for profile: ChromeProfile, size: CGFloat) -> NSImage {
        let source = picture(for: profile)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect)
            if let source {
                NSGraphicsContext.saveGraphicsState()
                circle.addClip()
                source.draw(in: aspectFill(source.size, into: rect))
                NSGraphicsContext.restoreGraphicsState()
            } else {
                monogram(profile, in: rect, circle: circle)
            }
            return true
        }
        return image
    }

    /// Live from Chrome's profile folder (refreshing a cached copy), or the cached copy when
    /// the read is blocked.
    private static func picture(for profile: ChromeProfile) -> NSImage? {
        guard let file = profile.picture else { return nil }
        let live = ChromeProfiles.localStateURL.deletingLastPathComponent()
            .appendingPathComponent(profile.directory).appendingPathComponent(file)
        let cached = ConfigStore.standard.url.deletingLastPathComponent()
            .appendingPathComponent("avatars").appendingPathComponent("\(profile.directory).png")
        if let data = try? Data(contentsOf: live), let image = NSImage(data: data) {
            let previous = try? Data(contentsOf: cached)
            if previous != data {
                try? FileManager.default.createDirectory(at: cached.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: cached, options: .atomic)
            }
            return image
        }
        return (try? Data(contentsOf: cached)).flatMap(NSImage.init(data:))
    }

    private static func monogram(_ p: ChromeProfile, in rect: NSRect, circle: NSBezierPath) {
        color(p.fillColor, fallback: fallbackColor(for: p.directory)).setFill()
        circle.fill()
        let text = NSAttributedString(string: p.initial, attributes: [
            .font: NSFont.systemFont(ofSize: rect.height * 0.46, weight: .semibold),
            .foregroundColor: color(p.strokeColor, fallback: .white),
        ])
        let s = text.size()
        text.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
    }

    private static func color(_ argb: UInt32?, fallback: NSColor) -> NSColor {
        guard let v = argb else { return fallback }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: CGFloat((v >> 24) & 0xFF) / 255)
    }

    private static func fallbackColor(for key: String) -> NSColor {
        let hue = CGFloat(abs(key.hashValue % 360)) / 360
        return NSColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
    }

    private static func aspectFill(_ size: NSSize, into rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
