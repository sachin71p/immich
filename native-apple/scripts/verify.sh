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
  xcodegen generate
  xcodebuild -project Heirloom.xcodeproj -scheme Heirloom-iOS -destination "platform=iOS Simulator,name=$simulator" -skipPackagePluginValidation build test
}

mac() {
  cd "$root"
  if [ "${RUN_ON_HOST:-0}" = "1" ]; then
    xcodegen generate
    xcodebuild -project Heirloom.xcodeproj -scheme Heirloom-macOS -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" CODE_SIGN_ENTITLEMENTS="" DEVELOPMENT_TEAM="" build test
  else
    # Default: isolated Tart VM run (host desktop untouched).
    "$root/scripts/run-macos-ui-tests.sh"
  fi
}

case "$mode" in
  core) core ;;
  ios) ios ;;
  mac) mac ;;
  all) core; ios; mac ;;
  *) echo "usage: $0 [core|ios|mac|all]" >&2; exit 64 ;;
esac
