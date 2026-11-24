import AppKit
import SwiftUI
import LinkRouteCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: Config
    @Published private(set) var saved: Config
    @Published var profiles: [ChromeProfile]
    @Published var testURL = ""
    @Published var error: String?
    let router: Router

    init(router: Router) {
        self.router = router
        router.reload()
        config = router.config
        saved = router.config
        profiles = router.profiles()
        error = router.loadError
    }

    var dirty: Bool { config != saved }

    func save() {
        do {
            try router.save(config)
            saved = config
            error = nil
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }

    func revert() {
        router.reload()
        config = router.config
        saved = router.config
        profiles = router.profiles()
        error = router.loadError
    }

    func addRule() {
        let profile = config.rules.last?.profile ?? profiles.first?.directory ?? "Default"
        config.rules.append(Rule(pattern: "", profile: profile))
    }

    func label(for dir: String?) -> String {
        guard let dir else { return "—" }
        return profiles.first { $0.directory == dir }?.name ?? "\(dir) (not found)"
    }

    /// Result line for the link tester, computed against the unsaved config.
    var testResult: String? {
        var s = testURL.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), url.host() != nil else { return "Not a link" }
        switch decide(url: url, config: config, lastProfile: nil, paused: false) {
        case let .open(profile, rule?):
            let n = (config.rules.firstIndex { $0.id == rule } ?? 0) + 1
            return "Rule \(n) → \(label(for: profile))"
        case let .open(profile, nil):
            return "No rule → fallback → \(label(for: profile))"
        case .ask:
            return "No rule → ask"
        case .openDefault:
            return "No rule → \(config.browser), no profile"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var m: SettingsModel
    var onMakeDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if m.profiles.isEmpty { profileWarning }
            rules
            HStack(alignment: .top, spacing: 14) {
                fallback
                VStack(alignment: .leading, spacing: 14) {
                    tester
                    appearance
                }
            }
            footer
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 560)
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Rules").font(.headline)
                Text("top to bottom, first match wins · drag to reorder")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { m.addRule() } label: { Label("Add rule", systemImage: "plus") }
            }
            List {
                ForEach($m.config.rules) { $rule in
                    RuleRow(rule: $rule, profiles: m.profiles) {
                        m.config.rules.removeAll { $0.id == rule.id }
                    }
                }
                .onMove { m.config.rules.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if m.config.rules.isEmpty {
                    Text("No rules yet. Add one, or tick “Always open … this way” in the picker.")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Pattern: host[/path]. In the host, * matches anything and *.example.com includes example.com. In the path, * stays within one segment, ** spans segments, and /acme/** also matches /acme.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fallback: some View {
        GroupBox("Links no rule matches") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $m.config.fallback.mode) {
                    Text("Ask with the profile picker").tag(FallbackMode.ask)
                    Text("Open in a fixed profile").tag(FallbackMode.profile)
                    Text("Open in the profile used last").tag(FallbackMode.lastUsed)
                    Text("Let \(m.config.browser) decide").tag(FallbackMode.browser)
                }
                .pickerStyle(.radioGroup).labelsHidden()

                if m.config.fallback.mode == .profile {
                    ProfilePicker(selection: Binding(
                        get: { m.config.fallback.profile ?? m.profiles.first?.directory ?? "Default" },
                        set: { m.config.fallback.profile = $0 }), profiles: m.profiles)
                }
                Toggle("Picker: “Always open this way” ticked by default", isOn: $m.config.fallback.rememberByDefault)
                    .toggleStyle(.checkbox)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var tester: some View {
        GroupBox("Test a link") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("https://github.com/acme/repo", text: $m.testURL)
                    .textFieldStyle(.roundedBorder)
                Text(m.testResult ?? "Uses the rules above, saved or not.")
                    .font(.callout)
                    .foregroundStyle(m.testResult == nil ? .secondary : .primary)
            }
            .padding(6)
        }
    }

    private var appearance: some View {
        GroupBox("Menu bar icon") {
            HStack {
                TextField("⇢", text: $m.config.icon).textFieldStyle(.roundedBorder).frame(width: 60)
                Image(nsImage: GlyphIcon.statusImage(m.config.icon))
                Text("any character: arrows, symbols, Nerd Font glyphs, emoji")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(6)
        }
    }

    private var profileWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
            Text("Can't read Chrome's profile list. Allow LinkRoute under Privacy & Security → Files & Folders (data from other apps), then reload. Until then, type profile directories such as Profile 1.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Settings") {
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                    NSWorkspace.shared.open(u)
                }
            }
            Button("Reload") { m.profiles = m.router.profiles() }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private var footer: some View {
        HStack {
            if let e = m.error {
                Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).lineLimit(2)
            } else {
                Text(m.router.store.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button("Make default browser", action: onMakeDefault)
            Button("Revert") { m.revert() }.disabled(!m.dirty)
            Button("Save") { m.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!m.dirty)
        }
    }
}

private struct RuleRow: View {
    @Binding var rule: Rule
    let profiles: [ChromeProfile]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox)
                .help("Enabled")
            TextField("github.com/acme/**", text: $rule.pattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(.red, lineWidth: Pattern(rule.pattern).isValid ? 0 : 1))
                .opacity(rule.enabled ? 1 : 0.5)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            ProfilePicker(selection: $rule.profile, profiles: profiles).frame(width: 260)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete rule")
        }
        .padding(.vertical, 2)
    }
}

private struct ProfilePicker: View {
    @Binding var selection: String
    let profiles: [ChromeProfile]

    var body: some View {
        if profiles.isEmpty {
            // Chrome's profile list is unreadable (privacy block or no Chrome): type the directory.
            TextField("Profile 1", text: $selection)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .help("Chrome profile directory, e.g. Default or Profile 1")
        } else {
            menu
        }
    }

    private var menu: some View {
        Picker("", selection: $selection) {
            ForEach(profiles) { Text($0.label).tag($0.directory) }
            if !profiles.contains(where: { $0.directory == selection }) {
                Text("\(selection) (not found)").tag(selection)
            }
        }
        .labelsHidden()
    }
}

/// Hosts the settings window and asks before closing with unsaved changes.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel

    init(router: Router, onMakeDefault: @escaping () -> Void) {
        model = SettingsModel(router: router)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "LinkRoute"
        window.contentViewController = NSHostingController(rootView: SettingsView(m: model, onMakeDefault: onMakeDefault))
        window.setContentSize(NSSize(width: 820, height: 620))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        if !(window?.isVisible ?? false) { model.revert() }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to your rules?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: model.save(); return !model.dirty
        case .alertSecondButtonReturn: model.revert(); return true
        default: return false
        }
    }
}
