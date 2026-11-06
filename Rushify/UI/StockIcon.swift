import SwiftUI

private struct IconLoaderKey: EnvironmentKey { static let defaultValue: IconLoader? = nil }
extension EnvironmentValues {
    /// Set once at the app root; nil (previews, UI tests) means every icon is just the letter badge.
    var iconLoader: IconLoader? { get { self[IconLoaderKey.self] } set { self[IconLoaderKey.self] = newValue } }
}

/// Stock logo on a white tile (so dark logos stay visible on the dark theme), or a letter badge when there is none.
struct StockIcon: View {
    let symbol: String?
    var size: CGFloat = 28
    @Environment(\.iconLoader) private var loader
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Color.white
                Image(uiImage: image).resizable().scaledToFit().padding(2)
            } else {
                Color(hue: IconBadge.hue(symbol) / 360, saturation: 0.45, brightness: 0.5)
                Text(IconBadge.text(symbol)).font(.system(size: max(10, size * 0.38), weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
        .task(id: symbol) {
            guard let loader else { image = nil; return }
            image = loader.cachedImage(symbol)
            if image == nil, !loader.isKnownMissing(symbol) { image = await loader.image(for: symbol) }
        }
    }
}
