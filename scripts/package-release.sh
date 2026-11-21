#!/bin/bash
set -euo pipefail

output="${1:?Usage: scripts/package-release.sh OUTPUT_DIRECTORY [EXPECTED_TAG]}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || "${2:-v$version}" != "v$version" ]]; then
    printf 'Expected a release tag matching version %s in Info.plist.\n' "$version" >&2
    exit 1
fi

temporary="$(mktemp -d "${TMPDIR:-/tmp}/tabrewind-package.XXXXXX")"
keychain=''
cleanup() {
    if [[ -n "$keychain" ]]; then
        security delete-keychain "$keychain" || true
    fi
    rm -rf "$temporary"
}
trap cleanup EXIT

export MACOS_SIGNING_IDENTITY=-
export MACOS_SIGNING_KEYCHAIN=''
signing_variables=(
    MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD
    APPLE_NOTARY_KEY_P8_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID
)
configured=0
for variable in "${signing_variables[@]}"; do
    if [[ -n "${!variable:-}" ]]; then
        configured=$((configured + 1))
    fi
done

if [[ "$configured" -ne 0 ]]; then
    if [[ "$configured" -ne "${#signing_variables[@]}" ]]; then
        printf '%s\n' 'Set all five Apple signing and notarization secrets before releasing.' >&2
        exit 1
    fi

    umask 077
    printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 -D > "$temporary/certificate.p12"
    printf '%s' "$APPLE_NOTARY_KEY_P8_BASE64" | base64 -D > "$temporary/AuthKey.p8"
    keychain="$temporary/signing.keychain-db"
    keychain_password="$(openssl rand -hex 32)"
    security create-keychain -p "$keychain_password" "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    security import "$temporary/certificate.p12" -f pkcs12 -k "$keychain" \
        -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain"
    MACOS_SIGNING_IDENTITY="$(security find-identity -v -p codesigning "$keychain" |
        awk '/"Developer ID Application:/ && !found { print $2; found = 1 }')"
    if [[ -z "$MACOS_SIGNING_IDENTITY" ]]; then
        printf '%s\n' 'The certificate must contain a valid Developer ID Application identity.' >&2
        exit 1
    fi
    MACOS_SIGNING_KEYCHAIN="$keychain"
    umask 022
fi

app="$temporary/TabRewind.app"
scripts/build-app.sh "$app" universal
signing_status=ad-hoc
if [[ "$configured" -ne 0 ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$app" "$temporary/notarize.zip"
    xcrun notarytool submit "$temporary/notarize.zip" \
        --key "$temporary/AuthKey.p8" --key-id "$APPLE_NOTARY_KEY_ID" \
        --issuer "$APPLE_NOTARY_ISSUER_ID" --wait --timeout 20m
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    signing_status=notarized
fi

archive="TabRewind-v$version-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$temporary/$archive"
ditto -x -k "$temporary/$archive" "$temporary/extracted"
codesign --verify --strict --all-architectures "$temporary/extracted/TabRewind.app"
for arch in arm64 x86_64; do
    xcrun lipo "$temporary/extracted/TabRewind.app/Contents/MacOS/TabRewind" -verify_arch "$arch"
done
mv "$temporary/$archive" "$output/$archive"
(cd "$output" && shasum -a 256 "$archive" > "$archive.sha256")
printf '%s\n' "$signing_status" > "$output/signing-status.txt"
