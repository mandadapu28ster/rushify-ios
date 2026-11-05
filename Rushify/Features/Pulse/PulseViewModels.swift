import Combine
import Foundation

struct PulseRefreshUi: Equatable { var busy = false; var message: String?; var failed = false }
struct PulseEditUi: Equatable { var busy = false; var message: String?; var error: String? }
struct PulseSearchUi: Equatable { var query = ""; var results: [SymbolHit] = []; var searching = false }

private func pulseMessage(_ error: Error) -> String { (error as? ApiError)?.message ?? error.localizedDescription }

/// Forwards a CachedLoader's changes so a view observing the model redraws.
@MainActor
class PulseLoaderModel<T: Decodable>: ObservableObject {
    let loader: CachedLoader<T>
    private var bag = Set<AnyCancellable>()
    init(loader: CachedLoader<T>) {
        self.loader = loader
        loader.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }
    var state: LoadState<T> { loader.state }
    func load() { loader.load() }
    func refresh() async { await loader.refresh() }
}

@MainActor
final class PulseRadarModel: PulseLoaderModel<PulseRadar> {
    private final class Box { var scope = "overall" }
    private let box: Box
    var scope: String { box.scope }

    init(repo: Repository) {
        let b = Box()
        box = b
        super.init(loader: CachedLoader(read: { await repo.pulseRadarCached(b.scope) }, fetch: { try await repo.pulseRadar(b.scope) }))
    }
    func select(_ key: String) {
        if key == box.scope { return }
        box.scope = key
        loader.reload()
    }
}

@MainActor
final class PulseNewsModel: PulseLoaderModel<PulseNews> {
    private final class Box { var force = false }
    private let box: Box
    init(repo: Repository) {
        let b = Box()
        box = b
        super.init(loader: CachedLoader(read: { await repo.pulseNewsCached() }, fetch: {
            let force = b.force
            b.force = false
            return try await repo.pulseNews(force: force)
        }))
    }
    func forceRefresh() async { box.force = true; await loader.refresh() }
}

@MainActor
final class PulseWatchlistsModel: ObservableObject {
    @Published private(set) var state = LoadState<PulseWatchlists>()
    @Published private(set) var refreshUi = PulseRefreshUi()
    @Published private(set) var edit = PulseEditUi()
    @Published private(set) var search = PulseSearchUi()

    private let repo: Repository
    private let debounceNanos: UInt64
    private var started = false
    private var searchTask: Task<Void, Never>?

    init(repo: Repository, debounceMillis: UInt64 = 350) { self.repo = repo; debounceNanos = debounceMillis * 1_000_000 }

    // MARK: load

    func load() {
        guard !started else { return }
        started = true
        Task {
            if let c = await repo.pulseWatchlistsCached() { state.data = c }
            await refresh()
        }
    }

    func refresh() async {
        state.loading = true
        do { state = LoadState(data: try await repo.pulseWatchlists()) }
        catch is CancellationError { state.loading = false }
        catch { state.loading = false; state.error = pulseMessage(error) }
    }

    /// Forced server refresh (force=true), then re-read the lists so the new quotes actually appear.
    func forceRefresh() async {
        if refreshUi.busy { return }
        refreshUi = PulseRefreshUi(busy: true)
        do {
            let (summary, fresh) = try await repo.pulseRefreshWatchlistsNow()
            state = LoadState(data: fresh)
            refreshUi = PulseRefreshUi(message: PulseRefreshMessage.of(summary))
        } catch is CancellationError {
            refreshUi = PulseRefreshUi()
        } catch {
            refreshUi = PulseRefreshUi(message: "Refresh failed: \(pulseMessage(error))", failed: true)
        }
    }

    // MARK: editing: every change is followed by a re-read, so the screen always shows the server's truth

    private func change(done: String?, _ call: () async throws -> Void) async {
        if edit.busy { return }
        edit = PulseEditUi(busy: true)
        do {
            try await call()
            let fresh = try await repo.pulseWatchlists()
            repo.notifyChanged()
            state = LoadState(data: fresh)
            edit = PulseEditUi(message: done)
        } catch is CancellationError {
            edit = PulseEditUi()
        } catch {
            edit = PulseEditUi(error: pulseMessage(error))
        }
    }

    func createList(_ name: String) async {
        let current = state.data?.value
        if !PulseWatchlistRules.canCreate(current, name) {
            edit = PulseEditUi(error: PulseWatchlistRules.atListCap(current) ? "Maximum lists reached." : "Enter a name (up to \(PulseWatchlistRules.nameMax) characters).")
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await change(done: "List created.") { try await repo.pulseCreateWatchlist(name: trimmed) }
    }

    func deleteList(_ id: Int) async {
        await change(done: "List deleted.") { try await repo.pulseDeleteWatchlist(id: id) }
    }

    func addSymbol(_ list: PulseWatchlist, _ hit: SymbolHit, fetchNews: Bool) async {
        if PulseWatchlistRules.atItemCap(state.data?.value, list) { edit = PulseEditUi(error: "This list is full."); return }
        clearSearch()
        await change(done: "\(hit.symbol) added.") { try await repo.pulseAddWatchItem(listId: list.id, hit: hit, fetchNews: fetchNews) }
    }

    func toggleNews(_ list: PulseWatchlist, _ item: PulseWatchItem) async {
        await change(done: nil) { try await repo.pulsePatchWatchItem(listId: list.id, itemId: item.id, fetchNews: !item.fetchNews) }
    }

    func removeSymbol(_ list: PulseWatchlist, _ item: PulseWatchItem) async {
        await change(done: "\(item.yahooSymbol) removed.") { try await repo.pulseDeleteWatchItem(listId: list.id, itemId: item.id) }
    }

    func clearEditMessage() { edit = PulseEditUi() }

    // MARK: symbol search: starts at 2 characters, 350 ms after the last keystroke; failures just clear the results

    func onQuery(_ q: String) {
        searchTask?.cancel()
        search = PulseSearchUi(query: q)
        guard PulseWatchlistRules.searchable(q) else { return }
        let delay = debounceNanos
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            search.searching = true
            let hits = (try? await repo.pulseSymbolSearch(q.trimmingCharacters(in: .whitespacesAndNewlines))) ?? []
            if Task.isCancelled { return }
            if search.query == q { search.results = hits; search.searching = false }
        }
    }

    func clearSearch() { searchTask?.cancel(); search = PulseSearchUi() }
}
