# Strip Format — version 1

Single source of truth for how the addon encodes action-bar state on screen and how the helper decodes it. The addon, helper and their tests all follow this document. Any change to the layout bumps the version.

## 1. Overview

The addon draws a small grid of solid-colour blocks (the **data grid**) and, directly beneath it, a row of digits (the **count area**). The helper captures the WoW window, locates the grid by its marker, and decodes it every capture frame.

## 2. Geometry

- **Pixel-perfect frame.** The strip's root frame ignores parent scale and sets its scale to `768 / physicalScreenHeight`, so 1 UI unit = 1 physical pixel of WoW's render output.
- **Block size `B` = 4 px** (square).
- **Grid width `W` = 48 blocks** (192 px). Blocks are laid out row-major from the top-left; the grid is `ceil(N / W)` rows tall, where `N` is the symbol count (§4). Unused trailing blocks in the last row are black.
- **Anchor.** Top-left of the WoW window by default, offset (0, 0). The position is a saved setting; the helper does not assume it and finds the strip by searching for the marker (§3.1).
- **Sampling.** The helper reads the average of the central 2×2 pixels of each block, so edge blur from scaling up to ~1.5× is tolerated.

## 3. Symbols

Each block carries one **symbol** of 6 bits: 2 bits per colour channel, using four levels.

| Level | Nominal 8-bit value |
|---|---|
| 0 | 0 |
| 1 | 85 |
| 2 | 170 |
| 3 | 255 |

Symbol value = `R_level << 4 | G_level << 2 | B_level`.

Displays, colour profiles and capture can shift these values, so the decoder never uses fixed thresholds. It classifies each channel to the nearest **calibration** level measured in the header (§3.2), per channel.

### 3.1 Marker

Symbols 0–3, fixed: levels (R,G,B) = `(3,0,3)`, `(0,3,0)`, `(0,3,3)`, `(3,3,0)` — magenta, green, cyan, yellow. Chosen to be unlikely in game art in that exact sequence. The decoder searches for this sequence on 4-px boundaries, then confirms with the checksum.

### 3.2 Calibration

Symbols 4–7, fixed greys at levels 0, 1, 2, 3 (`(0,0,0)`, `(1,1,1)`, `(2,2,2)`, `(3,3,3)`). The decoder records the measured value of each level per channel and classifies every other block against those.

## 4. Symbol sequence

`N` = 230 symbols.

| Index | Count | Field |
|---|---|---|
| 0–3 | 4 | Marker (§3.1) |
| 4–7 | 4 | Calibration (§3.2) |
| 8 | 1 | Format version = `1` |
| 9–10 | 2 | Sequence number, 12 bits, big-endian (symbol 9 = high 6 bits). Increments on every redraw, wraps at 4096. |
| 11 | 1 | Global flags (§4.1) |
| 12–227 | 216 | 36 slot records × 6 symbols (§5) |
| 228–229 | 2 | Checksum (§6) |

### 4.1 Global flags (symbol 11)

| Bit | Meaning |
|---|---|
| 0 | Player is in combat |
| 1 | Keybinds are applied |
| 2 | Keybinds are pending (waiting for combat to end) |
| 3 | Counts are secret this frame (counts come only from the count area) |
| 4–5 | Reserved, 0 |

## 5. Slot records

### 5.1 Slot order

| Slots | Bar | Action slots | Blizzard buttons | Bartender4 buttons |
|---|---|---|---|---|
| 0–11 | Bar 1 (main) | 1–12, paged | `ActionButton1`–`12` | `BT4Button1`–`12` |
| 12–23 | Bar 2 | 61–72 | `MultiBarBottomLeftButton1`–`12` | `BT4Button61`–`72` |
| 24–35 | Bar 3 | 49–60 | `MultiBarBottomRightButton1`–`12` | `BT4Button49`–`60` |

Bar numbers are as Blizzard's Edit Mode and Bartender4's WoW 10 layout label them. (Bartender4 stores bars 2 and 3 internally as bars 6 and 5, which is why its buttons are numbered from 61 and 49.)

Each slot always describes the action currently on that button, so bar 1 follows stance, form and bonus-bar paging. The addon uses the Bartender4 buttons when Bartender4 is loaded, otherwise Blizzard's (`/sdb layout` overrides this).

### 5.2 Record layout

6 symbols = 36 bits, big-endian across symbols (first symbol holds bits 35–30).

