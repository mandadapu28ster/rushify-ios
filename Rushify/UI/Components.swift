import SwiftUI

struct RCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RColors.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 17, weight: .semibold)).foregroundStyle(RColors.text) }
}

struct Muted: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 13)).foregroundStyle(RColors.muted).fixedSize(horizontal: false, vertical: true) }
}

struct Num: View {
    let text: String
    var color: Color = RColors.text
    var size: CGFloat = 14
    var bold = false
    init(_ text: String, color: Color = RColors.text, size: CGFloat = 14, bold: Bool = false) { self.text = text; self.color = color; self.size = size; self.bold = bold }
    var body: some View { Text(text).font(.system(size: size, weight: bold ? .semibold : .regular, design: .monospaced)).foregroundStyle(color) }
}

struct Stat: View {
    let label: String, value: String
    var color: Color = RColors.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) { Muted(label); Num(value, color: color, size: 16, bold: true) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Banner: View {
    let text: String
    var color: Color = RColors.warn
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Chip: View {
    let text: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(selected ? RColors.accent : RColors.muted)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? RColors.accent.opacity(0.22) : RColors.variant, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct ErrorState: View {
    let message: String
    var retry: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Text("Couldn't load this").font(.system(size: 15, weight: .semibold)).foregroundStyle(RColors.text)
            Muted(message).multilineTextAlignment(.center)
            Chip(text: "Retry", action: retry)
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
                if loading { Muted("refreshing…") }
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
                        if !expanded { Muted(summary).accessibilityIdentifier("section_summary_\(id)") }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12)).foregroundStyle(RColors.muted).padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("section_toggle_\(id)")
            if expanded {
                VStack(alignment: .leading, spacing: 8) { content() }.padding(.top, 8).accessibilityIdentifier("section_body_\(id)")
            }
        }
        .accessibilityIdentifier("section_\(id)")
    }
}
