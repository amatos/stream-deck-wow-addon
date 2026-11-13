import Foundation
import ImageIO
import Testing
@testable import IconKit

@Suite struct BuildInfoTests {
    let sample = """
    Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|Version!STRING:0|Product!STRING:0
    us|0|aaa|1.15.7.1|wow_classic_era
    us|1|bbb|1.60.1.70888|wowf
    """

    @Test func parsesRowsByColumnName() {
        let rows = BuildInfo.parse(sample)
        #expect(rows.count == 2)
        #expect(rows[1]["Product"] == "wowf")
        #expect(rows[1]["Version"] == "1.60.1.70888")
        #expect(rows[0]["Active"] == "0")
    }

    @Test func parsesEmptyText() {
        #expect(BuildInfo.parse("").isEmpty)
    }

    @Test func mapsFlavourFolders() {
        #expect(BuildInfo.product(forFlavourFolder: "_forever_") == "wowf")
        #expect(BuildInfo.product(forFlavourFolder: "_retail_") == "wow")
        #expect(BuildInfo.product(forFlavourFolder: "_classic_") == "wow_classic")
        #expect(BuildInfo.product(forFlavourFolder: "_classic_era_") == "wow_classic_era")
        #expect(BuildInfo.product(forFlavourFolder: "_ptr_") == "wowt")
        #expect(BuildInfo.product(forFlavourFolder: "_beta_") == "wow_beta")
        #expect(BuildInfo.product(forFlavourFolder: "Data") == nil)
    }

    @Test func locatesAnInstallFromTheAppBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("_forever_"), withIntermediateDirectories: true)
        try sample.write(to: root.appendingPathComponent(".build.info"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("_forever_/World of Warcraft.app")
        let install = try #require(WoWInstall.locate(appBundle: app))
        #expect(install.root.path == root.path)
        #expect(install.product == "wowf")
        #expect(install.version == "1.60.1.70888")
        #expect(install.storagePath == root.path + "*wowf")
    }
}

@Suite struct IconStoreTests {
    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    let install = WoWInstall(root: URL(fileURLWithPath: "/nonexistent"), product: "wowf", version: "1.2.3")

    func rawBLP() -> Data {
        BLPFile.make(compression: 3, alphaDepth: 8, alphaType: 0, width: 2, height: 2,
                     mip: [UInt8](repeating: 200, count: 16))
    }

    @Test func extractsCachesAndReusesIcons() throws {
        let cache = tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        var opens = 0, reads = 0
        let store = IconStore(install: install, cacheRoot: cache) { _ in
            opens += 1
            return { _ in reads += 1; return rawBLP() }
        }
        let url = try #require(store.png(for: 42))
        #expect(url.lastPathComponent == "42.png")
        #expect(url.deletingLastPathComponent().lastPathComponent == "wowf-1.2.3")
        #expect(store.png(for: 42) == url)
        #expect(store.png(for: 43) != nil)
        #expect(opens == 1)
        #expect(reads == 2)

        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        #expect(image.width == 2 && image.height == 2)
    }

    @Test func remembersFailures() {
        let cache = tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        var reads = 0
        let store = IconStore(install: install, cacheRoot: cache) { _ in
            { _ in reads += 1; return Data("nope".utf8) }
        }
        #expect(store.png(for: 7) == nil)
        #expect(store.png(for: 7) == nil)
        #expect(reads == 1)
    }

    @Test func ignoresIconZero() {
        let store = IconStore(install: install, cacheRoot: tempDir()) { _ in { _ in Data() } }
        #expect(store.png(for: 0) == nil)
    }

    @Test func reportsStorageThatCannotOpen() {
        let cache = tempDir()
        let store = IconStore(install: install, cacheRoot: cache)
        #expect(store.png(for: 136048) == nil)
        #expect(throws: CascStorage.Failure.self) { try CascStorage(path: "/nonexistent*wowf") }
    }

    /// Reads a real icon when WoW Forever is installed on this Mac.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Applications/World of Warcraft/.build.info")))
    func extractsARealIconFromTheInstall() throws {
        let install = try #require(WoWInstall.locate(appBundle: nil))
        let storage = try CascStorage(path: install.storagePath)
        let image = try BLP.decode(try storage.read(fileDataID: 136048))
        #expect(image.width == 64 && image.height == 64)
        // A real icon has varied, mostly opaque pixels.
        let alphas = stride(from: 3, to: image.pixels.count, by: 4).map { image.pixels[$0] }
        #expect(alphas.filter { $0 == 255 }.count > 3000)
        #expect(Set(image.pixels).count > 50)
        #expect(throws: CascStorage.Failure.self) { try storage.read(fileDataID: 0xFFFFFF0) }
    }
}
