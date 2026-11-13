local helpers = require("helpers")
local mock = require("wowmock")

describe("State", function()
  local S, env

  before_each(function()
    env = mock.install()
    S = helpers.load({}, "Layout", "State").State
  end)

  after_each(mock.restore)

  describe("barButton", function()
    it("maps slots to bars and buttons", function()
      assert.same({ 1, 1 }, { S.barButton(1) })
      assert.same({ 1, 12 }, { S.barButton(12) })
      assert.same({ 2, 1 }, { S.barButton(13) })
      assert.same({ 3, 12 }, { S.barButton(36) })
      assert.same({ 4, 1 }, { S.barButton(37) })
      assert.same({ 4, 12 }, { S.barButton(48) })
      assert.same({ 5, 12 }, { S.barButton(60) })
      assert.is_nil(S.barButton(61))
      assert.is_nil(S.barButton(0))
    end)
  end)

  describe("actionFor", function()
    it("uses the button's current action (follows bar 1 paging)", function()
      local b = mock.button("ActionButton3", 75)
      local action, button = S.actionFor(3)
      assert.equal(75, action)
      assert.equal(b, button)
    end)

    it("falls back to the action attribute", function()
      local b = mock.button("MultiBarBottomLeftButton2", nil)
      function b:GetAttribute(k) if k == "action" then return 62 end end
      assert.equal(62, (S.actionFor(14)))
    end)

    it("falls back to fixed slots without a button", function()
      assert.equal(1, (S.actionFor(1)))
      assert.equal(61, (S.actionFor(13)))
      assert.equal(72, (S.actionFor(24)))
      assert.equal(49, (S.actionFor(25)))
      assert.equal(60, (S.actionFor(36)))
      assert.equal(25, (S.actionFor(37)))
      assert.equal(36, (S.actionFor(48)))
      assert.equal(37, (S.actionFor(49)))
      assert.equal(48, (S.actionFor(60)))
    end)

    it("ignores a secret action", function()
      mock.button("ActionButton1", mock.secret(99))
      assert.equal(1, (S.actionFor(1)))
    end)
  end)

  describe("iconId", function()
    it("passes numeric file IDs through", function()
      assert.equal(136048, S.iconId(136048))
    end)

    it("resolves texture paths", function()
      env.paths = { ["Interface\\Icons\\Foo"] = 1234 }
      assert.equal(1234, S.iconId("Interface\\Icons\\Foo"))
      assert.equal(0, S.iconId("Interface\\Icons\\Unknown"))
    end)

    it("returns 0 for nil and secret values", function()
      assert.equal(0, S.iconId(nil))
      assert.equal(0, S.iconId(mock.secret(5)))
    end)

    it("returns 0 for paths when GetFileIDFromPath is missing", function()
      _G.GetFileIDFromPath = nil
      assert.equal(0, S.iconId("x"))
    end)
  end)

  describe("glow", function()
    it("is true when the button's activation alert is shown", function()
      local b = mock.button("ActionButton1", 1)
      b.SpellActivationAlert = mock.frame()
      assert.is_true(S.glow(1, b))
    end)

    it("asks the overlay API for spells", function()
      env.actions[1] = { type = "spell", id = 529 }
      env.overlayed = { [529] = true }
      assert.is_true(S.glow(1, nil))
      env.overlayed = {}
      assert.is_false(S.glow(1, nil))
    end)

    it("asks the overlay API for macros that resolve to a spell", function()
      env.actions[1] = { type = "macro", id = 529, subType = "spell" }
      env.overlayed = { [529] = true }
      assert.is_true(S.glow(1, nil))
    end)

    it("is false for items and unknown types", function()
      env.actions[1] = { type = "item", id = 529 }
      env.overlayed = { [529] = true }
      assert.is_false(S.glow(1, nil))
    end)

    it("is false when the id is secret", function()
      env.actions[1] = { type = "spell", id = mock.secret(529) }
      assert.is_false(S.glow(1, nil))
    end)

    it("falls back to the global IsSpellOverlayed", function()
      _G.C_SpellActivationOverlay = nil
      _G.IsSpellOverlayed = function(id) return id == 7 end
      env.actions[1] = { type = "spell", id = 7 }
      assert.is_true(S.glow(1, nil))
    end)

    it("is false when no overlay API exists or it errors", function()
      _G.C_SpellActivationOverlay = nil
      env.actions[1] = { type = "spell", id = 7 }
      assert.is_false(S.glow(1, nil))
      _G.IsSpellOverlayed = function() error("bad id") end
      assert.is_false(S.glow(1, nil))
    end)

    it("prefers C_ActionBar functions over globals", function()
      _G.C_ActionBar.GetActionInfo = function() return "spell", 8 end
      env.overlayed = { [8] = true }
      assert.is_true(S.glow(1, nil))
    end)
  end)

  describe("count", function()
    it("reports consumables with their count", function()
      env.actions[5] = { consumable = true, count = 3 }
      assert.same({ true, 3 }, { S.count(5) })
    end)

    it("reports stackables", function()
      env.actions[5] = { stackable = true, count = 20 }
      assert.same({ true, 20 }, { S.count(5) })
    end)

    it("passes a secret count through untouched", function()
      local secret = mock.secret(3)
      env.actions[5] = { consumable = true, count = secret }
      local has, count = S.count(5)
      assert.is_true(has)
      assert.equal(secret, count)
    end)

    it("reports charges when max charges is above one", function()
      env.actions[5] = { charges = 2, maxCharges = 3 }
      assert.same({ true, 2 }, { S.count(5) })
    end)

    it("ignores single-charge spells", function()
      env.actions[5] = { charges = 1, maxCharges = 1 }
      assert.same({ false, 0 }, { S.count(5) })
    end)

    it("reports reagent spells with a positive count", function()
      env.actions[5] = { count = 12 }
      assert.same({ true, 12 }, { S.count(5) })
    end)

    it("does not report items that are not consumable", function()
      env.actions[5] = { item = true, count = 1 }
      assert.is_false((S.count(5)))
    end)

    it("remembers a reagent count once it turns secret", function()
      env.actions[5] = { count = 12 }
      S.count(5)
      local secret = mock.secret(11)
      env.actions[5].count = secret
      local has, count = S.count(5)
      assert.is_true(has)
      assert.equal(secret, count)
    end)

    it("reports nothing for an unseen secret count", function()
      env.actions[5] = { count = mock.secret(11) }
      assert.same({ false }, { S.count(5) })
    end)
  end)

  describe("collectSlot", function()
    it("returns an empty slot without an action", function()
      local s, count = S.collectSlot(1)
      assert.same({}, s)
      assert.is_nil(count)
    end)

    it("collects every field", function()
      env.actions[1] = {
        texture = 136048, usable = true, noMana = false, inRange = false,
        type = "spell", id = 529, consumable = true, count = 4,
      }
      env.overlayed = { [529] = true }
      local s, count = S.collectSlot(1)
      assert.same({
        icon = 136048, hasAction = true, usable = true, noMana = false, glow = true,
        rangeApplies = true, inRange = false, hasCount = true,
      }, s)
      assert.equal(4, count)
    end)

    it("treats nil range as not applicable", function()
      env.actions[1] = { texture = 1, usable = true }
      local s = S.collectSlot(1)
      assert.is_false(s.rangeApplies)
      assert.is_false(s.inRange)
    end)

    it("treats secret usability and range as unknown", function()
      env.actions[1] = { texture = 1, usable = mock.secret(true), inRange = mock.secret(true) }
      local s = S.collectSlot(1)
      assert.is_false(s.usable)
      assert.is_false(s.rangeApplies)
    end)
  end)

  describe("collect", function()
    it("returns 60 slots and counts in slot order", function()
      env.actions[1] = { texture = 1, consumable = true, count = 7 }
      env.actions[49] = { texture = 2, stackable = true, count = 9 } -- bar 3 button 1 = slot 25
      env.actions[36] = { texture = 3 }                                 -- bar 4 button 12 = slot 48
      env.actions[48] = { texture = 5 }                                 -- bar 5 button 12 = slot 60
      local slots, counts, secret = S.collect()
      assert.equal(60, #slots)
      assert.equal(5, slots[60].icon)
      assert.equal(3, slots[48].icon)
      assert.equal(1, slots[1].icon)
      assert.equal(2, slots[25].icon)
      assert.same({ 7, 9 }, counts)
      assert.is_false(secret)
    end)

    it("flags secret counts", function()
      env.actions[1] = { texture = 1, consumable = true, count = mock.secret(7) }
      local _, counts, secret = S.collect()
      assert.equal(1, #counts)
      assert.is_true(secret)
    end)
  end)

  describe("with Bartender4", function()
    local ns

    before_each(function()
      ns = helpers.load({}, "Layout", "State")
      S = ns.State
      ns.Layout.use("bartender")
    end)

    it("reads the paged action from LibActionButton state", function()
      local b = mock.button("BT4Button1", nil)
      b._state_type, b._state_action = "action", 85
      local action, button = S.actionFor(1)
      assert.equal(85, action)
      assert.equal(b, button)
    end)

    it("uses bar 6 and bar 5 buttons for bars 2 and 3", function()
      mock.button("BT4Button61", 61)
      mock.button("BT4Button49", 49)
      assert.equal(61, (S.actionFor(13)))
      assert.equal(49, (S.actionFor(25)))
    end)

    it("falls back past non-action LibActionButton state", function()
      local b = mock.button("BT4Button2", 2)
      b._state_type, b._state_action = "empty", nil
      assert.equal(2, (S.actionFor(2)))
    end)

    it("detects the LibButtonGlow overlay", function()
      local b = mock.button("BT4Button1", 1)
      b.__LBGoverlay = mock.frame()
      assert.is_true(S.glow(1, b))
      b.__LBGoverlay:Hide()
      assert.is_false(S.glow(1, b))
    end)
  end)

  describe("without issecretvalue", function()
    it("treats every value as readable", function()
      _G.issecretvalue = nil
      assert.is_false(S.isSecret(5))
      assert.equal(5, S.readable(5))
    end)
  end)
end)
