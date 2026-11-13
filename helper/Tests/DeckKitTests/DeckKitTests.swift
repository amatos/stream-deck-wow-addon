import CoreGraphics
import Foundation
import ImageIO
import StripKit
import Testing

@testable import DeckKit

/// Reads pixels (r, g, b) from a rendered key, top-left origin.
struct Pixels {
    let w: Int, h: Int
    var bytes: [UInt8]

    init(_ image: CGImage) {
        w = image.width
        h = image.height
        bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(
            data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * w + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }
}

/// A solid orange 64x64 test icon.
func orangeIcon() -> CGImage {
    let ctx = CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    return ctx.makeImage()!
}

func face(_ slot: SlotState?, connected: Bool = true, loaded: Bool = true) -> KeyFace {
    KeyFace(connected: connected, slot: slot, iconLoaded: loaded)
}

@Suite struct KeyRendererTests {
    let usable = SlotState(iconID: 1, hasAction: true, usable: true)

    @Test func rendersAt144Pixels() {
        let img = KeyRenderer.render(face(usable), icon: orangeIcon())
        #expect(img.width == 144 && img.height == 144)
    }

    @Test func emptySlotIsBlack() {
        let p = Pixels(KeyRenderer.render(face(nil), icon: nil))
        #expect(p.at(72, 72) == (0, 0, 0))
    }

    @Test func usableSlotShowsTheIcon() {
        let (r, g, b) = Pixels(KeyRenderer.render(face(usable), icon: orangeIcon())).at(72, 72)
        #expect(r > 240 && (110...150).contains(g) && b < 15)
    }

    @Test func unusableSlotIsGreyAndDark() {
        var slot = usable
        slot.usable = false
        let (r, g, b) = Pixels(KeyRenderer.render(face(slot), icon: orangeIcon())).at(72, 72)
        #expect(abs(r - g) < 6 && abs(g - b) < 6)
        #expect(r < 120)
    }

    @Test func noManaIsTintedBlue() {
        var slot = usable
        slot.usable = false
        slot.noMana = true
        let (r, _, b) = Pixels(KeyRenderer.render(face(slot), icon: orangeIcon())).at(72, 72)
        #expect(b > 90)
        #expect(r < 200)
    }

    @Test func glowDrawsAGoldBorder() {
        var slot = usable
        slot.glow = true
        let p = Pixels(KeyRenderer.render(face(slot), icon: orangeIcon()))
        let (r, g, b) = p.at(5, 72)
        #expect(r > 240 && g > 190 && b < 80)
        #expect(Pixels(KeyRenderer.render(face(usable), icon: orangeIcon())).at(5, 72).1 < 150)
    }

    @Test func countIsDrawnBottomRight() {
        var slot = usable
        slot.hasCount = true
        slot.count = 8
        let p = Pixels(KeyRenderer.render(face(slot), icon: nil))
        var white = 0
        for y in 90..<140 { for x in 90..<140 where p.at(x, y) == (255, 255, 255) { white += 1 } }
        #expect(white > 40)
        let plain = Pixels(KeyRenderer.render(face(usable), icon: nil))
        #expect(plain.at(120, 120) != (255, 255, 255))
    }

    @Test func missingIconShowsAPlaceholder() {
        let (r, g, b) = Pixels(KeyRenderer.render(face(usable, loaded: false), icon: nil)).at(72, 72)
        #expect(r > 30 && r < 60 && abs(r - g) < 5 && b >= g)
    }

    @Test func disconnectedKeysAreFaded() {
        let (r, _, _) = Pixels(KeyRenderer.render(face(usable, connected: false), icon: orangeIcon())).at(72, 72)
        #expect(r < 90)
    }

    @Test func producesAPNGDataURL() throws {
        let url = KeyRenderer.dataURL(face(usable), icon: orangeIcon())
        #expect(url.hasPrefix("data:image/png;base64,"))
        let data = try #require(Data(base64Encoded: String(url.dropFirst("data:image/png;base64,".count))))
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(src, 0, nil)?.width == 144)
    }
}

@Suite struct KeyFaceTests {
    @Test func dropsCountsWhenThereIsNoCount() {
        var slot = SlotState(iconID: 1, hasAction: true, usable: true)
        slot.count = 5
        #expect(face(slot).count == nil)
        slot.hasCount = true
        #expect(face(slot).count == 5)
    }

    @Test func dimmedMeansUnusableForReasonsOtherThanMana() {
        #expect(face(SlotState(iconID: 1, hasAction: true)).dimmed)
        #expect(!face(SlotState(iconID: 1, hasAction: true, noMana: true)).dimmed)
        #expect(!face(SlotState(iconID: 1, hasAction: true, usable: true)).dimmed)
        #expect(!face(nil).dimmed)
    }

    @Test func equalStatesGiveEqualFaces() {
        let a = SlotState(iconID: 9, hasAction: true, usable: true, rangeApplies: true, inRange: true)
        var b = a
        b.inRange = false  // range is not shown, so it does not change the face
        #expect(face(a) == face(b))
        b.glow = true
        #expect(face(a) != face(b))
    }
}

@Suite struct DeckMessageTests {
    @Test func roundTripsEveryMessage() {
        for m in [DeckMessage.slot(slot: 3, image: "data:x"), .hello(version: 1), .press(slot: 59)] {
            #expect(DeckMessage.decode(m.encoded()) == m)
        }
    }

    @Test func decodesThePluginsPressMessage() {
        #expect(DeckMessage.decode(Data(#"{"type":"press","slot":12}"#.utf8)) == .press(slot: 12))
    }

    @Test func rejectsBadMessages() {
        for text in [
            #"{"type":"press"}"#, #"{"type":"press","slot":60}"#, #"{"type":"press","slot":-1}"#,
            #"{"type":"slot","slot":1}"#, #"{"type":"dance"}"#, "not json",
        ] {
            #expect(DeckMessage.decode(Data(text.utf8)) == nil, "\(text)")
        }
    }

    @Test func helloDefaultsToVersionZero() {
        #expect(DeckMessage.decode(Data(#"{"type":"hello"}"#.utf8)) == .hello(version: 0))
    }
}

@Suite struct EmblemTests {
    func render(_ size: Int, gap: CGFloat) -> Pixels {
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        Emblem.drawMono(
            in: ctx, rect: CGRect(x: 0, y: 0, width: size, height: size),
            colour: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), gap: gap)
        return Pixels(ctx.makeImage()!)
    }

    @Test func drawsTheWAndLeavesGapsBetweenKeys() {
        let p = render(120, gap: 6)
        // Top of the W's left stroke is filled; the middle of the top-middle key is not (the W dips there).
        #expect(p.at(8, 34) == (255, 255, 255))
        #expect(p.at(45, 34) == (0, 0, 0))
        // The vertical gap between the first and second key columns stays empty.
        let gapX = Int((120.0 - 18.0) / 4.0) + 3
        #expect(p.at(gapX, 34) == (0, 0, 0))
    }

    @Test func tilesFitTheWidthAndCentreVertically() {
        let box = Emblem.tilesPath(in: CGRect(x: 0, y: 0, width: 100, height: 100), gap: 4).boundingBoxOfPath
        #expect(abs(box.width - 100) < 0.001)
        #expect(abs(box.midY - 50) < 0.001)
        #expect(box.height < box.width)
    }

    @Test func wSpansItsRect() {
        let box = Emblem.wPath(in: CGRect(x: 10, y: 20, width: 40, height: 30)).boundingBoxOfPath
        #expect(box == CGRect(x: 10, y: 20, width: 40, height: 30))
    }
}
