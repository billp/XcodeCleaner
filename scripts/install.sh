#!/bin/bash
#
# scripts/install.sh
#
# Archive XcodeCleaner (Release), install it to /Applications,
# terminate any running instance, and launch the new copy.
#
# The app is signed with the project's Apple Development identity by default.
# macOS ties Full Disk Access to an app's code signature: a properly signed
# build keeps a stable identity (bundle ID + team) across rebuilds, so the
# permission survives updates. An ad-hoc build is identified by its code hash
# instead, which changes on every build — so the grant is silently dropped and
# has to be re-added after each install.
#
# Usage:
#   scripts/install.sh
#   scripts/install.sh -d            # Debug config instead of Release
#   scripts/install.sh --signing=NO  # ad-hoc signing (no certificate needed)
#
set -euo pipefail

CONFIGURATION=Release
SIGNING=YES
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

# Manual signing style deliberately: it resolves the certificate straight from
# the keychain, so a signed build works without the Apple ID being logged into
# Xcode (automatic signing fails with "No Account for Team" in that case).
run_archive() {
    local allowed="$1"; shift
    xcodebuild \
        -project "$project" \
        -scheme XcodeCleaner \
        -configuration "$CONFIGURATION" \
        -archivePath "$archive_path" \
        archive \
        CODE_SIGNING_ALLOWED="$allowed" \
        "$@" \
        "${extra_args[@]+"${extra_args[@]}"}" \
        > /tmp/XcodeCleaner-archive.log 2>&1
}

echo "→ Archiving ($CONFIGURATION)…"
rm -rf "$archive_path"
if [[ "$SIGNING" == "NO" ]]; then
    run_archive NO
elif ! run_archive YES CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER=; then
    echo "  ! No usable signing certificate — falling back to ad-hoc signing."
    echo "    You will have to re-grant Full Disk Access after every install."
    echo "    Details: /tmp/XcodeCleaner-archive.log"
    rm -rf "$archive_path"
    run_archive NO
fi

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
codesign -dv "$app_bundle" 2>&1 | grep -q "TeamIdentifier=not set" \
    && echo "  Note: ad-hoc signed — Full Disk Access must be re-granted." || true