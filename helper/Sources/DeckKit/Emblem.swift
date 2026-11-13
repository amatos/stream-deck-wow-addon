import CoreGraphics

/// The project's mark: a W cut into a 4 x 3 grid of keys. Same shape as
/// tools/app-icon.swift and tools/plugin-images.swift.
public enum Emblem {
    /// W outline in `r` (y up): flared tops, sharp inner valleys.
    public static func wPath(in r: CGRect) -> CGPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let path = CGMutablePath()
        path.addLines(between: [
            p(0.00, 1.00), p(0.22, 1.00), p(0.32, 0.36), p(0.43, 0.80), p(0.57, 0.80), p(0.68, 0.36),
            p(0.78, 1.00), p(1.00, 1.00), p(0.80, 0.00), p(0.62, 0.00), p(0.50, 0.48), p(0.38, 0.00), p(0.20, 0.00),
        ])
        path.closeSubpath()
        return path
    }

    /// The 4 x 3 key tiles, as one path, fitted to the width of `r` and centred vertically.
    public static func tilesPath(in r: CGRect, gap: CGFloat) -> CGPath {
        let cols = 4, rows = 3
        let tile = (r.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let gridH = CGFloat(rows) * tile + CGFloat(rows - 1) * gap
        let top = r.midY - gridH / 2
        let radius = tile * 0.17
        let path = CGMutablePath()
        for row in 0..<rows {
            for col in 0..<cols {
                let t = CGRect(x: r.minX + CGFloat(col) * (tile + gap), y: top + CGFloat(row) * (tile + gap),
                               width: tile, height: tile)
                path.addRoundedRect(in: t, cornerWidth: radius, cornerHeight: radius)
            }
        }
        return path
    }

    /// Fills the W, split by the key grid, in `colour` within `r` (a single-colour mark, e.g. a template image).
    public static func drawMono(in ctx: CGContext, rect r: CGRect, colour: CGColor, gap: CGFloat) {
        let tiles = tilesPath(in: r, gap: gap)
        let grid = tiles.boundingBoxOfPath
        ctx.saveGState()
        ctx.addPath(tiles)
        ctx.clip()
        ctx.addPath(wPath(in: grid))
        ctx.setFillColor(colour)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
