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

    /// Modifier prefixes for bars 1...5. Bar 4 uses bare keypad keys, bar 5 Command (WoW's META).
    public static let barModifiers: [Modifiers] = [[.control, .shift], [.control], [.shift], [], [.command]]
    static let barPrefixes = ["CTRL-SHIFT-", "CTRL-", "SHIFT-", "", "META-"]

    /// macOS virtual keycodes of the left modifier keys.
    public static let modifierKeyCodes: [(Modifiers, UInt16)] = [
        (.control, 0x3B), (.shift, 0x38), (.option, 0x3A), (.command, 0x37),
    ]

    /// Key for a 0-based strip slot, or nil when out of range.
    public static func key(slot: Int) -> Key? {
        guard let (bar, button) = Spec.barButton(slot: slot) else { return nil }
        return Key(keyCode: keyCodes[button - 1], modifiers: barModifiers[bar - 1],
                   bindingName: barPrefixes[bar - 1] + keyNames[button - 1])
    }

    /// Keycodes of the modifiers to hold, in press order.
    public static func modifierKeys(_ m: Modifiers) -> [UInt16] {
        modifierKeyCodes.filter { m.contains($0.0) }.map(\.1)
    }
}
