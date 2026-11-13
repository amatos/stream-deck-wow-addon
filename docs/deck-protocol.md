# Helper ↔ Stream Deck plugin protocol — version 1

The helper app runs a WebSocket server on `ws://127.0.0.1:47811` (loopback only). The Stream Deck plugin connects as a client and reconnects every 2 s while the helper is unavailable. Every message is a single JSON text frame with a `type` field.

## Helper → plugin

| Type | Fields | When |
|---|---|---|
| `hello` | `version`: protocol version (1) | First message on every connection |
| `slot` | `slot`: 0–59, `image`: PNG data URL (144 × 144) | After `hello`, once per slot that has an image; then whenever a slot's appearance changes |

Slots follow the strip format (docs/strip-format.md §5.1): 0–11 bar 1, 12–23 bar 2, 24–35 bar 3, 36–47 bar 4, 48–59 bar 5. The helper draws the whole key (icon, unusable dimming, not-enough-mana tint, proc-glow border, count); the plugin only displays it. Keys fade when the helper has no live data from the game.

## Plugin → helper

| Type | Fields | When |
|---|---|---|
| `press` | `slot`: 0–59 | A key showing that slot was pressed |

The helper sends that slot's keybind (§9) to the WoW process. Messages that do not parse, have an unknown `type`, or carry an out-of-range slot are ignored.
