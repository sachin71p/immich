#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-all}
simulator="iPhone 17"
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
  xcodebuild -project PhotosFork.xcodeproj -scheme PhotosFork-iOS -destination "platform=iOS Simulator,name=$simulator" build test
}

mac() {
  cd "$root"
  xcodegen generate
  xcodebuild -project PhotosFork.xcodeproj -scheme PhotosFork-macOS -destination 'platform=macOS' build test
}

case "$mode" in
  core) core ;;
  ios) ios ;;
  mac) mac ;;
  all) core; ios; mac ;;
  *) echo "usage: $0 [core|ios|mac|all]" >&2; exit 64 ;;
esac
