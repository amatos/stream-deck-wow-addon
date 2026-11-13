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
        #expect(g == StripGeometry(originX: 37, originY: 53, pitch: 1))
        #expect(decoded == frame)
    }

    @Test func handlesDoubleScale() throws {
        var o = Render.Options()
        o.scale = 2; o.width = 500; o.height = 200
        let frame = StripFrame.sample(counted: [1, 2])
        let (g, decoded) = try #require(StripDecoder.locate(Render.image(frame, counts: [12, 7], o)))
        #expect(g.pitch == 2)
        #expect(decoded.slots[1].count == 12)
        #expect(decoded.slots[2].count == 7)
    }

    @Test func handlesTheVersion1BlockSize() throws {
        var o = Render.Options()
        o.scale = 4; o.width = 800; o.height = 400
        let frame = StripFrame.sample(counted: [7])
        let (g, decoded) = try #require(StripDecoder.locate(Render.image(frame, counts: [42], o)))
        #expect(g.pitch == 4)
        #expect(decoded.slots[7].count == 42)
    }

    @Test func readsSinglePixelBlocksExactly() throws {
        // Neighbouring 1 px blocks must not bleed into each other when sampled.
        var symbols = StripFrame.sample().symbols
        let (g, _) = try #require(StripDecoder.locate(Render.image(symbols: symbols)))
        #expect(g.pitch == 1)
        symbols[13] = 63; symbols[14] = 0
        #expect(StripDecoder.symbols(Render.image(symbols: symbols), g)?[13...14] == [63, 0])
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
        let g = StripGeometry(originX: 0, originY: 0, pitch: 1)
        #expect(StripDecoder.decodeGrid(img, g) == .failure(.badChecksum))
        #expect(decode(img) == nil)
    }

    @Test func rejectsAnUnknownVersion() {
        var symbols = StripFrame.sample().symbols
        symbols[8] = 5
        let g = StripGeometry(originX: 0, originY: 0, pitch: 1)
        #expect(StripDecoder.decodeGrid(Render.image(symbols: symbols), g) == .failure(.badVersion(5)))
    }

    @Test func rejectsAWrongMarker() {
        let img = Render.image(StripFrame.sample())
        let shifted = StripGeometry(originX: 1, originY: 0, pitch: 1)
        #expect(StripDecoder.decodeGrid(img, shifted) != .success(StripFrame.sample()))
        let g = StripGeometry(originX: 0, originY: 0, pitch: 1)
        var symbols = StripFrame.sample().symbols
        symbols[1] = 63
        #expect(StripDecoder.decodeGrid(Render.image(symbols: symbols), g) == .failure(.badMarker))
    }

    @Test func rejectsAGridOffTheImage() {
        var o = Render.Options()
        o.width = 40   // narrower than the 48 px grid
        let g = StripGeometry(originX: 0, originY: 0, pitch: 1)
        #expect(StripDecoder.decodeGrid(Render.image(StripFrame.sample(), o), g) == .failure(.offImage))
        #expect(StripDecoder.symbols(RGBImage(width: 4, height: 4), g) == nil)
    }

    @Test func rejectsFlatCalibration() {
        var o = Render.Options()
        o.colour = { _ in 128 }
        let g = StripGeometry(originX: 0, originY: 0, pitch: 1)
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

    /// Screenshot of a version 1 strip from the game (WoW Forever, Bartender4). Real pixels:
    /// the marker and calibration still read, and the old version is recognised and rejected.
    @Test func rejectsTheVersion1InGameScreenshot() throws {
        let img = Fixtures.png("ingame-strip-v1.png")
        let g = try #require(StripDecoder.candidates(in: img).first)
        #expect(g == StripGeometry(originX: 0, originY: 0, pitch: 4))
        #expect(StripDecoder.decodeGrid(img, g) == .failure(.badVersion(1)))
        #expect(StripDecoder.locate(img) == nil)
    }
}
