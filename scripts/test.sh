#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
args=(--disable-sandbox)
compiler="$(xcrun --find swiftc)"
plugin="${compiler:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$plugin" ]]; then
  args+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
fi
swift test --package-path "$root" "${args[@]}"
swift test --package-path "$root/Packages/WeMacroDOF" "${args[@]}"
