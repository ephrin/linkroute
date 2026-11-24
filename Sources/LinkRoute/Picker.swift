import AppKit
import SwiftUI
import LinkRouteCore

/// The app that handed a link to LinkRoute, for the picker's title.
struct LinkSource {
    let name: String
    let icon: NSImage?

    /// The sender of the Apple Event being handled right now, if it is another app.
    @MainActor
    static func current() -> LinkSource? {
        let keySenderPID = AEKeyword(0x7370_6964) // 'spid'
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: keySenderPID)?.int32Value, pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid),
              let name = app.localizedName else { return nil }
        return LinkSource(name: name, icon: app.icon)
    }
}

/// Floating glass panel that asks which profile to open a link in. Number keys pick, Esc cancels.
@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    private struct Pending { let url: URL; let source: LinkSource?; let suggested: String? }

    private unowned let router: Router
    private var queue: [Pending] = []
    private var panel: NSPanel?

    init(router: Router) { self.router = router }

    func enqueue(_ url: URL, source: LinkSource?, suggested: String? = nil) {
        queue.append(Pending(url: url, source: source, suggested: suggested))
        if panel == nil { showNext() }
    }

    private func showNext() {
        guard let item = queue.first else { return }
        let url = item.url
        let profiles = router.profiles()
        let state = PickerState(remember: router.config.fallback.rememberByDefault)
        state.hovered = item.suggested
        let view = PickerView(url: url, source: item.source, suggested: item.suggested,
                              profiles: profiles.map { ($0, Avatars.image(for: $0, size: 32)) },
                              state: state, pending: queue.count - 1,
                              onPick: { [weak self] p, remember in self?.finish(url, p, remember) },
                              onCancel: { [weak self] in self?.finish(url, nil, false) })

        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Open \(url.host(percentEncoded: false) ?? "link") in which Chrome profile?"
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        panel.contentView = Self.glass(around: hosting, size: size, cornerRadius: 22)
        panel.delegate = self
        panel.setContentSize(size)
        panel.invalidateShadow()
        place(panel)
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Liquid Glass (NSGlassEffectView) on macOS 26 and later, a popover material before.
    /// AppKit clips the window to the rounded shape, so no square corners show.
    private static func glass(around content: NSView, size: NSSize, cornerRadius: CGFloat) -> NSView {
        let frame = NSRect(origin: .zero, size: size)
        content.frame = frame
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let fx = NSVisualEffectView(frame: frame)
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.maskImage = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        fx.addSubview(content)
        return fx
    }

    /// Near the mouse, kept on the mouse's screen.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x - 40, y: mouse.y - panel.frame.height + 20)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    private func finish(_ url: URL, _ profile: ChromeProfile?, _ remember: Bool) {
        guard queue.first?.url == url else { return }
        queue.removeFirst()
        let p = panel
        panel = nil
        p?.delegate = nil
        p?.close()
        if let profile {
            if remember { router.remember(url, profile: profile.directory) }
            router.open(url, profile: profile.directory, via: .picked)
        }
        showNext()
    }

    /// Clicking elsewhere cancels, like a popover.
    func windowDidResignKey(_ n: Notification) {
        if let url = queue.first?.url { finish(url, nil, false) }
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// View state lives in an ObservableObject: `@State` is a macro, and the Command Line Tools
/// ship no SwiftUI macro plugin.
final class PickerState: ObservableObject {
    @Published var remember: Bool
    @Published var hovered: String?
    init(remember: Bool) { self.remember = remember }
}

struct PickerView: View {
    let url: URL
    let source: LinkSource?
    /// Profile a rule or the fallback would have used; Return picks it.
    let suggested: String?
    let profiles: [(ChromeProfile, NSImage)]
    @ObservedObject var state: PickerState
    let pending: Int
    let onPick: (ChromeProfile, Bool) -> Void
    let onCancel: () -> Void

    private var host: String { url.host(percentEncoded: false) ?? url.absoluteString }
    private var rest: String {
        var s = url.path(percentEncoded: false)
        if let q = url.query(percentEncoded: false), !q.isEmpty { s += "?" + q }
        return s == "/" ? "" : s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 2) {
                ForEach(Array(profiles.enumerated()), id: \.element.0.id) { i, entry in
                    row(index: i + 1, profile: entry.0, avatar: entry.1)
                }
            }
            footer
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = source?.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(source.map { "Link from \($0.name) · choose a Chrome profile" } ?? "Choose a Chrome profile")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if pending > 0 {
                    Text("+\(pending) waiting").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("Open \(host) in…")
                .font(.title3.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
            if !rest.isEmpty {
                Text(rest)
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .help(url.absoluteString)
    }

    private func row(index: Int, profile p: ChromeProfile, avatar: NSImage) -> some View {
        let hovered = state.hovered == p.directory
        return Button { onPick(p, state.remember) } label: {
            HStack(spacing: 10) {
                Image(nsImage: avatar)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.body.weight(.medium))
                    if let e = p.email {
                        Text(e).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if p.directory == suggested {
                    Text("rule")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .help("The profile LinkRoute would have used. Return keeps it.")
                }
                if index <= 9 {
                    Text("\(index)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.4)))
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.10 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { state.hovered = p.directory } else if hovered { state.hovered = nil }
        }
        .modifier(DigitShortcut(index: index))
    }

    private var footer: some View {
        HStack {
            Toggle("Always open \(host) here", isOn: $state.remember)
                .toggleStyle(.checkbox).font(.callout)
            Spacer()
            // Return: the highlighted row, else the suggested profile.
            Button("") {
                let dir = state.hovered ?? suggested
                if let p = profiles.first(where: { $0.0.directory == dir })?.0 { onPick(p, state.remember) }
            }
            .keyboardShortcut(.defaultAction)
            .frame(width: 0, height: 0).opacity(0)
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DigitShortcut: ViewModifier {
    let index: Int
    func body(content: Content) -> some View {
        if index <= 9, let c = "\(index)".first {
            content.keyboardShortcut(KeyEquivalent(c), modifiers: [])
        } else {
            content
        }
    }
}
