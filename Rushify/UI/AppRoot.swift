import SwiftUI

final class AppContainer: ObservableObject {
    let session: SessionManager
    let api: ApiClient
    let repo: Repository

    init(session: SessionManager? = nil, cache: CacheStore? = nil) {
        if let t = UITestMode.parts() {   // debug-only UI-test scenario: canned responses, no real storage
            self.session = t.session
            api = ApiClient(session: t.session, urlSession: t.urlSession)
            repo = Repository(api: api, session: t.session, cache: t.cache)
            return
        }
        let s = session ?? SessionManager(store: UserDefaultsStore(), secrets: KeychainStore())
        self.session = s
        api = ApiClient(session: s)
        repo = Repository(api: api, session: s, cache: cache ?? FileCacheStore())
    }
}

struct AppRoot: View {
    let container: AppContainer
    @ObservedObject var session: SessionManager
    @State private var hide: Bool

    init(container: AppContainer) {
        self.container = container
        session = container.session
        _hide = State(initialValue: container.session.hideBalances)
    }

    var body: some View {
        Group {
            if session.state.serverUrl == nil { ConnectView(repo: container.repo) }
            else if !session.state.loggedIn { LoginView(repo: container.repo, session: session) }
            else { MainTabs(container: container, session: session, hide: $hide) }
        }
        .environment(\.hideBalances, hide)
        .onChange(of: hide) { _, v in session.hideBalances = v }
        .background(RColors.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct MainTabs: View {
    let container: AppContainer
    @ObservedObject var session: SessionManager
    @Binding var hide: Bool

    var body: some View {
        VStack(spacing: 0) {
            if session.state.cleartext {
                Banner(text: "Not encrypted (http) — avoid public Wi-Fi").padding(.horizontal, 12).padding(.vertical, 4).accessibilityIdentifier("http_chip")
            }
            TabView {
                HomeView(repo: container.repo, session: session)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                PulseScreen(repo: container.repo, session: session)
                    .tabItem { Label("Pulse", systemImage: "star.fill") }
                MoreView(repo: container.repo, session: session, hideBalances: $hide) {
                    container.session.logout()
                    Task { await container.repo.wipeCache() }
                }
                .tabItem { Label("More", systemImage: "line.3.horizontal") }
            }
            .tint(RColors.accent)
        }
        // Like the web: when the app opens, refresh Monzo if the server says its last sync is older than 6 hours.
        .task(id: session.state.cacheScope) { _ = await syncMonzoRefreshIfStale(repo: container.repo) }
    }
}
