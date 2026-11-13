import CascBridge
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads files by FileDataID from a local install through CascLib.
public final class CascStorage {
    public struct Failure: Error, Equatable {
        public var code: Int32
    }

    private let handle: OpaquePointer

    public init(path: String) throws {
        var error: Int32 = 0
        guard let h = casc_bridge_open(path, &error) else { throw Failure(code: error) }
        handle = h
    }

    deinit { casc_bridge_close(handle) }

    public func read(fileDataID: UInt32) throws -> Data {
        var bytes: UnsafeMutablePointer<UInt8>?
        var size = 0
        let code = casc_bridge_read(handle, fileDataID, &bytes, &size)
        guard code == 0, let bytes else { throw Failure(code: code) }
        defer { casc_bridge_free(bytes) }
        return Data(bytes: bytes, count: size)
    }
}

/// Extracts icons from the install on demand and caches them as PNG files,
/// one folder per client version. Thread-safe; calls block while extracting.
public final class IconStore: @unchecked Sendable {
    public let install: WoWInstall
    public let directory: URL

    private let lock = NSLock()
    private var storage: CascStorage?
    private var failed: Set<Int> = []
    private let openStorage: (WoWInstall) throws -> (UInt32) throws -> Data

    /// `cacheRoot` holds one subfolder per client version.
    public init(install: WoWInstall, cacheRoot: URL,
                reader: ((WoWInstall) throws -> (UInt32) throws -> Data)? = nil) {
        self.install = install
        directory = cacheRoot.appendingPathComponent("\(install.product)-\(install.version)", isDirectory: true)
        openStorage = reader ?? { install in
            let storage = try CascStorage(path: install.storagePath)
            return { try storage.read(fileDataID: $0) }
        }
    }

    private var readFile: ((UInt32) throws -> Data)?

    public func cachedURL(for id: Int) -> URL {
        directory.appendingPathComponent("\(id).png")
    }

    /// Returns the PNG for an icon, extracting it first if needed. Nil when the icon
    /// cannot be read or decoded (failures are remembered and not retried).
    public func png(for id: Int) -> URL? {
        guard id > 0 else { return nil }
        let url = cachedURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        lock.lock()
        defer { lock.unlock() }
        if failed.contains(id) { return nil }
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do {
            if readFile == nil { readFile = try openStorage(install) }
            let image = try BLP.decode(try readFile!(UInt32(id)))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PNG.write(image, to: url)
            return url
        } catch {
            failed.insert(id)
            return nil
        }
    }
}

public enum PNG {
    public struct WriteError: Error {}

    public static func cgImage(_ image: RGBAImage) -> CGImage? {
        let data = Data(image.pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    public static func write(_ image: RGBAImage, to url: URL) throws {
        guard let cg = cgImage(image),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw WriteError() }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw WriteError() }
    }
}
