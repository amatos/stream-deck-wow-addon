/// The keys the addon binds for each slot (docs/strip-format.md §9), as macOS
/// virtual keycodes and modifiers. Pure data; the app turns these into events.
public enum KeyMap {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    public struct Key: Equatable, Sendable {
        public var keyCode: UInt16
        public var modifiers: Modifiers
        /// The WoW binding name, e.g. "CTRL-SHIFT-NUMPAD1".
        public var bindingName: String
    }

    /// Keypad keys for buttons 1...12.
    public static let keyCodes: [UInt16] = [0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C, 0x52, 0x4B, 0x43]
    static let keyNames = ["NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", "NUMPAD5", "NUMPAD6",
                           "NUMPAD7", "NUMPAD8", "NUMPAD9", "NUMPAD0", "NUMPADDIVIDE", "NUMPADMULTIPLY"]

    /// Modifier prefixes for bars 1...3.
    public static let barModifiers: [Modifiers] = [[.control, .shift], [.control], [.shift]]
    static let barPrefixes = ["CTRL-SHIFT-", "CTRL-", "SHIFT-"]

    /// macOS virtual keycodes of the left modifier keys.
    public static let modifierKeyCodes: [(Modifiers, UInt16)] = [
        (.control, 0x3B), (.shift, 0x38), (.option, 0x3A), (.command, 0x37),
    ]

    /// Key for strip slot 0...35, or nil when out of range.
    public static func key(slot: Int) -> Key? {
        guard (0..<Spec.slots).contains(slot) else { return nil }
        let bar = slot / 12, button = slot % 12
        return Key(keyCode: keyCodes[button], modifiers: barModifiers[bar],
                   bindingName: barPrefixes[bar] + keyNames[button])
    }

    /// Keycodes of the modifiers to hold, in press order.
    public static func modifierKeys(_ m: Modifiers) -> [UInt16] {
        modifierKeyCodes.filter { m.contains($0.0) }.map(\.1)
    }
}
