import SwiftUI

/// Convrt's blue palette. One place for every colour the UI uses.
enum Theme {
    enum Swatch { case primary, navy, ice, glow }

    static func hex(for swatch: Swatch) -> UInt32 {
        switch swatch {
        case .primary: return 0x2F7BFF   // main blue: highlights, buttons, accent
        case .navy:    return 0x0B1B3A   // text and deep shadows
        case .ice:     return 0xEAF2FF   // wedge and panel fill
        case .glow:    return 0x6FA8FF   // soft glow around the highlighted wedge
        }
    }

    static func components(hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static func color(_ swatch: Swatch) -> Color {
        let c = components(hex: hex(for: swatch))
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    static let primary = color(.primary)
    static let navy = color(.navy)
    static let ice = color(.ice)
    static let glow = color(.glow)
}
