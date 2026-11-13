-- Override keybinds for bars 1-5 (docs/strip-format.md §9).
local _, ns = ...

local Bindings = {}
ns.Bindings = Bindings

-- Bar 4 has no modifier: bare keypad keys, which have no physical key to press by accident.
-- Bar 5 uses Command (META), the one modifier left that is not ALT (self-cast).
Bindings.PREFIXES = { "CTRL-SHIFT-", "CTRL-", "SHIFT-", "", "META-" }
Bindings.KEYS = {
  "NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", "NUMPAD5", "NUMPAD6",
  "NUMPAD7", "NUMPAD8", "NUMPAD9", "NUMPAD0", "NUMPADDIVIDE", "NUMPADMULTIPLY",
}

-- Returns every binding as { bar, button, key }.
function Bindings.list()
  local out = {}
  for bar = 1, #Bindings.PREFIXES do
    for button = 1, ns.Layout.BUTTONS[bar] do
      out[#out + 1] = {
        bar = bar,
        button = button,
        key = Bindings.PREFIXES[bar] .. Bindings.KEYS[button],
      }
    end
  end
  return out
end

-- Applies the bindings owned by `owner` through the current layout.
-- Returns false when blocked by combat.
function Bindings.apply(owner)
  if InCombatLockdown() then return false end
  ClearOverrideBindings(owner)
  local layout = ns.Layout.current
  for _, b in ipairs(Bindings.list()) do
    layout.bind(owner, b.key, b.bar, b.button)
  end
  return true
end

return Bindings
