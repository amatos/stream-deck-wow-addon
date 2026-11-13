/// Finds and decodes the strip in a captured image (docs/strip-format.md §2-§7).
public enum StripDecoder {

    // MARK: Locating

    @inline(__always) static func isMagenta(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 140 && p.g < 110 && p.b > 140 }
    @inline(__always) static func isGreen(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.g > 140 && p.r < 110 && p.b < 110 }
    @inline(__always) static func isCyan(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.g > 140 && p.b > 140 && p.r < 110 }
    @inline(__always) static func isYellow(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 140 && p.g > 140 && p.b < 110 }

    /// Candidate geometries: top-left corners of magenta-green-cyan-yellow runs.
    public static func candidates<P: PixelSource>(in img: P, limit: Int = 16) -> [StripGeometry] {
        var out: [StripGeometry] = []
        for y in 0..<img.height {
            var x = 0
            while x < img.width {
                guard isMagenta(img.rgb(x, y)) else {
                    x += 1
                    continue
                }
                // Only consider the top-left corner of a magenta area.
                if y > 0 && isMagenta(img.rgb(x, y - 1)) {
                    x += 1
                    continue
                }
                if let g = markerGeometry(img, x: x, y: y) {
                    out.append(g)
                    if out.count >= limit { return out }
                }
                // Skip the rest of this magenta run.
                while x < img.width && isMagenta(img.rgb(x, y)) { x += 1 }
            }
        }
        return out
    }

    static func markerGeometry<P: PixelSource>(_ img: P, x: Int, y: Int) -> StripGeometry? {
        var run = 0
        while x + run < img.width && isMagenta(img.rgb(x + run, y)) { run += 1 }
        guard run >= 1 else { return nil }
        // Measure along a row inside the block, away from blended edges.
        let row = y + run / 2
        guard row < img.height else { return nil }
        let tests: [((r: Int, g: Int, b: Int)) -> Bool] = [isMagenta, isGreen, isCyan, isYellow]
        var starts: [Int] = []
        var cx = x
        for test in tests {
            while cx < img.width && !test(img.rgb(cx, row)) {
                cx += 1
                if cx - x > run * 6 { return nil }
            }
            guard cx < img.width else { return nil }
            starts.append(cx)
            while cx < img.width && test(img.rgb(cx, row)) { cx += 1 }
        }
        let pitch = Double(starts[3] - starts[0]) / 3.0
        guard pitch >= 1 else { return nil }
        for i in 1..<4 {
            let gap = Double(starts[i] - starts[i - 1])
            if abs(gap - pitch) > 1.5 { return nil }
        }
        // Keep the run measured on the first row only if it agrees with the pitch.
        if abs(Double(run) - pitch) > 1.5 && Double(run) > pitch { return nil }
        return StripGeometry(originX: x, originY: y, pitch: pitch)
    }

    // MARK: Sampling

