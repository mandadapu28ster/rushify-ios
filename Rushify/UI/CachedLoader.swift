import Foundation

struct LoadState<T> {
    var data: Cached<T>?
    var loading = false
    var error: String?
}

/// Cache-first loading: show the saved copy immediately, refresh in the background, and on failure keep the
/// saved copy on screen with an error so the UI can show the offline banner.
@MainActor
final class CachedLoader<T: Decodable>: ObservableObject {
    @Published private(set) var state = LoadState<T>()
    private let readCache: () async -> Cached<T>?
    private let fetch: () async throws -> Cached<T>
    private var started = false
    private var generation = 0

    init(read: @escaping () async -> Cached<T>?, fetch: @escaping () async throws -> Cached<T>) { readCache = read; self.fetch = fetch }

    func load() {
        guard !started else { return }
        started = true
        launch()
    }

    /// Parameter changed: drop stale data and load again; late replies for the old parameter are ignored.
    func reload() {
        started = true
        generation += 1
        state = LoadState()
        launch()
    }

    private func launch() {
        let g = generation
        Task {
            if let c = await readCache(), g == generation { state.data = c }
            await doRefresh()
        }
    }

    func refresh() async { await doRefresh() }

    private func doRefresh() async {
        let g = generation
        state.loading = true
        do {
            let c = try await fetch()
            if g == generation { state = LoadState(data: c) }
        } catch is CancellationError {
            if g == generation { state.loading = false }
        } catch {
            if g == generation { state.loading = false; state.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }
}
