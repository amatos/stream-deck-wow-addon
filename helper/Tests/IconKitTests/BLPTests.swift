import Foundation
import Testing
@testable import IconKit

/// Builds BLP2 files for tests.
enum BLPFile {
    static func make(compression: UInt8, alphaDepth: UInt8, alphaType: UInt8,
                     width: Int, height: Int, palette: [UInt8] = [], mip: [UInt8]) -> Data {
        var b = [UInt8]("BLP2".utf8)
        b += le32(1)
        b += [compression, alphaDepth, alphaType, 0]
        b += le32(UInt32(width)) + le32(UInt32(height))
        let offset = 148 + 1024
        b += le32(UInt32(offset)) + [UInt8](repeating: 0, count: 15 * 4)
        b += le32(UInt32(mip.count)) + [UInt8](repeating: 0, count: 15 * 4)
        var pal = palette
        pal += [UInt8](repeating: 0, count: 1024 - pal.count)
        b += pal
        b += mip
        return Data(b)
    }

    static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)]
    }

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
}

@Suite struct BLPTests {
    @Test func rejectsNonBLP() {
        #expect(throws: BLP.DecodeError.notBLP2) { try BLP.decode(Data("PNG!".utf8)) }
        #expect(throws: BLP.DecodeError.notBLP2) { try BLP.decode(Data(repeating: 0, count: 200)) }
    }

    @Test func rejectsTruncatedMips() {
        var data = BLPFile.make(compression: 3, alphaDepth: 8, alphaType: 0, width: 2, height: 2, mip: [1, 2, 3])
        #expect(throws: BLP.DecodeError.truncated) { try BLP.decode(data) }
        data = BLPFile.make(compression: 2, alphaDepth: 0, alphaType: 0, width: 8, height: 8, mip: [0, 0])
        #expect(throws: BLP.DecodeError.truncated) { try BLP.decode(data) }
        data = BLPFile.make(compression: 1, alphaDepth: 8, alphaType: 0, width: 4, height: 4, mip: [0])
        #expect(throws: BLP.DecodeError.truncated) { try BLP.decode(data) }
    }

    @Test func rejectsAMipPastTheEnd() {
        var bytes = [UInt8](BLPFile.make(compression: 3, alphaDepth: 8, alphaType: 0, width: 1, height: 1, mip: [1, 2, 3, 4]))
        bytes[84] = 200   // mip size beyond the data
        #expect(throws: BLP.DecodeError.truncated) { try BLP.decode(Data(bytes)) }
    }

    @Test func rejectsUnknownFormats() {
        let jpeg = BLPFile.make(compression: 0, alphaDepth: 0, alphaType: 0, width: 1, height: 1, mip: [0])
        #expect(throws: BLP.DecodeError.unsupported(compression: 0, alphaType: 0)) { try BLP.decode(jpeg) }
        let odd = BLPFile.make(compression: 2, alphaDepth: 8, alphaType: 3, width: 4, height: 4,
                               mip: [UInt8](repeating: 0, count: 16))
        #expect(throws: BLP.DecodeError.unsupported(compression: 2, alphaType: 3)) { try BLP.decode(odd) }
    }

    @Test func decodesRawBGRA() throws {
        let img = try BLP.decode(BLPFile.make(compression: 3, alphaDepth: 8, alphaType: 0, width: 2, height: 1,
                                              mip: [10, 20, 30, 40, 1, 2, 3, 4]))
        #expect(img.width == 2 && img.height == 1)
        #expect(img.pixel(0, 0) == [30, 20, 10, 40])
        #expect(img.pixel(1, 0) == [3, 2, 1, 4])
    }

    @Test func decodesPaletteWithEachAlphaDepth() throws {
        let palette: [UInt8] = [255, 0, 0, 0, /* blue */ 0, 255, 0, 0 /* green */]
        let indices: [UInt8] = [0, 1, 1, 0]

        let a8 = try BLP.decode(BLPFile.make(compression: 1, alphaDepth: 8, alphaType: 0, width: 2, height: 2,
                                             palette: palette, mip: indices + [10, 20, 30, 40]))
        #expect(a8.pixel(0, 0) == [0, 0, 255, 10])
        #expect(a8.pixel(1, 0) == [0, 255, 0, 20])

        let a4 = try BLP.decode(BLPFile.make(compression: 1, alphaDepth: 4, alphaType: 0, width: 2, height: 2,
                                             palette: palette, mip: indices + [0xF1, 0x08]))
        #expect(a4.pixel(0, 0)[3] == 17)
        #expect(a4.pixel(1, 0)[3] == 255)
        #expect(a4.pixel(0, 1)[3] == 136)
        #expect(a4.pixel(1, 1)[3] == 0)

        let a1 = try BLP.decode(BLPFile.make(compression: 1, alphaDepth: 1, alphaType: 0, width: 2, height: 2,
                                             palette: palette, mip: indices + [0b0101]))
        #expect(a1.pixels.enumerated().filter { $0.offset % 4 == 3 }.map(\.element) == [255, 0, 255, 0])

        let a0 = try BLP.decode(BLPFile.make(compression: 1, alphaDepth: 0, alphaType: 0, width: 2, height: 2,
                                             palette: palette, mip: indices))
        #expect(a0.pixel(1, 1) == [0, 0, 255, 255])
    }

