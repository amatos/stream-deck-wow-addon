WOW_ADDONS ?= /Applications/World of Warcraft/_forever_/Interface/AddOns

.PHONY: addon-test addon-lint addon-install lint

# Minimum line coverage, in percent, that addon-test, helper-test and plugin-test enforce.
COVERAGE_MIN ?= 80

# Fails unless coverage $(1) (a percentage) is at least COVERAGE_MIN; $(2) names the component.
check_coverage = awk -v c="$(1)" -v min="$(COVERAGE_MIN)" -v name="$(2)" 'BEGIN { \
	if (c == "" || c + 0 < min + 0) { printf "%s line coverage %s%% is below %s%%\n", name, c, min; exit 1 } \
	printf "%s line coverage %s%% (minimum %s%%)\n", name, c, min }'

# busted, luacov and luacheck come from the Nix dev shell (`nix develop`).
addon-test:
	cd addon && rm -f luacov.stats.out luacov.report.out \
		&& busted --coverage && luacov \
		&& sed -n '/^Summary/,$$p' luacov.report.out
	@$(call check_coverage,$$(awk '/^Total/ { sub("%", "", $$4); print $$4 }' addon/luacov.report.out),Addon)

# Settings, including the WoW API globals the addon may use, are in addon/.luacheckrc.
addon-lint:
	cd addon && luacheck StreamDeckBars spec

lint: addon-lint helper-lint

# Copies the addon into the WoW Forever AddOns folder.
addon-install:
	mkdir -p "$(WOW_ADDONS)"
	rsync -a --delete addon/StreamDeckBars/ "$(WOW_ADDONS)/StreamDeckBars/"

.PHONY: helper-test helper-lint helper-app helper-run fixtures fixtures-check

HELPER_TEST_BINS = helper/.build/debug/StripKitTests.xctest/Contents/MacOS/StripKitTests \
	-object helper/.build/debug/IconKitTests.xctest/Contents/MacOS/IconKitTests \
	-object helper/.build/debug/DeckKitTests.xctest/Contents/MacOS/DeckKitTests

HELPER_COV_REPORT = xcrun llvm-cov report $(HELPER_TEST_BINS) -instr-profile helper/.build/debug/codecov/default.profdata \
	-ignore-filename-regex '(Tests|WoWBarsHelper|Vendor|\.build)/'

# Runs the helper's tests and reports StripKit, IconKit and DeckKit line coverage.
helper-test:
	cd helper && swift test --enable-code-coverage
	$(HELPER_COV_REPORT)
	@$(call check_coverage,$$($(HELPER_COV_REPORT) | awk '/^TOTAL/ { sub("%", "", $$10); print $$10 }'),Helper)

# Style settings are in .swift-format. Fix findings with `swift format -i -r -p $(SWIFT_SOURCES)`.
SWIFT_SOURCES = helper/Package.swift helper/Sources helper/Tests tools/app-icon.swift tools/plugin-images.swift

helper-lint:
	swift format lint --strict -r -p $(SWIFT_SOURCES)

# A stable identity keeps macOS permissions across rebuilds. Override with
# `make helper-app SIGN_IDENTITY=-` for ad-hoc signing. WoWBarsHelper.xcodeproj
# runs `make helper-app` with SIGN_IDENTITY from its Debug/Release build settings.
SIGN_IDENTITY ?= Apple Development: Alberth Matos (9X3H5J6MYQ)

helper-app:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" helper/scripts/bundle.sh

HELPER_ID = cc.matos.streamdeck.wowbars.helper

# Quits a running helper (waiting up to 5 s for it to exit), then launches the fresh build.
helper-run: helper-app
	@if pgrep -qf "WoW Bars Helper.app/Contents/MacOS/WoWBarsHelper"; then \
		echo "Quitting running helper"; \
		osascript -e 'tell application id "$(HELPER_ID)" to quit' >/dev/null 2>&1 || true; \
		for i in 1 2 3 4 5 6 7 8 9 10; do \
			pgrep -qf "WoW Bars Helper.app/Contents/MacOS/WoWBarsHelper" || break; sleep 0.5; \
		done; \
		if pgrep -qf "WoW Bars Helper.app/Contents/MacOS/WoWBarsHelper"; then \
			echo "Helper did not quit; stopping it"; pkill -f "WoW Bars Helper.app/Contents/MacOS/WoWBarsHelper"; sleep 0.5; \
		fi; \
	fi
	open "helper/build/WoW Bars Helper.app"

# Regenerates the Lua-encoded fixture the helper tests compare against.
fixtures:
	luajit tools/lua-fixture.lua > helper/Tests/StripKitTests/Fixtures/lua-frame.json

# Fails if the committed fixture no longer matches what the addon's encoder produces.
fixtures-check: fixtures
	@git diff --exit-code -- helper/Tests/StripKitTests/Fixtures/lua-frame.json \
		|| { echo "lua-frame.json is out of date; run make fixtures and commit it"; exit 1; }

.PHONY: plugin-test plugin-build plugin-validate plugin-install

SD_PLUGINS = $(HOME)/Library/Application Support/com.elgato.StreamDeck/Plugins
PLUGIN_DIR = plugin/cc.matos.streamdeck.wowbars.sdPlugin

plugin-test:
	cd plugin && npx tsc --noEmit && npx vitest run --coverage --coverage.thresholds.lines=$(COVERAGE_MIN)

