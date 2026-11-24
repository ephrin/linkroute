// Behaviour tests for LinkRouteCore, through its public API only.
// Run: swift run linkroute-tests   (exit code 1 on any failure)

import Foundation
import LinkRouteCore

var failures = 0
var passed = 0

func expect(_ cond: @autoclosure () -> Bool, _ what: String, file: String = #fileID, line: Int = #line) {
    if cond() { passed += 1 } else { failures += 1; print("FAIL \(file):\(line)  \(what)") }
}

func u(_ s: String) -> URL { URL(string: s)! }

func matches(_ pattern: String, _ url: String) -> Bool { Pattern(pattern).matches(u(url)) }

// MARK: host patterns

expect(matches("github.com", "https://github.com/"), "exact host")
expect(matches("github.com", "https://github.com/a/b?c=d#e"), "host-only pattern ignores path, query, fragment")
expect(matches("GitHub.COM", "https://github.com/x"), "host is case-insensitive")
expect(!matches("github.com", "https://gist.github.com/"), "exact host does not match a subdomain")
expect(!matches("github.com", "https://github.com.evil.io/"), "exact host does not match a longer host")
expect(matches("*.example.com", "https://a.example.com/"), "*. matches one subdomain level")
expect(matches("*.example.com", "https://a.b.example.com/"), "*. matches deeper subdomains")
expect(matches("*.example.com", "https://example.com/"), "*. also matches the apex")
expect(!matches("*.example.com", "https://notexample.com/"), "*. does not match a suffix that is not a label")
expect(matches("mail.*.com", "https://mail.google.com/"), "* in the middle of a host")
expect(matches("github.com", "http://github.com:8080/x"), "port is ignored")
expect(matches("https://github.com/x/**", "https://github.com/x/y"), "scheme in the pattern is tolerated")

// MARK: path patterns

expect(matches("github.com/acme/**", "https://github.com/acme/repo/pull/1"), "** spans segments")
expect(matches("github.com/acme/**", "https://github.com/acme"), "trailing /** also matches the bare prefix")
expect(matches("github.com/acme/**", "https://github.com/acme/"), "trailing /** matches prefix with slash")
expect(!matches("github.com/acme/**", "https://github.com/acmecorp/repo"), "/** does not match a longer segment")
expect(matches("github.com/acme/*", "https://github.com/acme/repo"), "* matches one segment")
expect(!matches("github.com/acme/*", "https://github.com/acme/repo/issues"), "* stops at a slash")
expect(matches("github.com/ACME/**", "https://github.com/acme/r"), "path is case-insensitive")
expect(matches("github.com/*/settings", "https://github.com/acme/settings"), "* inside a path")
expect(!matches("github.com/acme", "https://github.com/acme/repo"), "path without wildcard is exact")
expect(matches("github.com/", "https://github.com"), "empty URL path counts as /")
expect(matches("example.com/a b", "https://example.com/a%20b"), "path is compared percent-decoded")

// MARK: invalid or unusual input

expect(!matches("", "https://github.com/"), "empty pattern never matches")
expect(!matches("   ", "https://github.com/"), "blank pattern never matches")
expect(!matches("github.com", "file:///tmp/x.html"), "URL without host never matches")
expect(matches("example.com/a.b", "https://example.com/a.b"), "dots are literal")
expect(!matches("example.com/a.b", "https://example.com/aXb"), "dot is not a regex wildcard")
expect(matches("example.com/a+(b)", "https://example.com/a+(b)"), "regex metacharacters are literal")

// MARK: rules: first enabled match wins

let p1 = "Profile 1", p2 = "Profile 2", p3 = "Profile 3"
let rules = [
    Rule(pattern: "github.com/acme/**", profile: p1),
    Rule(pattern: "github.com", profile: p3),
    Rule(pattern: "*.atlassian.net", profile: p1, enabled: false),
    Rule(pattern: "*.atlassian.net", profile: p2),
]
expect(Rule.firstMatch(in: rules, for: u("https://github.com/acme/x"))?.profile == p1, "specific rule above general wins")
expect(Rule.firstMatch(in: rules, for: u("https://github.com/other/x"))?.profile == p3, "falls through to general rule")
expect(Rule.firstMatch(in: rules, for: u("https://x.atlassian.net/"))?.profile == p2, "disabled rules are skipped")
expect(Rule.firstMatch(in: rules, for: u("https://example.org/")) == nil, "no match gives nil")

// MARK: decisions

