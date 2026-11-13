-- Which button frames represent bars 1-5, and how keybinds reach them.
-- Supports Blizzard's bars and Bartender4 (docs/strip-format.md §5.1, §9).
local _, ns = ...

local Layout = {}
ns.Layout = Layout

-- Action slot of button 1 minus one, per bar (same for both layouts).
Layout.BASE = { 0, 60, 48, 24, 36 }
-- Buttons mirrored per bar.
Layout.BUTTONS = { 12, 12, 12, 12, 12 }
Layout.SLOT_COUNT = 60

-- Returns bar (1-5) and button for a strip slot (1-60), or nil when out of range.
function Layout.barButton(slot)
  if slot < 1 or slot > Layout.SLOT_COUNT then return nil end
  local bar = math.floor((slot - 1) / 12) + 1
  return bar, (slot - 1) % 12 + 1
end

Layout.blizzard = {
  name = "blizzard",
  prefixes = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton" },
  commands = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON",
    "MULTIACTIONBAR4BUTTON" },
}

function Layout.blizzard.buttonName(bar, n)
  return Layout.blizzard.prefixes[bar] .. n
end

-- Binds to WoW's own action commands, so bar 1 follows paging natively.
function Layout.blizzard.bind(owner, key, bar, n)
  SetOverrideBinding(owner, true, key, Layout.blizzard.commands[bar] .. n)
end

-- Bartender4 names its buttons by action slot: BT4Button<slot>. With its WoW 10
-- layout, the bars it labels 1-5 use slots 1-12 (paged), 61-72, 49-60, 25-36 and 37-48.
Layout.bartender = {
  name = "bartender",
}

function Layout.bartender.buttonName(bar, n)
  return "BT4Button" .. (Layout.BASE[bar] + n)
end

-- LibActionButton treats the "Keybind" mouse button as a key press.
function Layout.bartender.bind(owner, key, bar, n)
  SetOverrideBindingClick(owner, true, key, Layout.bartender.buttonName(bar, n), "Keybind")
end

function Layout.bartenderActive()
  return _G.Bartender4 ~= nil and _G.BT4Button1 ~= nil
end

-- Picks the layout. `preference` is "auto", "blizzard" or "bartender".
function Layout.detect(preference)
  if preference == "blizzard" then return Layout.blizzard end
  if preference == "bartender" then return Layout.bartender end
  if Layout.bartenderActive() then return Layout.bartender end
  return Layout.blizzard
end

Layout.current = Layout.blizzard

function Layout.use(preference)
  Layout.current = Layout.detect(preference)
  return Layout.current
end

return Layout
