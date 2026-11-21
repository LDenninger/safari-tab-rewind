#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
app_name='TabRewind.app'
previous_name='Safari Tab Recall.app'
bundle_id='io.github.ldenninger.safari-tab-recall'
applications="$HOME/Applications"
destination="$applications/$app_name"
mkdir -p "$applications"

if /usr/bin/pgrep -x 'TabRewind|SafariTabRecall' >/dev/null; then
    printf '%s\n' 'Reopen the app for settings, then quit it before reinstalling.' >&2
    exit 1
fi

for name in "$app_name" "$previous_name"; do
    existing="$applications/$name"
    if [[ -e "$existing" ]]; then
        identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$existing/Contents/Info.plist")"
        if [[ "$identifier" != "$bundle_id" ]]; then
            printf 'An unrelated app is installed at %s\n' "$existing" >&2
            exit 1
        fi
    fi
done

staging="$(mktemp -d "$applications/.tab-rewind.XXXXXX")"
installed=false
cleanup() {
    if [[ "$installed" == false ]]; then
        for name in "$app_name" "$previous_name"; do
            backup="$staging/previous/$name"
            if [[ -d "$backup" ]] && ! mv "$backup" "$applications/$name"; then
                printf 'The previous app is still available at %s\n' "$backup" >&2
                return
            fi
        done
    fi
    rm -rf "$staging"
}
trap cleanup EXIT

app="$staging/$app_name"
mkdir -p "$app/Contents/MacOS" "$staging/previous"
cp Info.plist "$app/Contents/Info.plist"

deployment_target="arm64-apple-macos13.0"
if [[ "$(uname -m)" == "x86_64" ]]; then
    deployment_target="x86_64-apple-macos13.0"
fi
xcrun swiftc -swift-version 5 -target "$deployment_target" -O Sources/*.swift \
    -o "$app/Contents/MacOS/TabRewind"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

for name in "$app_name" "$previous_name"; do
    if [[ -e "$applications/$name" ]]; then
        mv "$applications/$name" "$staging/previous/"
    fi
done
mv "$app" "$destination"
installed=true
open "$destination"
printf 'Installed %s\n' "$destination"
