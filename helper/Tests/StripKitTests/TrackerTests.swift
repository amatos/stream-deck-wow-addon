import Testing
@testable import StripKit

@Suite struct TrackerTests {
    func image(_ frame: StripFrame, at x: Int = 0, counts: [Int?] = []) -> RGBImage {
        var o = Render.Options()
        o.originX = x; o.width = 400
        return Render.image(frame, counts: counts, o)
    }

    @Test func startsSearching() {
        #expect(StripTracker().status(at: 0) == .searching)
    }

    @Test func findsAndFollowsTheStrip() {
        let t = StripTracker()
        #expect(t.process(image(.sample(sequence: 1)), now: 0))
        #expect(t.status(at: 0.1) == .connected)
        #expect(t.frame?.sequence == 1)
        // Same sequence again is not new.
        #expect(!t.process(image(.sample(sequence: 1)), now: 0.1))
        #expect(t.process(image(.sample(sequence: 2)), now: 0.2))
    }

    @Test func goesStaleWithoutGoodFrames() {
        let t = StripTracker()
        t.process(image(.sample()), now: 0)
        #expect(t.status(at: 2.4) == .connected)
        #expect(t.status(at: 2.6) == .stale)
    }

    @Test func toleratesATornFrame() {
        let t = StripTracker()
        t.process(image(.sample(sequence: 1)), now: 0)
        var torn = StripFrame.sample(sequence: 2).symbols
        torn[100] ^= 3
        var o = Render.Options(); o.width = 400
        #expect(!t.process(Render.image(symbols: torn, o), now: 0.05))
        #expect(t.lastFailure == .badChecksum)
        #expect(t.badFrames == 1)
        #expect(t.geometry != nil)
        #expect(t.frame?.sequence == 1)
        #expect(t.process(image(.sample(sequence: 3)), now: 0.1))
        #expect(t.badFrames == 0)
    }

    @Test func searchesAgainWhenTheStripMoves() {
        let t = StripTracker()
        t.process(image(.sample(sequence: 1)), now: 0)
        #expect(t.process(image(.sample(sequence: 2), at: 100), now: 1))
        #expect(t.geometry?.originX == 100)
    }

    @Test func throttlesSearches() {
        let t = StripTracker()
        let blank = RGBImage(width: 400, height: 160)
        t.process(blank, now: 0)
        #expect(t.lastSearchTime == 0)
        t.process(blank, now: 0.2)
        #expect(t.lastSearchTime == 0)
        // Even a good image waits for the search interval.
        #expect(!t.process(image(.sample()), now: 0.3))
        #expect(t.process(image(.sample()), now: 0.6))
    }

    @Test func forgetsTheGeometryWhenTheStripDisappears() {
        let t = StripTracker()
        t.process(image(.sample()), now: 0)
        t.process(RGBImage(width: 400, height: 160), now: 1)
        #expect(t.geometry == nil)
        #expect(t.frame != nil)
    }

    @Test func keepsTheLastCountWhenUnreadable() {
        let t = StripTracker()
        let frame = StripFrame.sample(counted: [3])
        t.process(image(frame, counts: [5]), now: 0)
        #expect(t.frame?.slots[3].count == 5)
        var next = frame; next.sequence += 1
        t.process(image(next, counts: [nil]), now: 0.1)
        #expect(t.frame?.slots[3].count == 5)
    }

    @Test func dropsTheOldCountWhenTheIconChanges() {
        let t = StripTracker()
        let frame = StripFrame.sample(counted: [3])
        t.process(image(frame, counts: [5]), now: 0)
        var next = frame; next.sequence += 1; next.slots[3].iconID = 4242
        t.process(image(next, counts: [nil]), now: 0.1)
        #expect(t.frame?.slots[3].count == nil)
    }
}
