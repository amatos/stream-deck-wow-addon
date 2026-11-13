local helpers = require("helpers")
local mock = require("wowmock")

describe("Strip", function()
  local ns, Strip, E, env

  before_each(function()
    env = mock.install({ physicalHeight = 1536 })
    ns = helpers.load({}, "Encoding", "Strip")
    Strip, E = ns.Strip, ns.Encoding
  end)

  after_each(mock.restore)

  it("computes a pixel-perfect scale", function()
    assert.equal(0.5, Strip.pixelScale())
  end)

  it("falls back to scale 1 without a screen height", function()
    _G.GetPhysicalScreenSize = function() return 0, 0 end
    assert.equal(1, Strip.pixelScale())
  end)

  describe("create", function()
    local root

    before_each(function()
      root = Strip.create({ x = 10, y = 20 })
    end)

    it("ignores parent scale and uses the pixel scale", function()
      assert.is_true(root.ignoreParentScale)
      assert.equal(0.5, root.scale)
      assert.equal("TOOLTIP", root.strata)
    end)

    it("creates one 1px block per symbol inside the 2px padding", function()
      assert.equal(E.SYMBOL_COUNT, #Strip.blocks)
      local b = Strip.blocks[49]
      assert.equal(1, b.w)
      assert.same({ "TOPLEFT", root, "TOPLEFT", 2, -3 }, b.points[1])
      assert.same({ "TOPLEFT", root, "TOPLEFT", 2, -2 }, Strip.blocks[1].points[1])
    end)

    it("fills the whole strip with one black background", function()
      assert.equal(root, Strip.bg.allPoints)
      assert.same({ 0, 0, 0, 1 }, Strip.bg.color)
    end)

    it("anchors at the saved position", function()
      assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 10, -20 }, root.points[1])
    end)

    it("draws the reference digits in a monochrome font below the grid", function()
      assert.equal("0123456789", Strip.reference.text)
      assert.same({ "Fonts\\FRIZQT__.TTF", 7, "MONOCHROME" }, Strip.reference.font)
      assert.same({ "TOPLEFT", root, "TOPLEFT", 2, -12 }, Strip.reference.points[1])
    end)

    it("is 54 x 21 px with only the reference line", function()
      assert.equal(54, root.w)
      assert.equal(21, root.h)
    end)
  end)

  it("defaults the position to the top-left corner", function()
    local root = Strip.create(nil)
    assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 0, -0 }, root.points[1])
    Strip.setPosition({})
    assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 0, -0 }, root.points[1])
  end)

  describe("render", function()
    before_each(function() Strip.create({}) end)

    it("paints each block with its symbol colour", function()
      local symbols = E.buildFrame(1, 0, {})
      Strip.render(symbols, {})
      assert.same({ 1, 0, 1, 1 }, Strip.blocks[1].color) -- marker magenta
      assert.same({ 1, 1, 1, 1 }, Strip.blocks[8].color) -- calibration white
    end)

    it("writes counts into cells and grows the strip", function()
      local secret = mock.secret(3)
      Strip.render(E.buildFrame(1, 0, {}), { 5, secret, 7, 8, 9, 10, 11 })
      assert.equal(7, #Strip.cells)
      assert.equal(5, Strip.cells[1].text)
      assert.equal(secret, Strip.cells[2].text)
      assert.same({ "TOPLEFT", Strip.root, "TOPLEFT", 2, -(12 + 28) }, Strip.cells[7].points[1])
      assert.same({ "TOPLEFT", Strip.root, "TOPLEFT", 2 + 25, -(12 + 21) }, Strip.cells[6].points[1])
      assert.equal(12 + 5 * 7 + 2, Strip.root.h)
    end)

    it("hides cells no longer needed", function()
      Strip.render(E.buildFrame(1, 0, {}), { 5, 6 })
      Strip.render(E.buildFrame(2, 0, {}), { 5 })
      assert.is_true(Strip.cells[1].shown)
      assert.is_false(Strip.cells[2].shown)
      assert.equal("", Strip.cells[2].text)
      assert.equal(12 + 2 * 7 + 2, Strip.root.h)
    end)
  end)

  it("shows and hides", function()
    Strip.create({})
    Strip.setShown(false)
    assert.is_false(Strip.root.shown)
    Strip.setShown(true)
    assert.is_true(Strip.root.shown)
  end)

  it("reapplies scale", function()
    Strip.create({})
    env.physicalHeight = 768
    Strip.applyScale()
    assert.equal(1, Strip.root.scale)
  end)
end)
