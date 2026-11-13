import AppKit
import ApplicationServices
import CoreGraphics
import StripKit

/// Sends a slot's keybind (docs/strip-format.md §9) to the World of Warcraft process.
final class KeySender {
    enum Outcome: Equatable {
        case sent(String)
        case noAccessibility
        case noWoW
        case badSlot
    }

    /// Delay between synthetic events, so WoW sees modifiers before the key.
    static let eventGap: useconds_t = 8_000
    /// Time for WoW to become active before keys arrive.
    static let activationDelay = 0.25

    private let queue = DispatchQueue(label: "WoWBarsHelper.keys")

    static func wowApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: WindowCapture.wowBundleID).first
    }

    /// Presses a slot's key. With `activate`, WoW is brought to the front first.
    @discardableResult
    func press(slot: Int, activate: Bool) -> Outcome {
        guard let key = KeyMap.key(slot: slot) else { return .badSlot }
        guard AXIsProcessTrusted() else { return .noAccessibility }
        guard let app = Self.wowApp() else { return .noWoW }
        let pid = app.processIdentifier
        var delay = 0.0
        if activate && !app.isActive {
            app.activate()
            delay = Self.activationDelay
        }
        queue.asyncAfter(deadline: .now() + delay) { Self.post(key, to: pid) }
        return .sent(key.bindingName)
    }

    static func flag(for modifierKeyCode: UInt16) -> CGEventFlags {
        switch modifierKeyCode {
        case 0x3B: return .maskControl
        case 0x38: return .maskShift
        case 0x3A: return .maskAlternate
        default: return .maskCommand
        }
    }

    /// Modifier down, key down, key up, modifier up — all addressed to WoW only.
    static func post(_ key: KeyMap.Key, to pid: pid_t) {
        // A private source keeps the user's physical modifier state out of the events.
        let source = CGEventSource(stateID: .privateState)
        var flags: CGEventFlags = []
        let modifiers = KeyMap.modifierKeys(key.modifiers)

        func send(_ code: UInt16, down: Bool, flags: CGEventFlags, modifier: Bool) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            if modifier { event.type = .flagsChanged }
            event.flags = flags
            event.postToPid(pid)
            usleep(eventGap)
        }

        for code in modifiers {
            flags.insert(flag(for: code))
            send(code, down: true, flags: flags, modifier: true)
        }
        let keyFlags = flags.union(.maskNumericPad)
        send(key.keyCode, down: true, flags: keyFlags, modifier: false)
        send(key.keyCode, down: false, flags: keyFlags, modifier: false)
        for code in modifiers.reversed() {
            flags.remove(flag(for: code))
            send(code, down: false, flags: flags, modifier: true)
        }
    }
}
