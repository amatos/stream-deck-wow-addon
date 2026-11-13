LUAROCKS := luarocks --lua-version 5.1 --tree $(CURDIR)/.luarocks
WOW_ADDONS ?= /Applications/World of Warcraft/_forever_/Interface/AddOns

.PHONY: addon-deps addon-test addon-install

# Installs busted and luacov into ./.luarocks (needs LuaJIT headers).
addon-deps:
	$(LUAROCKS) install busted LUA_INCDIR=$$(dirname $$(dirname $$(readlink -f $$(command -v luajit))))/include/luajit-2.1
	$(LUAROCKS) install luacov

addon-test:
	cd addon && eval "$$($(LUAROCKS) path)" && rm -f luacov.stats.out luacov.report.out \
		&& ../.luarocks/bin/busted --coverage && ../.luarocks/bin/luacov \
		&& sed -n '/^Summary/,$$p' luacov.report.out

# Copies the addon into the WoW Forever AddOns folder.
addon-install:
	mkdir -p "$(WOW_ADDONS)"
	rsync -a --delete addon/StreamDeckBars/ "$(WOW_ADDONS)/StreamDeckBars/"

.PHONY: helper-test helper-app helper-run fixtures

HELPER_TEST_BINS = helper/.build/debug/StripKitTests.xctest/Contents/MacOS/StripKitTests \
	-object helper/.build/debug/IconKitTests.xctest/Contents/MacOS/IconKitTests \
	-object helper/.build/debug/DeckKitTests.xctest/Contents/MacOS/DeckKitTests

# Runs the helper's tests and reports StripKit, IconKit and DeckKit line coverage.
helper-test:
	cd helper && swift test --enable-code-coverage
	xcrun llvm-cov report $(HELPER_TEST_BINS) -instr-profile helper/.build/debug/codecov/default.profdata \
		-ignore-filename-regex '(Tests|WoWBarsHelper|Vendor|\.build)/'

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

.PHONY: plugin-test plugin-build plugin-install

SD_PLUGINS = $(HOME)/Library/Application Support/com.elgato.StreamDeck/Plugins
PLUGIN_DIR = plugin/cc.matos.streamdeck.wowbars.sdPlugin

plugin-test:
	cd plugin && npx tsc --noEmit && npx vitest run --coverage

plugin-build:
	cd plugin && npm run build

# Links the plugin folder into Stream Deck (restart the Stream Deck app afterwards).
plugin-install: plugin-build
	ln -sfn "$(CURDIR)/$(PLUGIN_DIR)" "$(SD_PLUGINS)/cc.matos.streamdeck.wowbars.sdPlugin"
