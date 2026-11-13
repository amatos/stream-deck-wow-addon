/// Read-only access to a captured image in 8-bit RGB.
public protocol PixelSource {
    var width: Int { get }
    var height: Int { get }
    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int)
}

/// BGRA pixels in memory (the ScreenCaptureKit format), borrowed from a pointer.
public struct BGRAPixels: PixelSource {
    public let base: UnsafePointer<UInt8>
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int

    public init(base: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) {
        self.base = base
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }

    @inline(__always)
    public func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let p = base + y * bytesPerRow + x * 4
        return (Int(p[2]), Int(p[1]), Int(p[0]))
    }
}

/// An owned RGB image, used by tests and for decoded fixtures.
public struct RGBImage: PixelSource {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]  // r, g, b per pixel

    public init(width: Int, height: Int, fill: (Int, Int, Int) = (0, 0, 0)) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            pixels[i * 3] = UInt8(fill.0)
            pixels[i * 3 + 1] = UInt8(fill.1)
            pixels[i * 3 + 2] = UInt8(fill.2)
        }
    }

    public func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 3
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }

    public mutating func set(_ x: Int, _ y: Int, _ c: (Int, Int, Int)) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 3
        pixels[i] = UInt8(clamping: c.0)
        pixels[i + 1] = UInt8(clamping: c.1)
        pixels[i + 2] = UInt8(clamping: c.2)
    }

    public mutating func fill(x: Int, y: Int, w: Int, h: Int, _ c: (Int, Int, Int)) {
        for yy in y..<(y + h) { for xx in x..<(x + w) { set(xx, yy, c) } }
    }
}
