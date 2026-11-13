-- Draws the data grid and count area (docs/strip-format.md §2, §7).
local _, ns = ...

local Strip = {}
ns.Strip = Strip

local E -- ns.Encoding, resolved in create()

-- Scale that makes 1 UI unit equal 1 physical pixel.
function Strip.pixelScale()
  local _, height = GetPhysicalScreenSize()
  if not height or height <= 0 then return 1 end
  return 768 / height
end

local function newBlock(root, x, y, size)
  local t = root:CreateTexture(nil, "ARTWORK")
  t:SetSize(size, size)
  t:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
  t:SetColorTexture(0, 0, 0, 1)
  return t
end

local function newText(root, x, y)
  local fs = root:CreateFontString(nil, "OVERLAY")
  fs:SetFont(E.COUNT_FONT, E.COUNT_FONT_SIZE, "MONOCHROME")
  fs:SetTextColor(1, 1, 1, 1)
  fs:SetJustifyH("LEFT")
  fs:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
  return fs
end

-- Creates the strip frame. position = { x = px, y = px } from the window's top-left.
function Strip.create(position)
  E = ns.Encoding
  local root = CreateFrame("Frame", "StreamDeckBarsStrip", UIParent)
  root:SetIgnoreParentScale(true)
  root:SetFrameStrata("TOOLTIP")
  root:SetFrameLevel(10000)

  -- Everything sits inside a black padding border (docs/strip-format.md §2).
  local pad = E.PADDING
  local gridW, gridH = E.gridSize()
  local areaX, areaY = E.countAreaOffset()
  areaX, areaY = areaX + pad, areaY + pad

  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0, 0, 0, 1)
  bg:SetAllPoints(root)

  local blocks = {}
  for i = 1, E.SYMBOL_COUNT do
    local x, y = E.blockPosition(i)
    blocks[i] = newBlock(root, pad + x, pad + y, E.BLOCK)
  end

  local reference = newText(root, areaX, areaY)
  reference:SetText(E.COUNT_REFERENCE)

  Strip.root = root
  Strip.bg = bg
  Strip.blocks = blocks
  Strip.reference = reference
  Strip.cells = {}
  Strip.areaX, Strip.areaY = areaX, areaY
  Strip.width = 2 * pad + math.max(gridW, E.COUNT_AREA_WIDTH)
  Strip.countCells = 0

  Strip.applyScale()
  Strip.setPosition(position)
  Strip.setCountLines(0)
  return root
end

function Strip.applyScale()
  Strip.root:SetScale(Strip.pixelScale())
end

function Strip.setPosition(position)
  local x, y = 0, 0
  if position then x, y = position.x or 0, position.y or 0 end
  Strip.root:ClearAllPoints()
  Strip.root:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -y)
  Strip.setCountLines(Strip.countCells or 0)
end

-- Sizes the strip for the reference line plus `cells` count cells.
function Strip.setCountLines(cells)
  Strip.countCells = cells
  local lines = 1 + math.ceil(cells / E.COUNT_CELLS_PER_LINE)
  Strip.root:SetSize(Strip.width, Strip.areaY + lines * E.COUNT_LINE_HEIGHT + E.PADDING)
end

local function cell(k)
  local fs = Strip.cells[k]
  if not fs then
    local x, y = E.countCellPosition(k)
    fs = newText(Strip.root, Strip.areaX + x, Strip.areaY + y)
    Strip.cells[k] = fs
  end
  return fs
end

-- Paints symbols (array of SYMBOL_COUNT) and count values (array, values may be secret).
function Strip.render(symbols, counts)
  for i, s in ipairs(symbols) do
    local r, g, b = E.symbolToColor(s)
    Strip.blocks[i]:SetColorTexture(r, g, b, 1)
  end
  local n = #counts
  for k = 1, n do
    local fs = cell(k)
    -- SetText accepts secret values; never compare or format them here.
    fs:SetText(counts[k])
    fs:Show()
  end
  for k = n + 1, #Strip.cells do
    Strip.cells[k]:SetText("")
    Strip.cells[k]:Hide()
  end
  Strip.setCountLines(n)
end

function Strip.setShown(shown)
  if shown then Strip.root:Show() else Strip.root:Hide() end
end

return Strip
