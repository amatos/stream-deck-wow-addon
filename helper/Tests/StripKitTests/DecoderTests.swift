import Testing
@testable import StripKit

@Suite struct DecoderTests {
    func decode(_ img: RGBImage) -> StripFrame? {
        StripDecoder.locate(img)?.1
    }

    @Test func decodesAtTheOrigin() {
        let frame = StripFrame.sample()
        #expect(decode(Render.image(frame)) == frame)
    }

    @Test func findsAStripAwayFromTheOrigin() throws {
        var o = Render.Options()
        o.originX = 37; o.originY = 53; o.width = 400; o.height = 200
        let frame = StripFrame.sample(sequence: 4000)
        let (g, decoded) = try #require(StripDecoder.locate(Render.image(frame, o)))
        #expect(g == StripGeometry(originX: 37, originY: 53, pitch: 4))
        #expect(decoded == frame)
    }

    @Test func handlesDoubleScale() throws {
        var o = Render.Options()
        o.scale = 2; o.width = 500; o.height = 200
        let frame = StripFrame.sample(counted: [1, 2])
        let (g, decoded) = try #require(StripDecoder.locate(Render.image(frame, counts: [12, 7], o)))
        #expect(g.pitch == 8)
        #expect(decoded.slots[1].count == 12)
        #expect(decoded.slots[2].count == 7)
    }

    @Test func toleratesColourShifts() {
        var o = Render.Options()
        // Compress and lift levels, as a colour profile or gamma change might.
        o.colour = { 30 + $0 * 180 / 255 + ($0 == 85 ? 25 : 0) }
        let frame = StripFrame.sample()
        #expect(decode(Render.image(frame, o)) == frame)
    }

    @Test func ignoresDecoyMagentaAreas() {
        var o = Render.Options()
        o.originX = 40; o.originY = 60; o.width = 400; o.height = 200
        var img = Render.image(StripFrame.sample(), o)
        img.fill(x: 2, y: 2, w: 20, h: 8, (255, 0, 255))     // magenta but no marker after it
        img.fill(x: 0, y: 20, w: 4, h: 4, (255, 0, 255))     // marker colours, wrong spacing
        img.fill(x: 4, y: 20, w: 9, h: 4, (0, 255, 0))
        #expect(decode(img) == StripFrame.sample())
    }

    @Test func rejectsABadChecksum() {
        var symbols = StripFrame.sample().symbols
        symbols[20] ^= 1
        let img = Render.image(symbols: symbols)
        let g = StripGeometry(originX: 0, originY: 0, pitch: 4)
        #expect(StripDecoder.decodeGrid(img, g) == .failure(.badChecksum))
        #expect(decode(img) == nil)
    }

    @Test func rejectsAnUnknownVersion() {
        var symbols = StripFrame.sample().symbols
        symbols[8] = 2
        let g = StripGeometry(originX: 0, originY: 0, pitch: 4)
        #expect(StripDecoder.decodeGrid(Render.image(symbols: symbols), g) == .failure(.badVersion(2)))
    }

    @Test func rejectsAWrongMarker() {
        let img = Render.image(StripFrame.sample())
        let shifted = StripGeometry(originX: 4, originY: 0, pitch: 4)
        #expect(StripDecoder.decodeGrid(img, shifted) != .success(StripFrame.sample()))
        let g = StripGeometry(originX: 0, originY: 0, pitch: 4)
        var symbols = StripFrame.sample().symbols
        symbols[1] = 63
        #expect(StripDecoder.decodeGrid(Render.image(symbols: symbols), g) == .failure(.badMarker))
    }

    @Test func rejectsAGridOffTheImage() {
        var o = Render.Options()
        o.width = 150
        let g = StripGeometry(originX: 0, originY: 0, pitch: 4)
        #expect(StripDecoder.decodeGrid(Render.image(StripFrame.sample(), o), g) == .failure(.offImage))
        #expect(StripDecoder.symbols(RGBImage(width: 4, height: 4), g) == nil)
    }

    @Test func rejectsFlatCalibration() {
        var o = Render.Options()
        o.colour = { _ in 128 }
        let g = StripGeometry(originX: 0, originY: 0, pitch: 4)
        #expect(StripDecoder.symbols(Render.image(StripFrame.sample(), o), g) == nil)
        #expect(StripDecoder.Calibration(samples: []) == nil)
    }

    @Test func findsNothingInAnEmptyImage() {
        #expect(StripDecoder.locate(RGBImage(width: 100, height: 50)) == nil)
        #expect(StripDecoder.candidates(in: RGBImage(width: 100, height: 50)).isEmpty)
    }

    @Test func rejectsAMarkerCutOffAtTheEdge() {
        var img = RGBImage(width: 10, height: 4)
        img.fill(x: 0, y: 0, w: 4, h: 4, (255, 0, 255))
        img.fill(x: 4, y: 0, w: 4, h: 4, (0, 255, 0))
        img.fill(x: 8, y: 0, w: 2, h: 4, (0, 255, 255))
        #expect(StripDecoder.candidates(in: img).isEmpty)
    }

    @Test func rejectsATinyMagentaSpeck() {
        var img = RGBImage(width: 10, height: 4)
        img.set(3, 1, (255, 0, 255))
        #expect(StripDecoder.candidates(in: img).isEmpty)
    }

    @Test func limitsCandidates() {
        var img = RGBImage(width: 64, height: 64)
        for row in 0..<8 {
            let y = row * 8
            img.fill(x: 0, y: y, w: 4, h: 4, (255, 0, 255))
            img.fill(x: 4, y: y, w: 4, h: 4, (0, 255, 0))
            img.fill(x: 8, y: y, w: 4, h: 4, (0, 255, 255))
            img.fill(x: 12, y: y, w: 4, h: 4, (255, 255, 0))
        }
        #expect(StripDecoder.candidates(in: img, limit: 3).count == 3)
    }

    // MARK: The real thing

    /// Screenshot of the strip from the game (WoW Forever, Bartender4, 3 counted slots).
    @Test func decodesTheInGameScreenshot() throws {
        let img = Fixtures.png("ingame-strip.png")
        let (g, frame) = try #require(StripDecoder.locate(img))
        #expect(g.pitch == 4)
        #expect(g.originX == 0 && g.originY == 0)
        #expect(frame.version == 1)
        #expect(frame.flags.bindingsApplied)
        let counted = frame.slots.filter(\.hasCount)
        #expect(counted.map(\.count) == [2, 0, 3])
        #expect(frame.slots.contains { $0.hasAction && $0.iconID > 0 })
    }
}
