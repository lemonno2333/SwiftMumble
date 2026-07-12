#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
vendor_root="${project_root}/Vendor/Opus"
output_path="${vendor_root}/Opus.xcframework"
opus_version="1.6.1"
opus_sha256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"
work_root="${TMPDIR:-/tmp}/native-mumble-opus.$$"
archive_path="${work_root}/opus.tar.gz"
source_root="${work_root}/opus-${opus_version}"
install_root="${work_root}/install"

trap 'rm -rf "${work_root}"' EXIT

mkdir -p "${work_root}"
curl -sS -L \
    "https://downloads.xiph.org/releases/opus/opus-${opus_version}.tar.gz" \
    -o "${archive_path}"

actual_sha256="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${opus_sha256}" ]]; then
    print -u2 "Opus archive checksum mismatch."
    exit 1
fi

tar -xzf "${archive_path}" -C "${work_root}"

cd "${source_root}"
MACOSX_DEPLOYMENT_TARGET=14.0 \
CFLAGS="-O3 -arch arm64 -mmacosx-version-min=14.0" \
LDFLAGS="-arch arm64 -mmacosx-version-min=14.0" \
./configure \
    --prefix="${install_root}" \
    --disable-shared \
    --enable-static \
    --disable-extra-programs \
    --disable-doc
make -j"$(sysctl -n hw.logicalcpu)"
make install

mkdir -p "${install_root}/include"
cp "${project_root}/Vendor/Opus/module.modulemap" "${install_root}/include/module.modulemap"
cp "${source_root}/COPYING" "${vendor_root}/COPYING"
rm -rf "${output_path}"

xcodebuild -create-xcframework \
    -library "${install_root}/lib/libopus.a" \
    -headers "${install_root}/include" \
    -output "${output_path}"

print "Created ${output_path}"
