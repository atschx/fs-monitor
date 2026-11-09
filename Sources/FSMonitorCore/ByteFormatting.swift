import Foundation

public enum ByteFormatting {
    public static func signed(from bytes: Int64) -> String {
        if bytes < 0 {
            let magnitude: UInt64
            if bytes == Int64.min {
                magnitude = UInt64(Int64.max) + 1
            } else {
                magnitude = UInt64(-bytes)
            }
            return "-" + unsigned(from: magnitude)
        }
        return unsigned(from: UInt64(bytes))
    }

    public static func unsigned(from bytes: UInt64) -> String {
        let units: [(UInt64, String)] = [
            (1 << 40, "TB"),
            (1 << 30, "GB"),
            (1 << 20, "MB"),
            (1 << 10, "KB")
        ]
        for (unit, name) in units where bytes >= unit {
            let whole = bytes / unit
            let fraction = (bytes % unit) * 10 / unit
            return "\(whole).\(fraction) \(name)"
        }
        return "\(bytes) 字节"
    }

    public static func optionalUnsigned(_ bytes: UInt64?) -> String {
        guard let bytes else { return "不可获得" }
        return unsigned(from: bytes)
    }
}
