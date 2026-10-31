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
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Sign in").font(.system(size: 32, weight: .bold)).foregroundStyle(RColors.text)
            Muted([session.state.serverUrl, version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
            if session.state.cleartext { Banner(text: "Not encrypted (http). Your password is sent in clear text.") }
            if session.state.expired { Banner(text: "Your session expired. Please sign in again.", color: RColors.accent) }
            field("Username or email", text: $username, id: "username")
            SecureField("Password", text: $password)
                .padding(14).background(RColors.bg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(RColors.variant))
                .accessibilityIdentifier("password")
            if let error { Banner(text: error, color: RColors.loss) }
            Button(action: submit) {
                Text(busy ? "Signing in…" : "Sign in").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSubmit ? RColors.bg : RColors.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(canSubmit ? RColors.accent : RColors.variant, in: Capsule())
            }
            .disabled(!canSubmit).accessibilityIdentifier("sign_in")
            Button("Change server") { session.clearServer() }.font(.system(size: 14)).foregroundStyle(RColors.muted).padding(.top, 4)
            Spacer(); Spacer()
        }
        .padding(24)
        .task { if let s = session.state.serverUrl { version = (try? await repo.health(baseURL: s))?.version } }
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
            .padding(14).background(RColors.bg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(RColors.variant))
            .accessibilityIdentifier(id)
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
