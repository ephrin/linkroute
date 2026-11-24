import Foundation

public enum Decision: Equatable, Sendable {
    /// Open in this profile; `rule` is the matching rule, nil when it came from the fallback.
    case open(profile: String, rule: UUID?)
    /// Show the profile picker.
    case ask
    /// Hand the link to the browser without choosing a profile.
    case openDefault
}

/// Decide where a link goes. Pure: no I/O.
public func decide(url: URL, config: Config, lastProfile: String?, paused: Bool) -> Decision {
    if paused { return .openDefault }
    if let rule = Rule.firstMatch(in: config.rules, for: url) {
        return .open(profile: rule.profile, rule: rule.id)
    }
    switch config.fallback.mode {
    case .ask:
        return .ask
    case .profile:
        guard let p = config.fallback.profile, !p.isEmpty else { return .openDefault }
        return .open(profile: p, rule: nil)
    case .lastUsed:
        guard let p = lastProfile, !p.isEmpty else { return .ask }
        return .open(profile: p, rule: nil)
    case .browser:
        return .openDefault
    }
}

/// Arguments for `/usr/bin/open`.
///
/// With a profile, `-n` starts a new browser process carrying `--profile-directory`;
/// Chrome hands the URL to the already running instance, which opens it in that profile.
public enum Launch {
    public static func arguments(browser: String, profile: String?, url: URL) -> [String] {
        guard let profile else { return ["-a", browser, url.absoluteString] }
        return ["-na", browser, "--args", "--profile-directory=\(profile)", url.absoluteString]
    }
}

/// A Chrome profile as listed in Chrome's `Local State` file.
public struct ChromeProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var directory: String
    public var name: String
    public var email: String?
    public var id: String { directory }

    private enum CodingKeys: String, CodingKey { case directory, name, email }

    public init(directory: String, name: String, email: String?) {
        self.directory = directory; self.name = name; self.email = email
    }

    public var label: String {
        if let email { return "\(name) — \(email)" }
        return name
    }
}

public enum ChromeProfiles {
    public static var localStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
    }

    public static func load(from url: URL = localStateURL) -> [ChromeProfile] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(data)
    }

    /// Profiles in Chrome's own order (`profiles_order`), then any others by directory name.
    public static func parse(_ data: Data) -> [ChromeProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        let order = (profile["profiles_order"] as? [String]) ?? []
        let rest = cache.keys.filter { !order.contains($0) }.sorted { a, b in
            if a == "Default" { return true }
            if b == "Default" { return false }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        return (order.filter { cache[$0] != nil } + rest).map { dir in
            let info = cache[dir] as? [String: Any] ?? [:]
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? dir
            let email = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return ChromeProfile(directory: dir, name: name, email: email)
        }
    }
}

/// Last profile list read from Chrome, kept so a later blocked read still shows names.
public struct ProfileCache: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    /// Next to the config file.
    public static var standard: ProfileCache {
        ProfileCache(url: ConfigStore.standard.url.deletingLastPathComponent().appendingPathComponent("profiles.json"))
    }

    public func load() -> [ChromeProfile] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ChromeProfile].self, from: data)) ?? []
    }

    public func save(_ profiles: [ChromeProfile]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        try enc.encode(profiles).write(to: url, options: .atomic)
    }
}

public enum ProfileSource: Sendable { case live, cache, none }

/// Chrome's Local State when readable (refreshing the cache), else the cache.
public struct ProfileReader: Sendable {
    public let cache: ProfileCache
    public init(cache: ProfileCache) { self.cache = cache }

    /// `localState` nil means the file could not be read.
    public func read(localState: Data?) -> (profiles: [ChromeProfile], source: ProfileSource) {
        if let localState {
            let live = ChromeProfiles.parse(localState)
            if !live.isEmpty {
                try? cache.save(live)
                return (live, .live)
            }
        }
        let cached = cache.load()
        return (cached, cached.isEmpty ? .none : .cache)
    }
}