plugin-build:
	cd plugin && npm run build

# Checks manifest.json against Elgato's schema. Needs the build, since it checks that CodePath exists.
plugin-validate: plugin-build
	cd plugin && npx streamdeck validate --no-update-check $(notdir $(PLUGIN_DIR))

# Links the plugin folder into Stream Deck (restart the Stream Deck app afterwards).
plugin-install: plugin-build
	ln -sfn "$(CURDIR)/$(PLUGIN_DIR)" "$(SD_PLUGINS)/cc.matos.streamdeck.wowbars.sdPlugin"

.PHONY: dist dist-check version-check dist-addon dist-plugin dist-helper set-version

# VERSION is the single source of the release version. Change it with `make set-version V=x.y.z`.
VERSION := $(shell cat VERSION)
TOC = addon/StreamDeckBars/StreamDeckBars.toc
DIST = $(CURDIR)/dist
DIST_IDENTITY ?= Developer ID Application
# Store the credentials once with: xcrun notarytool store-credentials wowbars-notary
NOTARY_PROFILE ?= wowbars-notary
# Set NOTARIZE=0 to skip notarization, e.g. for a local test of the packaging.
NOTARIZE ?= 1
DIST_APP = helper/build/dist/WoW Bars Helper.app

# Builds every artifact into dist/ for a release.
dist: dist-check dist-addon dist-plugin dist-helper
	@ls -1 "$(DIST)"

# Fails unless the addon .toc and plugin manifest match VERSION.
version-check:
	@grep -qx '## Version: $(VERSION)' $(TOC) && grep -q '"Version": "$(VERSION).0"' $(PLUGIN_DIR)/manifest.json \
		|| { echo "Versions don't match VERSION ($(VERSION)); run make set-version V=$(VERSION)"; exit 1; }
	@echo "Versions match $(VERSION)"

# Fails unless the addon, plugin manifest and working tree agree on what's being released.
dist-check: version-check
	@git diff --quiet HEAD -- addon helper plugin \
		|| echo "warning: addon/, helper/ or plugin/ has uncommitted changes"
	@rm -rf "$(DIST)" && mkdir -p "$(DIST)"

# Zip with the addon folder at the top, as WoW addon sites and manual installs expect.
# Packs a copy in addon/build/ so LICENSE can be added.
dist-addon:
	rm -rf addon/build && mkdir -p addon/build
	cp -R addon/StreamDeckBars addon/build/
	cp LICENSE addon/build/StreamDeckBars/
	cd addon/build && zip -qrX "$(DIST)/StreamDeckBars-$(VERSION).zip" StreamDeckBars -x '*.DS_Store'

# Writes V to VERSION, the addon .toc and the plugin manifest (which needs a 4-part version).
# Only the manifest's first "Version" is the plugin's; the later one is the Node.js version.
# The helper reads VERSION when it's built.
set-version:
	@echo "$(V)" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+' || { echo "Usage: make set-version V=x.y.z"; exit 1; }
	echo "$(V)" > VERSION
	sed 's/^## Version: .*/## Version: $(V)/' $(TOC) > $(TOC).tmp && mv $(TOC).tmp $(TOC)
	sed '1,/"Version":/s/^\([[:space:]]*"Version": "\)[^"]*"/\1$(V).0"/' $(PLUGIN_DIR)/manifest.json > $(PLUGIN_DIR)/manifest.json.tmp \
		&& mv $(PLUGIN_DIR)/manifest.json.tmp $(PLUGIN_DIR)/manifest.json

# Elgato's CLI validates the manifest and packs the .sdPlugin folder into an installer file.
# It rewrites manifest.json while packing, so it packs a copy in plugin/build/,
# with LICENSE and the bundled dependencies' licenses added.
dist-plugin: plugin-build
	rm -rf plugin/build && mkdir -p plugin/build
	cp -R $(PLUGIN_DIR) plugin/build/
	cp LICENSE plugin/build/cc.matos.streamdeck.wowbars.sdPlugin/
	node tools/third-party-licenses.mjs plugin > plugin/build/cc.matos.streamdeck.wowbars.sdPlugin/THIRD_PARTY_LICENSES
	cd plugin && npx streamdeck pack --no-update-check --force --no-file-list \
		--output "$(DIST)" build/cc.matos.streamdeck.wowbars.sdPlugin
	mv "$(DIST)/cc.matos.streamdeck.wowbars.streamDeckPlugin" \
		"$(DIST)/cc.matos.streamdeck.wowbars-$(VERSION).streamDeckPlugin"

# Signs with Developer ID and the hardened runtime, notarizes, staples, then zips with ditto
# so the bundle's signature and extended attributes survive.
dist-helper:
	BUILD_DIR=build/dist HARDENED=1 SIGN_IDENTITY="$(DIST_IDENTITY)" \
		helper/scripts/bundle.sh
	codesign --verify --strict --deep "$(DIST_APP)"
ifeq ($(NOTARIZE),1)
	ditto -c -k --keepParent "$(DIST_APP)" helper/build/dist/notarize.zip
	xcrun notarytool submit helper/build/dist/notarize.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DIST_APP)"
	spctl --assess --type execute "$(DIST_APP)"
endif
	ditto -c -k --keepParent "$(DIST_APP)" "$(DIST)/WoW-Bars-Helper-$(VERSION).zip"
