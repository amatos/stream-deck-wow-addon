// Draws the Stream Deck plugin's static images (1x and @2x PNGs), matching the
// helper's app icon: a W cut into a 4 x 3 grid of keys.
// Usage: swift tools/plugin-images.swift plugin/cc.matos.streamdeck.wowbars.sdPlugin/imgs
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func colour(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ a: CGColor, _ b: CGColor) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: [a, b] as CFArray, locations: [0, 1])!
}

/// Same W outline as tools/app-icon.swift, in rect `r` (y up).
func wPath(in r: CGRect) -> CGPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
    let path = CGMutablePath()
    path.addLines(between: [
        p(0.00, 1.00), p(0.22, 1.00), p(0.32, 0.36), p(0.43, 0.80), p(0.57, 0.80), p(0.68, 0.36),
        p(0.78, 1.00), p(1.00, 1.00), p(0.80, 0.00), p(0.62, 0.00), p(0.50, 0.48), p(0.38, 0.00), p(0.20, 0.00),
    ])
    path.closeSubpath()
    return path
}

enum Style {
    case full  // navy tile, dark keys, gold W (plugin icon)
    case mono  // white W on transparent, split by the grid (category / action list icons)
    case placeholder  // black key, dim keys and W (default key image before the helper connects)
}

/// Draws the 4 x 3 key grid with the W into a square of side `size` (in points of the context).
func emblem(_ ctx: CGContext, size: CGFloat, style: Style) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    let inset: CGFloat
    switch style {
    case .full:
        let body = CGPath(roundedRect: full, cornerWidth: size * 0.2, cornerHeight: size * 0.2, transform: nil)
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        ctx.drawLinearGradient(gradient(colour(0x1D2340), colour(0x090B15)), start: CGPoint(x: 0, y: size), end: .zero, options: [])
        ctx.restoreGState()
        inset = size * 0.12
    case .mono:
        inset = size * 0.02
    case .placeholder:
        ctx.setFillColor(colour(0x000000))
        ctx.fill(full)
        inset = size * 0.18
    }

    let cols = 4
    let rows = 3
    let area = full.insetBy(dx: inset, dy: inset)
    let gap = area.width * 0.035
    let tile = (area.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
    let gridH = CGFloat(rows) * tile + CGFloat(rows - 1) * gap
    let grid = CGRect(x: area.minX, y: full.midY - gridH / 2, width: area.width, height: gridH)
    let radius = tile * 0.17
    var tiles: [CGPath] = []
    for row in 0..<rows {
        for col in 0..<cols {
            let r = CGRect(x: grid.minX + CGFloat(col) * (tile + gap), y: grid.minY + CGFloat(row) * (tile + gap), width: tile, height: tile)
            tiles.append(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        }
    }

    if style != .mono {
        let (top, bottom): (UInt32, UInt32) = style == .full ? (0x262C44, 0x161A2B) : (0x1A1D2A, 0x111320)
        for t in tiles {
            ctx.saveGState()
            ctx.addPath(t)
            ctx.clip()
            ctx.drawLinearGradient(
                gradient(colour(top), colour(bottom)), start: CGPoint(x: 0, y: grid.maxY), end: CGPoint(x: 0, y: grid.minY), options: [])
            ctx.restoreGState()
        }
    }

    let w = wPath(in: grid.insetBy(dx: grid.width * 0.01, dy: grid.height * 0.02))
    ctx.saveGState()
    for t in tiles { ctx.addPath(t) }
    ctx.clip()
    ctx.addPath(w)
    ctx.clip()
    switch style {
    case .full:
        ctx.drawLinearGradient(
            gradient(colour(0xFFE7A0), colour(0xC07A22)), start: CGPoint(x: 0, y: grid.maxY), end: CGPoint(x: 0, y: grid.minY), options: [])
    case .mono:
        ctx.setFillColor(colour(0xFFFFFF))
        ctx.fill(full)
    case .placeholder:
        ctx.drawLinearGradient(
            gradient(colour(0xFFE7A0, 0.35), colour(0xC07A22, 0.35)), start: CGPoint(x: 0, y: grid.maxY), end: CGPoint(x: 0, y: grid.minY),
            options: [])
    }
    ctx.restoreGState()
}

func image(_ name: String, size: Int, style: Style) {
    for scale in [1, 2] {
        let px = size * scale
        let ctx = CGContext(
            data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        emblem(ctx, size: CGFloat(px), style: style)
        let file = out.appendingPathComponent(scale == 1 ? "\(name).png" : "\(name)@2x.png")
        let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }
}

image("plugin", size: 256, style: .full)
image("category", size: 28, style: .mono)
image("action", size: 20, style: .mono)
image("key", size: 72, style: .placeholder)
print("Wrote images to \(out.path)")
