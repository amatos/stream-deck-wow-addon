public struct GlobalFlags: Equatable, Sendable {
    public var inCombat = false
    public var bindingsApplied = false
    public var bindingsPending = false
    public var countsSecret = false

    public init(
        inCombat: Bool = false, bindingsApplied: Bool = false,
        bindingsPending: Bool = false, countsSecret: Bool = false
    ) {
        self.inCombat = inCombat
        self.bindingsApplied = bindingsApplied
        self.bindingsPending = bindingsPending
        self.countsSecret = countsSecret
    }

    public init(symbol: Int) {
        inCombat = symbol & 1 != 0
        bindingsApplied = symbol & 2 != 0
        bindingsPending = symbol & 4 != 0
        countsSecret = symbol & 8 != 0
    }

    public var symbol: Int {
        (inCombat ? 1 : 0) | (bindingsApplied ? 2 : 0) | (bindingsPending ? 4 : 0) | (countsSecret ? 8 : 0)
    }
}

public struct SlotState: Equatable, Sendable {
    public var iconID: Int = 0
    public var hasAction = false
    public var usable = false
    public var noMana = false
    public var glow = false
    public var rangeApplies = false
    public var inRange = false
    public var hasCount = false
    /// Decoded from the count area; nil when there is no count or it could not be read.
    public var count: Int?

    public init(
        iconID: Int = 0, hasAction: Bool = false, usable: Bool = false, noMana: Bool = false,
        glow: Bool = false, rangeApplies: Bool = false, inRange: Bool = false,
        hasCount: Bool = false, count: Int? = nil
    ) {
        self.iconID = iconID
        self.hasAction = hasAction
        self.usable = usable
        self.noMana = noMana
        self.glow = glow
        self.rangeApplies = rangeApplies
        self.inRange = inRange
        self.hasCount = hasCount
        self.count = count
    }

    /// Decodes a 6-symbol slot record (§5.2).
    public init(record: ArraySlice<Int>) {
        var value: UInt64 = 0
        for s in record { value = value << 6 | UInt64(s) }
        let flags = Int(value & 0xFFF)
        func bit(_ n: Int) -> Bool { flags >> n & 1 == 1 }
        self.init(
            iconID: Int(value >> 12),
            hasAction: bit(11), usable: bit(10), noMana: bit(9), glow: bit(8),
            rangeApplies: bit(7), inRange: bit(7) && bit(6), hasCount: bit(5)
        )
    }

    /// Encodes into a 6-symbol slot record (used by tests and tooling).
    public var record: [Int] {
        var flags = 0
        if hasAction { flags |= 1 << 11 }
        if usable { flags |= 1 << 10 }
        if noMana { flags |= 1 << 9 }
        if glow { flags |= 1 << 8 }
        if rangeApplies { flags |= 1 << 7 }
        if rangeApplies && inRange { flags |= 1 << 6 }
        if hasCount { flags |= 1 << 5 }
        let value = UInt64(iconID & 0xFFFFFF) << 12 | UInt64(flags)
        return (0..<Spec.symbolsPerSlot).map { i in
            Int(value >> UInt64(6 * (Spec.symbolsPerSlot - 1 - i)) & 63)
        }
    }
}

public struct StripFrame: Equatable, Sendable {
    public var version: Int
    public var sequence: Int
    public var flags: GlobalFlags
    public var slots: [SlotState]

    public init(version: Int = Spec.version, sequence: Int, flags: GlobalFlags, slots: [SlotState]) {
        self.version = version
        self.sequence = sequence
        self.flags = flags
        self.slots = slots
    }

    /// Builds the full symbol sequence (§4), including marker and checksum.
    public var symbols: [Int] {
        var out = Spec.marker + Spec.calibration
        out.append(version)
        out.append((sequence % 4096) >> 6)
        out.append(sequence % 64)
        out.append(flags.symbol)
        for i in 0..<Spec.slots {
            out += (i < slots.count ? slots[i] : SlotState()).record
        }
        let (a, b) = Spec.checksum(out, from: Spec.checksumFirst, to: Spec.checksumLast)
        out += [a, b]
        return out
    }
}

/// Where the strip sits in a captured image.
public struct StripGeometry: Equatable, Sendable {
    /// Top-left pixel of the marker's first block.
    public var originX: Int
    public var originY: Int
    /// Block pitch in captured pixels (4 when WoW renders 1:1 with the capture).
    public var pitch: Double

    public init(originX: Int, originY: Int, pitch: Double) {
        self.originX = originX
        self.originY = originY
        self.pitch = pitch
    }

    /// Captured pixels per strip pixel.
    public var scale: Double { pitch / Double(Spec.block) }
}
