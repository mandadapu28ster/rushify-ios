import SwiftUI

struct ConnectView: View {
    let repo: Repository
    @State private var input = ""
    @State private var error: String?
    @State private var busy = false
    @State private var pending: ServerURL.Parsed?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Rushify").font(.system(size: 34, weight: .bold)).foregroundStyle(RColors.accent)
            Muted("Connect to your Rushify server")
            TextField("Server address", text: $input)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(14).background(RColors.bg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(RColors.variant))
                .accessibilityIdentifier("server_url")
            Muted("HTTPS is recommended. Plain http:// works for a public or private IP with a port, but traffic is not encrypted.")
            if let error { Banner(text: error, color: RColors.loss) }
            Button(action: submit) {
                Text(busy ? "Testing…" : "Test connection").font(.system(size: 16, weight: .semibold)).foregroundStyle(RColors.bg)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(RColors.accent, in: Capsule())
            }
            .disabled(busy).accessibilityIdentifier("test_connection")
            Spacer(); Spacer()
        }
        .padding(24)
        .alert("Traffic is not encrypted", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Connect anyway") { if let p = pending { pending = nil; connect(p, acknowledged: true) } }
        } message: {
            Text("\(pending?.url ?? "") uses plain HTTP. Your password and session token can be read by anyone on the network path. Only continue if you trust this network, or use HTTPS.")
        }
    }

    private func submit() {
        error = nil
        switch ServerURL.parse(input) {
        case .bad(let reason): error = reason
        case .ok(let p):
            if p.isCleartext && !repo.session.cleartextAcknowledged(p.url) { pending = p } else { connect(p, acknowledged: false) }
        }
    }

    private func connect(_ p: ServerURL.Parsed, acknowledged: Bool) {
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await repo.health(baseURL: p.url)
                if acknowledged { repo.session.acknowledgeCleartext(p.url) }
                if repo.session.setServer(p.url) { await repo.wipeCache() }
            } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }
}
