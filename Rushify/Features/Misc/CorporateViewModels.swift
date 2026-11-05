import Foundation

/// Cache-first loader that view models can subclass and also write into (used after a save).
@MainActor
class MiscLoader<T: Decodable>: ObservableObject {
    @Published var state = LoadState<T>()
    private let readCache: () async -> Cached<T>?
    private let fetch: () async throws -> Cached<T>
    private var started = false

    init(read: @escaping () async -> Cached<T>?, fetch: @escaping () async throws -> Cached<T>) { readCache = read; self.fetch = fetch }

    func load() async {
        guard !started else { return }
        started = true
        if let c = await readCache() { state.data = c }
        await refresh()
    }

    func refresh() async {
        state.loading = true
        do { state = LoadState(data: try await fetch()) }
        catch is CancellationError { state.loading = false }
        catch { state.loading = false; state.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }
}

struct CorporateResolveUi: Equatable {
    var busyId: Int?
    var message: String?
    var failed = false
}

enum CorporateText {
    /// Exactly the web wording.
    static let mapSavedInfo = "Latest portfolio tracking will include this shortly. Until then, treat your portfolio update as in progress. Open Home after a moment for refreshed numbers."
    static let mapEmptyError = "Add the listing symbol you want us to use for quotes and history, then save."

    static func pending(_ list: [CorporateAction]) -> [CorporateAction] { list.filter { $0.status.lowercased() == "pending" } }

    static func label(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "_", with: " ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }
    static func actionTypeLabel(_ t: String) -> String { label(t) }

    /// Readable key/value lines for the free-form `details` object.
    static func detailLines(_ details: [String: CorporateJSON]) -> [(key: String, value: String)] {
        details.keys.sorted().map { k in
            let v = details[k]!
            let text: String
            switch v {
            case .null: text = Fmt.dash
            case .array(let a): text = a.map { $0.primitiveContent ?? $0.jsonText }.joined(separator: ", ")
            case .object: text = v.jsonText
            default: text = v.primitiveContent ?? ""
            }
            return (label(k), text)
        }
    }
}

@MainActor
final class CorporateViewModel: MiscLoader<[CorporateAction]> {
    @Published var resolveUi = CorporateResolveUi()
    private let repo: Repository

    init(repo: Repository) {
        self.repo = repo
        super.init(read: { await repo.miscCorporateCached() }, fetch: { try await repo.miscCorporate() })
    }

    /// status is "confirmed" or "dismissed"; changes server data, so the UI asks first.
    func resolve(id: Int, status: String) async {
        if resolveUi.busyId != nil { return }
        resolveUi = CorporateResolveUi(busyId: id)
        do {
            try await repo.miscResolveCorporateAction(id: id, status: status)
            repo.notifyChanged()
            resolveUi = CorporateResolveUi(message: status == "confirmed" ? "Action confirmed." : "Action dismissed.")
            await refresh()
        } catch let e as ApiError {
            resolveUi = CorporateResolveUi(message: "Could not update: \(e.message)", failed: true)
        } catch {
            resolveUi = CorporateResolveUi()
        }
    }
}

struct CorporateMapEditUi: Equatable {
    var savingKey: String?
    var message: String?
    var error: String?
}

@MainActor
final class CorporateTickerMapsViewModel: MiscLoader<CorporateTickerMaps> {
    @Published var edit = CorporateMapEditUi()
    private let repo: Repository

    init(repo: Repository) {
        self.repo = repo
        super.init(read: { await repo.miscTickerMapsCached() }, fetch: { try await repo.miscTickerMaps() })
    }

    /// Saves this user's override for one broker ticker. `onChanged` lets the caller refresh Home and Holdings.
    func save(sourceKey: String, symbol: String, onChanged: () -> Void = {}) async {
        let yahoo = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if yahoo.isEmpty { edit = CorporateMapEditUi(error: CorporateText.mapEmptyError); return }
        await change(sourceKey, onChanged) { try await self.repo.miscPutTickerMap(sourceKey: sourceKey, yahooSymbol: yahoo) }
    }

    /// Removes the user's override (global maps still apply).
    func remove(sourceKey: String, onChanged: () -> Void = {}) async {
        await change(sourceKey, onChanged) { try await self.repo.miscDeleteTickerMap(sourceKey: sourceKey) }
    }

    private func change(_ key: String, _ onChanged: () -> Void, call: () async throws -> Void) async {
        if edit.savingKey != nil { return }
        edit = CorporateMapEditUi(savingKey: key)
        do {
            try await call()
            let c = try await repo.miscTickerMaps()
            state = LoadState(data: c)
            repo.notifyChanged()
            onChanged()
            edit = CorporateMapEditUi(message: CorporateText.mapSavedInfo)
        } catch let e as ApiError {
            edit = CorporateMapEditUi(error: e.message)
        } catch {
            edit = CorporateMapEditUi()
        }
    }

    func clearMessage() { edit.message = nil }
}
