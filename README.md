<p align="center">
  <img src="docs/icon.png" width="128" alt="LinkRoute icon">
</p>

<h1 align="center">LinkRoute</h1>

<p align="center">
  Open every link in the right Chrome profile.<br>
  A small macOS menu bar app that you set as the default browser. It sends each link to the profile your rules choose.
</p>

---

You click a GitHub link in Slack, and it opens in your personal Chrome profile, signed in to the wrong
account. LinkRoute fixes that. It sits between macOS and Chrome. It checks each link against your rules
(host and path patterns, first match wins), then opens it in the Chrome profile that rule names. A link no
rule matches gets a small picker at the mouse pointer. Press a number key to choose a profile, and tick
"Always open this way" to save the choice as a rule.

- **Menu bar only.** No Dock icon. The icon is any character you like: an arrow, a symbol, a Nerd Font glyph, an emoji.
- **Host and path rules.** `github.com/acme/**` goes to Work and the rest of `github.com` to Personal.
- **Picker for unknown links**, with number-key shortcuts and a "remember" checkbox.
- **Settings for unmatched links:** ask, a fixed profile, the profile used last, or let Chrome decide.
- **Live link tester** in the rules window, which shows which rule wins before you save.
- **Recent links** in the menu, each with "open in …" and "always open in …".
- **Plain JSON config** at `~/.config/linkroute/config.json`, easy to edit by hand or keep in your dotfiles.
- **No network access, no tracking.** About 1,300 lines of Swift with no dependencies.

## Install

Requires macOS 14 or later and Google Chrome. Build it from source; the Xcode Command Line Tools are enough:

```sh
xcode-select --install            # once, if you have no Swift toolchain
git clone https://github.com/ephrin/linkroute.git
cd linkroute
make install                      # builds, installs to ~/Applications, starts it
```

Then:

