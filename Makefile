APP_NAME   := 3MF Preview
BUILD_DIR  := build
APP        := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
INSTALL_TO := /Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
XCODEBUILD := xcodebuild -project 3MFPreview.xcodeproj -scheme 3MFPreview -derivedDataPath $(BUILD_DIR)

.PHONY: build test install uninstall project fixtures render-test clean

build:
	$(XCODEBUILD) -configuration Release build

test:
	$(XCODEBUILD) -configuration Debug test

install: build
	rm -rf "$(INSTALL_TO)/$(APP_NAME).app"
	ditto "$(APP)" "$(INSTALL_TO)/$(APP_NAME).app"
	$(LSREGISTER) -f "$(INSTALL_TO)/$(APP_NAME).app"
	open -g "$(INSTALL_TO)/$(APP_NAME).app"
	qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1
	@echo "Installed. Select a .3mf in Finder and press Space."

uninstall:
	-osascript -e 'quit app "$(APP_NAME)"' >/dev/null 2>&1
	-$(LSREGISTER) -u "$(INSTALL_TO)/$(APP_NAME).app"
	rm -rf "$(INSTALL_TO)/$(APP_NAME).app"
	qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1

# Regenerate 3MFPreview.xcodeproj from project.yml (needs `brew install xcodegen`).
project:
	xcodegen generate

# Rebuild the small 3MF files the unit tests read.
fixtures:
	python3 -I Tests/Fixtures/make_fixtures.py

# Command-line renderer: prints parse stats and writes PNG renders.
# Usage: make render-test && build/render-test out/ model.3mf ...
render-test:
	mkdir -p $(BUILD_DIR)
	swiftc -O -o $(BUILD_DIR)/render-test Shared/*.swift Tools/main.swift

clean:
	rm -rf $(BUILD_DIR)
