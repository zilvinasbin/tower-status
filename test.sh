#!/bin/zsh
# Runs unit tests. Uses Xcode's toolchain when installed; with only Command Line
# Tools, SwiftPM doesn't find the swift-testing macro plugin, so point at it.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -z "${DEVELOPER_DIR:-}" && -d "$PLUGINS" ]]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS"
else
    swift test
fi
