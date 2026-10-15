import SwiftUI

/// Splits a hex color like "#e2b714" into red/green/blue/alpha numbers from 0 to 1.
/// Also understands "#abc" (short form) and "#rrggbbaa" (with transparency).
func hexComponents(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double) {
    var digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    if digits.count == 3 || digits.count == 4 {
        digits = digits.map { "\($0)\($0)" }.joined()      // "abc" -> "aabbcc"
    }
    var value: UInt64 = 0
    Scanner(string: digits).scanHexInt64(&value)           // text -> number, base 16

    if digits.count == 8 {
        let r = Double((value >> 24) & 0xFF) / 255
        let g = Double((value >> 16) & 0xFF) / 255
        let b = Double((value >> 8) & 0xFF) / 255
        let a = Double(value & 0xFF) / 255
        return (r, g, b, a)
    }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    return (r, g, b, 1)
}

extension Color {
    /// `Color(hex: "#e2b714")`
    init(hex: String) {
        let c = hexComponents(hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}
