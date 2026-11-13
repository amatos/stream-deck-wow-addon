import Testing
@testable import StripKit

@Suite struct ModelTests {
    @Test func slotRecordRoundTrips() {
        let slot = SlotState(iconID: 136048, hasAction: true, usable: true, noMana: true, glow: true,
                             rangeApplies: true, inRange: true, hasCount: true)
        #expect(SlotState(record: slot.record[...]) == slot)
    }

    @Test func emptySlotIsZeros() {
        #expect(SlotState().record == [0, 0, 0, 0, 0, 0])
    }

    @Test func inRangeNeedsRangeApplies() {
        let slot = SlotState(inRange: true)
        #expect(SlotState(record: slot.record[...]).inRange == false)
    }

    @Test func largestIconFits() {
        let slot = SlotState(iconID: 0xFFFFFF)
        #expect(SlotState(record: slot.record[...]).iconID == 0xFFFFFF)
    }

    @Test func globalFlagsRoundTrip() {
        for symbol in 0..<16 {
            #expect(GlobalFlags(symbol: symbol).symbol == symbol)
        }
        #expect(GlobalFlags(symbol: 9) == GlobalFlags(inCombat: true, countsSecret: true))
    }

    @Test func frameSymbolsFollowTheSpec() {
        let f = StripFrame(sequence: 4097, flags: GlobalFlags(inCombat: true), slots: [])
        let s = f.symbols
        #expect(s.count == Spec.symbolCount)
        #expect(Array(s[0..<4]) == Spec.marker)
        #expect(Array(s[4..<8]) == Spec.calibration)
        #expect(s[8] == 4)
        #expect(s[9] == 0 && s[10] == 1)       // 4097 wraps to 1
        #expect(s[11] == 1)
        let (a, b) = Spec.checksum(s, from: 8, to: 371)
        #expect(s[372] == a && s[373] == b)
    }

    @Test func checksumMatchesHandComputedValue() {
        #expect(Spec.checksum([1, 2, 3], from: 0, to: 2) == (6, 10))
        #expect(Spec.checksum([63, 63], from: 0, to: 1) == (62, 61))
    }

    @Test func markerAndCalibrationLevels() {
        #expect(Spec.levels(of: 51) == (3, 0, 3))
        #expect(Spec.levels(of: 60) == (3, 3, 0))
        #expect(Spec.levels(of: 21) == (1, 1, 1))
        #expect(Spec.gridRows == 8)
        #expect(Spec.countAreaY == 10)
        #expect(Spec.barButton(slot: 0)! == (1, 1))
        #expect(Spec.barButton(slot: 35)! == (3, 12))
        #expect(Spec.barButton(slot: 36)! == (4, 1))
        #expect(Spec.barButton(slot: 43)! == (4, 8))
        #expect(Spec.barButton(slot: 47)! == (4, 12))
        #expect(Spec.barButton(slot: 59)! == (5, 12))
        #expect(Spec.barButton(slot: 60) == nil)
        #expect(Spec.barButton(slot: -1) == nil)
    }

    @Test func geometryScale() {
        #expect(StripGeometry(originX: 0, originY: 0, pitch: 2).scale == 2)
        #expect(StripGeometry(originX: 0, originY: 0, pitch: 1).scale == 1)
    }

    /// The addon (Lua) and helper (Swift) must agree on every symbol.
    @Test func swiftEncodingMatchesLuaAddon() throws {
        let lua = try Fixtures.luaFrame()
        let slots = lua.slots.map {
            SlotState(iconID: $0.icon, hasAction: $0.hasAction, usable: $0.usable, noMana: $0.noMana,
                      glow: $0.glow, rangeApplies: $0.rangeApplies, inRange: $0.inRange, hasCount: $0.hasCount)
        }
        let frame = StripFrame(sequence: lua.sequence, flags: GlobalFlags(symbol: lua.flags), slots: slots)
        #expect(frame.symbols == lua.symbols)
    }

    @Test func bgraPixelsReadsChannelsInOrder() {
        let bytes: [UInt8] = [10, 20, 30, 255, 1, 2, 3, 255]   // B, G, R, A
        bytes.withUnsafeBufferPointer { buf in
            let px = BGRAPixels(base: buf.baseAddress!, width: 2, height: 1, bytesPerRow: 8)
            #expect(px.rgb(0, 0) == (30, 20, 10))
            #expect(px.rgb(1, 0) == (3, 2, 1))
        }
    }

    @Test func rgbImageIgnoresOutOfBoundsWrites() {
        var img = RGBImage(width: 2, height: 2)
        img.set(-1, 0, (255, 255, 255))
        img.set(2, 2, (255, 255, 255))
        img.set(1, 1, (300, -5, 7))
        #expect(img.rgb(1, 1) == (255, 0, 7))
        #expect(img.rgb(0, 0) == (0, 0, 0))
    }
}
