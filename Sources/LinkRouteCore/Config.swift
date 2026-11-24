import Foundation

/// One routing rule: links matching `pattern` open in Chrome profile directory `profile`.
public struct Rule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var pattern: String
    /// Chrome profile directory name, e.g. `Default` or `Profile 1` (not the display name).
    public var profile: String
    public var enabled: Bool

    public init(id: UUID = UUID(), pattern: String, profile: String, enabled: Bool = true) {
        self.id = id; self.pattern = pattern; self.profile = profile; self.enabled = enabled
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pattern = try c.decode(String.self, forKey: .pattern)
        profile = try c.decode(String.self, forKey: .profile)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// The first enabled rule, top to bottom, whose pattern matches.
    public static func firstMatch(in rules: [Rule], for url: URL) -> Rule? {
        rules.first { $0.enabled && Pattern($0.pattern).matches(url) }
    }
}

/// What to do with a link no rule matches.
public enum FallbackMode: String, Codable, CaseIterable, Sendable {
    /// Show the profile picker.
    case ask
    /// Open in `Fallback.profile`.
    case profile
    /// Open in the profile linkroute used last; ask if there is none yet.
    case lastUsed
    /// Hand the link to Chrome without a profile (Chrome's last active window).
    case browser
}

public struct Fallback: Codable, Equatable, Sendable {
    public var mode: FallbackMode
    public var profile: String?
    /// Initial state of the picker's "remember" checkbox.
    public var rememberByDefault: Bool

    public init(mode: FallbackMode = .ask, profile: String? = nil, rememberByDefault: Bool = false) {
        self.mode = mode; self.profile = profile; self.rememberByDefault = rememberByDefault
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(FallbackMode.self, forKey: .mode) ?? .ask
        profile = try c.decodeIfPresent(String.self, forKey: .profile)
        rememberByDefault = try c.decodeIfPresent(Bool.self, forKey: .rememberByDefault) ?? false
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var version: Int
    /// Application name passed to `open -a`.
    public var browser: String
    /// The character drawn as the menu bar icon.
    public var icon: String
    public var fallback: Fallback
    public var rules: [Rule]

    public init(version: Int = 1, browser: String = "Google Chrome", icon: String = "⇢",
                fallback: Fallback = Fallback(), rules: [Rule] = []) {
        self.version = version; self.browser = browser; self.icon = icon
        self.fallback = fallback; self.rules = rules
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Config()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? def.version
        browser = try c.decodeIfPresent(String.self, forKey: .browser) ?? def.browser
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? def.icon
        fallback = try c.decodeIfPresent(Fallback.self, forKey: .fallback) ?? def.fallback
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }

    /// Append a rule sending this link's host to `profile`. No-op for links without a host.
    public mutating func remember(url: URL, profile: String) {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return }
        rules.append(Rule(pattern: host, profile: profile))
    }
}

/// Reads and writes the JSON config file.
public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `$LINKROUTE_CONFIG`, else `~/.config/linkroute/config.json`.
    public static var standard: ConfigStore {
        if let p = ProcessInfo.processInfo.environment["LINKROUTE_CONFIG"], !p.isEmpty {
            return ConfigStore(url: URL(fileURLWithPath: (p as NSString).expandingTildeInPath))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ConfigStore(url: home.appendingPathComponent(".config/linkroute/config.json"))
    }

    /// Defaults when the file does not exist; throws when it exists but cannot be read.
    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    /// Atomic write; creates the directory.
    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(config).write(to: url, options: .atomic)
    }
}
