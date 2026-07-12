#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
vendor_root="${project_root}/Vendor/RNNoise"
output_path="${vendor_root}/RNNoise.xcframework"
source_commit="70f1d256acd4b34a572f999a05c87bf00b67730d"
model_sha256="0a8755f8e2d834eff6a54714ecc7d75f9932e845df35f8b59bc52a7cfe6e8b37"
work_root="${TMPDIR:-/tmp}/native-mumble-rnnoise.$$"
source_root="${work_root}/rnnoise"
install_root="${work_root}/install"

trap 'rm -rf "${work_root}"' EXIT
mkdir -p "${work_root}" "${install_root}/include" "${install_root}/lib" "${work_root}/objects"

git clone -q https://github.com/xiph/rnnoise.git "${source_root}"
git -C "${source_root}" checkout -q "${source_commit}"
model_archive="${work_root}/rnnoise-data.tar.gz"
curl -sS -L "https://media.xiph.org/rnnoise/models/rnnoise_data-${model_sha256}.tar.gz" -o "${model_archive}"
actual_sha256="$(shasum -a 256 "${model_archive}" | awk '{print $1}')"
[[ "${actual_sha256}" == "${model_sha256}" ]] || { print -u2 "RNNoise model checksum mismatch."; exit 1; }
tar -xzf "${model_archive}" -C "${source_root}"

sources=(denoise rnn pitch kiss_fft celt_lpc nnet nnet_default parse_lpcnet_weights rnnoise_data rnnoise_tables)
for source in "${sources[@]}"; do
    xcrun clang -c "${source_root}/src/${source}.c" \
        -o "${work_root}/objects/${source}.o" \
        -O3 -DNDEBUG -arch arm64 -mmacosx-version-min=14.0 \
        -I"${source_root}/include" -I"${source_root}/src"
done
xcrun libtool -static -o "${install_root}/lib/librnnoise.a" "${work_root}"/objects/*.o
cp "${source_root}/include/rnnoise.h" "${install_root}/include/"
cp "${vendor_root}/module.modulemap" "${install_root}/include/"
cp "${source_root}/COPYING" "${vendor_root}/COPYING"
rm -rf "${output_path}"
xcodebuild -create-xcframework \
    -library "${install_root}/lib/librnnoise.a" \
    -headers "${install_root}/include" \
    -output "${output_path}"

print "Created ${output_path}"
