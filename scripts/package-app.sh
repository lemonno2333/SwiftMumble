#!/bin/zsh

set -euo pipefail

configuration="${1:-debug}"
app_name="SwiftMumble"
binary_path=".build/arm64-apple-macosx/${configuration}/${app_name}"
app_path=".build/${configuration}/${app_name}.app"
icon_source="AppBundle/mumble.icon"

if [[ ! -f "${binary_path}" ]]; then
    print -u2 "Missing ${binary_path}. Run swift build first."
    exit 1
fi

mkdir -p "${app_path}/Contents/MacOS"
mkdir -p "${app_path}/Contents/Resources"
cp AppBundle/Info.plist "${app_path}/Contents/Info.plist"
for localization in AppBundle/*.lproj; do
    [[ -d "${localization}" ]] || continue
    cp -R "${localization}" "${app_path}/Contents/Resources/"
done
cp "${binary_path}" "${app_path}/Contents/MacOS/${app_name}"
resource_bundle=".build/arm64-apple-macosx/${configuration}/SwiftMumble_SwiftMumbleApp.bundle"
if [[ -d "${resource_bundle}" ]]; then
    rm -rf "${app_path}/Contents/Resources/SwiftMumble_SwiftMumbleApp.bundle"
    cp -R "${resource_bundle}" "${app_path}/Contents/Resources/"
fi
if [[ -d "${icon_source}" ]]; then
    icon_build_dir="$(mktemp -d)"
    xcrun actool "${icon_source}" \
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

# A stable code-signing identity keeps the app's designated requirement stable.
# Ad-hoc signatures are based on a changing cdhash, which makes Keychain ask for
# client-certificate private-key access again after every rebuild.
signing_identity="${SWIFTMUMBLE_SIGN_IDENTITY:-}"
if [[ -z "${signing_identity}" ]]; then
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi
if [[ -n "${signing_identity}" ]]; then
    codesign --force --sign "${signing_identity}" \
        --entitlements AppBundle/SwiftMumble.entitlements \
        --options runtime \
        "${app_path}"
else
    codesign --force --sign - "${app_path}"
fi

print "Created ${app_path} (${signing_identity:-ad-hoc})"
