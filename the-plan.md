# Porting WoW Bars Helper to Windows 11

> **Status:** work in progress, alpha quality. This branch is a lower priority than `main` and will likely lag behind it.

This branch ports the macOS helper app (`helper/`) to Windows 11 and changes the addon where the port needs it. The decoding core can be reused, but everything that talks to the operating system has to be replaced: screen capture, key sending, key rendering, the WebSocket server and the UI. Two things should be checked in game first, because they may force keybind changes: bar 5's Command (`META-`) binding, and how Windows handles Shift with keypad keys.

## What carries over

| Part | Status on Windows |
|---|---|
| `StripKit` (finding and decoding the strip, reading counts, key map data) | Pure Swift with no Apple frameworks. Builds with the Swift toolchain for Windows, tests included. |
| `IconKit`: `BLP.swift` and the `.build.info` parsing | Portable. |
| CascLib | Builds natively on Windows. The vendored copy relies on the system `libz`, which Windows doesn't have, so zlib must be added (CascLib's upstream bundles one; it was left out when vendoring). |
| Stream Deck plugin | Works as is. Add `{"Platform": "windows", "MinimumVersion": "10"}` to `manifest.json`. The protocol on `127.0.0.1:47811` doesn't change. |
| Addon | Unchanged except for the keybinds (see [Strip format and keybinds](#strip-format-and-keybinds)). |

## What has to be replaced

| macOS piece (where it lives) | Windows replacement |
|---|---|
| ScreenCaptureKit (`WindowCapture.swift`) | **Windows.Graphics.Capture**: a capture item created from WoW's window handle, with a Direct3D 11 frame pool in BGRA8. The frame layout matches what `PixelSource` already reads. Set `IsBorderRequired = false` to hide the yellow capture border. It can't capture exclusive fullscreen, so WoW must run windowed or borderless. |
| Posting key events straight to the WoW process (`KeySender.swift`) | **No direct equivalent.** `SendInput` only reaches the foreground window, and WoW tends to ignore `PostMessage(WM_KEYDOWN)` because it reads raw input. Pressing keys while WoW is in the background will probably stop working, and the helper would have to bring WoW to the front. Windows also limits when an app may take focus, so that needs testing. |
| CoreGraphics and CoreText for drawing keys (`KeyFace.swift`, `Emblem.swift`) | Direct2D with DirectWrite, or a portable rasteriser. Another option is to draw the keys in the plugin, using Node with a canvas library. That would also remove this code from the macOS version, but it changes the protocol. |
| ImageIO for writing PNGs (`IconStore.swift`) | WIC (Windows Imaging Component), or a small PNG writer using the zlib added for CascLib. |
| Network.framework WebSocket server (`DeckServer.swift`) | A WebSocket server built on http.sys, a small one hand-written over Winsock, or SwiftNIO (its Windows support is still incomplete). |
| SwiftUI and AppKit UI, with the Dock/menu bar choice (`MainView.swift`, `AppDelegate.swift`) | A WinUI 3 or plain Win32 window, plus a system tray icon instead of the Dock/menu bar choice. |
| Locating the WoW install (`WoWInstall.swift`) | Find it from the running `Wow.exe` (`QueryFullProcessImageName`), falling back to `C:\Program Files (x86)\World of Warcraft\`. The flavour folders and `.build.info` are the same as on macOS. |
| Icon cache under `~/Library/Caches/…` | `%LOCALAPPDATA%\…` |
| Screen Recording and Accessibility permissions | Nothing to grant. The macOS signing problem, where a new certificate resets permissions, doesn't exist on Windows. |

## Strip format and keybinds

- **Bar 5 uses `META-` (the Command key).** WoW for Windows has no Command key and, as far as we know, doesn't support the Windows key as a binding modifier. Bar 5 needs a different key on Windows, for example `CTRL-SHIFT-` with F13–F24, or other keys that aren't on the keypad. The addon would choose the binding at runtime with `IsMacClient()`. Both [docs/strip-format.md](docs/strip-format.md) §9 and `KeyMap` need a Windows column.
- **Shift with keypad keys:** when Num Lock is on, Windows turns Shift+Numpad1 into End, and so on. That affects bar 1 (`CTRL-SHIFT-`) and bar 3 (`SHIFT-`). Sending scan codes through `SendInput` might avoid this, but it needs checking in game first because it could force new keys for bars 1 and 3.
- **HDR and Auto HDR** can shift the colours captured from the strip. The per-channel calibration should handle a small shift, but this should be tested on an HDR monitor.

## Build, packaging and tooling

- **Language:** stay with Swift and keep `StripKit` and `IconKit` shared between the macOS and Windows versions. Put the Windows calls (capture, input, Direct2D, http.sys) behind a small C/C++ bridge target, the same pattern `CascBridge` already uses. Swift's own bindings for WinRT are still immature. Rewriting the app shell in C#/.NET would be easier, but then the decoder would exist twice, and the Lua fixture test only protects the Swift version.
- **Build scripts:** the `Makefile` and `helper/scripts/bundle.sh` depend on a Unix shell and on `codesign`. Windows needs PowerShell scripts, or CMake.
- **Packaging and signing:** distribute as MSIX or a plain `.exe` with an installer, signed with an Authenticode certificate. Without a signature, SmartScreen shows a warning when users run it.
- **`tools/fill-profile.py`:** on Windows, profiles are in `%APPDATA%\Elgato\StreamDeck\ProfilesV3`.

## Order of work

The biggest jobs are capture and key sending, then the WebSocket server, key rendering and the UI.

1. **Spike:** capture WoW with Windows.Graphics.Capture, decode the strip with `StripKit`, and press a bar 1 key with `SendInput` while WoW is in front. This settles the two riskiest questions: whether key sending works acceptably, and whether the Shift and keypad keybinds work on Windows.
2. **Keybinds:** choose the Windows keys for bar 5, and for bars 1 and 3 if the spike shows they're needed. Update `docs/strip-format.md` §9, `Bindings.lua`, `KeyMap`, and their tests.
3. **Core on Windows:** build `StripKit`, `IconKit` and CascLib (with zlib) on Windows, and get their tests passing.
4. **Platform layer:** capture, key sending, the WebSocket server, key rendering and PNG writing.
5. **App shell:** the window, the tray icon, and finding the WoW install.
6. **Plugin and packaging:** the Windows entry in the plugin manifest, build scripts, an installer and signing.
