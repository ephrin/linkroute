#!/bin/bash
# Sign the app with a stable local identity, so macOS privacy grants survive rebuilds.
#
# An ad-hoc signature changes with every build, and macOS treats each build as a new app:
# "allow access to data from other apps" would have to be granted again after each one.
# A self-signed certificate gives a constant designated requirement
# (bundle id + certificate), so one grant lasts.
#
# The certificate lives in its own keychain, not the login keychain:
#   ~/Library/Keychains/linkroute-signing.keychain-db
# Its random password is in ~/.config/linkroute/signing/keychain-password (mode 0600).
# The identity can only sign code; it is not trusted for anything else.
# Remove both to start over: `make unsign-identity`.
#
# Usage: scripts/sign.sh <App.app>      SIGN=adhoc scripts/sign.sh <App.app> for ad-hoc.
set -euo pipefail

app="$1"
name="LinkRoute Local Signing"
kc="$HOME/Library/Keychains/linkroute-signing.keychain-db"
dir="$HOME/.config/linkroute/signing"
pwfile="$dir/keychain-password"

if [[ "${SIGN:-}" == "adhoc" ]]; then
    codesign --force --sign - "$app"
    exit 0
fi

if [[ ! -f "$kc" || ! -f "$pwfile" ]]; then
    echo "creating signing identity '$name' in $kc"
    mkdir -p "$dir" && chmod 700 "$dir"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    (umask 077 && openssl rand -hex 24 > "$pwfile")
    cat > "$tmp/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$tmp/req.cnf" \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    p12pass="$(openssl rand -hex 12)"
    openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -out "$tmp/id.p12" -passout "pass:$p12pass" 2>/dev/null \
      || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -out "$tmp/id.p12" -passout "pass:$p12pass"
    rm -f "$kc"
    security create-keychain -p "$(cat "$pwfile")" "$kc"
    security set-keychain-settings "$kc"   # no auto-lock timeout
    security unlock-keychain -p "$(cat "$pwfile")" "$kc"
    security import "$tmp/id.p12" -k "$kc" -P "$p12pass" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$(cat "$pwfile")" "$kc" >/dev/null
fi

security unlock-keychain -p "$(cat "$pwfile")" "$kc"
codesign --force --keychain "$kc" --sign "$name" "$app"
codesign --verify "$app"
codesign -dr - "$app" 2>&1 | sed -n 's/^designated => /signed: /p'
