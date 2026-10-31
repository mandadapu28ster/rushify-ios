import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Same palette as the Android app.
enum RColors {
    static let bg = Color(hex: 0x0B0E14)
    static let surface = Color(hex: 0x161B22)
    static let variant = Color(hex: 0x21262D)
    static let accent = Color(hex: 0x58A6FF)
    static let gain = Color(hex: 0x00E676)
    static let loss = Color(hex: 0xFF5252)
    static let text = Color(hex: 0xF0F6FC)
    static let muted = Color(hex: 0x8B949E)
    static let warn = Color(hex: 0xFFB74D)
    static let chart: [Color] = [0x58A6FF, 0x00E676, 0xFFB74D, 0xBA68C8, 0x4DD0E1, 0xFF8A65, 0xAED581, 0xF06292, 0x9FA8DA, 0xFFF176].map { Color(hex: $0) }

    static func pnl(_ v: Decimal?) -> Color {
        guard let v else { return text }
        return v > 0 ? gain : (v < 0 ? loss : text)
    }
}

private struct HideBalancesKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// When true, monetary amounts render as dots ("hide balances").
    var hideBalances: Bool { get { self[HideBalancesKey.self] } set { self[HideBalancesKey.self] = newValue } }
}
