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
