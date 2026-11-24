import AppKit
import LinkRouteCore

/// Executes routing decisions: loads the config, opens links, keeps recent history.
@MainActor
final class Router {
    struct Recent {
        enum Via { case rule, fallback, picked, paused, manual }
        let url: URL
        let profile: String?
        let via: Via
        let date = Date()
    }

    let store = ConfigStore.standard
    private(set) var config = Config()
    private(set) var loadError: String?
    private(set) var recent: [Recent] = []
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    lazy var picker = PickerController(router: self)

    var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused"); onChange?() }
    }

    private(set) var lastProfile: String? {
        get { defaults.string(forKey: "lastProfile") }
        set { defaults.set(newValue, forKey: "lastProfile") }
    }

    init() { reload() }

    /// Re-read the config file. A broken file keeps the last good config and records the error.
    func reload() {
        do {
            config = try store.load()
            loadError = nil
        } catch {
            loadError = "\(store.url.path): \(error.localizedDescription)"
            NSLog("linkroute: config error: \(error)")
        }
        onChange?()
    }

    func save(_ new: Config) throws {
        try store.save(new)
        config = new
        loadError = nil
        onChange?()
    }

    private let profileReader = ProfileReader(cache: .standard)
    private(set) var profileSource: ProfileSource = .none

    /// Chrome's profiles: live from Local State, or the cached list when macOS blocks the read.
    func profiles() -> [ChromeProfile] {
        let result = profileReader.read(localState: try? Data(contentsOf: ChromeProfiles.localStateURL))
        profileSource = result.source
        return result.profiles
    }

    func profileName(_ dir: String?) -> String {
        guard let dir else { return config.browser }
        return profiles().first { $0.directory == dir }?.name ?? dir
    }

    // MARK: routing

    func handle(_ url: URL, source: LinkSource? = nil) {
        reload()
        let force = Self.isHeld(config.pickerModifier)
        switch decide(url: url, config: config, lastProfile: lastProfile, paused: paused, forcePicker: force) {
        case let .open(profile, rule):
            open(url, profile: profile, via: rule == nil ? .fallback : .rule)
        case let .ask(suggested):
            if profiles().isEmpty {
                open(url, profile: nil, via: .fallback)
            } else {
                picker.enqueue(url, source: source, suggested: suggested)
            }
        case .openDefault:
            open(url, profile: nil, via: paused ? .paused : .fallback)
        }
    }

    /// Whether the picker key is down right now, i.e. while the link click is being delivered.
    static func isHeld(_ key: ModifierKey) -> Bool {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch key {
        case .option: return flags.contains(.option)
        case .shift: return flags.contains(.shift)
        case .control: return flags.contains(.control)
        case .command: return flags.contains(.command)
        case .none: return false
        }
    }

    func open(_ url: URL, profile: String?, via: Recent.Via) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = Launch.arguments(browser: config.browser, profile: profile, url: url)
        do { try p.run() } catch { NSLog("linkroute: open failed: \(error)") }
        if let profile { lastProfile = profile }
        recent.insert(Recent(url: url, profile: profile, via: via), at: 0)
        if recent.count > 12 { recent.removeLast(recent.count - 12) }
        onChange?()
    }

    /// Add a rule for this link's host and save.
    func remember(_ url: URL, profile: String) {
        var c = config
        c.remember(url: url, profile: profile)
        do { try save(c) } catch { NSLog("linkroute: save failed: \(error)") }
    }
}
