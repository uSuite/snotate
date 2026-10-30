# sNotate build entry points. Every command a session needs is a target here.

VERSION := $(shell cat VERSION)
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
PREFIX ?= $(HOME)/.local
CLT := /Library/Developer/CommandLineTools

# Use Xcode when it is usable (licence accepted), else fall back to the
# Command Line Tools, whose Swift Testing macros need an explicit plugin path.
XCODE_OK := $(shell xcrun swift --version >/dev/null 2>&1 && echo yes)
ifeq ($(XCODE_OK),yes)
SWIFT := swift
TEST_FLAGS :=
else
SWIFT := DEVELOPER_DIR=$(CLT) swift
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(CLT)/usr/lib/swift/host/plugins/testing
endif
XCODEGEN := $(shell command -v xcodegen 2>/dev/null)

.PHONY: gen build app run smoke activate hostile bench idle export install icon cheatsheet screenshots release notarize cask test test-common coverage golden fixtures clean version

gen:
	@test -n "$(XCODEGEN)" || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
	xcodegen generate

build:
	$(SWIFT) build

# swift test does not run a dependency's tests, so the shared code's run first
# when it is checked out beside this repository.
test: test-common
	$(SWIFT) test $(TEST_FLAGS)

test-common:
	@if [ -f ../scommon/Package.swift ]; then $(MAKE) -C ../scommon test; else echo "test-common: no ../scommon, its tests run in its own repository"; fi

coverage:
	$(SWIFT) test $(TEST_FLAGS) --enable-code-coverage
	scripts/coverage.sh

# Rewrites fixtures/golden/ from the current renderer; only when a rendering
# change is intended, then review the images and run make test.
golden:
	SNOTATE_GOLDEN=1 $(SWIFT) test $(TEST_FLAGS)

# Xcode path when Xcode and XcodeGen are both usable, otherwise an SPM build
# wrapped into a bundle by scripts/bundle.sh. Both produce build/sNotate.app.
app:
ifeq ($(XCODE_OK)$(if $(XCODEGEN),yes,),yesyes)
	xcodegen generate
	xcodebuild -project sNotate.xcodeproj -scheme sNotate -configuration Debug \
		-destination "platform=macOS,arch=$(shell uname -m)" \
		-derivedDataPath build/DerivedData \
		MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) build
	rm -rf build/sNotate.app
	cp -R build/DerivedData/Build/Products/Debug/sNotate.app build/sNotate.app
else
	SWIFT="$(SWIFT)" VERSION=$(VERSION) BUILD_NUMBER=$(BUILD_NUMBER) scripts/bundle.sh
endif

run: app
	open -n build/sNotate.app --args "$(CURDIR)/fixtures/poc-sample-vm-migrate"

smoke: app
	scripts/smoke.sh

activate: app
	scripts/activate.sh

# Hostile fixtures in build/hostile (SN-605), then the activation check.
hostile: app
	scripts/hostile.sh

# Performance targets (SN-606), one line appended to bench/RESULTS.md.
bench: app
	scripts/bench.sh

# Idle CPU and leaks after editing (SN-606).
idle: app
	scripts/idle.sh

# Every annotated case under a PoC root, or one case: make export ROOT=<path>.
export: app
	@test -n "$(ROOT)" || { echo "usage: make export ROOT=<poc-root or case folder>"; exit 2; }
	build/sNotate.app/Contents/MacOS/sNotate --export "$(ROOT)"

fixtures:
	rm -rf fixtures/poc-sample-vm-migrate fixtures/poc-sample-vm-scale
	xcrun swift scripts/make-fixtures.swift fixtures

# The app icon from the brand SVGs (SN-604), and the flat PNG for the README.
icon:
	xcrun swift scripts/make-icon.swift build/AppIcon.iconset brand/snotate-1024.png
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

# docs/keys.md from the built-in keymap; a test fails when it is stale.
cheatsheet:
	$(SWIFT) run -q snotate-cheatsheet > docs/keys.md

# README screenshots from the fixtures, into docs/images.
screenshots: app
	scripts/screenshots.sh

# Universal Release app and zip in build/release (SN-604), ad hoc signed
# unless DEVELOPER_ID is set; notarize signs, submits and staples; cask fills
# the Homebrew cask from the zip.
release:
	scripts/release.sh

notarize:
	scripts/notarize.sh

cask:
	scripts/cask.sh

# The snotate launcher (SN-602), linked into $(PREFIX)/bin.
install:
	mkdir -p "$(PREFIX)/bin"
	ln -sf "$(CURDIR)/scripts/snotate" "$(PREFIX)/bin/snotate"
	@echo "installed $(PREFIX)/bin/snotate"

clean:
	rm -rf .build build sNotate.xcodeproj

version:
	@echo $(VERSION)