    /// A DXT colour block: endpoints and 2-bit indices for 16 texels.
    func colourBlock(_ c0: Int, _ c1: Int, _ indices: [Int]) -> [UInt8] {
        var bits: UInt32 = 0
        for (i, v) in indices.enumerated() { bits |= UInt32(v) << UInt32(i * 2) }
        return BLPFile.le16(c0) + BLPFile.le16(c1) + BLPFile.le32(bits)
    }

    let red = 0xF800, blue = 0x001F

    @Test func decodesDXT1FourColourMode() throws {
        let block = colourBlock(red, blue, [0, 1, 2, 3] + [Int](repeating: 0, count: 12))
        let img = try BLP.decode(BLPFile.make(compression: 2, alphaDepth: 0, alphaType: 0, width: 4, height: 4, mip: block))
        #expect(img.pixel(0, 0) == [255, 0, 0, 255])
        #expect(img.pixel(1, 0) == [0, 0, 255, 255])
        #expect(img.pixel(2, 0) == [170, 0, 85, 255])
        #expect(img.pixel(3, 0) == [85, 0, 170, 255])
    }

    @Test func decodesDXT1ThreeColourModeWithTransparency() throws {
        let block = colourBlock(blue, red, [2, 3] + [Int](repeating: 0, count: 14))
        let opaque = try BLP.decode(BLPFile.make(compression: 2, alphaDepth: 0, alphaType: 0, width: 4, height: 4, mip: block))
        #expect(opaque.pixel(0, 0) == [127, 0, 127, 255])
        #expect(opaque.pixel(1, 0) == [0, 0, 0, 255])
        let alpha = try BLP.decode(BLPFile.make(compression: 2, alphaDepth: 1, alphaType: 0, width: 4, height: 4, mip: block))
        #expect(alpha.pixel(1, 0) == [0, 0, 0, 0])
    }

    @Test func decodesDXT3ExplicitAlpha() throws {
        var alpha = [UInt8](repeating: 0xFF, count: 8)
        alpha[0] = 0x50   // texel 0 = 0, texel 1 = 5
        let block = alpha + colourBlock(red, blue, [Int](repeating: 1, count: 16))
        let img = try BLP.decode(BLPFile.make(compression: 2, alphaDepth: 8, alphaType: 1, width: 4, height: 4, mip: block))
        #expect(img.pixel(0, 0) == [0, 0, 255, 0])
        #expect(img.pixel(1, 0) == [0, 0, 255, 85])
        #expect(img.pixel(2, 0)[3] == 255)
    }

    @Test func decodesDXT5InterpolatedAlpha() throws {
        // a0 > a1: eight-value table. Texel 0 index 0 (a0), texel 1 index 1 (a1), texel 2 index 2.
        let bits: UInt64 = 0 | 1 << 3 | 2 << 6
        var alpha: [UInt8] = [210, 70]
        for k in 0..<6 { alpha.append(UInt8(bits >> UInt64(8 * k) & 0xFF)) }
        let block = alpha + colourBlock(red, red, [Int](repeating: 0, count: 16))
        let img = try BLP.decode(BLPFile.make(compression: 2, alphaDepth: 8, alphaType: 7, width: 4, height: 4, mip: block))
        #expect(img.pixel(0, 0)[3] == 210)
        #expect(img.pixel(1, 0)[3] == 70)
        #expect(img.pixel(2, 0)[3] == 190)   // (6*210 + 1*70) / 7
    }

    @Test func dxt5SixValueTableHasZeroAndFull() {
        // a0 <= a1: indices 6 and 7 are 0 and 255.
        let bits: UInt64 = 6 | 7 << 3 | 2 << 6
        var block: [UInt8] = [50, 100]
        for k in 0..<6 { block.append(UInt8(bits >> UInt64(8 * k) & 0xFF)) }
        let a = BLP.dxt5Alpha(block, 0)
        #expect(a[0] == 0 && a[1] == 255)
        #expect(a[2] == 60)   // (4*50 + 1*100) / 5
    }

    @Test func clipsBlocksAtOddSizes() throws {
        let block = colourBlock(red, blue, [Int](repeating: 0, count: 16))
        let img = try BLP.decode(BLPFile.make(compression: 2, alphaDepth: 0, alphaType: 0, width: 2, height: 3, mip: block))
        #expect(img.pixels.count == 2 * 3 * 4)
        #expect(img.pixel(1, 2) == [255, 0, 0, 255])
    }
}
