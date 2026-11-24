import AppKit
import SwiftUI
import LinkRouteCore

/// Floating panel that asks which profile to open a link in. Number keys pick, Esc cancels.
@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    private unowned let router: Router
    private var queue: [URL] = []
    private var panel: NSPanel?

    init(router: Router) { self.router = router }

    func enqueue(_ url: URL) {
        queue.append(url)
        if panel == nil { showNext() }
    }

    private func showNext() {
        guard let url = queue.first else { return }
        let profiles = router.profiles()
        let state = PickerState(remember: router.config.fallback.rememberByDefault)
        let view = PickerView(url: url, profiles: profiles, state: state,
                              pending: queue.count - 1,
                              onPick: { [weak self] p, remember in self?.finish(url, p, remember) },
                              onCancel: { [weak self] in self?.finish(url, nil, false) })

        let panel = KeyPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: view)
        panel.delegate = self
        panel.setContentSize(panel.contentViewController!.view.fittingSize)
        place(panel)
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
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
        guard queue.first == url else { return }
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
        if let url = queue.first { finish(url, nil, false) }
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
    let profiles: [ChromeProfile]
    @ObservedObject var state: PickerState
    let pending: Int
    let onPick: (ChromeProfile, Bool) -> Void
    let onCancel: () -> Void

    private var host: String { url.host(percentEncoded: false) ?? url.absoluteString }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(host).font(.headline)
                Text(url.absoluteString)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(url.absoluteString)
            }
            VStack(spacing: 2) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { i, p in
                    Button { onPick(p, state.remember) } label: { ProfileRow(index: i + 1, profile: p) }
                        .buttonStyle(RowStyle(hover: state.hovered == p.directory))
                        .onHover { inside in
                            if inside { state.hovered = p.directory } else if state.hovered == p.directory { state.hovered = nil }
                        }
                        .modifier(DigitShortcut(index: i + 1))
                }
            }
            Divider()
            HStack {
                Toggle("Always open \(host) this way", isOn: $state.remember)
                    .toggleStyle(.checkbox).font(.callout)
                Spacer()
                if pending > 0 { Text("+\(pending) waiting").font(.caption).foregroundStyle(.secondary) }
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

private struct ProfileRow: View {
    let index: Int
    let profile: ChromeProfile
    var body: some View {
        HStack(spacing: 10) {
            Text(index <= 9 ? "\(index)" : " ")
                .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(profile.name)
                if let e = profile.email { Text(e).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

private struct RowStyle: ButtonStyle {
    let hover: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(configuration.isPressed ? 0.35 : hover ? 0.18 : 0)))
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
