import Foundation

/// A link pattern: `host[/path]`, with wildcards.
///
/// - Host: `*` matches any characters, dots included. A leading `*.` also matches the
///   bare domain, so `*.example.com` covers `example.com` and every subdomain.
/// - Path (optional, starts at the first `/`): `*` matches within one segment, `**` across
///   segments. A trailing `/**` also matches the bare prefix (`/acme/**` matches `/acme`).
///   No path in the pattern means any path.
/// - Matching ignores case, the scheme, the port, the query and the fragment.
///   A scheme written in the pattern (`https://`) is tolerated and ignored.
public struct Pattern: Equatable, Sendable {
    public let source: String
    private let host: NSRegularExpression?
    private let path: NSRegularExpression?

    public init(_ source: String) {
        self.source = source
        var s = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        guard !s.isEmpty else { host = nil; path = nil; return }

        let hostPart: Substring, pathPart: Substring?
        if let slash = s.firstIndex(of: "/") {
            hostPart = s[..<slash]; pathPart = s[slash...]
        } else {
            hostPart = s[...]; pathPart = nil
        }
        guard !hostPart.isEmpty else { host = nil; path = nil; return }

        host = Pattern.compile(Pattern.hostRegex(String(hostPart).lowercased()))
        path = pathPart.map { Pattern.compile(Pattern.pathRegex(String($0).lowercased())) } ?? nil
    }

    public static func == (a: Pattern, b: Pattern) -> Bool { a.source == b.source }

    /// True when the pattern is usable (non-empty, has a host part).
    public var isValid: Bool { host != nil }

    public func matches(_ url: URL) -> Bool {
        guard let host, let urlHost = url.host(percentEncoded: false)?.lowercased(), !urlHost.isEmpty else {
            return false
        }
        guard Pattern.full(host, urlHost) else { return false }
        guard let path else { return true }
        var p = url.path(percentEncoded: false).lowercased()
        if p.isEmpty { p = "/" }
        return Pattern.full(path, p)
    }

    // MARK: compile

    private static func compile(_ regex: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "^" + regex + "$", options: [])
    }

    private static func full(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func hostRegex(_ h: String) -> String {
        var h = h
        // drop a port written in the pattern
        if let colon = h.lastIndex(of: ":"), h[h.index(after: colon)...].allSatisfy(\.isNumber) {
            h = String(h[..<colon])
        }
        if h.hasPrefix("*.") {
            return "(?:.*\\.)?" + glob(String(h.dropFirst(2)), star: ".*", doubleStar: ".*")
        }
        return glob(h, star: ".*", doubleStar: ".*")
    }

    static func pathRegex(_ p: String) -> String {
        if p.hasSuffix("/**") {
            return glob(String(p.dropLast(3)), star: "[^/]*", doubleStar: ".*") + "(?:/.*)?"
        }
        return glob(p, star: "[^/]*", doubleStar: ".*")
    }

    /// Translate a glob into a regex body: everything literal except `*` and `**`.
    static func glob(_ g: String, star: String, doubleStar: String) -> String {
        var out = ""
        var chars = Array(g)[...]
        while let c = chars.first {
            chars = chars.dropFirst()
            if c == "*" {
                if chars.first == "*" { chars = chars.dropFirst(); out += doubleStar } else { out += star }
            } else {
                out += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        return out
    }
}