    /// Block `index`'s colour, or nil when off-image: its single pixel for blocks under
    /// 2 px, otherwise the average of its central 2x2 pixels.
    static func sample<P: PixelSource>(_ img: P, _ g: StripGeometry, _ index: Int) -> (r: Int, g: Int, b: Int)? {
        let col = index % Spec.width
        let row = index / Spec.width
        if g.pitch < 2 {
            let x = g.originX + Int((Double(col) * g.pitch).rounded(.down))
            let y = g.originY + Int((Double(row) * g.pitch).rounded(.down))
            guard x >= 0, y >= 0, x < img.width, y < img.height else { return nil }
            return img.rgb(x, y)
        }
        let cx = Double(g.originX) + (Double(col) + 0.5) * g.pitch
        let cy = Double(g.originY) + (Double(row) + 0.5) * g.pitch
        let x0 = Int((cx - 0.5).rounded(.down))
        let y0 = Int((cy - 0.5).rounded(.down))
        guard x0 >= 0, y0 >= 0, x0 + 1 < img.width, y0 + 1 < img.height else { return nil }
        var r = 0
        var gg = 0
        var b = 0
        for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let p = img.rgb(x0 + dx, y0 + dy)
            r += p.r
            gg += p.g
            b += p.b
        }
        return (r / 4, gg / 4, b / 4)
    }

    /// Measured values of levels 0...3 per channel, from the calibration blocks.
    public struct Calibration: Equatable, Sendable {
        public var levels: [[Int]]  // [channel][level]

        public init?(samples: [(r: Int, g: Int, b: Int)]) {
            guard samples.count == 4 else { return nil }
            levels = [samples.map(\.r), samples.map(\.g), samples.map(\.b)]
            for ch in levels {
                for k in 1..<4 where ch[k] - ch[k - 1] < 20 { return nil }
            }
        }

        public func classify(_ value: Int, channel: Int) -> Int {
            var best = 0
            var bestDistance = Int.max
            for (k, level) in levels[channel].enumerated() {
                let d = abs(value - level)
                if d < bestDistance {
                    best = k
                    bestDistance = d
                }
            }
            return best
        }

        public func symbol(_ p: (r: Int, g: Int, b: Int)) -> Int {
            classify(p.r, channel: 0) << 4 | classify(p.g, channel: 1) << 2 | classify(p.b, channel: 2)
        }
    }

    /// Reads all symbols, or nil when the grid is off-image or calibration is unusable.
    public static func symbols<P: PixelSource>(_ img: P, _ g: StripGeometry) -> [Int]? {
        var cal: [(r: Int, g: Int, b: Int)] = []
        for i in 4..<8 {
            guard let s = sample(img, g, i) else { return nil }
            cal.append(s)
        }
        guard let calibration = Calibration(samples: cal) else { return nil }
        var out: [Int] = []
        out.reserveCapacity(Spec.symbolCount)
        for i in 0..<Spec.symbolCount {
            guard let s = sample(img, g, i) else { return nil }
            out.append(calibration.symbol(s))
        }
        return out
    }

    // MARK: Decoding

    public enum Failure: Error, Equatable {
        case offImage
        case badMarker
        case badVersion(Int)
        case badChecksum
    }

    /// Decodes the data grid only (counts are left nil).
    public static func decodeGrid<P: PixelSource>(_ img: P, _ g: StripGeometry) -> Result<StripFrame, Failure> {
        guard let s = symbols(img, g) else { return .failure(.offImage) }
        guard Array(s[0..<4]) == Spec.marker else { return .failure(.badMarker) }
        guard s[8] == Spec.version else { return .failure(.badVersion(s[8])) }
        let (a, b) = Spec.checksum(s, from: Spec.checksumFirst, to: Spec.checksumLast)
        guard s[Spec.checksumLast + 1] == a, s[Spec.checksumLast + 2] == b else { return .failure(.badChecksum) }
        var slots: [SlotState] = []
        for i in 0..<Spec.slots {
            let first = Spec.headerSymbols + i * Spec.symbolsPerSlot
            slots.append(SlotState(record: s[first..<(first + Spec.symbolsPerSlot)]))
        }
        return .success(
            StripFrame(
                version: s[8], sequence: s[9] * 64 + s[10], flags: GlobalFlags(symbol: s[11]), slots: slots
            ))
    }

    /// Decodes the grid and fills in counts read from the count area.
    public static func decode<P: PixelSource>(_ img: P, _ g: StripGeometry) -> Result<StripFrame, Failure> {
        decodeGrid(img, g).map { frame in
            var frame = frame
            let counted = frame.slots.indices.filter { frame.slots[$0].hasCount }
            if !counted.isEmpty, let reader = CountReader(img, g) {
                for (k, slot) in counted.enumerated() {
                    frame.slots[slot].count = reader.readCell(img, k)
                }
            }
            return frame
        }
    }

    /// Searches the whole image and returns the first candidate that decodes.
    public static func locate<P: PixelSource>(_ img: P) -> (StripGeometry, StripFrame)? {
        for g in candidates(in: img) {
            if case .success(let frame) = decode(img, g) { return (g, frame) }
        }
        return nil
    }
}
