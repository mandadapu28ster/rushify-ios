import SwiftUI

struct RCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RSpace.l)
            .background(RColors.surface, in: RoundedRectangle(cornerRadius: RRadius.card))
            .overlay(RoundedRectangle(cornerRadius: RRadius.card).strokeBorder(Color.rHairline))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.r(17, .semibold)).foregroundStyle(RColors.text).accessibilityAddTraits(.isHeader) }
}

struct Muted: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.r(13)).foregroundStyle(RColors.muted).fixedSize(horizontal: false, vertical: true) }
}

/// A number: tabular figures so columns of amounts line up, without the code-like look of a monospaced face.
struct Num: View {
    let text: String
    var color: Color = RColors.text
    var size: CGFloat = 14
    var bold = false
    init(_ text: String, color: Color = RColors.text, size: CGFloat = 14, bold: Bool = false) { self.text = text; self.color = color; self.size = size; self.bold = bold }
    var body: some View {
        Text(text).font(.r(size, bold ? .semibold : .regular)).monospacedDigit().foregroundStyle(color)
            .contentTransition(.numericText()).animation(.snappy(duration: 0.3), value: text)
    }
}

struct Stat: View {
    let label: String, value: String
    var color: Color = RColors.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) { Muted(label); Num(value, color: color, size: 16, bold: true) }
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct Banner: View {
    let text: String
    var color: Color = RColors.warn
    var body: some View {
        Text(text).font(.r(12)).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.18)))
    }
}

/// Slim "not encrypted" marker shown while connected over plain http (replaces a full-width banner on every screen).
struct HTTPPill: View {
    var body: some View {
        Label("Not encrypted (http)", systemImage: "lock.open.fill")
            .font(.r(11, .semibold)).foregroundStyle(RColors.warn)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RColors.warn.opacity(0.14), in: Capsule())
            .accessibilityLabel("Not encrypted. Avoid public Wi-Fi.")
    }
}

struct Chip: View {
    let text: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.r(13, .medium)).foregroundStyle(selected ? RColors.accent : RColors.muted)
                .padding(.horizontal, 14).frame(minHeight: 34)
                .background(selected ? RColors.accent.opacity(0.22) : RColors.variant, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? RColors.accent.opacity(0.35) : Color.clear))
        }
        .buttonStyle(RPressStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ErrorState: View {
    let message: String
    var retry: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").font(.r(26)).foregroundStyle(RColors.warn)
            Text("Couldn't load this").font(.r(16, .semibold)).foregroundStyle(RColors.text)
            Muted(message).multilineTextAlignment(.center)
            Button("Try again", action: retry).buttonStyle(RSecondaryButtonStyle())
        }.frame(maxWidth: .infinity).padding(24)
    }
}

/// "As of" label plus the stale/offline banner.
struct AsOfBar: View {
    var asOf: Date?
    var error: String?
    var hasData: Bool
    var loading: Bool
    var label: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error, hasData { Banner(text: "Offline or server error — showing saved data. \(error)") }
            HStack(spacing: 8) {
                let text = label ?? asOf.map { "Updated \(Fmt.stamp($0))" } ?? ""
                if !text.isEmpty { Muted(text) }
                if loading { ProgressView().controlSize(.mini).tint(RColors.muted); Text("refreshing").font(.r(12)).foregroundStyle(RColors.muted) }
            }
        }
    }
}

/// Title and a short summary while collapsed; the full content when expanded (the web's HomeCollapsible).
struct HomeCollapsible<Content: View>: View {
    let id: String, title: String, summary: String
    let expanded: Bool
    let onToggle: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        RCard {
            Button(action: onToggle) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTitle(title)
                        if !expanded { Muted(summary).accessibilityIdentifier("section_summary_\(id)").transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.15))) }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.r(12, .semibold)).foregroundStyle(RColors.muted)
                        .rotationEffect(.degrees(expanded ? 180 : 0)).padding(.top, 5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RPressStyle())
            .sensoryFeedback(.selection, trigger: expanded)
            .accessibilityIdentifier("section_toggle_\(id)")
            .accessibilityValue(expanded ? "expanded" : "collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 8) { content() }.padding(.top, 8)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("section_body_\(id)")
                    .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.3).delay(0.12)), removal: .opacity.animation(.easeOut(duration: 0.15))))
            }
        }
        .animation(RMotion.expand, value: expanded)
    }
}
