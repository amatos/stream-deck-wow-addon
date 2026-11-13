/// Follows the strip across captured frames: remembers where it is, searches
/// again when it moves, and keeps the last good state across bad frames.
public final class StripTracker {
    public enum Status: Equatable, Sendable {
        case searching
        case connected
        case stale   // found before, but no good frame recently
    }

    /// Seconds without a good frame before the state counts as stale (heartbeat is 1 s).
    public var staleAfter = 2.5
    /// Minimum seconds between full-image searches.
    public var searchInterval = 0.5

    public private(set) var geometry: StripGeometry?
    public private(set) var frame: StripFrame?
    public private(set) var lastGoodTime = -Double.infinity
    public private(set) var lastSearchTime = -Double.infinity
    public private(set) var badFrames = 0
    public private(set) var lastFailure: StripDecoder.Failure?

    public init() {}

    public func status(at now: Double) -> Status {
        guard frame != nil else { return .searching }
        return now - lastGoodTime <= staleAfter ? .connected : .stale
    }

    /// Processes one captured image. Returns true when a new sequence was decoded.
    @discardableResult
    public func process<P: PixelSource>(_ img: P, now: Double) -> Bool {
        if let g = geometry {
            switch StripDecoder.decode(img, g) {
            case .success(let f):
                return accept(f, now: now)
            case .failure(let failure):
                lastFailure = failure
                badFrames += 1
                // A single torn frame is normal; search again if it persists.
                if failure == .badChecksum && badFrames < 3 { return false }
            }
        }
        guard now - lastSearchTime >= searchInterval else { return false }
        lastSearchTime = now
        if let (g, f) = StripDecoder.locate(img) {
            geometry = g
            return accept(f, now: now)
        }
        geometry = nil
        return false
    }

    private func accept(_ new: StripFrame, now: Double) -> Bool {
        var merged = new
        // Keep the last readable count for a slot whose count could not be read.
        if let old = frame {
            for i in merged.slots.indices where merged.slots[i].hasCount && merged.slots[i].count == nil {
                let prev = old.slots[i]
                if prev.iconID == merged.slots[i].iconID { merged.slots[i].count = prev.count }
            }
        }
        let isNew = frame?.sequence != merged.sequence || frame != merged
        frame = merged
        lastGoodTime = now
        badFrames = 0
        lastFailure = nil
        return isNew
    }
}
