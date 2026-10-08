#!/bin/bash
#
# Builds the signed, notarized installer and uninstaller that go on the
# Releases page. Double-click it in Finder on a Mac that holds both Developer
# ID certificates. The finished packages land in Release/ beside
# SHA256SUMS.txt.
#
# Run it from Terminal with --preview to check the installer pages instead.
# That build needs no certificates and skips notarization. It leaves unsigned
# packages in dist/, opens the installer, and leaves Release/ alone.

set -euo pipefail

PREVIEW=false
if [[ "${1:-}" == "--preview" ]]; then
    PREVIEW=true
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/VERSION")"
# The app is assembled and signed in a private temporary folder. Inside
# Documents or Desktop, iCloud and Finder can put Finder information back on
# the bundle between clearing it and signing, and codesign refuses that.
BUILD="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/scrippy-build.XXXXXX")"
DIST="$ROOT/dist"
RELEASE="$ROOT/Release"
PAYLOAD="$BUILD/payload"
APP="$PAYLOAD/Applications/Scrippy.app"
APP_SUPPORT="$PAYLOAD/Library/Application Support/Scrippy"
SERVICES="$PAYLOAD/Library/Services"
WORKFLOW="$SERVICES/Convert with Scrippy.workflow"
SCRIPTS="$BUILD/scripts"
RESOURCES="$BUILD/resources"
COMPONENTS="$BUILD/components"
DISTRIBUTION="$BUILD/PublicDistribution.xml"
UNINSTALL_COMPONENTS="$BUILD/uninstall-components"
UNINSTALL_RESOURCES="$BUILD/uninstall-resources"
UNINSTALL_SCRIPTS="$BUILD/uninstall-scripts"
UNINSTALL_DISTRIBUTION="$BUILD/UninstallDistribution.xml"
PROFILE="${SCRIPPY_NOTARY_PROFILE:-Scrippy}"
if [[ "$PREVIEW" == true ]]; then
    PACKAGE_NAME="Scrippy-$VERSION-preview.pkg"
    UNINSTALL_NAME="Uninstall-Scrippy-$VERSION-preview.pkg"
else
    PACKAGE_NAME="Scrippy-$VERSION.pkg"
    UNINSTALL_NAME="Uninstall-Scrippy-$VERSION.pkg"
fi

# One-step Finder actions, each a copy of the main workflow that passes
# "--to FORMAT" to the engine. Each entry is the SIPS format key, which also
# ends the bundle and package identifiers, the format name people know, and
# the name shown in the Quick Actions menu. Each one is a package of its own,
# so a person can leave it out on the Installation Type page. The choices in
# package/PublicDistribution.xml must list the same keys.
ONE_STEP_ACTIONS=(
    "jpeg|JPEG|Convert to JPEG with Scrippy"
    "png|PNG|Convert to PNG with Scrippy"
    "heic|HEIC|Convert to HEIC with Scrippy"
)

# The app uses SF Symbols and Quick Look thumbnails, which together set the
# floor at macOS 11. The installer refuses older systems with the same number.
MIN_MACOS="11.0"

fail() {
    /usr/bin/printf '\nPublic installer build stopped.\n%s\n' "$1" >&2
    exit 1
}

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
    fail 'This command must be run on a Mac.'
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "VERSION must hold a version such as 1.0.0, not '$VERSION'."
fi

for tool in /usr/bin/pkgbuild /usr/bin/productbuild /usr/bin/xcrun /usr/bin/security /usr/bin/codesign /usr/sbin/pkgutil /usr/sbin/spctl /usr/bin/lipo /usr/bin/plutil /usr/bin/xattr /usr/bin/iconutil; do
    [[ -x "$tool" ]] || fail "Required macOS tool is missing: $tool"
done

if [[ "$PREVIEW" == true ]]; then
    # An ad hoc signature is enough for the app to run on this Mac.
    APP_IDENTITY="-"
