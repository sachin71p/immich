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

## macOS UI tests (isolated via Tart)

`Heirloom-macOS-UITests` runs in a disposable Tart VM by default, so your desktop is never interrupted and the
host needs no Accessibility/Screen Recording grants for the app under test:

1. One-time setup (installs Tart, pulls the macOS 27 beta + Xcode image, builds a golden VM):
   `native-apple/scripts/tart-setup.sh`. On the VM host, boot bridged once
   (`tart run --net-bridged=en0 <vm>`, reserved DHCP IP) and install this host's key
   (`cat ~/.ssh/heirloom-tart.pub | ssh admin@<vm-ip> 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'`).
2. Run all macOS UI tests: `make test-macos-ui` (defaults to the reserved-IP guest `admin@192.168.4.58`).
3. Narrow the scope: `make test-macos-ui ONLY_TESTING="Heirloom-macOS-UITests/MacSmokeTests/testLaunchMakesMainWindowAccessible"`
4. On-host escape hatch (old behavior): `make test-macos-ui RUN_ON_HOST=1`
5. Alternatives: `GUEST=admin@<other-ip>` to target another booted VM, `REMOTE=user@macbook2` for a
   fresh disposable clone on a 2nd Mac (same absolute checkout path required), `TART_GUEST=` (empty) to
   opt out to a local disposable clone. The persistent guest keeps state between runs; prefer REMOTE
   (fresh clone) for clean gates.

How it works: the host builds (`build-for-testing`, ad-hoc signed — fresh VMs Gatekeeper-reject team
signatures; `--team-signing` restores automatic signing), syncs DerivedData to the same absolute path in the guest,
runs `xcodebuild test-without-building` there, and copies the `.xcresult` back to
`native-apple/.build/tart-results/<timestamp>/`. The throwaway VM is deleted afterwards; the golden image stays.

Expectations: ~60 GB free (image + 140 GB virtual disk + ~0.65 GB first sync of Build/Products,
then incremental rsync deltas), Apple Silicon host.
Troubleshooting: VM won't boot (check `tart list`, free disk, rerun setup); SSH never comes up (golden needs
Remote Login + the setup SSH key — rerun `tart-setup.sh`); guest signing errors (host build uses the Makefile
`DEVELOPMENT_TEAM`, same as before); missing `.xcresult` after failure (see `guest-xcodebuild.log` next to it).
