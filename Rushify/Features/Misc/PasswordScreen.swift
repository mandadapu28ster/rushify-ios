import SwiftUI

struct PasswordUi: Equatable {
    var busy = false
    var error: String?
    var done = false
}

enum PasswordRules {
    static let min = 8
    /// Same checks and wording as the web's "Set your own password" page.
    static func validate(_ current: String, _ new: String, _ confirm: String) -> String? {
        if new != confirm { return "New password and confirmation do not match." }
        if new.count < min { return "New password must be at least \(min) characters." }
        if new == current { return "New password must be different from your current password." }
        if current.isEmpty { return "Enter your current password." }
        return nil
    }
}

/// Changes the password through the same public endpoint as the web. The server then ends every session of this
/// user, so on success the app signs out and asks for the new password. Passwords are never stored.
@MainActor
final class PasswordViewModel: ObservableObject {
    @Published var ui = PasswordUi()
    private let repo: Repository

    init(repo: Repository) { self.repo = repo }

    func submit(current: String, new: String, confirm: String) async {
        if ui.busy { return }
        if let msg = PasswordRules.validate(current, new, confirm) { ui = PasswordUi(error: msg); return }
        guard let username = repo.session.current.username else { ui = PasswordUi(error: "You are not signed in."); return }
        ui = PasswordUi(busy: true)
        do {
            try await repo.miscReplacePassword(username: username, current: current, new: new, confirm: confirm)
            ui = PasswordUi(done: true)
        } catch ApiError.badCredentials, ApiError.sessionExpired {
            // The endpoint is public, so a 401 means the current password was wrong. The session itself is untouched.
            ui = PasswordUi(error: "Current password is incorrect.")
        } catch let e as ApiError {
            ui = PasswordUi(error: e.message.isEmpty ? "Could not update password" : e.message)
        } catch {
            ui = PasswordUi()
        }
    }

    /// After success: all sessions are revoked server-side, so leave cleanly and show the sign-in screen.
    func finish() async { repo.session.expire(); await repo.wipeCache() }
}

struct ChangePasswordScreen: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    let onChanged: () -> Void
    @StateObject private var vm: PasswordViewModel
    @State private var cur = ""
    @State private var new = ""
    @State private var conf = ""

    init(repo: Repository, session: SessionManager, onChanged: @escaping () -> Void) {
        self.repo = repo; self.session = session; self.onChanged = onChanged
        _vm = StateObject(wrappedValue: PasswordViewModel(repo: repo))
    }

    private var canSubmit: Bool { !vm.ui.busy && !vm.ui.done && !cur.isEmpty && !new.isEmpty && !conf.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Muted("Choose a new password (at least \(PasswordRules.min) characters). You will be signed out everywhere and asked to sign in with the new password.")
                field("Current password", $cur, "pw_current", .password)
                field("New password", $new, "pw_new", .newPassword)
                field("Confirm new password", $conf, "pw_confirm", .newPassword)
                if let e = vm.ui.error { Banner(text: e, color: RColors.loss).accessibilityIdentifier("pw_error") }
                if vm.ui.done { Banner(text: "Password updated. Please sign in with your new password.", color: RColors.gain).accessibilityIdentifier("pw_done") }
                Button { Task { await vm.submit(current: cur, new: new, confirm: conf) } } label: {
                    Text(vm.ui.busy ? "Saving…" : "Save new password").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(RColors.accent).disabled(!canSubmit)
                .accessibilityIdentifier("pw_submit").padding(.top, 4)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RColors.bg)
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: vm.ui.done) { _, done in
            guard done else { return }
            cur = ""; new = ""; conf = ""
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await vm.finish()
                onChanged()
            }
        }
    }

    private func field(_ title: String, _ text: Binding<String>, _ id: String, _ type: UITextContentType) -> some View {
        SecureField(title, text: text)
            .textContentType(type).textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(12).foregroundStyle(RColors.text)
            .background(RColors.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(RColors.variant))
            .accessibilityIdentifier(id)
    }
}