| Bits | Field |
|---|---|
| 35–12 | Icon file ID (24 bits). `0` = no icon. |
| 11 | Has action |
| 10 | Usable |
| 9 | Not enough mana / power |
| 8 | Proc glow active |
| 7 | Range applies (the action has a range and there is a target) |
| 6 | In range (meaningful only when bit 7 is set) |
| 5 | Has count (the button would show a count or charges) |
| 4–0 | Reserved, 0 |

## 6. Checksum

Fletcher-style over symbols 8–227 (version through the last slot record), each symbol `s` in 0–63:

```
a = 0; b = 0
for each s: a = (a + s) mod 64; b = (b + a) mod 64
symbol 228 = a, symbol 229 = b
```

The decoder discards any frame whose checksum does not match (for example a frame captured mid-redraw) and keeps the last good state.

## 7. Count area

Counts can be secret in combat, so they are drawn as text rather than encoded.

- **Position.** Starts one block (4 px) below the bottom of the data grid, left-aligned with it; same width as the grid (192 px).
- **Font.** `Fonts\ARIALN.TTF`, 12 px, flags `MONOCHROME` (no anti-aliasing), white `(255,255,255)` on black. Glyphs are therefore pixel-exact and repeatable.
- **Reference line.** The first line shows the fixed string `0123456789`. The decoder segments it into ten glyph templates at runtime, so it does not depend on font rendering details or resolution.
- **Count cells.** Following lines contain one cell per slot whose *has count* bit is set, in slot order. The k-th cell belongs to the k-th slot with that bit set. Cells are 32 px wide, 6 per line, left-aligned text, line height 14 px.
- **Decoding.** Within a cell, the decoder splits glyphs on empty pixel columns and matches each against the templates. An empty cell, or one that fails to match, is treated as "count unknown" and the last good value is kept.
- **Cell count.** Lines only exist for the cells needed, so the area is just the reference line when no slot has a count.

## 8. Redraw

- The addon redraws at most 20 times per second, and only when something changed or 1 s has passed (a heartbeat, so the helper can tell the addon is alive).
- Counts are written by passing the value straight to `FontString:SetText`, which accepts secret values (verified in game: counts update in combat).

## 9. Keybinds

The addon applies these as priority override bindings. The helper sends the same keys.

- **Blizzard bars:** bound to WoW's own action-bar commands (`ACTIONBUTTON1`–`12`, `MULTIACTIONBAR1BUTTON1`–`12`, `MULTIACTIONBAR2BUTTON1`–`12`), so bar 1 follows paging exactly as the default keys do.
- **Bartender4:** bound as clicks on the `BT4Button`s in §5.1 with LibActionButton's `Keybind` button, the same way Bartender4 binds its own keys.

`ALT` is never used: it is WoW's default self-cast modifier, so holding it would self-cast friendly spells. Macros that test `[mod:ctrl]` or `[mod:shift]` will see the modifier held.

| Button | Key | macOS virtual keycode |
|---|---|---|
| 1 | `NUMPAD1` | `0x53` |
| 2 | `NUMPAD2` | `0x54` |
| 3 | `NUMPAD3` | `0x55` |
| 4 | `NUMPAD4` | `0x56` |
| 5 | `NUMPAD5` | `0x57` |
| 6 | `NUMPAD6` | `0x58` |
| 7 | `NUMPAD7` | `0x59` |
| 8 | `NUMPAD8` | `0x5B` |
| 9 | `NUMPAD9` | `0x5C` |
| 10 | `NUMPAD0` | `0x52` |
| 11 | `NUMPADDIVIDE` | `0x4B` |
| 12 | `NUMPADMULTIPLY` | `0x43` |

| Bar | WoW modifier prefix | macOS modifier flags |
|---|---|---|
| 1 | `CTRL-SHIFT-` | Control + Shift |
| 2 | `CTRL-` | Control |
| 3 | `SHIFT-` | Shift |

Whether WoW on macOS maps `CTRL` to the Control key or the Command key is to be verified in game during the helper's keypress step; this table is updated then.

## 10. Open items to verify in game

1. ~~`FontString:SetText` accepts a secret count (§8).~~ Verified.
2. `CTRL` modifier mapping on macOS (§9). Tested once the helper sends keys.
3. Proc glow detection returns `true` while a glow is showing (§5.2 bit 8). Needs a proc ability.

Also verified in game: the grid renders pixel-exact at 4 px blocks with exact level values, and the count digits render as pure black and white glyphs matching the reference line.
