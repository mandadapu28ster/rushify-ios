import Combine
import Foundation

/// A cache-first loader whose parameters can change. Each parameter set gets its own CachedLoader that captures the
/// parameters by value, so a request is always made for the parameters that were selected, and a late reply for an old
/// selection lands in a loader nobody reads any more (stale-reply protection).
@MainActor
class PerformanceParamModel<P: Equatable, T: Decodable>: ObservableObject {
    private(set) var loader: CachedLoader<T>
    private(set) var params: P
    private let make: (P) -> CachedLoader<T>
    private var forward: AnyCancellable?
    /// True once this model has been asked to load; data-change events only refresh models that are in use.
    private(set) var didLoad = false

    var state: LoadState<T> { loader.state }

    init(initial: P, read: @escaping (P) async -> Cached<T>?, fetch: @escaping (P) async throws -> Cached<T>) {
        make = { p in CachedLoader(read: { await read(p) }, fetch: { try await fetch(p) }) }
        params = initial
        loader = make(initial)
        subscribe()
    }

    private func subscribe() { forward = loader.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }

    func load() { didLoad = true; loader.load() }
    func refresh() async { didLoad = true; await loader.refresh() }

    /// Returns true when the parameters actually changed (and a load for the new ones started).
    @discardableResult
    func setParams(_ p: P) -> Bool {
        guard p != params else { return false }
        reset(p)
        return true
    }

    /// Start over with a fresh loader (same or new parameters).
    func reset(_ p: P) {
        objectWillChange.send()
        params = p
        didLoad = true
        loader = make(p)
        subscribe()
        loader.load()
    }
}

struct PerformanceGrowthParams: Equatable {
    var granularity = "monthly"
    var count = PerformancePeriodOptions.default("monthly")
}

@MainActor
final class PerformanceGrowthModel: PerformanceParamModel<PerformanceGrowthParams, PerformanceGrowth> {
    var granularity: String { params.granularity }
    var count: Int { params.count }
    init(repo: Repository) {
        super.init(initial: PerformanceGrowthParams(),
                   read: { await repo.performanceGrowthCached($0.granularity, $0.count) },
                   fetch: { try await repo.performanceGrowth($0.granularity, $0.count) })
    }
    /// Switching granularity resets the count to the web default; picking a count keeps the granularity.
    func select(_ g: String? = nil, n: Int? = nil) {
        let gran = g ?? granularity
        setParams(PerformanceGrowthParams(granularity: gran, count: n ?? (gran == granularity ? count : PerformancePeriodOptions.default(gran))))
    }
}

struct PerformanceBenchmarkParams: Equatable {
    var mode = "monthly"
    var count = PerformancePeriodOptions.default("monthly")
}

/// mode: "day", "week" (server ranges) or "monthly", "yearly" (+ count), matching the web's Monthly/Yearly + Periods.
@MainActor
final class PerformanceBenchmarksModel: PerformanceParamModel<PerformanceBenchmarkParams, PerformanceBenchmarks> {
    var mode: String { params.mode }
    var count: Int { params.count }
    init(repo: Repository) {
        super.init(initial: PerformanceBenchmarkParams(),
                   read: { await repo.performanceBenchmarksCached($0.mode, $0.count) },
                   fetch: { try await repo.performanceBenchmarks($0.mode, $0.count) })
    }
    func select(_ m: String? = nil, n: Int? = nil) {
        let mode = m ?? self.mode
        setParams(PerformanceBenchmarkParams(mode: mode, count: n ?? (mode == self.mode ? count : PerformancePeriodOptions.default(mode))))
    }
}

struct PerformanceDividendParams: Equatable {
    var granularity = "yearly"
    var count = PerformancePeriodOptions.default("yearly")
    var symbol: String?
}

/// Web defaults: Year, 5 years of history.
@MainActor
final class PerformanceDividendsModel: PerformanceParamModel<PerformanceDividendParams, PerformanceDividends> {
    var granularity: String { params.granularity }
    var count: Int { params.count }
    var symbol: String? { params.symbol }
    init(repo: Repository) {
        super.init(initial: PerformanceDividendParams(),
                   read: { await repo.performanceDividendsCached($0.granularity, $0.count, symbol: $0.symbol) },
                   fetch: { try await repo.performanceDividends($0.granularity, $0.count, symbol: $0.symbol) })
    }
    /// `symbol`: nil keeps the current filter; `.some(nil)` clears it ("All holdings"); `.some("AAA")` filters.
    func select(_ g: String? = nil, n: Int? = nil, symbol: String?? = nil) {
        let gran = g ?? granularity
        setParams(PerformanceDividendParams(granularity: gran, count: n ?? (gran == granularity ? count : PerformancePeriodOptions.default(gran)), symbol: symbol ?? self.symbol))
    }
}

/// Listed-equity chart preferences. Daily points are only fetched when "Daily" is on.
struct PerformanceEquityPrefs: Equatable {
    var daily = false
    var totals = true
    var selected: Set<String>?
}

struct PerformanceEquityParams: Equatable {
    var granularity = "monthly"
    var count = 12
    var brokers: [String] = []
}

@MainActor
final class PerformanceEquityModel: PerformanceParamModel<PerformanceEquityParams, PerformanceGrowth> {
    @Published var prefs = PerformanceEquityPrefs()
    init(repo: Repository) {
        super.init(initial: PerformanceEquityParams(),
                   read: { await repo.performanceGrowthDailyCached($0.granularity, $0.count, brokers: $0.brokers) },
                   fetch: { try await repo.performanceGrowthDaily($0.granularity, $0.count, brokers: $0.brokers) })
    }
    func update(_ change: (inout PerformanceEquityPrefs) -> Void) { var p = prefs; change(&p); prefs = p }

    /// Called when the window or the broker selection changes while Daily is on.
    func sync(_ g: String, _ n: Int, selected: [String]) {
        let p = PerformanceEquityParams(granularity: g, count: n, brokers: selected)
        if p == params && state.data != nil { return }
        if !setParams(p) { reset(p) }   // same parameters but no data yet (earlier failure): load again
    }
}
