local helpers = require("helpers")
local mock = require("wowmock")

describe("Core", function()
  local ns, Core, env

  before_each(function()
    env = mock.install()
    ns = helpers.load({}, "Encoding", "Layout", "State", "Bindings", "Strip", "Core")
    Core = ns.Core
  end)

  after_each(mock.restore)

  local function login()
    Core.onEvent(nil, "PLAYER_LOGIN")
  end

  it("registers events and the slash command on load", function()
    assert.is_true(Core.frame.events.PLAYER_LOGIN)
    assert.is_true(Core.frame.events.PLAYER_REGEN_ENABLED)
    assert.equal("/sdb", SLASH_STREAMDECKBARS1)
    assert.equal(Core.slash, SlashCmdList.STREAMDECKBARS)
  end)

  describe("login", function()
    it("creates the strip, applies bindings and starts the loop", function()
      login()
      assert.is_not_nil(ns.Strip.root)
      assert.is_true(Core.bindingsApplied)
      assert.is_function(Core.frame.scripts.OnUpdate)
      Core.frame.scripts.OnUpdate()
      assert.equal(1, Core.sequence)
    end)

    it("marks bindings pending in combat and applies them after", function()
      env.combat = true
      login()
      assert.is_false(Core.bindingsApplied)
      assert.is_true(Core.bindingsPending)
      env.combat = false
      Core.onEvent(nil, "PLAYER_REGEN_ENABLED")
      assert.is_true(Core.bindingsApplied)
      assert.is_false(Core.bindingsPending)
    end)

    it("ignores regen when nothing is pending", function()
      login()
      local cleared = env.cleared
      Core.onEvent(nil, "PLAYER_REGEN_ENABLED")
      assert.equal(cleared, env.cleared)
    end)

    it("auto-detects Bartender4 at login", function()
      _G.Bartender4 = {}
      mock.button("BT4Button1", 1)
      login()
      assert.equal("bartender", ns.Layout.current.name)
      assert.equal("BT4Button1", env.bindings["CTRL-SHIFT-NUMPAD1"].click)
    end)

    it("honours a saved hidden state", function()
      _G.StreamDeckBarsDB = { shown = false }
      login()
      assert.is_false(ns.Strip.root.shown)
    end)

    it("rescales on display changes", function()
      login()
      env.physicalHeight = 768
      Core.onEvent(nil, "DISPLAY_SIZE_CHANGED")
      assert.equal(1, ns.Strip.root.scale)
    end)

    it("ignores display changes before login", function()
      Core.onEvent(nil, "UI_SCALE_CHANGED")
      assert.is_nil(ns.Strip.root)
    end)
  end)

  describe("tick", function()
    before_each(login)

    it("draws on the first tick", function()
      assert.is_true(Core.tick(1))
      assert.equal(1, Core.sequence)
    end)

    it("throttles to 20 per second", function()
      Core.tick(1)
      env.actions[1] = { texture = 5 }
      assert.is_false(Core.tick(1.01))
    end)

    it("skips unchanged frames until the heartbeat", function()
      Core.tick(1)
      assert.is_false(Core.tick(1.1))
      assert.is_true(Core.tick(2.1))
      assert.equal(2, Core.sequence)
    end)

    it("redraws when state changes", function()
      Core.tick(1)
      env.actions[1] = { texture = 5 }
      assert.is_true(Core.tick(1.1))
    end)

    it("redraws every tick while counts are secret", function()
      env.actions[1] = { texture = 5, consumable = true, count = mock.secret(2) }
      Core.tick(1)
      assert.is_true(Core.tick(1.1))
      assert.is_true(Core.tick(1.2))
    end)

    it("encodes combat and binding flags", function()
      env.combat = true
      Core.tick(1)
      local E = ns.Encoding
      local flagsColor = ns.Strip.blocks[12].color
      local r, g, b = E.symbolToColor(E.globalFlags({ inCombat = true, bindingsApplied = true }))
      assert.same({ r, g, b, 1 }, flagsColor)
    end)

    it("wraps the sequence at 4096", function()
      Core.sequence = 4095
      Core.tick(1)
      assert.equal(0, Core.sequence)
    end)
  end)

  describe("signature", function()
    it("is nil when counts are secret", function()
      assert.is_nil(Core.signature({}, {}, true))
    end)

    it("changes with counts", function()
      local symbols = ns.Encoding.buildFrame(0, 0, {})
      assert.are_not.equal(Core.signature(symbols, { 1 }, false), Core.signature(symbols, { 2 }, false))
    end)

    it("changes with every slot, including bars 4 and 5", function()
      local empty = Core.signature(ns.Encoding.buildFrame(0, 0, {}), {}, false)
      for _, slot in ipairs({ 1, 36, 37, 48, 60 }) do
        local slots = { [slot] = { icon = 1, hasAction = true } }
        local symbols = ns.Encoding.buildFrame(0, 0, slots)
        assert.are_not.equal(empty, Core.signature(symbols, {}, false), "slot " .. slot)
      end
    end)

    it("ignores the sequence number", function()
      local a = ns.Encoding.buildFrame(1, 0, {})
      local b = ns.Encoding.buildFrame(2, 0, {})
      assert.are.equal(Core.signature(a, {}, false), Core.signature(b, {}, false))
    end)
  end)

  describe("slash", function()
    before_each(login)

    it("prints status by default", function()
      Core.slash("")
      assert.matches("blizzard bars, strip shown at %(0, 0%) px, keybinds applied", env.printed[#env.printed])
    end)

    it("moves the strip", function()
      Core.slash("pos 30 40")
      assert.equal(30, StreamDeckBarsDB.x)
      assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 30, -40 }, ns.Strip.root.points[1])
    end)

    it("hides and shows", function()
      Core.slash("hide")
      assert.is_false(StreamDeckBarsDB.shown)
      assert.is_false(ns.Strip.root.shown)
      assert.matches("hidden", env.printed[#env.printed])
      Core.slash("show")
      assert.is_true(ns.Strip.root.shown)
    end)

    it("reapplies bindings", function()
      local cleared = env.cleared
      Core.slash("bind")
      assert.equal(cleared + 1, env.cleared)
    end)

    it("reports pending bindings", function()
      env.combat = true
      Core.slash("bind")
      assert.matches("pending", env.printed[#env.printed])
    end)

    it("lists keys", function()
      Core.slash("keys")
      assert.equal(60, #env.printed)
      assert.matches("CTRL%-SHIFT%-NUMPAD1", env.printed[1])
    end)

    it("switches layout and rebinds", function()
      Core.slash("layout bartender")
      assert.equal("bartender", StreamDeckBarsDB.layout)
      assert.equal("bartender", ns.Layout.current.name)
      assert.equal("BT4Button1", env.bindings["CTRL-SHIFT-NUMPAD1"].click)
      assert.matches("bartender bars", env.printed[#env.printed])
    end)

    it("rejects an unknown layout", function()
      Core.slash("layout elvui")
      assert.matches("/sdb %[", env.printed[#env.printed])
    end)

    it("prints usage for unknown commands", function()
      Core.slash("nope")
      assert.matches("/sdb %[", env.printed[#env.printed])
    end)
  end)

  it("reports bindings not applied before login", function()
    assert.matches("not applied", Core.status())
  end)
end)
