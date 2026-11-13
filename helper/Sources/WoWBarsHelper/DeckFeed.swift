import AppKit
import DeckKit
import StripKit

/// Turns decoded slot state into key images and pushes changed ones to the plugin.
/// Main thread only; rendering happens on a background queue.
final class DeckFeed {
    let server: DeckServer
    private var faces: [Int: KeyFace] = [:]
    private let queue = DispatchQueue(label: "WoWBarsHelper.render", qos: .userInitiated)

    init(server: DeckServer) {
        self.server = server
    }

    func update(snapshot: CaptureSnapshot, icons: [Int: NSImage]) {
        let connected = snapshot.status == .connected
        for slot in 0..<Spec.slots {
            let state = snapshot.frame?.slots[slot]
            let icon = state.flatMap { icons[$0.iconID] }
            let face = KeyFace(connected: connected, slot: state, iconLoaded: icon != nil)
            guard faces[slot] != face else { continue }
            faces[slot] = face
            let cg = icon?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            queue.async { [server] in
                server.update(slot: slot, image: KeyRenderer.dataURL(face, icon: cg))
            }
        }
    }
}
