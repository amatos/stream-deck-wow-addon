-- Minimal fake of the WoW API surface the addon uses.
local mock = {}

local realPrint = print

function mock.restore()
  _G.print = realPrint
end

local SECRET_MT = { __tostring = function() return "<secret>" end }

function mock.secret(v)
  return setmetatable({ value = v }, SECRET_MT)
end

local function region()
  local r = { shown = true, points = {} }
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:ClearAllPoints() self.points = {} end
  function r:SetAllPoints(target) self.allPoints = target end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  return r
end

local function texture()
  local t = region()
  function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
  return t
end

local function fontString()
  local f = region()
  function f:SetFont(...) self.font = { ... } end
  function f:SetTextColor(...) self.textColor = { ... } end
  function f:SetJustifyH(j) self.justify = j end
  function f:SetText(t) self.text = t end
  return f
end

function mock.frame(name)
  local f = region()
  f.name = name
  f.events, f.scripts, f.textures, f.fontStrings = {}, {}, {}, {}
  function f:SetIgnoreParentScale(v) self.ignoreParentScale = v end
  function f:SetFrameStrata(s) self.strata = s end
  function f:SetFrameLevel(l) self.level = l end
  function f:SetScale(s) self.scale = s end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:CreateTexture()
    local t = texture()
    self.textures[#self.textures + 1] = t
    return t
  end
  function f:CreateFontString()
    local fs = fontString()
    self.fontStrings[#self.fontStrings + 1] = fs
    return fs
  end
  return f
end

-- Installs fresh globals. `actions` maps action slot -> table of API results.
function mock.install(opts)
  opts = opts or {}
  local env = {
    actions = opts.actions or {},
    combat = opts.combat or false,
    bindings = {},
    cleared = 0,
    printed = {},
    frames = {},
    physicalHeight = opts.physicalHeight or 1440,
  }
  mock.env = env

  _G.issecretvalue = function(v) return getmetatable(v) == SECRET_MT end
  _G.C_ActionBar = {}
  _G.C_SpellActivationOverlay = {
    IsSpellOverlayed = function(id) return env.overlayed and env.overlayed[id] or false end,
  }
  _G.IsSpellOverlayed = nil
  _G.GetFileIDFromPath = function(path) return env.paths and env.paths[path] end

  local function field(name, default)
    return function(action)
      local a = env.actions[action]
      if not a then return default end
      local v = a[name]
      if type(v) == "function" then return v() end
      if v == nil then return default end
      return v
    end
  end

  _G.HasAction = function(action) return env.actions[action] ~= nil end
  _G.GetActionTexture = field("texture", nil)
  _G.IsUsableAction = function(action)
    local a = env.actions[action] or {}
    return a.usable, a.noMana
  end
  _G.IsActionInRange = field("inRange", nil)
  _G.GetActionInfo = function(action)
    local a = env.actions[action] or {}
    return a.type, a.id, a.subType
  end
  _G.IsConsumableAction = field("consumable", false)
  _G.IsStackableAction = field("stackable", false)
  _G.IsItemAction = field("item", false)
  _G.GetActionCount = field("count", 0)
  _G.GetActionCharges = function(action)
    local a = env.actions[action] or {}
    return a.charges, a.maxCharges
  end

  _G.InCombatLockdown = function() return env.combat end
  _G.ClearOverrideBindings = function() env.bindings = {}; env.cleared = env.cleared + 1 end
  _G.SetOverrideBinding = function(_, priority, key, command)
    env.bindings[key] = { command = command, priority = priority }
  end
  _G.SetOverrideBindingClick = function(_, priority, key, button, mouseButton)
    env.bindings[key] = { click = button, mouseButton = mouseButton, priority = priority }
  end
  _G.Bartender4 = nil
  for i = 1, 120 do _G["BT4Button" .. i] = nil end

  _G.GetPhysicalScreenSize = function() return 2560, env.physicalHeight end
  _G.UIParent = mock.frame("UIParent")
  _G.CreateFrame = function(_, name)
    local f = mock.frame(name)
    env.frames[#env.frames + 1] = f
    return f
  end
  _G.GetTime = function() return env.time or 0 end
  _G.SlashCmdList = {}
  _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  _G.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return unpack(out)
  end
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    env.printed[#env.printed + 1] = table.concat(parts, " ")
  end
  _G.StreamDeckBarsDB = nil

  for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton" }) do
    for i = 1, 12 do _G[prefix .. i] = nil end
  end
  return env
end

-- Creates a button global with a given action slot.
function mock.button(name, action)
  local b = mock.frame(name)
  b.action = action
  _G[name] = b
  return b
end

return mock
