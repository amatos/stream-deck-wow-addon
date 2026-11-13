import CoreGraphics
import CoreText
import Foundation
import ImageIO
import StripKit
import UniformTypeIdentifiers

/// Everything that changes how one Stream Deck key looks. Equal faces render identically,
/// so the helper only re-renders and re-sends a key when its face changes.
public struct KeyFace: Hashable, Sendable {
    public var connected: Bool
    public var hasAction: Bool
    public var iconID: Int
    public var iconLoaded: Bool
    public var usable: Bool
    public var noMana: Bool
    public var glow: Bool
    public var count: Int?
    public var hasCount: Bool

    public init(connected: Bool, slot: SlotState?, iconLoaded: Bool) {
        self.connected = connected
        hasAction = slot?.hasAction ?? false
        iconID = slot?.iconID ?? 0
        self.iconLoaded = iconLoaded
        usable = slot?.usable ?? false
        noMana = slot?.noMana ?? false
        glow = slot?.glow ?? false
        hasCount = slot?.hasCount ?? false
        count = hasCount ? slot?.count : nil
    }

    /// Unusable for any reason other than lack of mana (which gets its own tint).
    public var dimmed: Bool { hasAction && !usable && !noMana }
}

/// Draws key images for the Stream Deck.
public enum KeyRenderer {
    /// Key image size in pixels (Stream Deck XL keys are 96 pt; 144 px covers high-DPI).
    public static let size = 144

    static let glowColour = CGColor(srgbRed: 1.0, green: 0.82, blue: 0.2, alpha: 1)
    static let manaTint = CGColor(srgbRed: 0.15, green: 0.35, blue: 1.0, alpha: 0.45)
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Renders a face. `icon` is the slot's icon image, if loaded.
    public static func render(_ face: KeyFace, icon: CGImage?) -> CGImage {
        let s = CGFloat(size)
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(rect)
        ctx.interpolationQuality = .high

        if face.hasAction, let icon {
            let drawn = face.dimmed ? (greyscale(icon) ?? icon) : icon
            ctx.draw(drawn, in: rect)
            if face.dimmed {
                ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
                ctx.fill(rect)
            }
            if face.noMana {
                ctx.setFillColor(manaTint)
                ctx.fill(rect)
            }
        } else if face.hasAction {
            // Icon not extracted yet: a neutral placeholder.
            ctx.setFillColor(CGColor(srgbRed: 0.18, green: 0.18, blue: 0.2, alpha: 1))
            ctx.fill(rect.insetBy(dx: 8, dy: 8))
        }

        if face.glow {
            ctx.setStrokeColor(glowColour)
            ctx.setLineWidth(10)
            ctx.stroke(rect.insetBy(dx: 5, dy: 5))
        }

        if face.hasCount, let count = face.count {
            drawCount(ctx, String(count))
        }

        if !face.connected {
            // No live data: fade everything so stale state is obvious.
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.7))
            ctx.fill(rect)
        }
        return ctx.makeImage()!
    }

    static func greyscale(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func drawCount(_ ctx: CGContext, _ text: String) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 40, nil)!
        func line(fill: CGColor, strokeWidth: Double) -> CTLine {
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
                NSAttributedString.Key(kCTStrokeColorAttributeName as String): CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                NSAttributedString.Key(kCTStrokeWidthAttributeName as String): strokeWidth,
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        }
        let outline = line(fill: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), strokeWidth: 16)
        let body = line(fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), strokeWidth: 0)
        let width = CTLineGetTypographicBounds(body, nil, nil, nil)
        let x = CGFloat(size) - 10 - CGFloat(width)
        let y: CGFloat = 12
        for l in [outline, body] {
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(l, ctx)
        }
    }

    public static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// PNG as a data URL, the form Stream Deck's setImage accepts.
    public static func dataURL(_ face: KeyFace, icon: CGImage?) -> String {
        "data:image/png;base64," + png(render(face, icon: icon)).base64EncodedString()
    }
}
