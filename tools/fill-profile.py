#!/usr/bin/env python3 -I
"""Fills a Stream Deck XL profile page with WoW Slot keys.

Layout (8 x 4 keys): bar 1 buttons 1-12 then bar 2 buttons 1-12 in reading
order across rows 1-3, and bar 3 buttons 1-8 across row 4 (the row holds 8 keys).

Usage: python3 -I tools/fill-profile.py <path to *.sdProfile> [page id]
Quit the Stream Deck app first; it rewrites profiles while running.
"""
import json
import pathlib
import sys
import uuid

PLUGIN = {"Name": "WoW Bars", "UUID": "cc.matos.streamdeck.wowbars", "Version": "0.1.0.0"}
ACTION_UUID = "cc.matos.streamdeck.wowbars.slot"
COLUMNS = 8
LAYOUT = [(1, b) for b in range(1, 13)] + [(2, b) for b in range(1, 13)] + [(3, b) for b in range(1, 9)]


def action(bar: int, button: int) -> dict:
    return {
        "ActionID": str(uuid.uuid4()),
        "LinkedTitle": True,
        "Name": "WoW Slot",
        "Plugin": PLUGIN,
        "Resources": None,
        "Settings": {"bar": str(bar), "button": str(button)},
        "State": 0,
        "States": [{"ShowTitle": False}],
        "UUID": ACTION_UUID,
    }


def main() -> None:
    profile = pathlib.Path(sys.argv[1])
    top = json.loads((profile / "manifest.json").read_text())
    page = sys.argv[2] if len(sys.argv) > 2 else top["Pages"]["Pages"][0]
    page_manifest = profile / "Profiles" / page.upper() / "manifest.json"
    m = json.loads(page_manifest.read_text())
    keypad = next(c for c in m["Controllers"] if c["Type"] == "Keypad")
    actions = keypad.get("Actions") or {}
    for i, (bar, button) in enumerate(LAYOUT):
        actions[f"{i % COLUMNS},{i // COLUMNS}"] = action(bar, button)
    keypad["Actions"] = actions
    page_manifest.write_text(json.dumps(m, separators=(",", ":")))
    print(f"Wrote {len(LAYOUT)} keys to {page_manifest}")


if __name__ == "__main__":
    main()
