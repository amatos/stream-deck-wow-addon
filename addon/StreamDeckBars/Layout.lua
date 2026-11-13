-- Which button frames represent bars 1-3, and how keybinds reach them.
-- Supports Blizzard's bars and Bartender4 (docs/strip-format.md §5.1, §9).
local _, ns = ...

local Layout = {}
ns.Layout = Layout

-- Action slot of button 1 minus one, per bar (same for both layouts).
Layout.BASE = { 0, 60, 48 }

Layout.blizzard = {
  name = "blizzard",
  prefixes = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton" },
  commands = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON" },
}

function Layout.blizzard.buttonName(bar, n)
  return Layout.blizzard.prefixes[bar] .. n
end

-- Binds to WoW's own action commands, so bar 1 follows paging natively.
function Layout.blizzard.bind(owner, key, bar, n)
  SetOverrideBinding(owner, true, key, Layout.blizzard.commands[bar] .. n)
end

-- Bartender4 names its buttons by action slot: BT4Button<slot>. With its WoW 10
-- layout, the bars it labels 1, 2 and 3 use slots 1-12 (paged), 61-72 and 49-60.
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
