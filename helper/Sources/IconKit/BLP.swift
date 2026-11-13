import Foundation

/// An 8-bit RGBA image.
public struct RGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]  // r, g, b, a per pixel

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * width + x) * 4
        return Array(pixels[i..<(i + 4)])
    }
}

/// Decodes the first mip level of Blizzard BLP2 textures (WoW icons).
public enum BLP {
    public enum DecodeError: Error, Equatable {
        case notBLP2
        case truncated
        case unsupported(compression: Int, alphaType: Int)
    }

    static let headerSize = 148
    static let paletteSize = 1024

    public static func decode(_ data: Data) throws -> RGBAImage {
        let b = [UInt8](data)
        guard b.count >= headerSize, b[0] == 0x42, b[1] == 0x4C, b[2] == 0x50, b[3] == 0x32 else {
            throw DecodeError.notBLP2
        }
        let compression = Int(b[8])
        let alphaDepth = Int(b[9])
        let alphaType = Int(b[10])
        let width = Int(u32(b, 12))
        let height = Int(u32(b, 16))
        let offset = Int(u32(b, 20))
        let size = Int(u32(b, 84))
        guard width > 0, height > 0, width <= 4096, height <= 4096,
            offset >= 0, size >= 0, offset + size <= b.count
        else { throw DecodeError.truncated }
        let mip = b[offset..<(offset + size)]

        switch compression {
        case 1:
            guard b.count >= headerSize + paletteSize else { throw DecodeError.truncated }
            return try palette(
                Array(mip), palette: Array(b[headerSize..<(headerSize + paletteSize)]),
                width: width, height: height, alphaDepth: alphaDepth)
        case 2:
            let format: DXT
            switch (alphaDepth, alphaType) {
            case (0, _), (1, _): format = .dxt1(alpha: alphaDepth > 0)
            case (_, 1): format = .dxt3
            case (_, 7): format = .dxt5
            default: throw DecodeError.unsupported(compression: compression, alphaType: alphaType)
            }
            return try dxt(Array(mip), width: width, height: height, format: format)
        case 3:
            guard mip.count >= width * height * 4 else { throw DecodeError.truncated }
            var out = [UInt8](repeating: 0, count: width * height * 4)
            for i in 0..<(width * height) {
                let p = mip.startIndex + i * 4
                out[i * 4] = mip[p + 2]
                out[i * 4 + 1] = mip[p + 1]
                out[i * 4 + 2] = mip[p]
                out[i * 4 + 3] = mip[p + 3]
            }
            return RGBAImage(width: width, height: height, pixels: out)
        default:
            throw DecodeError.unsupported(compression: compression, alphaType: alphaType)
        }
    }

    static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    static func u16(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | Int(b[i + 1]) << 8
    }

    // MARK: Palette

    static func palette(_ mip: [UInt8], palette: [UInt8], width: Int, height: Int, alphaDepth: Int) throws -> RGBAImage {
        let n = width * height
        let alphaBytes = (n * alphaDepth + 7) / 8
        guard mip.count >= n + alphaBytes else { throw DecodeError.truncated }
        var out = [UInt8](repeating: 0, count: n * 4)
        for i in 0..<n {
            let p = Int(mip[i]) * 4
            out[i * 4] = palette[p + 2]
            out[i * 4 + 1] = palette[p + 1]
            out[i * 4 + 2] = palette[p]
            out[i * 4 + 3] = alpha(mip, at: i, base: n, depth: alphaDepth)
        }
        return RGBAImage(width: width, height: height, pixels: out)
    }

    static func alpha(_ mip: [UInt8], at i: Int, base: Int, depth: Int) -> UInt8 {
        switch depth {
        case 1: return (mip[base + i / 8] >> UInt8(i % 8)) & 1 == 1 ? 255 : 0
        case 4: return ((mip[base + i / 2] >> UInt8((i % 2) * 4)) & 0xF) * 17
        case 8: return mip[base + i]
        default: return 255
        }
    }

    // MARK: DXT

    enum DXT: Equatable {
        case dxt1(alpha: Bool)
        case dxt3
        case dxt5

