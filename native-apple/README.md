# Heirloom native Apple apps

The native clients target iOS 26.1+ and macOS 26+, with Swift 6 strict concurrency. Shared business logic
lives in `PhotosCore`; the two app targets are presentation shells.

## Build

1. Install Xcode 26 (including the iPhone 17 simulator) and select it with `xcode-select`.
2. Install XcodeGen: `brew install xcodegen`.
3. From the repository root, run `native-apple/scripts/verify.sh all`.

The verification script copies `open-api/immich-openapi-specs.json` into the generator target before building.
Extend `PhotosCore/Sources/ImmichAPI/openapi-generator-config.yaml` to expose further operations; generated API
types are the only server API types used by app code.
