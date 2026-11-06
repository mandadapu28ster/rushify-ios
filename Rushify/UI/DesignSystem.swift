import SwiftUI
import UIKit

/// Spacing and shape tokens shared by every screen.
enum RSpace {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
}
enum RRadius {
    static let card: CGFloat = 16, control: CGFloat = 12
}

extension Font {
    /// A fixed design size that still follows the user's Dynamic Type setting (text size in iOS Settings).
    static func r(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size), weight: weight, design: design)
    }
}

extension Color {
    /// Hairline used on cards and fields so surfaces read as layers, not flat blocks.
    static let rHairline = Color.white.opacity(0.07)
}

/// Pressed-state feedback for tappable rows and cards.
struct RPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Main call to action (filled accent) and its quieter sibling.
struct RPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.r(16, .semibold)).foregroundStyle(enabled ? RColors.bg : RColors.muted)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(enabled ? RColors.accent : RColors.variant, in: RoundedRectangle(cornerRadius: RRadius.control))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
struct RSecondaryButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.r(15, .semibold)).foregroundStyle(destructive ? RColors.loss : RColors.accent)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background((destructive ? RColors.loss : RColors.accent).opacity(0.14), in: RoundedRectangle(cornerRadius: RRadius.control))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A moving highlight over placeholder shapes while data loads. Static when Reduce Motion is on.
struct RShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { g in
                LinearGradient(colors: [.clear, Color.white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.6).offset(x: phase * g.size.width * 1.6)
            }.clipped().allowsHitTesting(false)
        )
        .onAppear { guard !reduceMotion else { return }; withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}
extension View { func rShimmer() -> some View { modifier(RShimmer()) } }

/// Placeholder card shown while the first load is in flight (instead of a bare "Loading…").
struct RSkeletonCard: View {
    var lines = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(RColors.variant).frame(width: 120, height: 14)
            ForEach(0..<lines, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6).fill(RColors.variant.opacity(0.7)).frame(height: i == 0 ? 30 : 12).frame(maxWidth: i == lines - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(RColors.surface, in: RoundedRectangle(cornerRadius: RRadius.card))
        .overlay(RoundedRectangle(cornerRadius: RRadius.card).strokeBorder(Color.rHairline))
        .rShimmer().clipShape(RoundedRectangle(cornerRadius: RRadius.card))
        .accessibilityHidden(true)
    }
}

/// Friendly empty state: an icon, a title and what to do next.
struct REmptyState: View {
    let icon: String, title: String, message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.r(28)).foregroundStyle(RColors.muted)
            Text(title).font(.r(16, .semibold)).foregroundStyle(RColors.text)
            Text(message).font(.r(13)).foregroundStyle(RColors.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

/// The Rushify mark (rising, falling, rising line with an arrowhead), drawn so it stays sharp at any size.
struct RushifyMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 108
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func line(_ pts: [CGPoint], _ color: Color, _ w: CGFloat) {
                var path = Path(); path.move(to: pts[0]); pts.dropFirst().forEach { path.addLine(to: $0) }
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w * s, lineCap: .round, lineJoin: .round))
            }
            var area = Path(); area.move(to: p(24, 72)); [p(42, 48), p(58, 68), p(77, 39), p(77, 86), p(24, 86)].forEach { area.addLine(to: $0) }; area.closeSubpath()
            ctx.fill(area, with: .color(RColors.accent.opacity(0.12)))
            line([p(24, 72), p(42, 48)], RColors.gain, 9)
            line([p(42, 48), p(58, 68)], RColors.loss, 9)
            line([p(58, 68), p(77, 39)], RColors.gain, 9)
            line([p(82.2, 44.8), p(80, 34), p(69.2, 36.2)], RColors.accent, 8)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A text field with a clear focus ring, used on the auth screens.
struct RField: View {
    let title: String
    @Binding var text: String
    var id: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField("", text: $text, prompt: prompt) } else { TextField("", text: $text, prompt: prompt).keyboardType(keyboard) }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(contentType)
        .focused($focused)
        .font(.r(16)).foregroundStyle(RColors.text)
        .padding(.horizontal, 14).frame(minHeight: 52)
        .background(RColors.surface, in: RoundedRectangle(cornerRadius: RRadius.control))
        .overlay(RoundedRectangle(cornerRadius: RRadius.control).strokeBorder(focused ? RColors.accent : Color.rHairline, lineWidth: focused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: focused)
        .accessibilityIdentifier(id)
    }
    private var prompt: Text { Text(title).foregroundStyle(RColors.muted) }
}

/// Dark background with a soft accent glow at the top, for the sign-in screens.
struct RAuthBackground: View {
    var body: some View {
        ZStack {
            RColors.bg
            RadialGradient(colors: [RColors.accent.opacity(0.20), .clear], center: .top, startRadius: 0, endRadius: 460)
        }.ignoresSafeArea()
    }
}

// MARK: - Motion

/// One set of animation curves for the whole app. Motion is brief and purposeful; with Reduce Motion on, movement becomes a quick fade.
enum RMotion {
    static let snappy = Animation.snappy(duration: 0.28)
    static let smooth = Animation.smooth(duration: 0.35)
    /// Expanding and collapsing a section: a soft spring with no bounce, slow enough to follow with the eye.
    static let expand = Animation.spring(response: 0.55, dampingFraction: 0.9)
    static let quick = Animation.easeOut(duration: 0.15)
    static let fade = Animation.easeInOut(duration: 0.18)
    static func standard(reduce: Bool) -> Animation { reduce ? fade : snappy }
    /// Delay for the nth item of a staggered entrance; none with Reduce Motion, and capped so long lists don't wait.
    static func stagger(_ index: Int, reduce: Bool) -> Double { reduce ? 0 : min(Double(index), 6) * 0.045 }
}

/// Fades and lifts a view in once, with an optional delay (staggered entrances). Plain fade with Reduce Motion.
struct RAppear: ViewModifier {
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 10)
            .onAppear { withAnimation(reduce ? RMotion.fade : RMotion.smooth.delay(delay)) { shown = true } }
    }
}
extension View {
    func rAppear(_ index: Int = 0) -> some View { modifier(RAppear(delay: RMotion.stagger(index, reduce: false))) }
}

/// Sliding selector for a small set of views (Pulse, Performance). The highlight glides between choices; each choice keeps its own identifier.
struct RSegmented: View {
    let titles: [String]
    @Binding var selection: Int
    var idPrefix: String
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                Button { withAnimation(RMotion.standard(reduce: reduce)) { selection = i } } label: {
                    Text(t).font(.r(13, .semibold)).foregroundStyle(selection == i ? RColors.text : RColors.muted)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selection == i {
                                Capsule().fill(RColors.elevated).matchedGeometryEffect(id: "seg", in: ns)
                                    .overlay(Capsule().strokeBorder(Color.rHairline))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(idPrefix)_\(t.lowercased())")
                .accessibilityAddTraits(selection == i ? .isSelected : [])
            }
        }
        .padding(3).background(RColors.variant, in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}
