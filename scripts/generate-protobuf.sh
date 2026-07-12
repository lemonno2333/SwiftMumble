#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
workspace_root="${project_root:h}"
proto_root="${workspace_root}/upstream/mumble/src"
output_root="${project_root}/Sources/MumbleProtocol/Generated"

for tool in protoc protoc-gen-swift; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        print -u2 "Missing ${tool}. Install with: brew install protobuf swift-protobuf"
        exit 1
    fi
done

if [[ ! -f "${proto_root}/Mumble.proto" || ! -f "${proto_root}/MumbleUDP.proto" ]]; then
    print -u2 "Official Mumble protocol files were not found under ${proto_root}."
    exit 1
fi

mkdir -p "${output_root}"

protoc \
    --proto_path="${proto_root}" \
    --swift_out="${output_root}" \
    --swift_opt=Visibility=Public \
    "${proto_root}/Mumble.proto" \
    "${proto_root}/MumbleUDP.proto"

print "Generated Swift protocol types in ${output_root}"
