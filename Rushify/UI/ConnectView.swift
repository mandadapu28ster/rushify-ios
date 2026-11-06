import SwiftUI

struct ConnectView: View {
    let repo: Repository
    @State private var input = ""
    @State private var error: String?
    @State private var busy = false
    @State private var pending: ServerURL.Parsed?

    var body: some View {
        ZStack {
            RAuthBackground()
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                RushifyMark().frame(width: 76, height: 76).padding(.bottom, 4)
                Text("Rushify").font(.r(34, .bold)).foregroundStyle(RColors.text)
                Muted("Connect to your Rushify server")
                RField(title: "Server address", text: $input, id: "server_url", keyboard: .URL).padding(.top, 8)
                Muted("HTTPS is recommended. Plain http:// works for a public or private IP with a port, but traffic is not encrypted.")
                if let error { Banner(text: error, color: RColors.loss) }
                Button(action: submit) { Text(busy ? "Testing…" : "Test connection") }
                    .buttonStyle(RPrimaryButtonStyle()).disabled(busy).accessibilityIdentifier("test_connection").padding(.top, 4)
                Spacer(); Spacer()
            }
            .padding(24)
        }
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
