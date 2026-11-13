import Testing

@testable import StripKit

@Suite struct CountReaderTests {
    let g = StripGeometry(originX: 0, originY: 0, pitch: 1)

    func frame(counted n: Int) -> StripFrame {
        StripFrame.sample(counted: Array(10..<(10 + n)))
    }

    @Test func learnsTenTemplates() throws {
        let reader = try #require(CountReader(Render.image(frame(counted: 0)), g))
        #expect(reader.templates.count == 10)
        #expect(reader.templates.allSatisfy { $0.width == 3 })
    }

    @Test func needsTheReferenceLine() {
        var o = Render.Options()
        o.drawReference = false
        #expect(CountReader(Render.image(frame(counted: 0), o), g) == nil)
    }

    @Test func readsSingleAndMultiDigitCounts() throws {
        let counts: [Int?] = [0, 7, 20, 1234, 99]
        let decoded = try #require(StripDecoder.locate(Render.image(frame(counted: 5), counts: counts))).1
        #expect(decoded.slots[10..<15].map(\.count) == counts)
    }

    @Test func readsCountsOnLaterLines() throws {
        var o = Render.Options()
        o.height = 200
        let counts: [Int?] = (0..<14).map { $0 * 3 }
        let decoded = try #require(StripDecoder.locate(Render.image(frame(counted: 14), counts: counts, o))).1
        #expect(decoded.slots[10..<24].map(\.count) == counts)
    }

    @Test func emptyCellIsNil() throws {
        let decoded = try #require(StripDecoder.locate(Render.image(frame(counted: 2), counts: [5, nil]))).1
        #expect(decoded.slots[10].count == 5)
        #expect(decoded.slots[11].count == nil)
    }

    @Test func unknownGlyphIsNil() throws {
        var img = Render.image(frame(counted: 1), counts: [nil])
        // A 2-wide blob matches no template width.
        img.fill(x: 0, y: Spec.countAreaY + Spec.countLineHeight + 2, w: 2, h: 5, (255, 255, 255))
        let reader = try #require(CountReader(img, g))
        #expect(reader.readCell(img, 0) == nil)
    }

    @Test func toleratesASinglePixelDifference() throws {
        var img = Render.image(frame(counted: 1), counts: [8])
        img.set(1, Spec.countAreaY + Spec.countLineHeight + 2 + 1, (255, 255, 255))  // fill 8's top hole
        let reader = try #require(CountReader(img, g))
        #expect(reader.readCell(img, 0) == 8)
    }

    @Test func toleratesTwoPixelsButNotThree() throws {
        #expect(CountReader.tolerance(area: 21) == 2)
        #expect(CountReader.tolerance(area: 100) == 5)
        let base = Render.image(frame(counted: 1), counts: [7])
        let reader = try #require(CountReader(base, g))
        let top = Spec.countAreaY + Spec.countLineHeight + 2
        var two = base
        two.set(0, top + 4, (255, 255, 255))
        two.set(2, top + 4, (255, 255, 255))  // 7's bottom row widened
        #expect(reader.readCell(two, 0) == 7)
        var three = two
        three.set(0, top + 2, (255, 255, 255))
        #expect(reader.readCell(three, 0) == nil)
    }

    @Test func rejectsTooManyGlyphs() throws {
        var img = Render.image(frame(counted: 1), counts: [nil])
        // Eight 1-wide glyphs fit in a 32 px cell.
        for i in 0..<8 {
            img.fill(x: i * 3, y: Spec.countAreaY + Spec.countLineHeight + 2, w: 1, h: 5, (255, 255, 255))
        }
        let reader = try #require(CountReader(img, g))
        #expect(reader.readCell(img, 0) == nil)
    }

    @Test func glyphsOfAnOffImageRectIsEmpty() {
        let img = RGBImage(width: 10, height: 10)
        #expect(CountReader.glyphs(img, .init(x: 20, y: 20, w: 5, h: 5)).isEmpty)
        #expect(CountReader.glyphs(img, .init(x: -1, y: 0, w: 5, h: 5)).isEmpty)
    }
}
