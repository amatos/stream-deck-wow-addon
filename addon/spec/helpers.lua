-- Loads addon files the way WoW does: each chunk receives (addonName, ns).
local helpers = {}

function helpers.load(ns, ...)
  for _, name in ipairs({ ... }) do
    local chunk = assert(loadfile("StreamDeckBars/" .. name .. ".lua"))
    chunk("StreamDeckBars", ns)
  end
  return ns
end

-- Decodes a 6-symbol slot record back into a table (test-side reference decoder).
function helpers.decodeSlot(symbols, first)
  local value = 0
  for i = 0, 5 do value = value * 64 + symbols[first + i] end
  local icon = math.floor(value / 4096)
  local flags = value % 4096
  local function bit(n) return math.floor(flags / 2 ^ n) % 2 == 1 end
  return {
    icon = icon,
    hasAction = bit(11),
    usable = bit(10),
    noMana = bit(9),
    glow = bit(8),
    rangeApplies = bit(7),
    inRange = bit(6),
    hasCount = bit(5),
    reserved = flags % 32,
  }
end

return helpers
