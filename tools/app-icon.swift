// Draws the helper's app icon: a gold W cut into a 4 x 3 grid of Stream Deck-style keys.
// Usage: swift tools/app-icon.swift <output .iconset folder> [preview.png]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func colour(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ a: UInt32, _ b: UInt32) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: [colour(a), colour(b)] as CFArray, locations: [0, 1])!
}

/// The W as a filled outline, in a unit square (y up): flared tops, sharp inner valleys.
func wPath(in r: CGRect) -> CGPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
    let path = CGMutablePath()
    path.addLines(between: [
        p(0.00, 1.00), p(0.22, 1.00),   // left top
        p(0.32, 0.36),                  // down left inner stroke
        p(0.43, 0.80), p(0.57, 0.80),   // middle peak
        p(0.68, 0.36),                  // down right inner stroke
        p(0.78, 1.00), p(1.00, 1.00),   // right top
        p(0.80, 0.00), p(0.62, 0.00),   // right foot
        p(0.50, 0.48),                  // centre valley
        p(0.38, 0.00), p(0.20, 0.00),   // left foot
    ])
    path.closeSubpath()
    return path
}

func draw(size px: Int) -> CGImage {
    let s = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    ctx.interpolationQuality = .high

    // macOS icon body: rounded square inset 100 pt on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: colour(0x000000, 0.45))
    ctx.addPath(bodyPath)
    ctx.setFillColor(colour(0x0D1020))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient(0x1D2340, 0x090B15), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(colour(0xC9963E, 0.55))
    ctx.setLineWidth(6)
    ctx.strokePath()

    // 4 x 3 key grid.
    let cols = 4, rows = 3
    let gap: CGFloat = 20
    let tile: CGFloat = (body.width - 2 * 78 - CGFloat(cols - 1) * gap) / CGFloat(cols)
    let gridW = CGFloat(cols) * tile + CGFloat(cols - 1) * gap
    let gridH = CGFloat(rows) * tile + CGFloat(rows - 1) * gap
    let grid = CGRect(x: body.midX - gridW / 2, y: body.midY - gridH / 2, width: gridW, height: gridH)
    var tiles: [CGPath] = []
    for row in 0..<rows {
        for col in 0..<cols {
            let r = CGRect(x: grid.minX + CGFloat(col) * (tile + gap), y: grid.minY + CGFloat(row) * (tile + gap),
                           width: tile, height: tile)
            tiles.append(CGPath(roundedRect: r, cornerWidth: 26, cornerHeight: 26, transform: nil))
        }
    }

    // Unlit keys.
    for t in tiles {
        ctx.saveGState()
        ctx.addPath(t)
        ctx.clip()
        ctx.drawLinearGradient(gradient(0x262C44, 0x161A2B), start: CGPoint(x: 0, y: grid.maxY), end: CGPoint(x: 0, y: grid.minY), options: [])
        ctx.restoreGState()
        ctx.addPath(t)
        ctx.setStrokeColor(colour(0x3A4263, 0.8))
        ctx.setLineWidth(3)
        ctx.strokePath()
    }

    // The W, lit only where it falls on a key.
    let w = wPath(in: grid.insetBy(dx: 6, dy: 10))
    ctx.saveGState()
    for t in tiles { ctx.addPath(t) }
    ctx.clip()
    ctx.addPath(w)
    ctx.clip()
    ctx.drawLinearGradient(gradient(0xFFE7A0, 0xC07A22), start: CGPoint(x: 0, y: grid.maxY), end: CGPoint(x: 0, y: grid.minY), options: [])
    ctx.restoreGState()

    // A soft glow over the keys that carry the W.
    ctx.saveGState()
    for t in tiles { ctx.addPath(t) }
    ctx.clip()
    ctx.addPath(w)
    ctx.setStrokeColor(colour(0xFFF3C8, 0.55))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    write(draw(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    write(draw(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 2 {
    write(draw(size: 1024), to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
print("Wrote \(iconset.path)")
