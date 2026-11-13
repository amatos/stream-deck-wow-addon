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
	-object helper/.build/debug/IconKitTests.xctest/Contents/MacOS/IconKitTests

# Runs the helper's tests and reports StripKit and IconKit line coverage.
helper-test:
	cd helper && swift test --enable-code-coverage
	xcrun llvm-cov report $(HELPER_TEST_BINS) -instr-profile helper/.build/debug/codecov/default.profdata \
		-ignore-filename-regex '(Tests|WoWBarsHelper|Vendor|\.build)/'

# A stable identity keeps macOS permissions across rebuilds. Override with
# `make helper-app SIGN_IDENTITY=-` for ad-hoc signing.
SIGN_IDENTITY ?= Apple Development: Alberth Matos (9X3H5J6MYQ)

helper-app:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" helper/scripts/bundle.sh

helper-run: helper-app
	open "helper/build/WoW Bars Helper.app"

# Regenerates the Lua-encoded fixture the helper tests compare against.
fixtures:
	luajit tools/lua-fixture.lua > helper/Tests/StripKitTests/Fixtures/lua-frame.json
