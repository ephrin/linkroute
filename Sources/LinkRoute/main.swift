// LinkRoute: menu bar link router. Set it as the default browser; it opens each link in the
// Chrome profile its rules choose. See README.md.

import AppKit
import LinkRouteCore

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

// Diagnostic: `open -W --stdout out.txt LinkRoute.app --args --list-profiles` runs it as LinkRoute
// itself (not as the terminal), so macOS privacy rules apply as they do for the app.
if args.contains("--list-profiles") {
    let url = ChromeProfiles.localStateURL
    do {
        let data = try Data(contentsOf: url)
        let profiles = ChromeProfiles.parse(data)
        print("read \(data.count) bytes from \(url.path)")
        for p in profiles { print("\(p.directory)\t\(p.name)\t\(p.email ?? "")") }
        exit(profiles.isEmpty ? 2 : 0)
    } catch {
        print("cannot read \(url.path): \(error.localizedDescription)")
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