1. Click the menu bar icon and choose **Make Default Browser**. macOS asks you to confirm.
2. Open **Rules…** (⌘,). If a banner says Chrome's profiles can't be read, see [Permissions](#permissions).
3. Add rules, then click **Save** (⌘S).
4. Optional: tick **Open at Login** in the menu. LinkRoute starts anyway when you click a link, because it is the default browser; this setting only keeps the icon in the menu bar.

To use another icon character for the app icon too, run `make install GLYPH=↬`. The menu bar icon is set in the rules window.

## Rules

A rule is a pattern and a Chrome profile. LinkRoute checks rules from top to bottom, and the first enabled
rule that matches wins. Drag rows to reorder them.

A pattern is `host[/path]`:

| Pattern | Matches | Does not match |
|---|---|---|
| `github.com` | `github.com/anything` | `gist.github.com` |
| `*.atlassian.net` | `acme.atlassian.net`, `atlassian.net` | `notatlassian.net` |
| `github.com/acme/**` | `github.com/acme`, `github.com/acme/repo/pull/1` | `github.com/acmecorp` |
| `github.com/acme/*` | `github.com/acme/repo` | `github.com/acme/repo/issues` |
| `github.com/*/settings` | `github.com/anyone/settings` | `github.com/a/b/settings` |
| `mail.*.com` | `mail.google.com` | `mail.google.co.uk` |

- **Host:** `*` matches any characters, dots included. A leading `*.` also matches the bare domain.
- **Path:** optional, starting at the first `/`. `*` matches within one path segment and `**` across segments. A trailing `/**` also matches the bare prefix.
- **Ignored:** case, scheme, port, query string and fragment. A pattern without a path matches every path on that host.
- **Literal:** everything except `*` is literal, so `.`, `+` and `(` mean themselves.

Put specific rules above general ones:

```
github.com/acme/**   →  Work
github.com           →  Personal
*.atlassian.net      →  Work
```

## Links no rule matches

Choose what happens in the rules window, under **Links no rule matches**:

| Mode | What happens |
|---|---|
| **Ask** (default) | A picker opens at the mouse pointer. Keys `1`–`9` choose a profile and Esc cancels; clicking elsewhere also cancels. Tick "Always open *host* this way" to add a rule for that host. |
| **Fixed profile** | Opens in the profile you choose. |
| **Profile used last** | Opens in the profile LinkRoute opened last, and asks if there is none yet. |
| **Let Chrome decide** | Hands the link to Chrome without a profile, so it opens in Chrome's last active window. |

**Pause Routing** in the menu bypasses all rules until you turn it off.

## Config file

The rules window reads and writes `~/.config/linkroute/config.json` (or `$LINKROUTE_CONFIG`). LinkRoute
reads the file again for every link, so you can also edit it by hand. Only `pattern` and `profile` are
required; every other key has a default:

```json
{
  "browser": "Google Chrome",
  "icon": "⇢",
  "fallback": { "mode": "ask", "profile": null, "rememberByDefault": false },
  "rules": [
    { "pattern": "github.com/acme/**", "profile": "Profile 1" },
    { "pattern": "github.com", "profile": "Default" },
    { "pattern": "*.atlassian.net", "profile": "Profile 1", "enabled": true }
  ]
}
```

`profile` is Chrome's profile **directory** (`Default`, `Profile 1`, …), not its display name. The rules
window shows names and email addresses, and stores the directory. `fallback.mode` is one of `ask`,
`profile`, `lastUsed` or `browser`. If the file is broken, LinkRoute keeps using the last good rules and
shows a warning in the menu.

## Permissions

LinkRoute reads Chrome's profile list from
`~/Library/Application Support/Google/Chrome/Local State`. Recent macOS versions block one app from
reading another app's data until you allow it, once:

1. Click **Grant Chrome Access…** in the menu, or **Open Privacy Settings** in the rules window.
2. In **Privacy & Security → Files & Folders**, allow **LinkRoute** to access data from other apps.
3. Return to LinkRoute. It checks again by itself, and the profile names appear.

Until then you can type profile directories (`Profile 1`) by hand; routing works either way. LinkRoute
also saves the last profile list it read to `~/.config/linkroute/profiles.json`, and uses that list
whenever the live read is blocked.

**Why the grant survives rebuilds:** macOS ties the grant to the app's code signature. An ad-hoc
signature changes with every build, so each build would look like a new app. `make app` therefore
signs with a self-signed certificate, which it creates on the first build in its own keychain
(`~/Library/Keychains/linkroute-signing.keychain-db`). Your login keychain is not touched. The
certificate can sign code only and is not trusted for anything else. `make unsign-identity` deletes
it, and `SIGN=adhoc make app` builds without it.

**If the toggle turns itself off:** an older build, signed differently, left a stale entry. macOS
compares the running app with that entry, finds no match, and records "denied" again. Clear the entry,
then allow LinkRoute once more:

```sh
tccutil reset SystemPolicyAppDataDetailed com.ephrin.linkroute
```

## How it works

LinkRoute registers for `http` and `https` URLs, so macOS can make it the default browser. For each link it:

1. reloads the config,
2. finds the first enabled rule that matches (or applies the fallback),
3. runs `open -na "Google Chrome" --args --profile-directory="<dir>" <url>`.

`-n` starts a short-lived Chrome process with the profile flag. That process passes the URL to the Chrome
already running, which opens it in a window of that profile (or opens one), and then exits.

```
Sources/
  LinkRouteCore/     pure logic: Pattern, Rule, Config, decide(), Chrome profile discovery
  LinkRoute/         the app: menu bar item, picker panel, rules window, icon drawing
  linkroute-tests/   behaviour tests for LinkRouteCore
scripts/Info.plist   bundle metadata: URL schemes, LSUIElement
scripts/sign.sh      stable local code signing
Makefile             app, test, install, uninstall
```

## Development

```sh
make test         # behaviour tests (swift run linkroute-tests)
make app          # build/LinkRoute.app
make install      # build, install into ~/Applications, (re)start
make uninstall
```

The tests are a plain executable, not XCTest or swift-testing. Both of those need a full Xcode install,
and this project builds with the Command Line Tools alone. For the same reason the SwiftUI code avoids
macro-based APIs such as `@State` and uses `ObservableObject` instead.

## Limitations

- Chrome only for now. `browser` in the config can name another Chromium browser, but profile discovery reads Chrome's own `Local State`.
- Links you click inside Chrome stay in that window's profile. macOS never sees them.
- No notarized release yet. Build from source.

## License

[MIT](LICENSE)
