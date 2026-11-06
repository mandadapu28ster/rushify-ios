import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
    /// Mixes toward white (positive) to make a lighter sibling of the same hue.
    func lightened(_ amount: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(.sRGB, red: Double(r) + (1 - Double(r)) * amount, green: Double(g) + (1 - Double(g)) * amount, blue: Double(b) + (1 - Double(b)) * amount, opacity: Double(a))
    }
}

/// User-selectable colour scheme for gains and losses. Red/green is hard for some people to tell apart (and blue/orange for others),
/// so the app also always pairs colour with a sign and an arrow, and offers this alternative.
enum RPalette {
    static let defaultsKey = "rushify.palette_cb"
    nonisolated(unsafe) static var colorBlindFriendly: Bool = UserDefaults(suiteName: "rushify.prefs")?.string(forKey: defaultsKey) == "1"
    static func set(colorBlindFriendly on: Bool) {
        colorBlindFriendly = on
        UserDefaults(suiteName: "rushify.prefs")?.set(on ? "1" : "0", forKey: defaultsKey)
    }
}

/// Dark-theme palette. Contrast targets (checked by unit tests): text 7:1+ on every surface, accent / gain / loss / warn 4.5:1+,
/// chart colours 3:1+. Colour is used sparingly: one accent for actions, gain/loss only for money moving, and never one colour for two meanings.
enum RColors {
    // Surfaces: a ladder of slightly brighter layers (dimmer base, brighter elevated)
    static let bg = Color(hex: 0x0B0E14)
    static let surface = Color(hex: 0x151B24)
    static let variant = Color(hex: 0x1F2733)
    static let elevated = Color(hex: 0x28323F)

    // Text
    static let text = Color(hex: 0xF0F6FC)
    static let muted = Color(hex: 0xAAB5C1)       // secondary text, 7:1+ on every surface
    static let faint = Color(hex: 0x7C8796)       // decoration and disabled only (not for text that must be read)

    // Roles
    static let accent = Color(hex: 0x6AB0FF)
    static let warn = Color(hex: 0xF5B84B)
    static var gain: Color { Color(hex: RPalette.colorBlindFriendly ? 0xC7E5FF : 0x5AE8AC) }
    static var loss: Color { Color(hex: RPalette.colorBlindFriendly ? 0xE0702F : 0xFF5C61) }

    /// Colours for categories in charts. None is green or red, so a category never looks like a gain or a loss.
    static let categorical: [Color] = [0x5AA9FF, 0xA78BFA, 0xF5B84B, 0xF472B6, 0x7DD3FC, 0xFB923C, 0x818CF8, 0xC4B5FD].map { Color(hex: $0) }
    static var chart: [Color] { categorical }

    static func pnl(_ v: Decimal?) -> Color {
        guard let v else { return text }
        return v > 0 ? gain : (v < 0 ? loss : text)
    }
    /// ▲ / ▼ so a gain or loss never depends on colour alone.
    static func arrow(_ v: Decimal?) -> String { guard let v, v != 0 else { return "" }; return v > 0 ? "▲" : "▼" }
}

/// Wayfinding colours for the areas of the app. Used only for small icons, never for backgrounds.
enum RSection {
    case holdings, sync, ai, performance, corporate, connections, addHolding, password
    var tint: Color {
        switch self {
        case .holdings: return Color(hex: 0x5AA9FF)
        case .sync: return Color(hex: 0x7DD3FC)
        case .ai: return Color(hex: 0xA78BFA)
        case .performance: return Color(hex: 0xF5B84B)
        case .corporate: return Color(hex: 0x818CF8)
        case .connections: return Color(hex: 0x94A3B8)
        case .addHolding: return Color(hex: 0xF472B6)
        case .password: return Color(hex: 0xFB923C)
        }
    }
    var symbol: String {
        switch self {
        case .holdings: return "list.bullet.rectangle.portrait"
        case .sync: return "arrow.triangle.2.circlepath"
        case .ai: return "sparkles"
        case .performance: return "chart.line.uptrend.xyaxis"
        case .corporate: return "building.columns"
        case .connections: return "link"
        case .addHolding: return "plus.circle"
        case .password: return "key"
        }
    }
}

private struct HideBalancesKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// When true, monetary amounts render as dots ("hide balances").
    var hideBalances: Bool { get { self[HideBalancesKey.self] } set { self[HideBalancesKey.self] = newValue } }
}
