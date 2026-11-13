/// Reads count digits from the count area (§7) using glyph templates learned
/// from the reference line "0123456789".
public struct CountReader {
    /// A glyph as columns of ink bits, top to bottom across the line height.
    public struct Glyph: Equatable, Sendable {
        public var columns: [[Bool]]
        public var width: Int { columns.count }
    }

    public let templates: [Glyph]  // index = digit
    let geometry: StripGeometry

    /// Learns templates from the reference line. Nil when it does not hold exactly 10 glyphs.
    public init?<P: PixelSource>(_ img: P, _ g: StripGeometry) {
        geometry = g
        let rect = Self.lineRect(g, line: 0, x: 0, width: Spec.countAreaWidth)
        let glyphs = Self.glyphs(img, rect)
        guard glyphs.count == 10 else { return nil }
        templates = glyphs
    }

    struct Rect { var x, y, w, h: Int }

    /// Rect of a count line, offsets in strip pixels (scaled to captured pixels).
    static func lineRect(_ g: StripGeometry, line: Int, x: Int, width: Int) -> Rect {
        let s = g.scale
        func px(_ v: Int) -> Int { Int((Double(v) * s).rounded()) }
        return Rect(
            x: g.originX + px(x),
            y: g.originY + px(Spec.countAreaY + line * Spec.countLineHeight),
            w: px(width),
            h: px(Spec.countLineHeight)
        )
    }

    @inline(__always) static func ink(_ p: (r: Int, g: Int, b: Int)) -> Bool {
        (p.r * 299 + p.g * 587 + p.b * 114) / 1000 > 128
    }

    /// Splits a rect into glyphs on empty columns.
    static func glyphs<P: PixelSource>(_ img: P, _ r: Rect) -> [Glyph] {
        var out: [Glyph] = []
        var current: [[Bool]] = []
        let x1 = min(r.x + r.w, img.width)
        let y1 = min(r.y + r.h, img.height)
        guard r.x >= 0, r.y >= 0, x1 > r.x, y1 > r.y else { return [] }
        for x in r.x..<x1 {
            let column = (r.y..<y1).map { ink(img.rgb(x, $0)) }
            if column.contains(true) {
                current.append(column)
            } else if !current.isEmpty {
                out.append(Glyph(columns: current))
                current = []
            }
        }
        if !current.isEmpty { out.append(Glyph(columns: current)) }
        return out
    }

    /// Pixels a glyph may differ from its template (§7): 2, or 5% of the glyph area if larger.
    static func tolerance(area: Int) -> Int { max(2, area / 20) }

    /// Best matching digit, allowing a few differing pixels; nil when nothing is close.
    public func match(_ glyph: Glyph) -> Int? {
        var best: Int?
        var bestMiss = Int.max
        for (digit, t) in templates.enumerated() where t.width == glyph.width {
            var miss = 0
            for (a, b) in zip(t.columns, glyph.columns) {
                for (p, q) in zip(a, b) where p != q { miss += 1 }
            }
            if miss < bestMiss {
                best = digit
                bestMiss = miss
            }
        }
        let area = glyph.width * (glyph.columns.first?.count ?? 0)
        guard let digit = best, bestMiss <= Self.tolerance(area: area) else { return nil }
        return digit
    }

    /// Reads count cell `k` (0-based). Nil when empty or unreadable.
    public func readCell<P: PixelSource>(_ img: P, _ k: Int) -> Int? {
        let line = 1 + k / Spec.countCellsPerLine
        let col = k % Spec.countCellsPerLine
        let rect = Self.lineRect(geometry, line: line, x: col * Spec.countCellWidth, width: Spec.countCellWidth)
        let glyphs = Self.glyphs(img, rect)
        guard !glyphs.isEmpty, glyphs.count <= 7 else { return nil }
        var value = 0
        for glyph in glyphs {
            guard let d = match(glyph) else { return nil }
            value = value * 10 + d
        }
        return value
    }
}
