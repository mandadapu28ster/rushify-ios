import Foundation
import SwiftUI

/// Bumped after any write so screens that show portfolio data reload. Observe it and refresh on `version` change.
final class DataEvents: ObservableObject {
    @Published private(set) var version = 0
    func bump() { if Thread.isMainThread { version += 1 } else { DispatchQueue.main.async { self.version += 1 } } }
}

/// Symbol search hit (shared by Pulse watchlists and Add holding).
struct SymbolHit: Equatable { var symbol = ""; var name: String?; var exchange: String?; var currency: String?; var type: String? }
extension SymbolHit: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        symbol = f.str("symbol") ?? ""; name = f.str("name"); exchange = f.str("exchange"); currency = f.str("currency"); type = f.str("type")
    }
}

struct SymbolQuote: Equatable { var normalizedSymbol: String?; var lastPrice: Decimal?; var currency: String? }
extension SymbolQuote: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        normalizedSymbol = f.str("normalized_symbol"); lastPrice = f.dec("last_price"); currency = f.str("currency")
    }
}

/// What the Holdings detail sheet knows about the row being shown. Lets other features add actions without depending on Holdings.
struct HoldingContext {
    let row: HoldingRow
    let displayTicker: String
    let isPrimaryLot: Bool
}
/// Supplied by the app shell; Holdings shows the returned view at the bottom of a position's detail sheet.
typealias HoldingActionsBuilder = (HoldingContext) -> AnyView

extension ApiClient {
    /// JSON write. `json` is anything JSONSerialization accepts (use NSNull for explicit nulls).
    @discardableResult
    func sendJSON(_ method: String, _ path: String, json: Any, query: [URLQueryItem] = [], auth: Bool = true) async throws -> Data {
        try await send(method, path, query: query, body: try JSONSerialization.data(withJSONObject: json), auth: auth)
    }
}

extension Repository {
    /// Call after a successful write: Home, Holdings and charts reload.
    func notifyChanged() { events.bump() }
}
