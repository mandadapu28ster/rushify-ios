import SwiftUI

struct ComingSoonView: View {
    let title: String
    var note = "This screen arrives in an upcoming update. The Android app already has it."
    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(RColors.text)
            Muted(note).multilineTextAlignment(.center)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(RColors.bg)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct MoreView: View {
    @ObservedObject var session: SessionManager
    @Binding var hideBalances: Bool
    var onSignOut: () -> Void

    private let rows: [(title: String, subtitle: String)] = [
        ("Holdings", "Positions by account, lots, sectors"),
        ("Sync", "Trading 212, SnapTrade and Monzo"),
        ("AI assistant", "Ask about your portfolio"),
        ("Performance & income", "Growth, benchmarks, dividends"),
        ("Corporate actions", "Splits, mergers, symbols to confirm"),
        ("Connections & keys", "Trading 212, SnapTrade, Monzo and AI status"),
        ("Add holding", "Stock or ETF lot, property, cash savings, other asset"),
        ("Change password", "Sign in again with a new password"),
    ]
    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("More").font(.system(size: 28, weight: .semibold)).foregroundStyle(RColors.text)
                    if session.state.isAdmin {
                        RCard {
                            Text("Admin account").font(.system(size: 15, weight: .semibold)).foregroundStyle(RColors.accent)
                            Muted("Admin tools are web-only. Open the web app → More → Admin. For your portfolio on this phone, sign in with your personal account.")
                        }
                    }
                    RCard {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                            NavigationLink { ComingSoonView(title: r.title) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title).font(.system(size: 16)).foregroundStyle(RColors.text)
                                        Muted(r.subtitle)
                                    }
                                    Spacer()
                                    Text("Soon").font(.system(size: 11, weight: .medium)).foregroundStyle(RColors.muted)
                                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(RColors.muted)
                                }.padding(.vertical, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("menu_\(i)")
                        }
                    }
                    RCard {
                        Muted("Signed in as")
                        Text(session.state.username ?? "").font(.system(size: 18, weight: .semibold)).foregroundStyle(RColors.text)
                        Muted("Server")
                        Num(session.state.serverUrl ?? "", size: 13)
                        if session.state.cleartext { Banner(text: "Connection is not encrypted (http).") }
                    }
                    RCard {
                        SectionTitle("Privacy")
                        Toggle(isOn: $hideBalances) {
                            VStack(alignment: .leading, spacing: 2) { Text("Hide balances").foregroundStyle(RColors.text); Muted("Show •••• instead of amounts") }
                        }.tint(RColors.accent).accessibilityIdentifier("toggle_hide")
                    }
                    Button(action: onSignOut) {
                        Text("Sign out").font(.system(size: 16, weight: .semibold)).foregroundStyle(RColors.loss)
                            .frame(maxWidth: .infinity).padding(.vertical, 14).background(RColors.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.accessibilityIdentifier("sign_out")
                    Muted("Rushify for iOS \(appVersion)").frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(RColors.bg)
        }
    }
}
