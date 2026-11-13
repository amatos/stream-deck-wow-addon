local helpers = require("helpers")
local mock = require("wowmock")

describe("Bindings", function()
  local ns, B, env

  before_each(function()
    env = mock.install()
    ns = helpers.load({}, "Layout", "Bindings")
    B = ns.Bindings
  end)

  after_each(mock.restore)

  it("lists 60 unique keys", function()
    local list = B.list()
    assert.equal(60, #list)
    local seen = {}
    for _, b in ipairs(list) do
      assert.is_nil(seen[b.key], b.key)
      seen[b.key] = true
    end
  end)

  it("matches the spec table", function()
    local list = B.list()
    assert.same({ bar = 1, button = 1, key = "CTRL-SHIFT-NUMPAD1" }, list[1])
    assert.same({ bar = 1, button = 10, key = "CTRL-SHIFT-NUMPAD0" }, list[10])
    assert.same({ bar = 2, button = 11, key = "CTRL-NUMPADDIVIDE" }, list[23])
    assert.same({ bar = 3, button = 12, key = "SHIFT-NUMPADMULTIPLY" }, list[36])
    assert.same({ bar = 4, button = 1, key = "NUMPAD1" }, list[37])
    assert.same({ bar = 4, button = 12, key = "NUMPADMULTIPLY" }, list[48])
    assert.same({ bar = 5, button = 1, key = "META-NUMPAD1" }, list[49])
    assert.same({ bar = 5, button = 12, key = "META-NUMPADMULTIPLY" }, list[60])
  end)

  it("never uses ALT, the default self-cast modifier", function()
    for _, b in ipairs(B.list()) do
      assert.is_nil(b.key:find("ALT"), b.key)
    end
  end)

  local function count()
    local n = 0
    for _ in pairs(env.bindings) do n = n + 1 end
    return n
  end

  it("binds Blizzard action commands", function()
    ns.Layout.use("blizzard")
    assert.is_true(B.apply({}))
    assert.equal(1, env.cleared)
    assert.same({ command = "ACTIONBUTTON1", priority = true }, env.bindings["CTRL-SHIFT-NUMPAD1"])
    assert.same({ command = "MULTIACTIONBAR1BUTTON12", priority = true }, env.bindings["CTRL-NUMPADMULTIPLY"])
    assert.same({ command = "MULTIACTIONBAR2BUTTON1", priority = true }, env.bindings["SHIFT-NUMPAD1"])
    assert.same({ command = "MULTIACTIONBAR3BUTTON12", priority = true }, env.bindings["NUMPADMULTIPLY"])
    assert.same({ command = "MULTIACTIONBAR4BUTTON1", priority = true }, env.bindings["META-NUMPAD1"])
    assert.equal(60, count())
  end)

  it("binds Bartender4 buttons by click with the Keybind button", function()
    ns.Layout.use("bartender")
    assert.is_true(B.apply({}))
    assert.same({ click = "BT4Button1", mouseButton = "Keybind", priority = true }, env.bindings["CTRL-SHIFT-NUMPAD1"])
    assert.same({ click = "BT4Button61", mouseButton = "Keybind", priority = true }, env.bindings["CTRL-NUMPAD1"])
    assert.same({ click = "BT4Button60", mouseButton = "Keybind", priority = true }, env.bindings["SHIFT-NUMPADMULTIPLY"])
    assert.same({ click = "BT4Button25", mouseButton = "Keybind", priority = true }, env.bindings["NUMPAD1"])
    assert.same({ click = "BT4Button36", mouseButton = "Keybind", priority = true }, env.bindings["NUMPADMULTIPLY"])
    assert.same({ click = "BT4Button48", mouseButton = "Keybind", priority = true }, env.bindings["META-NUMPADMULTIPLY"])
    assert.equal(60, count())
  end)

  it("refuses in combat", function()
    env.combat = true
    assert.is_false(B.apply({}))
    assert.equal(0, env.cleared)
    assert.is_nil(next(env.bindings))
  end)
end)
