# Stream Deck Bars for World of Warcraft

Mirrors World of Warcraft action bars 1–5 on an Elgato Stream Deck (macOS only) and presses them in game. Each Stream Deck key shows a live action button, with its icon, usability, not-enough-mana tint, proc glow and item count, and pressing the key fires that button in WoW.

WoW addons cannot talk to other programs, so data moves through the screen and the keyboard:

```
                                         WoW Bars Helper (macOS app)
 World of Warcraft                    (windows app coming eventually)             Stream Deck app
┌──────────────────────┐   screen      ┌────────────────────────────┐  WebSocket  ┌─────────────────┐
│ StreamDeckBars addon │──capture────▶ │ decode strip → render keys │───────────▶ │ WoW Bars plugin │
│ draws a pixel strip  │               │ ws://127.0.0.1:47811       │             │ (one key / slot)│
│ + override keybinds  │ ◀──keypress── │ send slot's keybind to WoW │ ◀────────── │ key pressed     │
└──────────────────────┘               └────────────────────────────┘             └─────────────────┘
```

1. The **addon** reads bars 1–5 every frame and encodes their state into a tiny grid of coloured pixels (the _strip_) in the corner of the WoW window. It also binds each button to a fixed key combination on the numeric keypad.
2. The **helper** captures the WoW window with ScreenCaptureKit, finds and decodes the strip, extracts the button icons from the local WoW install, and draws a 144 × 144 image for each key.
3. The **plugin** shows those images on Stream Deck keys. When a key is pressed it tells the helper, and the helper posts that button's keybind directly to the WoW process.

## Repository layout

