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

enum MoreDest: String, CaseIterable, Hashable {
    case holdings, sync, ai, performance, corporate, connections, addHolding, password
    var title: String {
        switch self {
        case .holdings: return "Holdings"
        case .sync: return "Sync"
        case .ai: return "AI assistant"
        case .performance: return "Performance & income"
        case .corporate: return "Corporate actions"
        case .connections: return "Connections & keys"
        case .addHolding: return "Add holding"
        case .password: return "Change password"
        }
    }
    var subtitle: String {
        switch self {
        case .holdings: return "Positions by account, lots, sectors"
        case .sync: return "Trading 212, SnapTrade and Monzo"
        case .ai: return "Ask about your portfolio"
        case .performance: return "Growth, benchmarks, dividends"
        case .corporate: return "Splits, mergers, symbols to confirm"
        case .connections: return "Trading 212, SnapTrade, Monzo and AI status"
        case .addHolding: return "Stock or ETF lot, property, cash savings, other asset"
        case .password: return "Sign in again with a new password"
        }
    }
}

struct MoreView: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    @Binding var hideBalances: Bool
    var onSignOut: () -> Void

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
                        ForEach(MoreDest.allCases, id: \.self) { d in
                            NavigationLink(value: d) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.title).font(.system(size: 16)).foregroundStyle(RColors.text)
                                        Muted(d.subtitle)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(RColors.muted)
                                }.padding(.vertical, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("menu_\(d.rawValue)")
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
            .navigationDestination(for: MoreDest.self) { destination($0) }
        }
    }

    @ViewBuilder private func destination(_ d: MoreDest) -> some View {
        switch d {
        case .holdings:
            HoldingsScreen(repo: repo, session: session, holdingActions: manualHoldingActions(repo: repo), showTitle: false)
                .background(RColors.bg).navigationTitle("Holdings").navigationBarTitleDisplayMode(.inline)
        case .sync:
            SyncScreen(repo: repo, session: session, showTitle: false).background(RColors.bg).navigationTitle("Sync").navigationBarTitleDisplayMode(.inline)
        case .ai: AiScreen(repo: repo, session: session).background(RColors.bg)
        case .performance: PerformanceScreen(repo: repo, session: session).background(RColors.bg)
        case .corporate: CorporateScreen(repo: repo, session: session).background(RColors.bg)
        case .connections: ConnectionsScreen(repo: repo, session: session).background(RColors.bg)
        case .addHolding: AddHoldingScreen(repo: repo).background(RColors.bg).navigationTitle("Add holding").navigationBarTitleDisplayMode(.inline)
        case .password:
            // The screen signs the user out itself once the password changed (the old token is revoked).
            ChangePasswordScreen(repo: repo, session: session, onChanged: {}).background(RColors.bg)
        }
    }
}
