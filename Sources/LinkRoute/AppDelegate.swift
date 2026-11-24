import AppKit
import ServiceManagement
import LinkRouteCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let router = Router()
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        router.onChange = { [weak self] in self?.refreshIcon() }
        refreshIcon()
        // Without any profile list (blocked read, empty cache) routing can't work: open the
        // rules window, which asks for Chrome's Local State file.
        if router.profiles().isEmpty && router.profileSource == .none { openSettings() }
    }

    /// Links arrive here when LinkRoute is the default browser (also on cold launch).
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(router.handle)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        button.image = GlyphIcon.statusImage(router.config.icon)
        button.appearsDisabled = router.paused
        button.toolTip = router.paused ? "LinkRoute (paused)" : "LinkRoute"
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        router.reload()
        menu.removeAllItems()
        let enabledRules = router.config.rules.filter(\.enabled).count
        menu.addItem(disabled("LinkRoute · \(enabledRules) rule\(enabledRules == 1 ? "" : "s") active"))
        if let e = router.loadError {
            let warn = disabled("⚠︎ Config error, using last good rules")
            warn.toolTip = e
            menu.addItem(warn)
        }
        if !isDefaultBrowser { menu.addItem(item("Make Default Browser", #selector(makeDefault))) }
        menu.addItem(.separator())

        menu.addItem(disabled("Recent"))
        if router.recent.isEmpty { menu.addItem(disabled("  nothing yet")) }
        let profiles = router.profiles()
        for (i, r) in router.recent.enumerated() {
            let host = r.url.host(percentEncoded: false) ?? r.url.absoluteString
            let entry = NSMenuItem(title: "\(host)  →  \(router.profileName(r.profile))", action: nil, keyEquivalent: "")
            entry.toolTip = r.url.absoluteString
            let sub = NSMenu()
            for p in profiles {
                let open = item("Open in \(p.name)", #selector(reopen(_:)))
                open.representedObject = [i, p.directory] as [Any]
                sub.addItem(open)
            }
            sub.addItem(.separator())
            for p in profiles {
                let always = item("Always open \(host) in \(p.name)", #selector(alwaysOpen(_:)))
                always.representedObject = [i, p.directory] as [Any]
                sub.addItem(always)
            }
            entry.submenu = sub
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        let pause = item("Pause Routing", #selector(togglePause))
        pause.state = router.paused ? .on : .off
        menu.addItem(pause)
        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Rules…", #selector(openSettings), key: ","))
        menu.addItem(item("Reveal Config File", #selector(revealConfig)))
        menu.addItem(.separator())
        menu.addItem(item("Quit LinkRoute", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target ?? self
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    // MARK: actions

    private func recentAndProfile(_ sender: NSMenuItem) -> (Router.Recent, String)? {
        guard let pair = sender.representedObject as? [Any], let i = pair.first as? Int,
              let dir = pair.last as? String, i < router.recent.count else { return nil }
        return (router.recent[i], dir)
    }

    @objc private func reopen(_ sender: NSMenuItem) {
        guard let (r, dir) = recentAndProfile(sender) else { return }
        router.open(r.url, profile: dir, via: .manual)
    }

    @objc private func alwaysOpen(_ sender: NSMenuItem) {
        guard let (r, dir) = recentAndProfile(sender) else { return }
        router.remember(r.url, profile: dir)
        router.open(r.url, profile: dir, via: .manual)
    }

    @objc private func togglePause() { router.paused.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Could not change Open at Login", error.localizedDescription)
        }
    }

    @objc func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(router: router) { [weak self] in self?.makeDefault() }
        }
        settings?.present()
    }

    @objc private func revealConfig() {
        let url = router.store.url
        if !FileManager.default.fileExists(atPath: url.path) { try? router.save(router.config) }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: default browser

    private var isDefaultBrowser: Bool {
        guard let probe = URL(string: "https://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return app.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// macOS asks the user to confirm the change.
    @objc func makeDefault() {
        let me = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { error in
            if let error {
                Task { @MainActor in self.alert("Could not set the default browser", error.localizedDescription) }
            }
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate()
        a.runModal()
    }
}
