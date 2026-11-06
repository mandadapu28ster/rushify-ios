import SwiftUI

struct LoginView: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var version: String?

    private var canSubmit: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !busy }

    var body: some View {
        ZStack {
            RAuthBackground()
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                RushifyMark().frame(width: 64, height: 64).padding(.bottom, 2)
                Text("Sign in").font(.r(32, .bold)).foregroundStyle(RColors.text)
                Muted([session.state.serverUrl, version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
                if session.state.cleartext { Banner(text: "Not encrypted (http). Your password is sent in clear text.") }
                if session.state.expired { Banner(text: "Your session expired. Please sign in again.", color: RColors.accent) }
                RField(title: "Username or email", text: $username, id: "username", contentType: .username).padding(.top, 6)
                RField(title: "Password", text: $password, id: "password", secure: true, contentType: .password)
                if let error { Banner(text: error, color: RColors.loss) }
                Button(action: submit) { Text(busy ? "Signing in…" : "Sign in") }
                    .buttonStyle(RPrimaryButtonStyle()).disabled(!canSubmit).accessibilityIdentifier("sign_in").padding(.top, 4)
                    .sensoryFeedback(.error, trigger: error)
                Button("Change server") { session.clearServer() }.font(.r(14)).foregroundStyle(RColors.muted).padding(.top, 4)
                Spacer(); Spacer()
            }
            .padding(24)
        }
        .task { if let s = session.state.serverUrl { version = (try? await repo.health(baseURL: s))?.version } }
    }

    private func submit() {
        error = nil; busy = true
        let u = username.trimmingCharacters(in: .whitespaces), p = password
        Task {
            defer { busy = false }
            do { try await repo.login(username: u, password: p); password = "" }
            catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }
}
