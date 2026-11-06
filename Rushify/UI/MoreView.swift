import SwiftUI

struct ComingSoonView: View {
    let title: String
    var note = "This screen arrives in an upcoming update. The Android app already has it."
    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.r(22, .semibold)).foregroundStyle(RColors.text)
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
    var section: RSection {
        switch self {
        case .holdings: return .holdings
        case .sync: return .sync
        case .ai: return .ai
        case .performance: return .performance
        case .corporate: return .corporate
        case .connections: return .connections
        case .addHolding: return .addHolding
        case .password: return .password
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
    @ObservedObject var lock: AppLock
    @Binding var hideBalances: Bool
    @Binding var paletteCB: Bool
    var onSignOut: () -> Void
    @State private var lockMessage: String?

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if session.state.isAdmin {
                        RCard {
                            Text("Admin account").font(.r(15, .semibold)).foregroundStyle(RColors.accent)
                            Muted("Admin tools are web-only. Open the web app → More → Admin. For your portfolio on this phone, sign in with your personal account.")
                        }
                    }
                    RCard {
                        ForEach(MoreDest.allCases, id: \.self) { d in
                            NavigationLink(value: d) {
                                HStack(spacing: 12) {
                                    Image(systemName: d.section.symbol).font(.r(15, .semibold)).foregroundStyle(d.section.tint)
                                        .frame(width: 32, height: 32)
                                        .background(d.section.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.title).font(.r(16)).foregroundStyle(RColors.text)
                                        Muted(d.subtitle)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.r(12)).foregroundStyle(RColors.muted)
                                }.padding(.vertical, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("menu_\(d.rawValue)")
                        }
                    }
                    RCard {
                        Muted("Signed in as")
                        Text(session.state.username ?? "").font(.r(18, .semibold)).foregroundStyle(RColors.text)
                        Muted("Server")
                        Num(session.state.serverUrl ?? "", size: 13)
                        if session.state.cleartext { Banner(text: "Connection is not encrypted (http).") }
                    }
                    RCard {
                        SectionTitle("Privacy & security")
                        Toggle(isOn: $hideBalances) {
                            VStack(alignment: .leading, spacing: 2) { Text("Hide balances").foregroundStyle(RColors.text); Muted("Show •••• instead of amounts") }
                        }.tint(RColors.accent).accessibilityIdentifier("toggle_hide")
                        Divider().overlay(Color.rHairline)
                        Toggle(isOn: Binding(get: { paletteCB }, set: { paletteCB = $0; RPalette.set(colorBlindFriendly: $0) })) {
                            VStack(alignment: .leading, spacing: 2) { Text("Colour-blind friendly").foregroundStyle(RColors.text); Muted("Blue and orange instead of green and red") }
                        }.tint(RColors.accent).accessibilityIdentifier("toggle_palette")
                        Divider().overlay(Color.rHairline)
                        Toggle(isOn: lockBinding) {
                            VStack(alignment: .leading, spacing: 2) { Text("Require \(lock.methodName ?? "passcode")").foregroundStyle(RColors.text); Muted("Ask each time you open Rushify") }
                        }.tint(RColors.accent).accessibilityIdentifier("toggle_lock")
                        if lock.enabled {
                            HStack {
                                Text("Lock").foregroundStyle(RColors.text)
                                Spacer()
                                Picker("Lock", selection: Binding(get: { lock.timeout }, set: { lock.setTimeout($0) })) {
                                    ForEach(AppLock.Timeout.allCases) { Text($0.label).tag($0) }
                                }.pickerStyle(.menu).tint(RColors.accent).accessibilityIdentifier("lock_timeout")
                            }
                        }
                        if let lockMessage { Banner(text: lockMessage, color: RColors.warn).accessibilityIdentifier("lock_message") }
                        Divider().overlay(Color.rHairline)
                        Toggle(isOn: Binding(get: { lock.privacyShield }, set: { lock.setPrivacyShield($0) })) {
                            VStack(alignment: .leading, spacing: 2) { Text("Hide in app switcher").foregroundStyle(RColors.text); Muted("Cover the screen when you leave the app") }
                        }.tint(RColors.accent).accessibilityIdentifier("toggle_shield")
                    }
                    Button(action: onSignOut) {
                        Text("Sign out").font(.r(16, .semibold)).foregroundStyle(RColors.loss)
                            .frame(maxWidth: .infinity).padding(.vertical, 14).background(RColors.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.accessibilityIdentifier("sign_out")
                    Muted("Rushify for iOS \(appVersion)").frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(RColors.bg)
            .navigationTitle("More").navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarLeading) { if session.state.cleartext { HTTPPill().accessibilityIdentifier("http_chip") } } }
            .navigationDestination(for: MoreDest.self) { destination($0).toolbar(.hidden, for: .tabBar) }
        }
    }

    private var lockBinding: Binding<Bool> {
        Binding(get: { lock.enabled }, set: { on in
            lockMessage = nil
            Task {
                let ok = await lock.setEnabled(on)
                if !ok && on { lockMessage = lock.methodName == nil ? "Set a passcode in the iPhone Settings app first, then try again." : "Couldn't confirm it's you, so the lock stays off." }
            }
        })
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