func cfg(_ mode: FallbackMode, profile: String? = nil) -> Config {
    var c = Config()
    c.rules = rules
    c.fallback = Fallback(mode: mode, profile: profile)
    return c
}

let hit = u("https://github.com/acme/x"), miss = u("https://example.org/")
expect(decide(url: hit, config: cfg(.ask), lastProfile: nil, paused: false) == .open(profile: p1, rule: rules[0].id), "rule hit opens its profile")
expect(decide(url: hit, config: cfg(.ask), lastProfile: nil, paused: true) == .openDefault, "paused bypasses rules")
expect(decide(url: miss, config: cfg(.ask), lastProfile: nil, paused: false) == .ask, "miss + ask asks")
expect(decide(url: miss, config: cfg(.profile, profile: p2), lastProfile: nil, paused: false) == .open(profile: p2, rule: nil), "miss + fixed profile")
expect(decide(url: miss, config: cfg(.profile), lastProfile: nil, paused: false) == .openDefault, "miss + fixed profile unset → default")
expect(decide(url: miss, config: cfg(.lastUsed), lastProfile: p3, paused: false) == .open(profile: p3, rule: nil), "miss + last used")
expect(decide(url: miss, config: cfg(.lastUsed), lastProfile: nil, paused: false) == .ask, "miss + last used, none yet → ask")
expect(decide(url: miss, config: cfg(.browser), lastProfile: p3, paused: false) == .openDefault, "miss + browser default")
expect(decide(url: u("file:///tmp/a.html"), config: cfg(.profile, profile: p2), lastProfile: nil, paused: false) == .open(profile: p2, rule: nil), "file URL goes to fallback")

// MARK: remembering a choice

var rc = Config()
rc.remember(url: u("https://www.Example.org/some/page"), profile: p2)
expect(rc.rules.count == 1, "remember adds one rule")
expect(rc.rules.last?.pattern == "www.example.org", "remembered pattern is the lowercased host")
expect(decide(url: u("https://www.example.org/other"), config: rc, lastProfile: nil, paused: false) == .open(profile: p2, rule: rc.rules[0].id), "remembered rule routes the host")
rc.remember(url: u("file:///tmp/a.html"), profile: p2)
expect(rc.rules.count == 1, "remember ignores URLs without host")

// MARK: config file round trip

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("linkroute-tests-\(UUID().uuidString)")
let file = dir.appendingPathComponent("sub/config.json")
let store = ConfigStore(url: file)
expect((try? store.load()) == Config(), "missing file loads defaults")
var saved = cfg(.profile, profile: p2)
saved.icon = "→"
do { try store.save(saved) } catch { expect(false, "save failed: \(error)") }
expect((try? store.load()) == saved, "save then load round-trips")
try? Data("{ not json".utf8).write(to: file)
expect((try? store.load()) == nil, "malformed file throws instead of silently resetting")
try? Data(#"{"rules":[{"pattern":"a.com","profile":"Default"}]}"#.utf8).write(to: file)
let partial = try? store.load()
expect(partial?.rules.first?.pattern == "a.com" && partial?.rules.first?.enabled == true, "hand-written minimal file fills defaults")
expect(partial?.fallback.mode == .ask && partial?.icon == Config().icon, "missing keys take defaults")
try? FileManager.default.removeItem(at: dir)

// MARK: Chrome profiles from Local State

let localState = #"""
{"profile":{"profiles_order":["Profile 2","Default"],
 "info_cache":{
  "Default":{"name":"Personal","user_name":"me@example.com"},
  "Profile 2":{"name":"Work","user_name":""},
  "Profile 7":{"name":"Old","user_name":"old@example.com"}}}}
"""#
let profiles = ChromeProfiles.parse(Data(localState.utf8))
expect(profiles.map(\.directory) == ["Profile 2", "Default", "Profile 7"], "profiles_order first, then the rest")
expect(profiles.first?.name == "Work" && profiles.first?.email == nil, "empty email becomes nil")
expect(profiles[1].email == "me@example.com", "email read from user_name")
expect(ChromeProfiles.parse(Data("garbage".utf8)).isEmpty, "garbage gives no profiles")

// MARK: launch arguments

expect(Launch.arguments(browser: "Google Chrome", profile: "Profile 1", url: u("https://a.com/x?y=1"))
       == ["-na", "Google Chrome", "--args", "--profile-directory=Profile 1", "https://a.com/x?y=1"], "profile launch args")
expect(Launch.arguments(browser: "Google Chrome", profile: nil, url: u("https://a.com/"))
       == ["-a", "Google Chrome", "https://a.com/"], "default launch args")

print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
