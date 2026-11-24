// LinkRoute: menu bar link router. Set it as the default browser; it opens each link in the
// Chrome profile its rules choose. See README.md.

import AppKit

let args = CommandLine.arguments

// Build helper: `LinkRoute --export-iconset <dir.iconset> [glyph]` renders the app icon.
if let i = args.firstIndex(of: "--export-iconset"), i + 1 < args.count {
    let glyph = i + 2 < args.count ? args[i + 2] : "⇢"
    do {
        try GlyphIcon.exportIconset(glyph: glyph, to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("export-iconset: \(error)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
