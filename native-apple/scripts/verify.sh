#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-all}
simulator="${SIMULATOR_NAME:-iPhone 17 Pro Max}"
module_cache="$root/.build/clang-module-cache"
mkdir -p "$module_cache"
export CLANG_MODULE_CACHE_PATH="$module_cache"

core() {
  "$root/scripts/gen-api.sh"
  cd "$root/PhotosCore"
  swift build
  swift test
}

ios() {
  cd "$root"
  "$root/scripts/gen-api.sh"
  xcodegen generate
  xcodebuild -project Heirloom.xcodeproj -scheme Heirloom-iOS -destination "platform=iOS Simulator,name=$simulator" -skipPackagePluginValidation build test
}

mac_prepare() {
  cd "$root"
  "$root/scripts/gen-api.sh"
  xcodegen generate
}

# Extra xcodebuild args (e.g. -only-testing:... test) pass through as "$@".
# (Flags stay inline: extracting the CODE_SIGN_* assignments into a variable
# would pass literal quote characters into the build settings.)
mac_build_cmd() {
  xcodebuild -project Heirloom.xcodeproj -scheme Heirloom-macOS -destination 'platform=macOS' \
    -skipPackagePluginValidation CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_ENTITLEMENTS="" DEVELOPMENT_TEAM="" "$@"
}

mac() {
  mac_prepare
  mac_build_cmd build test
}

# WP-T T1+T2: hosted macOS unit tests (fixture, gestures, snapshots).
mac_unit() {
  mac_prepare
  mac_build_cmd -only-testing:Heirloom-macOS-Tests test
}

# WP-T T0: XCUITest on the sized fixture (small).
mac_ui() {
  mac_prepare
  mac_build_cmd -only-testing:Heirloom-macOS-UITests test
}

# WP-T T6: perf scaffolding on the large fixture. Owner's Mac only; baselines
# live in the scheme's .xcbaseline. Fails on median regression > 10% (WP-X §2).
mac_perf() {
  mac_prepare
  mac_build_cmd -only-testing:Heirloom-macOS-UITests/HeirloomPerfTests test
}

case "$mode" in
  core) core ;;
  ios) ios ;;
  mac) mac ;;
  mac-unit) mac_unit ;;
  mac-ui) mac_ui ;;
  mac-perf) mac_perf ;;
  all) core; ios; mac ;;
  *) echo "usage: $0 [core|ios|mac|mac-unit|mac-ui|mac-perf|all]" >&2; exit 64 ;;
esac
