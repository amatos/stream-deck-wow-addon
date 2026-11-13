// Constants from docs/strip-format.md (version 1).
public enum Spec {
    public static let version = 1
    public static let block = 4
    public static let width = 48
    public static let slots = 36
    public static let symbolsPerSlot = 6
    public static let symbolCount = 230

    /// Marker symbols 0-3: magenta, green, cyan, yellow.
    public static let marker: [Int] = [51, 12, 15, 60]
    /// Calibration symbols 4-7: greys at levels 0...3.
    public static let calibration: [Int] = [0, 21, 42, 63]

    public static let headerSymbols = 12          // marker, calibration, version, sequence, flags
    public static let checksumFirst = 8           // version
    public static let checksumLast = 227          // last slot record symbol

    // Count area (§7), in strip pixels at block size 4.
    public static let countAreaY = 24
    public static let countLineHeight = 14
    public static let countCellWidth = 32
    public static let countCellsPerLine = 6
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
