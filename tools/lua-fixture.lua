-- Encodes a fixed frame with the addon's Encoding module and prints it as JSON,
-- so the helper's tests can check both sides agree on the strip format.
-- Usage (from the repo root): luajit tools/lua-fixture.lua > helper/Tests/StripKitTests/Fixtures/lua-frame.json
local ns = {}
assert(loadfile("addon/StreamDeckBars/Encoding.lua"))("StreamDeckBars", ns)
local E = ns.Encoding

local slots = {}
slots[1] = { icon = 136048, hasAction = true, usable = true, rangeApplies = true, inRange = true }
slots[2] = { icon = 134830, hasAction = true, usable = true, hasCount = true }
slots[5] = { icon = 135820, hasAction = true, noMana = true, glow = true }
slots[13] = { icon = 16777215, hasAction = true, rangeApplies = true }
slots[36] = { icon = 1, hasAction = true, usable = true, hasCount = true }
slots[48] = { icon = 136048, hasAction = true, glow = true }
slots[60] = { icon = 132794, hasAction = true, usable = true, hasCount = true }

local sequence, flags = 3001, E.globalFlags({ inCombat = true, bindingsApplied = true, countsSecret = true })
local symbols = E.buildFrame(sequence, flags, slots)

local function bool(v) return v and "true" or "false" end
local out = {}
out[#out + 1] = string.format('{\n  "sequence": %d,\n  "flags": %d,\n  "slots": [', sequence, flags)
for i = 1, E.SLOTS do
  local s = slots[i] or {}
  out[#out + 1] = string.format(
    '    {"icon": %d, "hasAction": %s, "usable": %s, "noMana": %s, "glow": %s, "rangeApplies": %s, "inRange": %s, "hasCount": %s}%s',
    s.icon or 0, bool(s.hasAction), bool(s.usable), bool(s.noMana), bool(s.glow),
    bool(s.rangeApplies), bool(s.rangeApplies and s.inRange), bool(s.hasCount), i < E.SLOTS and "," or "")
end
out[#out + 1] = '  ],\n  "symbols": [' .. table.concat(symbols, ", ") .. ']\n}'
print(table.concat(out, "\n"))
