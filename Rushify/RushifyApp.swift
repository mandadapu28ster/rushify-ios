import SwiftUI

@main
struct RushifyApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            AppRoot(container: container)
                .task { await debugSignIn() }
        }
    }

    /// Debug builds only: set RUSHIFY_DEBUG_SERVER and RUSHIFY_DEBUG_TOKEN to sign in without typing a password
    /// (xcrun simctl launch with SIMCTL_CHILD_ prefixed variables). Not compiled into release builds.
    private func debugSignIn() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let server = env["RUSHIFY_DEBUG_SERVER"], let token = env["RUSHIFY_DEBUG_TOKEN"], !server.isEmpty, !token.isEmpty else { return }
        if container.session.setServer(server) { await container.repo.wipeCache() }
        container.session.acknowledgeCleartext(server)
        try? await container.repo.signIn(withToken: token)
        #endif
    }
}
