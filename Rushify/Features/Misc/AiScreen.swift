import SwiftUI

struct AiScreen: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    @StateObject private var vm: AiViewModel
    @State private var draft = ""

    init(repo: Repository, session: SessionManager) {
        self.repo = repo; self.session = session
        _vm = StateObject(wrappedValue: AiViewModel(repo: repo))
    }

    var body: some View {
        let ui = vm.ui
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Muted(ui.disclaimer).accessibilityIdentifier("ai_disclaimer")
                    Spacer(minLength: 8)
                    if !ui.messages.isEmpty { Chip(text: "Clear chat") { vm.clear(); draft = "" }.accessibilityIdentifier("ai_clear") }
                }
                if !ui.blocked && !ui.online && ui.keyReady == true {
                    Muted("Standard mode: replies use your Rushify portfolio snapshot only (no live web). Turn on online augmentation (beta) to allow web search when data is missing.").accessibilityIdentifier("ai_standard_note")
                }
                if let w = ui.warning { Banner(text: w, color: RColors.warn) }
                if let e = ui.error { Banner(text: e, color: RColors.loss).accessibilityIdentifier("ai_error") }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            if ui.blocked {
                RCard {
                    Text(ui.providerLabel.map { "No \($0) API key saved yet." } ?? "AI isn't set up yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(RColors.text)
                    Muted("The assistant uses your own \(ui.providerLabel ?? "Gemini or OpenAI") API key. Add it, and choose the matching provider, in the web app under Settings → Keys, then come back here. Keys are never entered on the phone.")
                }.padding(16).accessibilityIdentifier("ai_not_configured")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if ui.messages.isEmpty && !ui.blocked { Muted("Ask about your portfolio, e.g. \"Which sectors am I most exposed to?\"").frame(maxWidth: .infinity, alignment: .leading) }
                        ForEach(ui.messages) { m in bubble(m) }
                        if ui.sending { HStack { ProgressView().controlSize(.small); Muted("  Thinking…"); Spacer() } }
                        if ui.suggestOnline { HStack { Chip(text: "Answer used local data only. Try online augmentation (beta)?") { vm.setOnline(true) }; Spacer() } }
                        Color.clear.frame(height: 1).id("ai_bottom")
                    }.padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("ai_messages")
                .onChange(of: ui.messages.count) { _, _ in withAnimation { proxy.scrollTo("ai_bottom") } }
                .onChange(of: ui.sending) { _, _ in withAnimation { proxy.scrollTo("ai_bottom") } }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(get: { vm.ui.online }, set: { vm.setOnline($0) })) { Muted("Use online augmentation (beta)") }
                    .accessibilityIdentifier("ai_online")
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Ask something", text: $draft, axis: .vertical)
                            .lineLimit(1...4).padding(10).foregroundStyle(RColors.text)
                            .background(RColors.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(RColors.variant))
                            .disabled(ui.blocked)
                            .accessibilityIdentifier("ai_input")
                        if draft.count > 3500 { Muted("\(draft.utf16.count)/\(AiViewModel.maxPrompt)") }
                    }
                    Button { let p = draft; draft = ""; Task { await vm.send(p) } } label: {
                        Text("Send").font(.system(size: 15, weight: .semibold)).foregroundStyle(RColors.bg)
                            .padding(.horizontal, 18).padding(.vertical, 11).background(RColors.accent, in: Capsule())
                    }
                    .buttonStyle(.plain).disabled(!canSend).opacity(canSend ? 1 : 0.5)
                    .accessibilityIdentifier("ai_send")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(RColors.bg)
        .navigationTitle("AI assistant")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.checkCredentials() }
        .onChange(of: vm.ui.restore) { _, r in
            if let r { draft = r; vm.consumeRestore() }
        }
        .onChange(of: draft) { old, new in if new.utf16.count > AiViewModel.maxPrompt { draft = old } }
        .task(id: vm.ui.warning) {
            guard vm.ui.warning != nil else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { vm.clearWarning() }
        }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.ui.sending && !vm.ui.blocked }

    private func bubble(_ m: AiChatMsg) -> some View {
        let mine = m.role == "user"
        return HStack {
            if mine { Spacer(minLength: 32) }
            Group {
                if mine { Text(m.text) } else { Text(AiSimpleMarkdown.attributed(m.text)) }
            }
            .font(.system(size: 14)).foregroundStyle(RColors.text).textSelection(.enabled)
            .padding(12)
            .background(mine ? RColors.accent.opacity(0.2) : RColors.surface, in: RoundedRectangle(cornerRadius: 14))
            if !mine { Spacer(minLength: 32) }
        }
    }
}
