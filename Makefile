# Heirloom native app build + local dev server helpers.
# Run `make help` for a summary of targets.

NATIVE_DIR     := native-apple
DOCKER_DIR     := docker
DERIVED_DATA   := $(NATIVE_DIR)/.build/DerivedData
MODULE_CACHE   := $(NATIVE_DIR)/.build/clang-module-cache
SIMULATOR_NAME ?= iPhone 17 Pro Max
IOS_BUNDLE_ID  := com.immich.heirloom.ios
SERVER_URL     := http://localhost:2283
DEVELOPMENT_TEAM ?= XS724Y6X3U
export DEVELOPMENT_TEAM

.DEFAULT_GOAL := help

.PHONY: help xcodegen build-ios build-macos install-macos \
        mock-server mock-server-down mock-server-logs ios-sim clean

help:
	@echo "Heirloom native app targets:"
	@echo "  make build-ios          Build the iOS app for the Simulator"
	@echo "  make build-macos        Build the macOS app"
	@echo "  make install-macos      Build and install the macOS app to /Applications"
	@echo "  make mock-server        Start the local Heirloom server via Docker (built from source)"
	@echo "  make mock-server-down   Stop the local Docker server"
	@echo "  make mock-server-logs   Tail the local server's logs"
	@echo "  make ios-sim            Start the mock server, build+install the iOS app, boot the Simulator"
	@echo "  make clean              Remove native-apple build output"
	@echo ""
	@echo "Override SIMULATOR_NAME=\"iPhone ...\" to target a different simulator."

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

# Uses the project's own (automatic) signing config, unlike verify.sh's ad-hoc
# CI build, so the installed app keeps its App Group entitlement and the
# share/widget/background-upload extensions keep working.
build-macos: xcodegen
	@mkdir -p $(MODULE_CACHE)
	cd $(NATIVE_DIR) && CLANG_MODULE_CACHE_PATH="$$PWD/.build/clang-module-cache" xcodebuild \
		-project Heirloom.xcodeproj \
		-scheme Heirloom-macOS \
		-destination 'platform=macOS' \
		-derivedDataPath .build/DerivedData \
		-skipPackagePluginValidation \
		-allowProvisioningUpdates \
		build

install-macos: build-macos
	@app=$$(find $(DERIVED_DATA)/Build/Products -maxdepth 2 -iname 'Heirloom-macOS.app' -type d | head -1); \
	if [ -z "$$app" ]; then echo "error: Heirloom-macOS.app not found under $(DERIVED_DATA)/Build/Products" >&2; exit 1; fi; \
	echo "Installing $$app -> /Applications/Heirloom-macOS.app"; \
	rm -rf "/Applications/Heirloom-macOS.app"; \
	cp -R "$$app" /Applications/; \
	xattr -dr com.apple.quarantine "/Applications/Heirloom-macOS.app" 2>/dev/null || true; \
	open "/Applications/Heirloom-macOS.app"

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
