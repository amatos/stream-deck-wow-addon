-- Wires events, the redraw loop and the slash command together.
local addonName, ns = ...

local Core = {}
ns.Core = Core

Core.MIN_INTERVAL = 0.05 -- at most 20 redraws per second
Core.HEARTBEAT = 1.0     -- redraw at least once per second

Core.sequence = 0
Core.lastDraw = -math.huge
Core.lastCheck = -math.huge
Core.lastSignature = nil
Core.bindingsApplied = false
Core.bindingsPending = false

local DEFAULTS = { x = 0, y = 0, shown = true, layout = "auto" }

function Core.db()
  StreamDeckBarsDB = StreamDeckBarsDB or {}
  for k, v in pairs(DEFAULTS) do
    if StreamDeckBarsDB[k] == nil then StreamDeckBarsDB[k] = v end
  end
  return StreamDeckBarsDB
end

-- Signature of everything except the sequence number and secret counts.
-- Secret counts force a redraw every tick instead (they cannot be compared).
function Core.signature(symbols, counts, anySecret)
  if anySecret then return nil end
  local parts = {}
  for i = 12, 228 do parts[#parts + 1] = symbols[i] end
  for k = 1, #counts do parts[#parts + 1] = tostring(counts[k]) end
  return table.concat(parts, ",")
end

function Core.applyBindings()
  if ns.Bindings.apply(Core.owner) then
    Core.bindingsApplied, Core.bindingsPending = true, false
  else
    Core.bindingsPending = true
  end
end

-- One redraw check. `now` is GetTime(). Returns true when the strip was redrawn.
function Core.tick(now)
  if now - Core.lastCheck < Core.MIN_INTERVAL then return false end
  Core.lastCheck = now

  local E = ns.Encoding
  local slots, counts, anySecret = ns.State.collect()
  local flags = E.globalFlags({
    inCombat = InCombatLockdown(),
    bindingsApplied = Core.bindingsApplied,
    bindingsPending = Core.bindingsPending,
    countsSecret = anySecret,
  })
  local symbols = E.buildFrame(Core.sequence, flags, slots)
  local signature = Core.signature(symbols, counts, anySecret)
  local changed = signature == nil or signature ~= Core.lastSignature
  if not changed and now - Core.lastDraw < Core.HEARTBEAT then return false end

  Core.sequence = (Core.sequence + 1) % 4096
  symbols = E.buildFrame(Core.sequence, flags, slots)
  ns.Strip.render(symbols, counts)
  Core.lastSignature = signature
  Core.lastDraw = now
  return true
end

function Core.status()
  local db = Core.db()
  return string.format(
    "%s: %s bars, strip %s at (%d, %d) px, keybinds %s, sequence %d",
    addonName,
    ns.Layout.current.name,
    db.shown and "shown" or "hidden",
    db.x, db.y,
    Core.bindingsPending and "pending (in combat)" or (Core.bindingsApplied and "applied" or "not applied"),
    Core.sequence
  )
end

function Core.slash(msg)
  local db = Core.db()
  local cmd, a, b = strsplit(" ", strtrim(msg or ""))
  cmd = (cmd or ""):lower()
  if cmd == "pos" and tonumber(a) and tonumber(b) then
    db.x, db.y = tonumber(a), tonumber(b)
    ns.Strip.setPosition(db)
  elseif cmd == "show" or cmd == "hide" then
    db.shown = cmd == "show"
    ns.Strip.setShown(db.shown)
  elseif cmd == "bind" then
    Core.applyBindings()
  elseif cmd == "layout" and (a == "auto" or a == "blizzard" or a == "bartender") then
    db.layout = a
    ns.Layout.use(a)
    Core.applyBindings()
  elseif cmd == "keys" then
    for _, k in ipairs(ns.Bindings.list()) do
      print(string.format("  bar %d button %2d: %s", k.bar, k.button, k.key))
    end
    return
  elseif cmd ~= "" and cmd ~= "status" then
    print(addonName .. ": /sdb [status | pos <x> <y> | show | hide | bind | keys | layout auto|blizzard|bartender]")
    return
  end
  print(Core.status())
end

function Core.onEvent(_, event)
  if event == "PLAYER_LOGIN" then
    local db = Core.db()
    ns.Layout.use(db.layout)
    ns.Strip.create(db)
    ns.Strip.setShown(db.shown)
    Core.applyBindings()
    Core.frame:SetScript("OnUpdate", function() Core.tick(GetTime()) end)
  elseif event == "PLAYER_REGEN_ENABLED" then
    if Core.bindingsPending then Core.applyBindings() end
  elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
    if ns.Strip.root then ns.Strip.applyScale() end
  end
end

function Core.init()
  local frame = CreateFrame("Frame", "StreamDeckBarsCore")
  Core.frame = frame
  Core.owner = frame
  for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    frame:RegisterEvent(e)
  end
  frame:SetScript("OnEvent", Core.onEvent)
  SLASH_STREAMDECKBARS1 = "/sdb"
  SlashCmdList.STREAMDECKBARS = Core.slash
end

Core.init()

return Core