        var blockSize: Int { if case .dxt1 = self { return 8 } else { return 16 } }
    }

    static func dxt(_ mip: [UInt8], width: Int, height: Int, format: DXT) throws -> RGBAImage {
        let bw = (width + 3) / 4
        let bh = (height + 3) / 4
        guard mip.count >= bw * bh * format.blockSize else { throw DecodeError.truncated }
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for by in 0..<bh {
            for bx in 0..<bw {
                let block = (by * bw + bx) * format.blockSize
                var alphas = [UInt8](repeating: 255, count: 16)
                let colourAt: Int
                switch format {
                case .dxt1: colourAt = block
                case .dxt3:
                    for i in 0..<16 {
                        let nibble = (mip[block + i / 2] >> UInt8((i % 2) * 4)) & 0xF
                        alphas[i] = nibble * 17
                    }
                    colourAt = block + 8
                case .dxt5:
                    alphas = dxt5Alpha(mip, block)
                    colourAt = block + 8
                }
                var transparent = false
                if case .dxt1(let a) = format { transparent = a }
                let colours = colourBlock(
                    mip, colourAt, threeColourMode: format != .dxt3 && format != .dxt5,
                    transparentBlack: transparent)
                for i in 0..<16 {
                    let x = bx * 4 + i % 4
                    let y = by * 4 + i / 4
                    guard x < width, y < height else { continue }
                    let c = colours[i]
                    let o = (y * width + x) * 4
                    out[o] = c.0
                    out[o + 1] = c.1
                    out[o + 2] = c.2
                    out[o + 3] = format == .dxt3 || format == .dxt5 ? alphas[i] : c.3
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: out)
    }

    static func rgb565(_ v: Int) -> (Int, Int, Int) {
        let r = (v >> 11) & 31
        let g = (v >> 5) & 63
        let b = v & 31
        return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))
    }

    /// Returns 16 RGBA texels for a DXT colour block.
    static func colourBlock(_ m: [UInt8], _ at: Int, threeColourMode: Bool, transparentBlack: Bool) -> [(UInt8, UInt8, UInt8, UInt8)] {
        let v0 = u16(m, at)
        let v1 = u16(m, at + 2)
        let c0 = rgb565(v0)
        let c1 = rgb565(v1)
        var palette: [(Int, Int, Int, Int)] = [(c0.0, c0.1, c0.2, 255), (c1.0, c1.1, c1.2, 255)]
        if v0 > v1 || !threeColourMode {
            palette.append(((2 * c0.0 + c1.0) / 3, (2 * c0.1 + c1.1) / 3, (2 * c0.2 + c1.2) / 3, 255))
            palette.append(((c0.0 + 2 * c1.0) / 3, (c0.1 + 2 * c1.1) / 3, (c0.2 + 2 * c1.2) / 3, 255))
        } else {
            palette.append(((c0.0 + c1.0) / 2, (c0.1 + c1.1) / 2, (c0.2 + c1.2) / 2, 255))
            palette.append((0, 0, 0, transparentBlack ? 0 : 255))
        }
        let bits = u32(m, at + 4)
        return (0..<16).map { i in
            let p = palette[Int((bits >> UInt32(i * 2)) & 3)]
            return (UInt8(p.0), UInt8(p.1), UInt8(p.2), UInt8(p.3))
        }
    }

    static func dxt5Alpha(_ m: [UInt8], _ at: Int) -> [UInt8] {
        let a0 = Int(m[at])
        let a1 = Int(m[at + 1])
        var table = [a0, a1]
        if a0 > a1 {
            for k in 1...6 { table.append(((7 - k) * a0 + k * a1) / 7) }
        } else {
            for k in 1...4 { table.append(((5 - k) * a0 + k * a1) / 5) }
            table += [0, 255]
        }
        var bits: UInt64 = 0
        for k in 0..<6 { bits |= UInt64(m[at + 2 + k]) << UInt64(8 * k) }
        return (0..<16).map { i in UInt8(table[Int((bits >> UInt64(3 * i)) & 7)]) }
    }
}
