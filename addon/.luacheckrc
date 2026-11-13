-- luacheck config for the addon and its busted specs (`make addon-lint`).
std = "luajit"
max_line_length = false
-- Methods like `function b:GetAttribute(k)` in mocks don't need to use self.
self = false

-- Globals the addon owns.
globals = {
  "StreamDeckBarsDB",
  "SLASH_STREAMDECKBARS1",
  "SlashCmdList",
}

-- WoW API the addon reads. Add new API here when the addon starts using it.
read_globals = {
  "C_ActionBar",
  "C_SpellActivationOverlay",
  "ClearOverrideBindings",
  "CreateFrame",
  "GetFileIDFromPath",
  "GetPhysicalScreenSize",
  "GetTime",
  "InCombatLockdown",
  "IsSpellOverlayed",
  "SetOverrideBinding",
  "SetOverrideBindingClick",
  "UIParent",
  "issecretvalue",
  "strsplit",
  "strtrim",
}

files["spec/"] = { std = "+busted" }
