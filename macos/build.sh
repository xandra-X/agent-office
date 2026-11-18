#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:?Pass an absolute output path for Agent Office.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Office"
cp "$project/dist/"*.{html,css,js} "$app/Contents/Resources/Office/"
cp "$project/macos/Info.plist" "$app/Contents/"
cp "$project/macos/AgentOffice.icns" "$app/Contents/Resources/"
arch="${AGENT_OFFICE_MAC_ARCH:-$(uname -m)}"
swiftc -O -target "$arch-apple-macosx14.0" "$project/macos/AgentOffice.swift" -o "$app/Contents/MacOS/AgentOffice"
xattr -cr "$app"

codesign --force --sign - "$app"
