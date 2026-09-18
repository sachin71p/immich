# Heirloom native app build + local dev server helpers.
# Run `make help` for a summary of targets.

NATIVE_DIR     := native-apple
DOCKER_DIR     := docker
DERIVED_DATA   := $(NATIVE_DIR)/.build/DerivedData
MODULE_CACHE   := $(NATIVE_DIR)/.build/clang-module-cache
SIMULATOR_NAME ?= iPhone 17 Pro Max
IOS_DEVICE      ?=
# Connected-device aliases. Pass a literal device name or UDID to IOS_DEVICE
# when working with a device not listed here.
IOS_DEVICE_spatel := 00008150-0002604111A1401C
IOS_DEVICE_bpatel := 00008150-00183958148B401C
IOS_DEVICE_UDID  := $(or $(IOS_DEVICE_$(IOS_DEVICE)),$(IOS_DEVICE))
IOS_BUNDLE_ID  := com.immich.heirloom.ios
SERVER_URL     := http://localhost:2283
DEVELOPMENT_TEAM ?= 599Z443923
export DEVELOPMENT_TEAM
# R0: install-macos used to build Debug (no -configuration), shipping an
# unoptimized bundle. Default to Release; developers can still opt into Debug.
CONFIGURATION ?= Release

.DEFAULT_GOAL := help

.PHONY: help xcodegen build-ios build-macos build-macos-debug check-ios-device install-ios install-macos \
        test-core test-macos-ui \
        mock-server mock-server-down mock-server-logs ios-sim clean

help:
	@echo "Heirloom native app targets:"
	@echo "  make build-ios          Build the iOS app for the Simulator"
	@echo "  make install-ios        Build, install, and launch the iOS app on a connected iPhone"
	@echo "  make build-macos        Build the macOS app (CONFIGURATION=$(CONFIGURATION), default Release)"
	@echo "  make build-macos-debug  Build the macOS app in Debug (developer iteration)"
	@echo "  make install-macos      Build and install the macOS app to /Applications"
	@echo "  make test-core          Run the PhotosCore SwiftPM test suite"
	@echo "  make test-macos-ui      Run the macOS UI tests in a Tart VM (RUN_ON_HOST=1 for host)"
	@echo "  make mock-server        Start the local Heirloom server via Docker (built from source)"
	@echo "  make mock-server-down   Stop the local Docker server"
	@echo "  make mock-server-logs   Tail the local server's logs"
	@echo "  make ios-sim            Start the mock server, build+install the iOS app, boot the Simulator"
	@echo "  make clean              Remove native-apple build output"
	@echo ""
	@echo "Override SIMULATOR_NAME=\"iPhone ...\" to target a different simulator."
	@echo "Use IOS_DEVICE=spatel or IOS_DEVICE=bpatel with install-ios."
	@echo "A literal iPhone name or UDID also works for IOS_DEVICE."

xcodegen:
	cd $(NATIVE_DIR) && xcodegen generate

# Building against a project-local derived data + module cache path mirrors
# native-apple/scripts/verify.sh so builds don't collide with Xcode's own cache.
build-ios: xcodegen
	@mkdir -p $(MODULE_CACHE)
	cd $(NATIVE_DIR) && CLANG_MODULE_CACHE_PATH="$$PWD/.build/clang-module-cache" xcodebuild \
		-project Heirloom.xcodeproj \
		-scheme Heirloom-iOS \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR_NAME)' \
		-derivedDataPath .build/DerivedData \
		-skipPackagePluginValidation \
		build

# Build a signed device bundle rather than the Simulator bundle produced by
# build-ios, then install and launch it using Xcode's CoreDevice CLI.  Building
# for a generic device keeps IOS_DEVICE usable as either an alias, a friendly
# device name, or a UDID when devicectl performs the install.
check-ios-device:
	@if [ -z "$(IOS_DEVICE)" ]; then echo "error: set IOS_DEVICE to a connected iPhone name or UDID (find it with: xcrun devicectl list devices)" >&2; exit 2; fi

install-ios: check-ios-device xcodegen
	@mkdir -p $(MODULE_CACHE)
	cd $(NATIVE_DIR) && CLANG_MODULE_CACHE_PATH="$$PWD/.build/clang-module-cache" xcodebuild \
		-project Heirloom.xcodeproj \
		-scheme Heirloom-iOS \
		-configuration Debug \
		-destination 'generic/platform=iOS' \
		-derivedDataPath .build/DerivedData \
		-skipPackagePluginValidation \
		-allowProvisioningUpdates \
		-allowProvisioningDeviceRegistration \
		build
	@set -e; \
	app="$(DERIVED_DATA)/Build/Products/Debug-iphoneos/Heirloom-iOS.app"; \
	if [ ! -d "$$app" ]; then echo "error: $$app not found after device build" >&2; exit 1; fi; \
	xcrun devicectl device install app --device "$(IOS_DEVICE_UDID)" "$$app"; \
	xcrun devicectl device process launch --device "$(IOS_DEVICE_UDID)" --terminate-existing $(IOS_BUNDLE_ID); \
	echo ""; \
	echo "Heirloom is running on $(IOS_DEVICE)."

# Uses the project's own (automatic) signing config, unlike verify.sh's ad-hoc
# CI build, so the installed app keeps its App Group entitlement and the
# share/widget/background-upload extensions keep working.
build-macos: xcodegen
	@mkdir -p $(MODULE_CACHE)
	cd $(NATIVE_DIR) && CLANG_MODULE_CACHE_PATH="$$PWD/.build/clang-module-cache" xcodebuild \
		-project Heirloom.xcodeproj \
		-scheme Heirloom-macOS \
		-configuration $(CONFIGURATION) \
		-destination 'platform=macOS' \
		-derivedDataPath .build/DerivedData \
		-skipPackagePluginValidation \
		-allowProvisioningUpdates \
		build

