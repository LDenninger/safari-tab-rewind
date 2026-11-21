#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
app="${1:?Usage: scripts/build-app.sh OUTPUT.app [arm64|x86_64|universal]}"
architecture="${2:-$(uname -m)}"
case "$architecture" in
    universal) architectures=(arm64 x86_64) ;;
    arm64|x86_64) architectures=("$architecture") ;;
    *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;;
esac

if [[ -e "$app" ]]; then
    printf 'Build destination already exists: %s\n' "$app" >&2
    exit 1
fi

temporary="$(mktemp -d "${TMPDIR:-/tmp}/tabrewind-build.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)"
binaries=()
for arch in "${architectures[@]}"; do
    binary="$temporary/TabRewind-$arch"
    xcrun swiftc -swift-version 5 -target "$arch-apple-macos$minimum_macos" -O Sources/*.swift -o "$binary"
    binaries+=("$binary")
done

executable="$app/Contents/MacOS/TabRewind"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"
if [[ "$architecture" == universal ]]; then
    xcrun lipo -create "${binaries[@]}" -output "$executable"
else
    cp "${binaries[0]}" "$executable"
fi

signing_options=(--force --sign "${MACOS_SIGNING_IDENTITY:--}")
if [[ -n "${MACOS_SIGNING_IDENTITY:-}" && "$MACOS_SIGNING_IDENTITY" != "-" ]]; then
    signing_options+=(--options runtime --timestamp)
    if [[ -n "${MACOS_SIGNING_KEYCHAIN:-}" ]]; then
        signing_options+=(--keychain "$MACOS_SIGNING_KEYCHAIN")
    fi
fi
codesign "${signing_options[@]}" "$app"
codesign --verify --strict --all-architectures "$app"
for arch in "${architectures[@]}"; do
    xcrun lipo "$executable" -verify_arch "$arch"
done
