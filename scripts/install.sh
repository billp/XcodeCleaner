#!/bin/bash
#
# scripts/install.sh
#
# Archive XcodeCleaner (Release), install it to /Applications,
# terminate any running instance, and launch the new copy.
#
# Usage:
#   scripts/install.sh
#   scripts/install.sh -d   # Debug config instead of Release
#   scripts/install.sh -- signing=YES  # force ad-hoc signing
#
set -euo pipefail

CONFIGURATION=Release
SIGNING=NO
extra_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug) CONFIGURATION=Debug; shift ;;
        --signing=*) SIGNING="${1#--signing=}"; shift ;;
        --) shift; extra_args+=("$@"); break ;;
        *) extra_args+=("$1"); shift ;;
    esac
done

project="XcodeCleaner.xcodeproj"
archive_path="/tmp/XcodeCleaner.xcarchive"
app_bundle="/Applications/XcodeCleaner.app"
bundle_id="com.local.XcodeCleaner"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

echo "→ Archiving ($CONFIGURATION)…"
rm -rf "$archive_path"
xcodebuild \
    -project "$project" \
    -scheme XcodeCleaner \
    -configuration "$CONFIGURATION" \
    -archivePath "$archive_path" \
    archive \
    CODE_SIGNING_ALLOWED="$SIGNING" \
    "${extra_args[@]+"${extra_args[@]}"}" \
    > /tmp/XcodeCleaner-archive.log

echo "→ Terminating any running instance…"
pkill -x XcodeCleaner 2>/dev/null || true
sleep 0.5

echo "→ Installing to /Applications…"
src="$archive_path/Products/Applications/XcodeCleaner.app"
need_elevate=0
if [[ ! -w /Applications ]]; then
    need_elevate=1
elif [[ -d "$app_bundle" && ! -w "$app_bundle" ]]; then
    need_elevate=1
fi
if [[ $need_elevate -eq 1 ]]; then
    osascript -e "do shell script \"rm -rf '$app_bundle' && cp -R '$src' '$app_bundle'\" with administrator privileges"
else
    rm -rf "$app_bundle"
    cp -R "$src" "$app_bundle"
fi

echo "→ Launching…"
open "$app_bundle"

echo "✓ Done. XcodeCleaner running from $app_bundle"