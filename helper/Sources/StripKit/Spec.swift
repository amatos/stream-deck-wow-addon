// Constants from docs/strip-format.md (version 4).
public enum Spec {
    public static let version = 4
    public static let block = 1
    public static let width = 48
    public static let slots = 60
    public static let symbolsPerSlot = 6
    public static let symbolCount = 374

    /// Marker symbols 0-3: magenta, green, cyan, yellow.
    public static let marker: [Int] = [51, 12, 15, 60]
    /// Calibration symbols 4-7: greys at levels 0...3.
    public static let calibration: [Int] = [0, 21, 42, 63]

    public static let headerSymbols = 12          // marker, calibration, version, sequence, flags
    public static let checksumFirst = 8           // version
    public static let checksumLast = 371          // last slot record symbol

    /// Buttons mirrored per bar (1-5).
    public static let barButtons = [12, 12, 12, 12, 12]

    /// Bar (1-5) and button (1-12) for a 0-based strip slot, or nil when out of range.
    public static func barButton(slot: Int) -> (bar: Int, button: Int)? {
        guard (0..<slots).contains(slot) else { return nil }
        return (slot / 12 + 1, slot % 12 + 1)
    }

    // Count area (§7), in strip pixels: 2 px below the grid, 96 px wide.
    public static let countGap = 2
    public static let countAreaWidth = 96
    public static var countAreaY: Int { gridRows * block + countGap }
    public static let countLineHeight = 14
    public static let countCellWidth = 32
    public static let countCellsPerLine = 3
    public static let gridPixelWidth = width * block

    public static var gridRows: Int { (symbolCount + width - 1) / width }

    /// Fletcher-style checksum over symbols[from...to].
    public static func checksum(_ symbols: [Int], from: Int, to: Int) -> (Int, Int) {
        var a = 0, b = 0
        for i in from...to {
            a = (a + symbols[i]) % 64
            b = (b + a) % 64
        }
        return (a, b)
    }

    public static func levels(of symbol: Int) -> (r: Int, g: Int, b: Int) {
        ((symbol >> 4) & 3, (symbol >> 2) & 3, symbol & 3)
    }
}
