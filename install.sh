#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
app_name='Safari Tab Recall.app'
applications="$HOME/Applications"
mkdir -p "$applications"
staging="$(mktemp -d "$applications/.safari-tab-recall.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/$app_name"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"

deployment_target="arm64-apple-macos13.0"
if [[ "$(uname -m)" == "x86_64" ]]; then
    deployment_target="x86_64-apple-macos13.0"
fi
xcrun swiftc -swift-version 5 -target "$deployment_target" -O Sources/*.swift \
    -o "$app/Contents/MacOS/SafariTabRecall"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

destination="$applications/$app_name"
if [[ -d "$destination" ]]; then
    if /usr/bin/pgrep -x SafariTabRecall >/dev/null; then
        printf '%s\n' 'Open Safari Tab Recall again to show settings, then quit before reinstalling.' >&2
        exit 1
    fi
    mv "$destination" "$staging/Previous.app"
fi
if ! mv "$app" "$destination"; then
    if [[ -d "$staging/Previous.app" ]]; then
        mv "$staging/Previous.app" "$destination"
    fi
    exit 1
fi
open "$destination"
printf 'Installed %s\n' "$destination"
