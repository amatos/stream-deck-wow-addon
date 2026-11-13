local helpers = require("helpers")
local mock = require("wowmock")

describe("Layout", function()
  local L

  before_each(function()
    mock.install()
    L = helpers.load({}, "Layout").Layout
  end)

  after_each(mock.restore)

  it("names Blizzard buttons for bars 1-3", function()
    assert.equal("ActionButton1", L.blizzard.buttonName(1, 1))
    assert.equal("MultiBarBottomLeftButton12", L.blizzard.buttonName(2, 12))
    assert.equal("MultiBarBottomRightButton5", L.blizzard.buttonName(3, 5))
  end)

  it("names Bartender4 buttons by action slot", function()
    assert.equal("BT4Button1", L.bartender.buttonName(1, 1))
    assert.equal("BT4Button12", L.bartender.buttonName(1, 12))
    assert.equal("BT4Button61", L.bartender.buttonName(2, 1))
    assert.equal("BT4Button72", L.bartender.buttonName(2, 12))
    assert.equal("BT4Button49", L.bartender.buttonName(3, 1))
    assert.equal("BT4Button60", L.bartender.buttonName(3, 12))
  end)

  it("defaults to Blizzard", function()
    assert.equal(L.blizzard, L.current)
    assert.equal(L.blizzard, L.detect("auto"))
  end)

  it("auto-detects Bartender4 only when its buttons exist", function()
    _G.Bartender4 = {}
    assert.equal(L.blizzard, L.detect("auto"))
    mock.button("BT4Button1", 1)
    assert.equal(L.bartender, L.detect("auto"))
  end)

  it("honours an explicit preference", function()
    _G.Bartender4 = {}
    mock.button("BT4Button1", 1)
    assert.equal(L.blizzard, L.detect("blizzard"))
    assert.equal(L.bartender, L.detect("bartender"))
  end)

  it("switches the current layout", function()
    assert.equal(L.bartender, L.use("bartender"))
    assert.equal(L.bartender, L.current)
  end)
end)
