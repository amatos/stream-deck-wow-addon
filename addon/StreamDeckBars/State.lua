-- Reads action-bar state from the WoW API, tolerating secret values.
local _, ns = ...

local State = {}
ns.State = State

-- Last readable "has count" per action slot, used while counts are secret.
State.countCache = {}

local floor = math.floor

local function isSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Returns v, or nil when v is secret.
local function readable(v)
  if isSecret(v) then return nil end
  return v
end

local function bool(v)
  v = readable(v)
  return v ~= nil and v ~= false
end

-- Looks a function up on C_ActionBar first, then as a global.
local function api(name)
  if C_ActionBar and C_ActionBar[name] then return C_ActionBar[name] end
  return _G[name]
end

local function call(name, ...)
  local fn = api(name)
  if not fn then return nil end
  return fn(...)
end

State.isSecret = isSecret
State.readable = readable

-- Returns bar (1-3) and button (1-12) for a slot index (1-36).
function State.barButton(slot)
  return floor((slot - 1) / 12) + 1, (slot - 1) % 12 + 1
end

-- Returns the action slot shown on a strip slot, and its button frame.
function State.actionFor(slot)
  local bar, n = State.barButton(slot)
  local button = _G[ns.Layout.current.buttonName(bar, n)]
  if button then
    local action
    -- LibActionButton (Bartender4) keeps the current paged action here.
    if readable(button._state_type) == "action" then
      action = readable(button._state_action)
    end
    if type(action) ~= "number" then
      action = readable(button.action)
    end
    if type(action) ~= "number" and button.GetAttribute then
      action = readable(button:GetAttribute("action"))
    end
    if type(action) == "number" and action > 0 then
      return action, button
    end
  end
  return ns.Layout.BASE[bar] + n, button
end

function State.iconId(texture)
  texture = readable(texture)
  if type(texture) == "number" then return texture end
  if type(texture) == "string" and GetFileIDFromPath then
    local id = readable(GetFileIDFromPath(texture))
    if type(id) == "number" then return id end
  end
  return 0
end

local function spellOverlayed(spellId)
  local fn = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed)
    or IsSpellOverlayed
  if not fn then return false end
  local ok, result = pcall(fn, spellId)
  return ok and bool(result)
end

local function shown(region)
  return region ~= nil and region.IsShown ~= nil and region:IsShown() == true
end

function State.glow(action, button)
  -- Blizzard's alert frame, or LibButtonGlow's overlay used by Bartender4.
  if button and (shown(button.SpellActivationAlert) or shown(button.__LBGoverlay)) then
    return true
  end
  local actionType, id, subType = call("GetActionInfo", action)
  actionType, id, subType = readable(actionType), readable(id), readable(subType)
  if type(id) ~= "number" then return false end
  if actionType == "spell" or (actionType == "macro" and subType == "spell") then
    return spellOverlayed(id)
  end
  return false
end

-- Returns hasCount and the count value to draw (which may be secret).
function State.count(action)
  local consumable = bool(call("IsConsumableAction", action)) or bool(call("IsStackableAction", action))
  local count = call("GetActionCount", action)
  if consumable then
    State.countCache[action] = true
    return true, count
  end

  local charges, maxCharges = call("GetActionCharges", action)
  local max = readable(maxCharges)
  if type(max) == "number" and max > 1 then
    State.countCache[action] = true
    return true, charges
  end

  -- Spells that use reagents show a count when it is above zero.
  local isItem = bool(call("IsItemAction", action))
  local readableCount = readable(count)
  if type(readableCount) == "number" then
    local has = not isItem and readableCount > 0
    State.countCache[action] = has
    return has, count
  end
  -- Secret values cannot be compared, so test secrecy before comparing to nil.
  if State.countCache[action] and (isSecret(count) or count ~= nil) then
    return true, count
  end
  return false, nil
end

-- Collects one strip slot. Returns the slot table and the count value (may be secret).
function State.collectSlot(slot)
  local action, button = State.actionFor(slot)
  if not bool(call("HasAction", action)) then
    return {}, nil
  end
  local usable, noMana = call("IsUsableAction", action)
  local inRange = readable(call("IsActionInRange", action))
  local hasCount, count = State.count(action)
  return {
    icon = State.iconId(call("GetActionTexture", action)),
    hasAction = true,
    usable = bool(usable),
    noMana = bool(noMana),
    glow = State.glow(action, button),
    rangeApplies = inRange ~= nil,
    inRange = inRange == true,
    hasCount = hasCount,
  }, count
end

-- Collects all 36 slots. Returns slots, counts (array of values for slots with
-- hasCount, in slot order) and whether any of those counts is secret.
function State.collect()
  local slots, counts, anySecret = {}, {}, false
  for slot = 1, 36 do
    local s, count = State.collectSlot(slot)
    slots[slot] = s
    if s.hasCount then
      counts[#counts + 1] = count
      if isSecret(count) then anySecret = true end
    end
  end
  return slots, counts, anySecret
end

return State
