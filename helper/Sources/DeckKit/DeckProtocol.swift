import Foundation
import StripKit

/// Messages between the helper (WebSocket server) and the Stream Deck plugin.
/// Documented in docs/deck-protocol.md.
public enum DeckMessage: Equatable, Sendable {
    /// helper -> plugin: the image to show for a strip slot (0...59).
    case slot(slot: Int, image: String)
    /// helper -> plugin: sent on connect.
    case hello(version: Int)
    /// plugin -> helper: a key showing `slot` was pressed.
    case press(slot: Int)

    public static let protocolVersion = 1
    public static let defaultPort: UInt16 = 47811

    private struct Wire: Codable {
        var type: String
        var slot: Int?
        var image: String?
        var version: Int?
    }

    public func encoded() -> Data {
        let wire: Wire
        switch self {
        case let .slot(slot, image): wire = Wire(type: "slot", slot: slot, image: image)
        case let .hello(version): wire = Wire(type: "hello", version: version)
        case let .press(slot): wire = Wire(type: "press", slot: slot)
        }
        return try! JSONEncoder().encode(wire)
    }

    /// Parses a message; nil for malformed or unknown messages, or out-of-range slots.
    public static func decode(_ data: Data) -> DeckMessage? {
        guard let w = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        switch w.type {
        case "press":
            guard let s = w.slot, (0..<Spec.slots).contains(s) else { return nil }
            return .press(slot: s)
        case "slot":
            guard let s = w.slot, (0..<Spec.slots).contains(s), let image = w.image else { return nil }
            return .slot(slot: s, image: image)
        case "hello":
            return .hello(version: w.version ?? 0)
        default:
            return nil
        }
    }
}
