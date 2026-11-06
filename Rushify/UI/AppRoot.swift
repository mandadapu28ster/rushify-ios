import SwiftUI

final class AppContainer: ObservableObject {
    let session: SessionManager
    let api: ApiClient
    let repo: Repository
    let lock: AppLock

    init(session: SessionManager? = nil, cache: CacheStore? = nil) {
        if let t = UITestMode.parts() {   // debug-only UI-test scenario: canned responses, no real storage
            self.session = t.session
            lock = t.lock
            api = ApiClient(session: t.session, urlSession: t.urlSession)
            repo = Repository(api: api, session: t.session, cache: t.cache)
            return
        }
        let s = session ?? SessionManager(store: UserDefaultsStore(), secrets: KeychainStore())
        self.session = s
        lock = AppLock(store: UserDefaultsStore())
        api = ApiClient(session: s)
        repo = Repository(api: api, session: s, cache: cache ?? FileCacheStore())
    }
}

struct AppRoot: View {
    let container: AppContainer
    @ObservedObject var session: SessionManager
    @ObservedObject var lock: AppLock
    @State private var hide: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    init(container: AppContainer) {
        self.container = container
        session = container.session
        lock = container.lock
        _hide = State(initialValue: container.session.hideBalances)
    }

    private var covered: Bool { lock.isLocked && session.state.loggedIn }

    var body: some View {
        ZStack {
            Group {
                if session.state.serverUrl == nil { ConnectView(repo: container.repo) }
                else if !session.state.loggedIn { LoginView(repo: container.repo, session: session) }
                else if !covered { MainTabs(container: container, session: session, lock: lock, hide: $hide) }   // not even built while locked
            }
            if covered { LockScreen(lock: lock).transition(.opacity) }
            if lock.shieldVisible { ShieldCover().transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.2), value: covered)
        .animation(.easeInOut(duration: 0.15), value: lock.shieldVisible)
        .environment(\.hideBalances, hide)
        .scrollDismissesKeyboard(.interactively)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .id(typeSize)       // rebuild once when the user changes the text size, so scaled fonts update
        .onChange(of: hide) { _, v in session.hideBalances = v }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive: lock.appBecameInactive()
            case .background: lock.appEnteredBackground()
            case .active: lock.appBecameActive()
            @unknown default: break
            }
        }
        .background(RColors.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// Shown while the app lock is on and the owner has not been confirmed yet.
struct LockScreen: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        ZStack {
            RAuthBackground()
            VStack(spacing: 14) {
                RushifyMark().frame(width: 72, height: 72)
                Text("Rushify is locked").font(.r(24, .bold)).foregroundStyle(RColors.text).accessibilityIdentifier("lock_screen")
                Muted("Confirm it's you to see your portfolio.")
                if lock.lastAttemptFailed { Banner(text: "Couldn't confirm it's you. Try again.", color: RColors.loss) }
                Button { Task { await lock.unlock() } } label: { Label("Unlock with \(lock.methodName ?? "passcode")", systemImage: "lock.open.fill") }
                    .buttonStyle(RPrimaryButtonStyle()).padding(.top, 8).accessibilityIdentifier("unlock_button")
            }
            .padding(32)
        }
        .task { await lock.unlock() }
    }
}

/// Opaque cover drawn whenever the app is not active, so the app switcher never shows balances.
struct ShieldCover: View {
    var body: some View {
        ZStack { RColors.bg; RushifyMark().frame(width: 84, height: 84) }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct MainTabs: View {
    let container: AppContainer
    @ObservedObject var session: SessionManager
    @ObservedObject var lock: AppLock
    @Binding var hide: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                HomeView(repo: container.repo, session: session, hideBalances: $hide)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                NavigationStack {
                    PulseScreen(repo: container.repo, session: session)
                        .navigationTitle("Pulse").navigationBarTitleDisplayMode(.large)
                        .toolbar { ToolbarItem(placement: .topBarLeading) { if session.state.cleartext { HTTPPill().accessibilityIdentifier("http_chip") } } }
                }
                .tabItem { Label("Pulse", systemImage: "star.fill") }
                MoreView(repo: container.repo, session: session, lock: lock, hideBalances: $hide) {
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
