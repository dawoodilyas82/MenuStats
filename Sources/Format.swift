import AppKit

enum Fmt {
    /// Compact rate for the menu bar: "0K", "102K", "1.2M", "120M".
    static func rate(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024
        if kb < 1000 { return String(format: "%.0fK", kb) }
        let mb = kb / 1024
        return String(format: mb < 100 ? "%.1fM" : "%.0fM", mb)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowsNonnumericFormatting = false   // "0 KB", not "Zero KB"
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func bytes(_ b: UInt64) -> String { byteFormatter.string(fromByteCount: Int64(b)) }

    static func speed(_ bytesPerSec: Double) -> String { bytes(UInt64(bytesPerSec)) + "/s" }

    static func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}

enum Palette {
    /// Green below 50%, amber to 80%, red above.
    static func load(_ fraction: Double) -> NSColor {
        fraction < 0.5 ? .systemGreen : fraction < 0.8 ? .systemOrange : .systemRed
    }

    static let download = NSColor.systemBlue
    static let upload = NSColor(srgbRed: 0.94, green: 0.45, blue: 0.33, alpha: 1)

    static let memApp = NSColor.systemTeal
    static let memWired = NSColor.systemIndigo
    static let memCompressed = NSColor.systemPurple
}
