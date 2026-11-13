import Foundation
import ImageIO
import CoreGraphics
@testable import StripKit

/// Renders frames into images the way the addon draws them, for decoder tests.
enum Render {
    static let levels = [0, 85, 170, 255]

    /// 3x5 test glyphs, one string per row; the decoder learns them from the reference line.
    static let font: [[String]] = [
        ["###", "#.#", "#.#", "#.#", "###"], // 0
        [".#.", "##.", ".#.", ".#.", "###"], // 1
        ["###", "..#", "###", "#..", "###"], // 2
        ["###", "..#", ".##", "..#", "###"], // 3
        ["#.#", "#.#", "###", "..#", "..#"], // 4
        ["###", "#..", "###", "..#", "##."], // 5
        ["###", "#..", "###", "#.#", "###"], // 6
        ["###", "..#", ".#.", ".#.", ".#."], // 7
        ["###", "#.#", "###", "#.#", "###"], // 8
        ["###", "#.#", "###", "..#", "###"], // 9
    ]

    struct Options {
        var originX = 0
        var originY = 0
        var scale = 1                       // integer pixel scale (pitch = 4 * scale)
        var width = 320
        var height = 160
        var background = (12, 14, 20)
        var colour: (Int) -> Int = { $0 }   // per-channel distortion
        var drawReference = true
    }

    static func image(_ frame: StripFrame, counts: [Int?] = [], _ o: Options = Options()) -> RGBImage {
        image(symbols: frame.symbols, counts: counts, o)
    }

    static func image(symbols: [Int], counts: [Int?] = [], _ o: Options = Options()) -> RGBImage {
        var img = RGBImage(width: o.width, height: o.height, fill: o.background)
        let pitch = Spec.block * o.scale
        // Grid background and blocks.
        img.fill(x: o.originX, y: o.originY, w: Spec.gridPixelWidth * o.scale,
                 h: Spec.gridRows * pitch, (0, 0, 0))
        for (i, s) in symbols.enumerated() {
            let (r, g, b) = Spec.levels(of: s)
            let c = (o.colour(levels[r]), o.colour(levels[g]), o.colour(levels[b]))
            img.fill(x: o.originX + (i % Spec.width) * pitch, y: o.originY + (i / Spec.width) * pitch,
                     w: pitch, h: pitch, c)
        }
        // Count area background: reference line plus count lines.
        let lines = 1 + (counts.count + Spec.countCellsPerLine - 1) / Spec.countCellsPerLine
        img.fill(x: o.originX, y: o.originY + Spec.countAreaY * o.scale,
                 w: Spec.gridPixelWidth * o.scale, h: lines * Spec.countLineHeight * o.scale, (0, 0, 0))
        if o.drawReference {
            text(&img, "0123456789", x: 0, line: 0, o)
        }
        for (k, count) in counts.enumerated() {
            guard let count else { continue }
            text(&img, String(count), x: (k % Spec.countCellsPerLine) * Spec.countCellWidth,
                 line: 1 + k / Spec.countCellsPerLine, o)
        }
        return img
    }

    static func text(_ img: inout RGBImage, _ s: String, x: Int, line: Int, _ o: Options) {
        var cx = x
        let top = Spec.countAreaY + line * Spec.countLineHeight + 2
        for ch in s {
            if let d = ch.wholeNumberValue {
                glyph(&img, font[d], x: cx, y: top, o)
            }
            cx += 4
        }
    }

    static func glyph(_ img: inout RGBImage, _ rows: [String], x: Int, y: Int, _ o: Options) {
        for (ry, row) in rows.enumerated() {
            for (rx, ch) in row.enumerated() where ch == "#" {
                img.fill(x: o.originX + (x + rx) * o.scale, y: o.originY + (y + ry) * o.scale,
                         w: o.scale, h: o.scale, (255, 255, 255))
            }
        }
    }
}

enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }

    static func png(_ name: String) -> RGBImage {
        let src = CGImageSourceCreateWithURL(url(name) as CFURL, nil)!
        let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let w = cg.width, h = cg.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var img = RGBImage(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                img.set(x, y, (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2])))
            }
        }
        return img
    }

    struct LuaFrame: Decodable {
        struct Slot: Decodable {
            var icon: Int
            var hasAction, usable, noMana, glow, rangeApplies, inRange, hasCount: Bool
        }
        var sequence: Int
        var flags: Int
        var slots: [Slot]
        var symbols: [Int]
    }

    static func luaFrame() throws -> LuaFrame {
        try JSONDecoder().decode(LuaFrame.self, from: Data(contentsOf: url("lua-frame.json")))
    }
}

extension StripFrame {
    static func sample(sequence: Int = 7, counted: [Int] = []) -> StripFrame {
        var slots = (0..<Spec.slots).map { _ in SlotState() }
        slots[0] = SlotState(iconID: 136048, hasAction: true, usable: true)
        slots[4] = SlotState(iconID: 135820, hasAction: true, noMana: true, glow: true)
        slots[30] = SlotState(iconID: 1, hasAction: true, rangeApplies: true, inRange: false)
        for i in counted { slots[i].hasAction = true; slots[i].iconID = 1000 + i; slots[i].hasCount = true }
        return StripFrame(sequence: sequence, flags: GlobalFlags(bindingsApplied: true), slots: slots)
    }
}
