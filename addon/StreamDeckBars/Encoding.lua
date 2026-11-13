-- Pure encoding of the strip format (docs/strip-format.md). No WoW API use.
local _, ns = ...

local Encoding = {}
ns.Encoding = Encoding

Encoding.VERSION = 3
Encoding.BLOCK = 4          -- block size in physical pixels
Encoding.WIDTH = 48         -- blocks per grid row
Encoding.SLOTS = 60          -- bars 1-5 x 12
Encoding.SYMBOLS_PER_SLOT = 6
Encoding.SYMBOL_COUNT = 374

Encoding.COUNT_FONT = "Fonts\\ARIALN.TTF"
Encoding.COUNT_FONT_SIZE = 12
Encoding.COUNT_REFERENCE = "0123456789"
Encoding.COUNT_CELL_WIDTH = 32
Encoding.COUNT_CELLS_PER_LINE = 6
Encoding.COUNT_LINE_HEIGHT = 14

-- Level index (0-3) to colour component (0-1).
Encoding.LEVELS = { [0] = 0, 85 / 255, 170 / 255, 1 }

Encoding.MARKER = { 51, 12, 15, 60 }      -- (3,0,3) (0,3,0) (0,3,3) (3,3,0)
Encoding.CALIBRATION = { 0, 21, 42, 63 }  -- greys at levels 0..3

-- Global flag bits (symbol 11).
Encoding.GLOBAL = {
  IN_COMBAT = 0,
  BINDINGS_APPLIED = 1,
  BINDINGS_PENDING = 2,
  COUNTS_SECRET = 3,
}

-- Slot record flag bits (bits 11..0 of the 36-bit record).
Encoding.SLOT = {
  HAS_ACTION = 11,
  USABLE = 10,
  NO_MANA = 9,
  GLOW = 8,
  RANGE_APPLIES = 7,
  IN_RANGE = 6,
  HAS_COUNT = 5,
}

local floor = math.floor

local function bitValue(bit, on)
  if on then return 2 ^ bit end
  return 0
end

function Encoding.symbolToLevels(s)
  return floor(s / 16) % 4, floor(s / 4) % 4, s % 4
end

function Encoding.symbolToColor(s)
  local r, g, b = Encoding.symbolToLevels(s)
  local L = Encoding.LEVELS
  return L[r], L[g], L[b]
end

-- Builds the global flags symbol from a table of booleans.
function Encoding.globalFlags(t)
  local G = Encoding.GLOBAL
  return bitValue(G.IN_COMBAT, t.inCombat)
    + bitValue(G.BINDINGS_APPLIED, t.bindingsApplied)
    + bitValue(G.BINDINGS_PENDING, t.bindingsPending)
    + bitValue(G.COUNTS_SECRET, t.countsSecret)
end

-- Encodes one slot state into 6 symbols (big-endian).
-- slot = { icon = number, hasAction, usable, noMana, glow, rangeApplies, inRange, hasCount }
function Encoding.encodeSlot(slot)
  local S = Encoding.SLOT
  local icon = slot.icon or 0
  if icon < 0 or icon >= 2 ^ 24 or icon ~= floor(icon) then icon = 0 end
  local flags = bitValue(S.HAS_ACTION, slot.hasAction)
    + bitValue(S.USABLE, slot.usable)
    + bitValue(S.NO_MANA, slot.noMana)
    + bitValue(S.GLOW, slot.glow)
    + bitValue(S.RANGE_APPLIES, slot.rangeApplies)
    + bitValue(S.IN_RANGE, slot.rangeApplies and slot.inRange)
    + bitValue(S.HAS_COUNT, slot.hasCount)
  local value = icon * 4096 + flags
  local out = {}
  for i = 1, Encoding.SYMBOLS_PER_SLOT do
    local shift = 64 ^ (Encoding.SYMBOLS_PER_SLOT - i)
    out[i] = floor(value / shift) % 64
  end
  return out
end

-- Fletcher-style checksum over symbols[from..to] (1-based, inclusive).
function Encoding.checksum(symbols, from, to)
  local a, b = 0, 0
  for i = from, to do
    a = (a + symbols[i]) % 64
    b = (b + a) % 64
  end
  return a, b
end

-- Builds the full symbol list (1-based Lua array; element i+1 is spec symbol i).
-- slots: array of 60 slot tables (missing entries encode as empty).
function Encoding.buildFrame(sequence, flags, slots)
  local out = {}
  for i = 1, 4 do out[i] = Encoding.MARKER[i] end
  for i = 1, 4 do out[4 + i] = Encoding.CALIBRATION[i] end
  out[9] = Encoding.VERSION
  local seq = sequence % 4096
  out[10] = floor(seq / 64)
  out[11] = seq % 64
  out[12] = flags
  local n = 12
  for s = 1, Encoding.SLOTS do
    local record = Encoding.encodeSlot(slots[s] or {})
    for i = 1, Encoding.SYMBOLS_PER_SLOT do
      n = n + 1
      out[n] = record[i]
    end
  end
  local a, b = Encoding.checksum(out, 9, n)
  out[n + 1] = a
  out[n + 2] = b
  return out
end

-- Pixel offset (x, y from top-left of the grid) of symbol index i (1-based).
function Encoding.blockPosition(i)
  local idx = i - 1
  return (idx % Encoding.WIDTH) * Encoding.BLOCK, floor(idx / Encoding.WIDTH) * Encoding.BLOCK
end

function Encoding.gridRows()
  return math.ceil(Encoding.SYMBOL_COUNT / Encoding.WIDTH)
end

function Encoding.gridSize()
  return Encoding.WIDTH * Encoding.BLOCK, Encoding.gridRows() * Encoding.BLOCK
end

-- Top-left pixel offset of the count area, relative to the grid's top-left.
function Encoding.countAreaOffset()
  local _, h = Encoding.gridSize()
  return 0, h + Encoding.BLOCK
end

-- Offset of count cell k (1-based) relative to the count area's top-left.
-- Line 0 holds the reference string; cells start on line 1.
function Encoding.countCellPosition(k)
  local idx = k - 1
  local line = 1 + floor(idx / Encoding.COUNT_CELLS_PER_LINE)
  local col = idx % Encoding.COUNT_CELLS_PER_LINE
  return col * Encoding.COUNT_CELL_WIDTH, line * Encoding.COUNT_LINE_HEIGHT
end

return Encoding
