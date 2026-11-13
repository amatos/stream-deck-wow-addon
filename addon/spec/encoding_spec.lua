local helpers = require("helpers")

describe("Encoding", function()
  local E

  before_each(function()
    E = helpers.load({}, "Encoding").Encoding
  end)

  describe("symbols", function()
    it("splits a symbol into RGB levels", function()
      assert.same({ 3, 0, 3 }, { E.symbolToLevels(51) })
      assert.same({ 1, 2, 3 }, { E.symbolToLevels(16 + 8 + 3) })
      assert.same({ 0, 0, 0 }, { E.symbolToLevels(0) })
    end)

    it("maps levels to colour components", function()
      local r, g, b = E.symbolToColor(63)
      assert.equal(1, r); assert.equal(1, g); assert.equal(1, b)
      r, g, b = E.symbolToColor(21)
      assert.near(85 / 255, r, 1e-9)
      assert.near(85 / 255, g, 1e-9)
      assert.near(85 / 255, b, 1e-9)
    end)

    it("defines the marker and calibration from the spec", function()
      local expected = { { 3, 0, 3 }, { 0, 3, 0 }, { 0, 3, 3 }, { 3, 3, 0 } }
      for i, levels in ipairs(expected) do
        assert.same(levels, { E.symbolToLevels(E.MARKER[i]) })
      end
      for i = 1, 4 do
        assert.same({ i - 1, i - 1, i - 1 }, { E.symbolToLevels(E.CALIBRATION[i]) })
      end
    end)
  end)

  describe("globalFlags", function()
    it("is zero when nothing is set", function()
      assert.equal(0, E.globalFlags({}))
    end)

    it("sets each bit", function()
      assert.equal(1, E.globalFlags({ inCombat = true }))
      assert.equal(2, E.globalFlags({ bindingsApplied = true }))
      assert.equal(4, E.globalFlags({ bindingsPending = true }))
      assert.equal(8, E.globalFlags({ countsSecret = true }))
      assert.equal(15, E.globalFlags({
        inCombat = true, bindingsApplied = true, bindingsPending = true, countsSecret = true,
      }))
    end)
  end)

  describe("encodeSlot", function()
    it("encodes an empty slot as zeros", function()
      assert.same({ 0, 0, 0, 0, 0, 0 }, E.encodeSlot({}))
    end)

    it("round-trips icon and every flag", function()
      local slot = {
        icon = 136048, hasAction = true, usable = true, noMana = true, glow = true,
        rangeApplies = true, inRange = true, hasCount = true,
      }
      local d = helpers.decodeSlot(E.encodeSlot(slot), 1)
      assert.equal(136048, d.icon)
      for _, k in ipairs({ "hasAction", "usable", "noMana", "glow", "rangeApplies", "inRange", "hasCount" }) do
        assert.is_true(d[k], k)
      end
      assert.equal(0, d.reserved)
    end)

    it("keeps flags independent", function()
      local d = helpers.decodeSlot(E.encodeSlot({ icon = 1, glow = true }), 1)
      assert.is_true(d.glow)
      assert.is_false(d.usable)
      assert.is_false(d.hasAction)
      assert.equal(1, d.icon)
    end)

    it("handles the largest 24-bit icon", function()
      local d = helpers.decodeSlot(E.encodeSlot({ icon = 2 ^ 24 - 1 }), 1)
      assert.equal(2 ^ 24 - 1, d.icon)
    end)

    it("drops icons that do not fit in 24 bits", function()
      assert.equal(0, helpers.decodeSlot(E.encodeSlot({ icon = 2 ^ 24 }), 1).icon)
      assert.equal(0, helpers.decodeSlot(E.encodeSlot({ icon = -5 }), 1).icon)
      assert.equal(0, helpers.decodeSlot(E.encodeSlot({ icon = 1.5 }), 1).icon)
    end)

    it("clears in-range when range does not apply", function()
      local d = helpers.decodeSlot(E.encodeSlot({ inRange = true }), 1)
      assert.is_false(d.inRange)
    end)

    it("keeps every symbol within 6 bits", function()
      for _, s in ipairs(E.encodeSlot({ icon = 2 ^ 24 - 1, hasAction = true, usable = true })) do
        assert.is_true(s >= 0 and s < 64)
      end
    end)
  end)

  describe("checksum", function()
    it("matches a hand-computed Fletcher sum", function()
      -- a: 1, 3, 6 ; b: 1, 4, 10
      assert.same({ 6, 10 }, { E.checksum({ 1, 2, 3 }, 1, 3) })
    end)

    it("wraps modulo 64", function()
      assert.same({ 62, 61 }, { E.checksum({ 63, 63 }, 1, 2) })
    end)

    it("detects a swapped pair of symbols", function()
      local a1, b1 = E.checksum({ 5, 9 }, 1, 2)
      local a2, b2 = E.checksum({ 9, 5 }, 1, 2)
      assert.equal(a1, a2)
      assert.are_not.equal(b1, b2)
    end)
  end)

  describe("buildFrame", function()
    local slots, frame

    before_each(function()
      slots = {}
      slots[1] = { icon = 136048, hasAction = true, usable = true }
      slots[36] = { icon = 42, hasCount = true }
      frame = E.buildFrame(4097, 9, slots)
    end)

    it("has exactly the spec symbol count", function()
      assert.equal(E.SYMBOL_COUNT, #frame)
      assert.equal(230, #frame)
    end)

    it("writes the header", function()
      assert.same(E.MARKER, { frame[1], frame[2], frame[3], frame[4] })
      assert.same(E.CALIBRATION, { frame[5], frame[6], frame[7], frame[8] })
      assert.equal(1, frame[9])
      -- 4097 wraps to 1: high 0, low 1
      assert.equal(0, frame[10])
      assert.equal(1, frame[11])
      assert.equal(9, frame[12])
    end)

    it("encodes the sequence big-endian", function()
      local f = E.buildFrame(64 * 5 + 7, 0, {})
      assert.equal(5, f[10])
      assert.equal(7, f[11])
    end)

    it("places slot records in order", function()
      local first = helpers.decodeSlot(frame, 13)
      assert.equal(136048, first.icon)
      assert.is_true(first.usable)
      local last = helpers.decodeSlot(frame, 13 + 35 * 6)
      assert.equal(42, last.icon)
      assert.is_true(last.hasCount)
      local middle = helpers.decodeSlot(frame, 13 + 10 * 6)
      assert.equal(0, middle.icon)
      assert.is_false(middle.hasAction)
    end)

    it("ends with the checksum over version..last record", function()
      local a, b = E.checksum(frame, 9, 228)
      assert.equal(a, frame[229])
      assert.equal(b, frame[230])
    end)
  end)

  describe("geometry", function()
    it("lays blocks out row-major in 4px steps", function()
      assert.same({ 0, 0 }, { E.blockPosition(1) })
      assert.same({ 4, 0 }, { E.blockPosition(2) })
      assert.same({ 47 * 4, 0 }, { E.blockPosition(48) })
      assert.same({ 0, 4 }, { E.blockPosition(49) })
      assert.same({ (229 % 48) * 4, 16 }, { E.blockPosition(230) })
    end)

    it("is 192x20 pixels", function()
      assert.equal(5, E.gridRows())
      assert.same({ 192, 20 }, { E.gridSize() })
    end)

    it("starts the count area one block below the grid", function()
      assert.same({ 0, 24 }, { E.countAreaOffset() })
    end)

    it("places count cells six per line below the reference line", function()
      assert.same({ 0, 14 }, { E.countCellPosition(1) })
      assert.same({ 5 * 32, 14 }, { E.countCellPosition(6) })
      assert.same({ 0, 28 }, { E.countCellPosition(7) })
    end)
  end)
end)