| Path                                                                                          | What it is                                                                                                                       |
| --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| [`addon/StreamDeckBars/`](addon/StreamDeckBars)                                               | The WoW addon (Lua).                                                                                                             |
| [`addon/spec/`](addon/spec)                                                                   | Addon unit tests (busted), with a WoW API mock in `wowmock.lua`.                                                                 |
| [`helper/`](helper)                                                                           | The macOS helper app (Swift package, macOS 15+).                                                                                 |
| [`helper/scripts/bundle.sh`](helper/scripts/bundle.sh)                                        | Builds and signs `WoW Bars Helper.app`.                                                                                          |
| [`helper/Vendor/CascLib/`](helper/Vendor/CascLib)                                             | Vendored [CascLib](https://github.com/ladislav-zezula/CascLib) (MIT) for reading WoW's game files. See `VERSION` for the commit. |
| [`plugin/`](plugin)                                                                           | The Stream Deck plugin (TypeScript, Stream Deck SDK v3).                                                                         |
| [`plugin/cc.matos.streamdeck.wowbars.sdPlugin/`](plugin/cc.matos.streamdeck.wowbars.sdPlugin) | The plugin bundle the Stream Deck app loads: manifest, images, property inspector, and built code in `bin/`.                     |
| [`docs/strip-format.md`](docs/strip-format.md)                                                | Spec of the on-screen strip and the keybinds. It's the source of truth for both the addon and the helper.                        |
| [`docs/deck-protocol.md`](docs/deck-protocol.md)                                              | Spec of the helper ↔ plugin WebSocket protocol.                                                                                  |
| [`tools/`](tools)                                                                             | Scripts that generate the icons, test fixtures and Stream Deck profiles.                                                         |
| [`Makefile`](Makefile)                                                                        | Entry point for building, testing and installing everything.                                                                     |
| [`WoWBarsHelper.xcodeproj`](WoWBarsHelper.xcodeproj)                                          | Xcode wrapper that builds the helper app through `make` (see [Xcode](#building-from-xcode)).                                     |

### Addon — `addon/StreamDeckBars/`

| File                 | Role                                                                                                                        |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `StreamDeckBars.toc` | Addon manifest. Settings are saved in `StreamDeckBarsDB`.                                                                   |
| `Encoding.lua`       | Pure encoding of the strip format: symbols, slot records, checksum. Uses no WoW API, and `tools/lua-fixture.lua` reuses it. |
| `Layout.lua`         | Maps bars 1–5 to button frames for Blizzard's bars and for Bartender4.                                                      |
| `State.lua`          | Reads action-bar state from the WoW API, coping with "secret" values that WoW hides during combat.                          |
| `Bindings.lua`       | Applies the override keybinds.                                                                                              |
| `Strip.lua`          | Draws the pixel-exact data grid and the count digits.                                                                       |
| `Core.lua`           | Events, the redraw loop (at most 20/s, plus a 1 s heartbeat) and the `/sdb` slash command.                                  |

### Helper — `helper/Sources/`

| Module          | Role                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `StripKit`      | Locates, samples and decodes the strip, reads count digits, and maps slots to keys. Uses no AppKit.                      |
| `CascBridge`    | CascLib plus a small C bridge for opening the WoW install's storage.                                                     |
| `IconKit`       | Finds the WoW install, reads icon files by FileDataID, decodes BLP textures, and caches them as PNGs.                    |
| `DeckKit`       | Renders Stream Deck key images and the plugin protocol messages.                                                         |
| `WoWBarsHelper` | The app: window capture, WebSocket server, key sending, and the settings window. It can sit in the Dock or the menu bar. |

Extracted icons are cached in `~/Library/Caches/cc.matos.streamdeck.wowbars.helper/icons/`, with one folder per client version.

### Plugin — `plugin/src/`

| File                                    | Role                                                                              |
| --------------------------------------- | --------------------------------------------------------------------------------- |
| `plugin.ts`                             | Entry point: registers the action and connects to the helper.                     |
| `helper-client.ts`                      | WebSocket client. Reconnects every 2 s while the helper is unavailable.           |
| `protocol.ts`                           | Message parsing and serialisation.                                                |
| `actions/slot.ts`, `slot-controller.ts` | The **WoW Slot** action. Each key mirrors one bar/button.                         |
| `slots.ts`                              | Converts bar/button settings to strip slots.                                      |
| `inspector.ts`, `inspector-entry.ts`    | The property inspector (choose a bar and button), bundled into `ui/inspector.js`. |

## Prerequisites

| For         | Needs                                                                                                                    |
| ----------- | ------------------------------------------------------------------------------------------------------------------------ |
| Helper      | macOS 15+, Xcode / Swift 6 toolchain, and a code-signing identity in your keychain (see [Signing](#signing-the-helper)). |
| Plugin      | Node.js 24 and npm. Stream Deck app 7.1+.                                                                                |
| Addon tests | LuaJIT with busted and luacov.                                                                                           |
| Running it  | World of Warcraft with render scale at 100%. The strip uses 1 px blocks and must be captured 1:1.                        |

The Nix flake provides Node.js 24, LuaJIT with busted and luacov, and Python. Enter it with `nix develop`, or run `direnv allow` once to load it automatically. Xcode isn't provided by the flake: the shell uses the system Xcode for `swift`, `xcrun` and `codesign`.

> [!NOTE]
> **Without Nix**, install Xcode from the App Store, then the rest with Homebrew and LuaRocks:
>
> ```bash
> brew install node@24 luajit luarocks python
> luarocks --lua-version 5.1 --local install busted LUA_INCDIR="$(brew --prefix luajit)/include/luajit-2.1"
> luarocks --lua-version 5.1 --local install luacov
> ```
>
> `node@24` is keg-only, and `make addon-test` expects `busted` and `luacov` on your `PATH`, so add this to your shell profile:
>
> ```bash
> export PATH="$(brew --prefix node@24)/bin:$PATH"
> eval "$(luarocks --lua-version 5.1 --local path)"
> ```

## Building the artifacts

All commands run from the repository root.

### WoW addon

The addon needs no build step. To copy it into WoW's AddOns folder:

```bash
make addon-install
```

By default it installs into `/Applications/World of Warcraft/_forever_/Interface/AddOns`. To use another WoW flavour or install location, override `WOW_ADDONS`:

```bash
make addon-install WOW_ADDONS="/Applications/World of Warcraft/_retail_/Interface/AddOns"
```

### Helper app

```bash
make helper-app
```

This builds `WoWBarsHelper` in release mode, assembles `helper/build/WoW Bars Helper.app` (Info.plist and icon), signs it with `SIGN_IDENTITY`, and registers it with Launch Services. To build and then (re)launch it:

```bash
make helper-run
```

If a copy is already running, it's quit first.

On first launch, grant the two permissions shown in its window: **Screen Recording**, to see the WoW window, and **Accessibility**, to send keys to WoW.

#### Signing the helper

macOS ties those permissions to the app's code signature. The Makefile therefore signs with a stable identity, set by `SIGN_IDENTITY` in the [`Makefile`](Makefile). To list the identities available to you:

```bash
security find-identity -v -p codesigning
```

To override the identity for a single build:

```bash
make helper-app SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
```

To sign ad-hoc, with no certificate, use `SIGN_IDENTITY=-`. macOS will then ask for both permissions again after every rebuild. Switching to a different certificate also counts as a new app, so you'll need to grant the permissions again.

#### Building from Xcode

`WoWBarsHelper.xcodeproj` has one External Build System target that runs `make helper-app SIGN_IDENTITY="$(SIGN_IDENTITY)"`. Choose the certificate per configuration under **Build Settings → User-Defined → SIGN_IDENTITY**:

- **Debug** (Build/Run) uses the Apple Development identity.
- **Release** (Archive) uses the Developer ID Application identity.

Build output, including `swift build` and `codesign` errors, appears in Xcode's build log. Clean only clears Xcode's DerivedData, not `helper/build/`. Run (⌘R) doesn't launch the app, so use `make helper-run` for that.

To work on the Swift code itself with indexing, debugging and tests, open `helper/Package.swift` in Xcode instead.

### Stream Deck plugin

The first time, install the plugin's npm dependencies:

```bash
cd plugin && npm install
```

Then build the plugin:

```bash
make plugin-build
```

This bundles `src/plugin.ts` into `cc.matos.streamdeck.wowbars.sdPlugin/bin/plugin.js` and the property inspector into `ui/inspector.js`. To link the plugin folder into the Stream Deck app (restart the app afterwards):

```bash
make plugin-install
```

The link points at the repository, so later `make plugin-build` runs take effect after a Stream Deck restart.

Then, in the Stream Deck app, drag **WoW Bars → WoW Slot** onto a key and choose its bar and button.

#### Filling a Stream Deck XL profile

Instead of setting up 32 keys by hand, `tools/fill-profile.py` can fill a profile page for you. It lays out bar 1 buttons 1–12, then bar 2 buttons 1–12, then bar 3 buttons 1–8. Quit the Stream Deck app first, because it rewrites profiles while running:

```bash
python3 -I tools/fill-profile.py ~/Library/Application\ Support/com.elgato.StreamDeck/ProfilesV3/<profile>.sdProfile
```

### Generated assets

These files are committed. You only need to regenerate them after changing the script that produces them.

| Asset                                                                            | Command                                                                            |
| -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Helper app icon `helper/Resources/AppIcon.icns`                                  | See the two commands below.                                                        |
| Plugin images `plugin/…sdPlugin/imgs/*.png`                                      | `swift tools/plugin-images.swift plugin/cc.matos.streamdeck.wowbars.sdPlugin/imgs` |
| Cross-language test fixture `helper/Tests/StripKitTests/Fixtures/lua-frame.json` | `make fixtures` (needs `luajit`). Rerun it whenever `Encoding.lua` changes.        |

To regenerate the app icon, draw the iconset and then convert it:

```bash
swift tools/app-icon.swift /tmp/AppIcon.iconset
```

```bash
iconutil -c icns /tmp/AppIcon.iconset -o helper/Resources/AppIcon.icns
```

## Packaging a release

`make dist` builds all three artifacts into `dist/`:

| File                                                     | Contents                                                                                           |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `StreamDeckBars-<version>.zip`                           | The addon folder. Unzip into `Interface/AddOns`.                                                   |
| `cc.matos.streamdeck.wowbars-<version>.streamDeckPlugin` | The plugin. Double-click to install it in the Stream Deck app.                                     |
| `WoW-Bars-Helper-<version>.zip`                          | The helper app, signed with Developer ID, notarized and stapled so Gatekeeper opens it on any Mac. |

The version lives in the top-level `VERSION` file. To change it, run `make set-version V=x.y.z`: it updates `VERSION`, `## Version` in `StreamDeckBars.toc`, and the plugin manifest's `Version` (`x.y.z.0`). The helper reads `VERSION` when it's built. `make dist` stops if the `.toc` or the manifest doesn't match `VERSION`. The helper is built into `helper/build/dist/`, so it doesn't replace your development build.

Notarization needs App Store Connect credentials stored in your keychain once:

```bash
xcrun notarytool store-credentials wowbars-notary
```

`DIST_IDENTITY` (default `Developer ID Application`) and `NOTARY_PROFILE` (default `wowbars-notary`) override the signing identity and the keychain profile. To check the packaging without notarizing, run `make dist NOTARIZE=0`.

## Testing

To run the addon tests with a coverage summary (inside the Nix shell):

```bash
make addon-test
```

To run the helper tests and report coverage for StripKit, IconKit and DeckKit:

```bash
make helper-test
```

To typecheck the plugin and run its tests with coverage:

```bash
make plugin-test
```

`lua-frame.json` is produced by the addon's encoder and decoded by the helper's tests, so the two sides can't drift apart on the strip format.

## Using it in game

The addon draws the strip at the top-left of the WoW window and binds the keys on login. Use `/sdb` to control it:

| Command                                 | Effect                                                                       |
| --------------------------------------- | ---------------------------------------------------------------------------- |
| `/sdb` or `/sdb status`                 | Shows the layout, strip position, keybind state and sequence number.         |
| `/sdb pos <x> <y>`                      | Moves the strip, in pixels from the window's top-left.                       |
| `/sdb show`, `/sdb hide`                | Shows or hides the strip.                                                    |
| `/sdb bind`                             | Reapplies the keybinds. Changes made in combat are applied when combat ends. |
| `/sdb keys`                             | Lists every bar/button keybind.                                              |
| `/sdb layout auto\|blizzard\|bartender` | Chooses which bar addon to read. Supports Blizzard's bars and Bartender4.    |

Bars use keypad keys 1–9, 0, `/` and `*`, with Ctrl+Shift for bar 1, Ctrl for bar 2, Shift for bar 3, no modifier for bar 4 and Command for bar 5. Alt is never used because it's WoW's self-cast modifier. The full table is in [docs/strip-format.md §9](docs/strip-format.md#9-keybinds).

Any change to the strip layout must update [docs/strip-format.md](docs/strip-format.md), bump its version, and change both `Encoding.lua` and `StripKit`, then regenerate the fixture.

## Windows port (`windows-helper` branch)

The [`windows-helper`](../../tree/windows-helper) branch ports the macOS helper app to Windows 11. It also changes the addon where the port needs it, for example keybinds that work with the Windows client. [`the-plan.md`](../../blob/windows-helper/the-plan.md) on that branch describes the approach.

> [!WARNING]
> The Windows port is a **work in progress** and of **alpha quality**. It's a lower priority than `main` and will likely lag behind it. Use `main` for the supported macOS version.

## License

BSD 2-Clause. See [LICENSE](LICENSE). CascLib is MIT-licensed. See [helper/Vendor/CascLib/LICENSE](helper/Vendor/CascLib/LICENSE).
