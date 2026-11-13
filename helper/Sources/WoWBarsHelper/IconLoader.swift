import AppKit
import IconKit

/// Loads icon images for the UI from the icon cache, extracting them from the
/// WoW install in the background on first use. Main thread only.
final class IconLoader {
    static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cc.matos.streamdeck.wowbars.helper/icons", isDirectory: true)
    }

    /// Called with each newly loaded icon.
    var onLoad: ((Int, NSImage) -> Void)?

    private(set) var store: IconStore?
    private var pending: Set<Int> = []
    private var loaded: Set<Int> = []
    private let queue = DispatchQueue(label: "WoWBarsHelper.icons", qos: .utility)

    /// Uses the install of the running client, or the default location.
    func prepare(appBundle: URL?) {
        guard store == nil, let install = WoWInstall.locate(appBundle: appBundle) else { return }
        store = IconStore(install: install, cacheRoot: Self.cacheRoot)
    }

    func request(_ ids: [Int]) {
        guard let store else { return }
        for id in Set(ids) where id > 0 && !pending.contains(id) && !loaded.contains(id) {
            pending.insert(id)
            queue.async { [weak self] in
                let image = store.png(for: id).flatMap(NSImage.init(contentsOf:))
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pending.remove(id)
                    self.loaded.insert(id)
                    if let image { self.onLoad?(id, image) }
                }
            }
        }
    }
}
