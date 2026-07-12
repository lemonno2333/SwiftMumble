#!/bin/zsh

# Build, Developer ID sign, notarize, staple, and package SwiftMumble as a DMG.
#
# This produces a distributable, notarized .app inside a .dmg. It requires an
# Apple Developer account and cannot run in an environment without one.
#
# Required environment variables:
#   DEVELOPER_ID_APP   "Developer ID Application: Name (TEAMID)" signing identity.
#   NOTARY_PROFILE     Name of a stored notarytool keychain profile, created with:
#                        xcrun notarytool store-credentials <profile> \
#                          --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>
#
# Usage: ./scripts/release-app.sh

set -euo pipefail

project_root="${0:A:h:h}"
cd "${project_root}"

configuration="release"
app_name="SwiftMumble"
binary_path=".build/arm64-apple-macosx/${configuration}/${app_name}"
app_path=".build/${configuration}/${app_name}.app"
entitlements="AppBundle/${app_name}.entitlements"
dmg_path=".build/${configuration}/${app_name}.dmg"

if [[ -z "${DEVELOPER_ID_APP:-}" ]]; then
    print -u2 "Set DEVELOPER_ID_APP to your 'Developer ID Application' signing identity."
    exit 1
fi
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    print -u2 "Set NOTARY_PROFILE to a stored notarytool keychain profile name."
    exit 1
fi

print "Building ${configuration} (arm64)..."
swift build -c "${configuration}" --arch arm64

if [[ ! -f "${binary_path}" ]]; then
    print -u2 "Missing ${binary_path} after build."
    exit 1
fi

print "Assembling ${app_path}..."
rm -rf "${app_path}"
mkdir -p "${app_path}/Contents/MacOS"
mkdir -p "${app_path}/Contents/Resources"
cp AppBundle/Info.plist "${app_path}/Contents/Info.plist"
for localization in AppBundle/*.lproj; do
    [[ -d "${localization}" ]] || continue
    cp -R "${localization}" "${app_path}/Contents/Resources/"
done
cp "${binary_path}" "${app_path}/Contents/MacOS/${app_name}"
resource_bundle=".build/arm64-apple-macosx/${configuration}/${app_name}_SwiftMumbleApp.bundle"
if [[ -d "${resource_bundle}" ]]; then
    cp -R "${resource_bundle}" "${app_path}/Contents/Resources/"
fi
if [[ -d AppBundle/mumble.icon ]]; then
    icon_build_dir="$(mktemp -d)"
    xcrun actool AppBundle/mumble.icon \
        --compile "${icon_build_dir}" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon mumble \
        --output-partial-info-plist "${icon_build_dir}/Info.plist" >/dev/null
    cp "${icon_build_dir}/Assets.car" "${app_path}/Contents/Resources/Assets.car"
    cp "${icon_build_dir}/mumble.icns" "${app_path}/Contents/Resources/mumble.icns"
    rm -rf "${icon_build_dir}"
fi
chmod 755 "${app_path}/Contents/MacOS/${app_name}"

print "Signing with Hardened Runtime..."
# Sign nested resource bundles first, then the app itself, inside-out.
find "${app_path}/Contents/Resources" -name "*.bundle" -type d 2>/dev/null | while read -r bundle; do
    codesign --force --options runtime --timestamp \
        --sign "${DEVELOPER_ID_APP}" "${bundle}"
done
codesign --force --options runtime --timestamp \
    --entitlements "${entitlements}" \
    --sign "${DEVELOPER_ID_APP}" "${app_path}"
codesign --verify --strict --verbose=2 "${app_path}"

print "Creating ${dmg_path}..."
rm -f "${dmg_path}"
hdiutil create -volname "${app_name}" \
    -srcfolder "${app_path}" \
    -ov -format UDZO "${dmg_path}"

print "Submitting to notary service (this can take a few minutes)..."
xcrun notarytool submit "${dmg_path}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

print "Stapling notarization ticket..."
xcrun stapler staple "${dmg_path}"
xcrun stapler validate "${dmg_path}"

print "Created notarized ${dmg_path}"
