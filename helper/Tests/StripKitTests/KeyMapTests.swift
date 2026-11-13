import Foundation
import Testing
@testable import StripKit

@Suite struct KeyMapTests {
    @Test func matchesTheSpecTable() throws {
        let first = try #require(KeyMap.key(slot: 0))
        #expect(first.keyCode == 0x53)
        #expect(first.modifiers == [.control, .shift])
        #expect(first.bindingName == "CTRL-SHIFT-NUMPAD1")

        let bar2Last = try #require(KeyMap.key(slot: 23))
        #expect(bar2Last.keyCode == 0x43)
        #expect(bar2Last.modifiers == [.control])
        #expect(bar2Last.bindingName == "CTRL-NUMPADMULTIPLY")

        let bar3Tenth = try #require(KeyMap.key(slot: 33))
        #expect(bar3Tenth.keyCode == 0x52)
        #expect(bar3Tenth.modifiers == [.shift])
        #expect(bar3Tenth.bindingName == "SHIFT-NUMPAD0")
    }

    @Test func coversAllSlotsWithUniqueBindings() {
        let names = (0..<36).compactMap { KeyMap.key(slot: $0)?.bindingName }
        #expect(names.count == 36)
        #expect(Set(names).count == 36)
    }

    @Test func neverUsesOption() {
        for slot in 0..<36 {
            #expect(KeyMap.key(slot: slot)?.modifiers.contains(.option) == false)
        }
    }

    @Test func rejectsOutOfRangeSlots() {
        #expect(KeyMap.key(slot: -1) == nil)
        #expect(KeyMap.key(slot: 36) == nil)
    }

    @Test func listsModifierKeysInPressOrder() {
        #expect(KeyMap.modifierKeys([.shift, .control]) == [0x3B, 0x38])
        #expect(KeyMap.modifierKeys([]) == [])
        #expect(KeyMap.modifierKeys([.command, .option]) == [0x3A, 0x37])
    }

    /// The addon's Bindings.lua must bind exactly these names.
    @Test func agreesWithTheAddonBindings() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../../addon/StreamDeckBars/Bindings.lua")
        let lua = try String(contentsOf: url, encoding: .utf8)
        #expect(lua.contains(#"Bindings.PREFIXES = { "CTRL-SHIFT-", "CTRL-", "SHIFT-" }"#))
        for name in KeyMap.keyNames { #expect(lua.contains("\"\(name)\"")) }
    }
}