# Debug iteration build. `build-macos`/`install-macos` default to Release (R0);
# use this target when stepping through app code with the debugger.
build-macos-debug: xcodegen
	@$(MAKE) build-macos CONFIGURATION=Debug

install-macos: build-macos
	@app="$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/Heirloom-macOS.app"; \
	if [ ! -d "$$app" ]; then echo "error: $$app not found; run 'make build-macos CONFIGURATION=$(CONFIGURATION)' first" >&2; exit 1; fi; \
	echo "Quitting a running Heirloom instance (if any) before overwriting /Applications"; \
	osascript -e 'tell application id "com.immich.heirloom.macos" to quit' 2>/dev/null || true; \
	for i in 1 2 3; do pgrep -x Heirloom-macOS >/dev/null || break; sleep 1; done; \
	if pgrep -x Heirloom-macOS >/dev/null; then pkill -x Heirloom-macOS || true; sleep 1; fi; \
	echo "Installing $$app -> /Applications/Heirloom-macOS.app"; \
	rm -rf "/Applications/Heirloom-macOS.app"; \
	cp -R "$$app" /Applications/; \
	xattr -dr com.apple.quarantine "/Applications/Heirloom-macOS.app" 2>/dev/null || true; \
	open "/Applications/Heirloom-macOS.app"

test-core:
	swift test --package-path $(NATIVE_DIR)/PhotosCore

# macOS UI tests run isolated in a disposable Tart VM by default so the host
# desktop is never interrupted (see native-apple/scripts/run-macos-ui-tests.sh).
# RUN_ON_HOST=1 restores the legacy on-host xcodebuild run. ONLY_TESTING narrows
# the scope (space-separated); CONFIGURATION defaults to Debug in the runner.
# REMOTE=user@macbook2 builds here, tests in that Mac's Tart VM (same checkout path).
# GUEST defaults in the runner to the reserved-IP bridged VM (admin@192.168.4.58);
# override per-run with GUEST= / REMOTE=, opt out to a local disposable clone with TART_GUEST=.
ifeq ($(RUN_ON_HOST),1)
test-macos-ui: xcodegen
	@mkdir -p $(MODULE_CACHE)
	cd $(NATIVE_DIR) && CLANG_MODULE_CACHE_PATH="$$PWD/.build/clang-module-cache" xcodebuild test \
		-project Heirloom.xcodeproj \
		-scheme Heirloom-macOS \
		-configuration $(CONFIGURATION) \
		-destination 'platform=macOS' \
		-derivedDataPath .build/DerivedData \
		-skipPackagePluginValidation \
		-allowProvisioningUpdates \
		-only-testing:Heirloom-macOS-UITests
else
test-macos-ui:
	cd $(NATIVE_DIR) && ./scripts/run-macos-ui-tests.sh $(if $(REMOTE),--remote $(REMOTE)) $(if $(GUEST),--guest $(GUEST)) $(if $(FULL_DERIVED_DATA),--full-derived-data)
endif

$(DOCKER_DIR)/.env:
	cp $(DOCKER_DIR)/example.env $(DOCKER_DIR)/.env
	@echo "Created $(DOCKER_DIR)/.env from example.env (edit to customize)"

# docker-compose.dev.yml builds the server image from local source, so it
# reflects fork changes on this branch (docker-compose.yml just pulls the
# published release image, which would not include them).
mock-server: $(DOCKER_DIR)/.env
	docker compose -f $(DOCKER_DIR)/docker-compose.dev.yml up -d --build
	@echo "Heirloom server starting at $(SERVER_URL) (built from local source)"

mock-server-down:
	docker compose -f $(DOCKER_DIR)/docker-compose.dev.yml down

mock-server-logs:
	docker compose -f $(DOCKER_DIR)/docker-compose.dev.yml logs -f immich-server

# The Simulator shares the Mac's own network stack, so it reaches the
# Docker-published port at localhost directly (no 10.0.2.2-style indirection).
ios-sim: mock-server build-ios
	@udid=$$(xcrun simctl list devices available | awk -F '[()]' '/$(SIMULATOR_NAME)/ {print $$2; exit}'); \
	if [ -z "$$udid" ]; then echo "error: simulator '$(SIMULATOR_NAME)' not found; see 'xcrun simctl list devicetypes'" >&2; exit 1; fi; \
	open -a Simulator 2>/dev/null || open "$$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || open "$$(xcode-select -p)/../Applications/DeviceHub.app" 2>/dev/null || true; \
	xcrun simctl bootstatus "$$udid" -b; \
	app=$$(find $(DERIVED_DATA)/Build/Products -maxdepth 2 -iname 'Heirloom-iOS.app' -type d | head -1); \
	if [ -z "$$app" ]; then echo "error: Heirloom-iOS.app not found under $(DERIVED_DATA)/Build/Products" >&2; exit 1; fi; \
	xcrun simctl install "$$udid" "$$app"; \
	xcrun simctl launch "$$udid" $(IOS_BUNDLE_ID); \
	echo ""; \
	echo "Heirloom is running in the Simulator."; \
	echo "On the connect screen, enter server URL: $(SERVER_URL)"

clean:
	rm -rf $(NATIVE_DIR)/.build
