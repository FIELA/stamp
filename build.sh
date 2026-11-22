#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")" && pwd)
build_dir=${1:-"$project_dir/build"}
mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)
app_dir="$build_dir/图章.app"
scratch_dir=$(mktemp -d "$build_dir/.stamp-build.XXXXXXXX")
trap 'rm -rf "$scratch_dir"' EXIT

bundle="$scratch_dir/图章.app"
iconset="$scratch_dir/StampIcon.iconset"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$iconset"
cp "$project_dir/Info.plist" "$bundle/Contents/Info.plist"
ditto --norsrc "$project_dir/Resources" "$bundle/Contents/Resources"

xcrun swiftc -O -target arm64-apple-macosx14.0 \
    "$project_dir"/Sources/*.swift -o "$bundle/Contents/MacOS/SealStudio"
xcrun swift "$project_dir/StampIcon.swift" "$iconset"
iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/StampIcon.icns"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"

if [[ -e "$app_dir" ]]; then
    if [[ -L "$app_dir" || ! -f "$app_dir/Contents/Info.plist" ]] ||
        [[ $(plutil -extract CFBundleIdentifier raw "$app_dir/Contents/Info.plist") != local.ws.sealstudio ]]; then
        echo "Build destination is occupied: $app_dir" >&2
        exit 1
    fi
    mv "$app_dir" "$scratch_dir/previous.app"
fi
mv "$bundle" "$app_dir"
printf '%s\n' "$app_dir"
