# Strip Format — version 5

Version 5 draws counts in 7 px Friz Quadrata (version 4 used 12 px Arial Narrow), so the whole strip is 54 × 21 px plus 7 px per line of counts. Blocks are 1 px (since version 4) and the strip mirrors bars 1–5 in 60 slot records (since version 3).

Single source of truth for how the addon encodes action-bar state on screen and how the helper decodes it. The addon, helper and their tests all follow this document. Any change to the layout bumps the version.

## 1. Overview

The addon draws a small grid of solid-colour blocks (the **data grid**) and, directly beneath it, a row of digits (the **count area**). The helper captures the WoW window, locates the grid by its marker, and decodes it every capture frame.

## 2. Geometry

- **Pixel-perfect frame.** The strip's root frame ignores parent scale and sets its scale to `768 / physicalScreenHeight`, so 1 UI unit = 1 physical pixel of WoW's render output.
- **Block size `B` = 1 px.** This needs WoW's render output captured 1:1 (render scale 100%); scaling would blur neighbouring blocks together.
- **Padding.** A 2 px black border surrounds the whole strip, so window edges and rounded corners never blend into the outermost blocks.
- **Grid width `W` = 48 blocks** (48 px). Blocks are laid out row-major from the top-left; the grid is `ceil(N / W)` rows tall, where `N` is the symbol count (§4). Unused trailing blocks in the last row are black.
- **Anchor.** Top-left of the WoW window by default, offset (0, 0) to the outside of the padding. The position is a saved setting; the helper does not assume it and finds the strip by searching for the marker (§3.1).
- **Sampling.** The helper reads each block's single pixel. (For blocks of 2 px or more it averages the central 2×2 pixels; the decoder measures the block pitch from the marker.)

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

Symbols 0–3, fixed: levels (R,G,B) = `(3,0,3)`, `(0,3,0)`, `(0,3,3)`, `(3,3,0)` — magenta, green, cyan, yellow. Chosen to be unlikely in game art in that exact sequence. The decoder searches for this sequence, then confirms with the checksum.

### 3.2 Calibration

Symbols 4–7, fixed greys at levels 0, 1, 2, 3 (`(0,0,0)`, `(1,1,1)`, `(2,2,2)`, `(3,3,3)`). The decoder records the measured value of each level per channel and classifies every other block against those.

## 4. Symbol sequence

`N` = 374 symbols (8 grid rows).

| Index | Count | Field |
|---|---|---|
| 0–3 | 4 | Marker (§3.1) |
| 4–7 | 4 | Calibration (§3.2) |
| 8 | 1 | Format version = `5` |
| 9–10 | 2 | Sequence number, 12 bits, big-endian (symbol 9 = high 6 bits). Increments on every redraw, wraps at 4096. |
| 11 | 1 | Global flags (§4.1) |
| 12–371 | 360 | 60 slot records × 6 symbols (§5) |
| 372–373 | 2 | Checksum (§6) |

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
| 36–47 | Bar 4 | 25–36 | `MultiBarRightButton1`–`12` | `BT4Button25`–`36` |
| 48–59 | Bar 5 | 37–48 | `MultiBarLeftButton1`–`12` | `BT4Button37`–`48` |

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

Fletcher-style over symbols 8–371 (version through the last slot record), each symbol `s` in 0–63:

```
a = 0; b = 0
for each s: a = (a + s) mod 64; b = (b + a) mod 64
symbol 372 = a, symbol 373 = b
```

The decoder discards any frame whose checksum does not match (for example a frame captured mid-redraw) and keeps the last good state.

## 7. Count area

Counts can be secret in combat, so they are drawn as text rather than encoded.

- **Position.** Starts 2 px below the bottom of the data grid, left-aligned with it; 50 px wide.
- **Font.** `Fonts\FRIZQT__.TTF`, 7 px, flags `MONOCHROME` (no anti-aliasing), white `(255,255,255)` on black. Glyphs are therefore pixel-exact and repeatable. Measured in game: at 7 px the digits are 5 px tall, 1–4 px wide, always separated by a blank column, and the two most similar digits differ by 5 px; repeated lines render identically. 6 px merges neighbouring digits, and Arial Narrow keeps only 1–2 px between some digits at 7–10 px.
- **Reference line.** The first line shows the fixed string `0123456789`. The decoder segments it into ten glyph templates at runtime, so it does not depend on font rendering details or resolution.
- **Count cells.** Following lines contain one cell per slot whose *has count* bit is set, in slot order. The k-th cell belongs to the k-th slot with that bit set. Cells are 25 px wide (room for 5 digits), 2 per line, left-aligned text, line height 7 px.
- **Decoding.** Within a cell, the decoder splits glyphs on empty pixel columns and matches each against the templates, accepting the closest template that differs by at most 2 px (or 5% of the glyph area, if larger). An empty cell, or one that fails to match, is treated as "count unknown" and the last good value is kept.
- **Cell count.** Lines only exist for the cells needed, so the area is just the reference line when no slot has a count.

## 8. Redraw

- The addon redraws at most 20 times per second, and only when something changed or 1 s has passed (a heartbeat, so the helper can tell the addon is alive).
- Counts are written by passing the value straight to `FontString:SetText`, which accepts secret values (verified in game: counts update in combat).

## 9. Keybinds

The addon applies these as priority override bindings. The helper sends the same keys.

- **Blizzard bars:** bound to WoW's own action-bar commands (`ACTIONBUTTON1`–`12`, `MULTIACTIONBAR1BUTTON1`–`12`, `MULTIACTIONBAR2BUTTON1`–`12`, `MULTIACTIONBAR3BUTTON1`–`12`, `MULTIACTIONBAR4BUTTON1`–`12`), so bar 1 follows paging exactly as the default keys do.
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
| 4 | none | none |
| 5 | `META-` | Command |

Bar 4 uses the bare keypad keys: the user has no physical keypad, so they cannot be pressed by accident. Bar 5 uses Command, the only modifier left that WoW does not use for self-cast or other modified clicks. Verified in game: WoW on macOS accepts Command as `META` for bar 5.

Verified in game: WoW on macOS maps `CTRL` to the Control key. The helper sends each key as modifier-down, key-down, key-up, modifier-up events posted directly to the WoW process, with the numeric-pad flag set on the key events.

## 10. Open items to verify in game

1. ~~`FontString:SetText` accepts a secret count (§8).~~ Verified.
2. ~~`CTRL` modifier mapping on macOS (§9).~~ Verified: Control key; all three bars fire.
3. Proc glow detection returns `true` while a glow is showing (§5.2 bit 8). Needs a proc ability.
4. ~~`META` (Command) bindings for bar 5 (§9).~~ Verified: bar 5 fires.
5. ~~1 px blocks decode in game (§2).~~ Verified: the helper connects at block pitch 1.0.
6. ~~7 px Friz Quadrata counts read correctly (§7).~~ Verified in game.

Also verified in game (version 1): the grid renders pixel-exact at 4 px blocks with exact level values, and the count digits render as pure black and white glyphs matching the reference line.