else
    APP_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | /usr/bin/head -n 1)"
    INSTALLER_IDENTITY="$(/usr/bin/security find-identity -v 2>/dev/null | /usr/bin/sed -n 's/.*"\(Developer ID Installer:.*\)"/\1/p' | /usr/bin/head -n 1)"
    [[ -n "$APP_IDENTITY" ]] || fail 'A Developer ID Application certificate was not found in Keychain.'
    [[ -n "$INSTALLER_IDENTITY" ]] || fail 'A Developer ID Installer certificate was not found in Keychain.'
fi

# A stale help page would ship text that no longer matches the app, so the
# build refuses to continue until it is regenerated.
/usr/bin/xcrun python3 "$ROOT/Scripts/make_help.py" --check || fail 'Run python3 Scripts/make_help.py, then build again.'

/bin/rm -rf "$DIST"
if [[ "$PREVIEW" == false ]]; then
    /bin/rm -rf "$RELEASE"
    /bin/mkdir -p "$RELEASE"
fi
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP_SUPPORT/bin" "$APP_SUPPORT/Example" \
    "$SERVICES" "$RESOURCES" "$COMPONENTS" "$UNINSTALL_COMPONENTS" "$UNINSTALL_RESOURCES" "$UNINSTALL_SCRIPTS" \
    "$DIST"

/bin/cp "$ROOT/src/scrippy.sh" "$APP_SUPPORT/bin/"
/bin/cp "$ROOT/Example/Example Image - Messier 88.png" "$APP_SUPPORT/Example/"
/bin/cp "$ROOT/help/Scrippy Help.md" "$APP/Contents/Resources/"
/bin/cp -R "$ROOT/workflow/Convert with Scrippy.workflow" "$SERVICES/"

# VERSION is the only place the number is typed. Every file that shows it
# receives it here, so a release can never ship two different numbers.
/usr/bin/sed "s/__VERSION__/$VERSION/g" "$ROOT/help/Scrippy Help.html" > "$APP_SUPPORT/Scrippy Help.html"
/usr/bin/sed "s/__VERSION__/$VERSION/g" "$ROOT/package/app/Info.plist" > "$APP/Contents/Info.plist"
/usr/bin/sed "s/__VERSION__/$VERSION/g" "$ROOT/package/PublicDistribution.xml" > "$DISTRIBUTION"
/usr/bin/sed "s/__VERSION__/$VERSION/g" "$ROOT/package/uninstall/UninstallDistribution.xml" > "$UNINSTALL_DISTRIBUTION"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$WORKFLOW/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$WORKFLOW/Contents/Info.plist"

# The one-step actions are made from the main workflow at build time rather
# than kept as copies in the repository, so a fix to one reaches all of them.
# Like the main workflow, each starts the engine with an empty environment
# apart from HOME and TMPDIR. The engine honors a few variables so the tests
# can swap in stand-ins, and clearing them here means nothing set elsewhere in
# the login session can point a Finder action at another program. Each goes
# into a payload of its own, beside the main one.
for spec in "${ONE_STEP_ACTIONS[@]}"; do
    IFS='|' read -r format_key format_name action_name <<< "$spec"
    action="$BUILD/payload-$format_key/Library/Services/$action_name.workflow"
    /bin/mkdir -p "$(/usr/bin/dirname "$action")"
    /bin/cp -R "$WORKFLOW" "$action"
    /usr/bin/plutil -replace actions.0.action.ActionParameters.COMMAND_STRING -string \
        "/usr/bin/env -i HOME=\"\$HOME\" TMPDIR=\"\$TMPDIR\" /bin/bash \"\$HOME/Library/Application Support/Scrippy/bin/scrippy.sh\" --to $format_key \"\$@\"" "$action/Contents/document.wflow"
    /usr/bin/plutil -replace NSServices.0.NSMenuItem.default -string "$action_name" "$action/Contents/Info.plist"
    /usr/bin/plutil -replace NSServices.0.NSServiceDescription -string "Convert the selected images to $format_name with Scrippy, without opening the window." "$action/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleName -string "$action_name" "$action/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleIdentifier -string "com.scrippy.quickaction.$format_key" "$action/Contents/Info.plist"
done

