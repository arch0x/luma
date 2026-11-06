#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"

# Some CLI toolchains need the Swift Testing macro plugin passed explicitly.
swiftc_path="$(xcrun --find swiftc)"
testing_plugin="${swiftc_path:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
test_swift_flags=()
if [[ -f "$testing_plugin" ]]; then
    test_swift_flags+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test --cache-path /private/tmp/luma-swift-cache "${test_swift_flags[@]}" "$@"