# The app icon is built from the same PNG set the README uses. iconutil needs
# each size under the names an icon set expects, including the doubled ones.
ICONSET="$BUILD/AppIcon.iconset"
/bin/mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    /bin/cp "$ROOT/Assets/png/AppIcon-$size.png" "$ICONSET/icon_${size}x${size}.png"
    /bin/cp "$ROOT/Assets/png/AppIcon-$((size * 2)).png" "$ICONSET/icon_${size}x${size}@2x.png"
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# swiftc builds for the chip and macOS version of the Mac it runs on unless
# told otherwise. Building each architecture against the minimum version and
# joining them lets one package run on Apple silicon and Intel alike.
for arch in arm64 x86_64; do
    /usr/bin/xcrun swiftc -O -target "$arch-apple-macos$MIN_MACOS" \
        -framework AppKit -framework QuickLookThumbnailing \
        "$ROOT"/package/app/Sources/*.swift -o "$BUILD/Scrippy-$arch"
done
/usr/bin/lipo -create "$BUILD/Scrippy-arm64" "$BUILD/Scrippy-x86_64" -output "$APP/Contents/MacOS/Scrippy"

# Installer pages: the welcome and last pages, the two background images, and
# the license set as formatted text.
/bin/cp "$ROOT"/package/resources/*.html "$ROOT"/package/resources/background*.png "$RESOURCES/"
/usr/bin/xcrun python3 "$ROOT/Scripts/make_license.py" "$ROOT/LICENSE" "$RESOURCES/License.rtf"

# Finder and iCloud attach extended attributes and .DS_Store files on their
# own. codesign rejects the first, and nobody wants the second installed.
for root in "$PAYLOAD" "$BUILD"/payload-*; do
    /usr/bin/find "$root" -name .DS_Store -delete
    /usr/bin/xattr -cr "$root"
    # Files unpacked from an archive can arrive locked or read only, which
    # pkgbuild reports while it reads them. The owner keeps write access.
    /usr/bin/chflags -R nouchg "$root"
    /bin/chmod -R u+w "$root"
    # Nothing installed is left writable by other accounts on the Mac.
    /bin/chmod -R go-w "$root"
done
# pkgbuild reads the install scripts from a private copy, which also makes
# sure the script can run whatever permissions the checkout gave it.
/bin/mkdir -p "$SCRIPTS"
/bin/cp "$ROOT/package/public-scripts/postinstall" "$SCRIPTS/"
/bin/chmod 755 "$SCRIPTS/postinstall"
/bin/chmod 755 "$APP_SUPPORT/bin/scrippy.sh" "$APP/Contents/MacOS/Scrippy"

# Signing the bundle seals its Info.plist, icon, and help text along with the
# program, so none of them can change without breaking the signature.
if [[ "$PREVIEW" == true ]]; then
    /usr/bin/codesign --force --options runtime --sign "$APP_IDENTITY" "$APP"
else
    /usr/bin/codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$APP"
fi
/usr/bin/codesign --verify --strict --deep --verbose=2 "$APP"
/usr/bin/lipo -info "$APP/Contents/MacOS/Scrippy"

# Installer can move an upgrade to wherever it finds an app with the same
# identifier, a copy in Downloads for instance. The engine looks for Scrippy
# in fixed places only, so every bundle in a payload is pinned in place.
build_component() {
    local root="$1" identifier="$2" output="$3"
    local plist="$BUILD/$identifier.plist" index=0
    /usr/bin/pkgbuild --analyze --root "$root" "$plist"
    while /usr/bin/plutil -extract "$index" xml1 -o /dev/null "$plist" 2>/dev/null; do
        /usr/bin/plutil -replace "$index.BundleIsRelocatable" -bool NO "$plist"
        index=$((index + 1))
    done
    # Every package carries the postinstall script, so Finder learns about
    # each Quick Action whichever ones a person picked.
    /usr/bin/pkgbuild \
        --root "$root" \
        --component-plist "$plist" \
        --identifier "$identifier" \
        --version "$VERSION" \
        --install-location / \
        --scripts "$SCRIPTS" \
        "$COMPONENTS/$output"
}

build_component "$PAYLOAD" com.scrippy.pkg Scrippy.pkg
for spec in "${ONE_STEP_ACTIONS[@]}"; do
    IFS='|' read -r format_key _ _ <<< "$spec"
    build_component "$BUILD/payload-$format_key" "com.scrippy.quickaction.$format_key.pkg" "Scrippy-$format_key.pkg"
done

# The uninstaller is a package with no files, only a script that removes
# what the installer placed. It shares the installer's background so the two
# look like a pair.
/bin/cp "$ROOT/package/uninstall/scripts/postinstall" "$UNINSTALL_SCRIPTS/"
/bin/chmod 755 "$UNINSTALL_SCRIPTS/postinstall"
/bin/cp "$ROOT"/package/uninstall/resources/*.html "$ROOT"/package/resources/background*.png "$UNINSTALL_RESOURCES/"
/usr/bin/pkgbuild \
    --nopayload \
    --scripts "$UNINSTALL_SCRIPTS" \
    --identifier com.scrippy.uninstall \
    --version "$VERSION" \
    "$UNINSTALL_COMPONENTS/Uninstall.pkg"

# Builds one product. A preview is left unsigned. A release is signed,
# notarized, stapled, and checked by Gatekeeper before it is copied to
# Release.
product() {
    local distribution="$1" resources="$2" components="$3" name="$4"
    local output="$DIST/$name"
    if [[ "$PREVIEW" == true ]]; then
        /usr/bin/productbuild --distribution "$distribution" --resources "$resources" \
            --package-path "$components" "$output"
        return
    fi
    /usr/bin/productbuild --distribution "$distribution" --resources "$resources" \
        --package-path "$components" --sign "$INSTALLER_IDENTITY" "$output"
    /usr/sbin/pkgutil --check-signature "$output"

    local result="$BUILD/$name-notarization.json" log="$BUILD/$name-notarization-log.json"
    if ! /usr/bin/xcrun notarytool submit "$output" --keychain-profile "$PROFILE" --wait --output-format json > "$result"; then
        fail "Apple notarization could not be submitted. If this is the first release build, run: xcrun notarytool store-credentials '$PROFILE'"
    fi
    local status submission
    status="$(/usr/bin/plutil -extract status raw -o - "$result")"
    submission="$(/usr/bin/plutil -extract id raw -o - "$result")"
    # The log is fetched even on success. It lists any warnings Apple raised,
    # which are easier to fix before they become errors in a later release.
    if [[ -n "$submission" ]]; then
        /usr/bin/xcrun notarytool log "$submission" --keychain-profile "$PROFILE" "$log" || true
    fi
    [[ "$status" == "Accepted" ]] || fail "Apple notarization of $name returned: $status. See $log"

    /usr/bin/xcrun stapler staple "$output"
    /usr/bin/xcrun stapler validate "$output"
    /usr/sbin/pkgutil --check-signature "$output"
    /usr/sbin/spctl --assess --type install --verbose=2 "$output"
    /bin/cp "$output" "$RELEASE/$name"
}

product "$DISTRIBUTION" "$RESOURCES" "$COMPONENTS" "$PACKAGE_NAME"
product "$UNINSTALL_DISTRIBUTION" "$UNINSTALL_RESOURCES" "$UNINSTALL_COMPONENTS" "$UNINSTALL_NAME"
/bin/rm -rf "$BUILD"

if [[ "$PREVIEW" == true ]]; then
    /usr/bin/printf '\nPreview packages are ready. They are unsigned and only for checking the pages:\n%s\n%s\n\n' \
        "$DIST/$PACKAGE_NAME" "$DIST/$UNINSTALL_NAME"
    /usr/bin/open "$DIST/$PACKAGE_NAME"
    exit 0
fi

# Written from inside Release so the file lists bare names, which is what
# `shasum -c` expects when a person checks the downloads beside it.
(cd "$RELEASE" && /usr/bin/shasum -a 256 "$PACKAGE_NAME" "$UNINSTALL_NAME" > SHA256SUMS.txt)

/usr/bin/printf '\nRelease packages are ready in %s:\n%s\n%s\n\n' "$RELEASE" "$PACKAGE_NAME" "$UNINSTALL_NAME"
/usr/bin/printf 'Upload both packages and SHA256SUMS.txt to the GitHub release.\n'
/usr/bin/open "$RELEASE"
