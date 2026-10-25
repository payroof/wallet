import SwiftUI

/// Draws a validated SVG logo (see `SVGLogo`) scaled to fit and centered in its frame.
struct WalletLogoView: View {
  let svg: String
  var body: some View {
    if let image = SVGLogo.image(svg) {
      Canvas { context, size in
        let scale = min(size.width / image.width, size.height / image.height)
        let dx = (size.width - image.width * scale) / 2 - image.originX * scale
        let dy = (size.height - image.height * scale) / 2 - image.originY * scale
        for layer in image.layers {
          var path = Path()
          for element in layer.elements {
            switch element {
            case .move(let p): path.move(to: point(p, scale, dx, dy))
            case .line(let p): path.addLine(to: point(p, scale, dx, dy))
            case .quad(let c, let e):
              path.addQuadCurve(to: point(e, scale, dx, dy), control: point(c, scale, dx, dy))
            case .curve(let c1, let c2, let e):
              path.addCurve(
                to: point(e, scale, dx, dy), control1: point(c1, scale, dx, dy),
                control2: point(c2, scale, dx, dy))
            case .close: path.closeSubpath()
            }
          }
          let color = Color(
            red: layer.color.red, green: layer.color.green, blue: layer.color.blue
          ).opacity(layer.opacity)
          context.fill(path, with: .color(color), style: FillStyle(eoFill: layer.evenOdd))
        }
      }
      .accessibilityHidden(true)
    }
  }
  private func point(_ p: SVGPoint, _ scale: Double, _ dx: Double, _ dy: Double) -> CGPoint {
    CGPoint(x: p.x * scale + dx, y: p.y * scale + dy)
  }
}

extension WalletArt {
  /// The accent the stored color stands for, resolved like an account's.
  var accent: WalletAccent { WalletAccent(rawValue: color) ?? .copper }
  /// The disc behind a mark. Logos and lettering are white, so the disc takes the accent's
  /// card shade, which keeps white readable in light and dark appearance alike.
  var fill: Color { accent.cardBright }
}

/// A round mark in the entry's color: its logo when it has one, otherwise `letters`.
private struct WalletArtDisc: View {
  let art: WalletArt
  let letters: String
  let size: CGFloat
  var body: some View {
    ZStack {
      Circle().fill(art.fill)
      if let logo = art.logo {
        WalletLogoView(svg: logo)
      } else {
        Text(letters)
          .font(RoofFont.sign(size * 0.36, relativeTo: .caption))
          .offset(y: SignMetrics.centering(size * 0.36))
          .foregroundStyle(WalletAccent.onCard)
          .minimumScaleFactor(0.5).lineLimit(1)
          .padding(.horizontal, size * 0.12)
      }
      Circle().inset(by: 0.5).stroke(Color.black.opacity(0.12), lineWidth: 1)
    }
    .clipShape(Circle())
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// A token as a coin in the token's color: its logo, or its symbol's first letters.
struct WalletAssetGlyph: View {
  let symbol: String
  let art: WalletArt
  var size: CGFloat = 36
  init(asset: WalletAsset, size: CGFloat = 36) {
    self.init(symbol: asset.symbol, art: asset.art, size: size)
  }
  /// A coin for a token that isn't saved yet (an editor's preview).
  init(symbol: String, art: WalletArt, size: CGFloat = 36) {
    self.symbol = symbol
    self.art = art
    self.size = size
  }
  var body: some View {
    WalletArtDisc(
      art: art, letters: String(symbol.prefix(symbol.count > 4 ? 2 : 3)).uppercased(),
      size: size)
  }

  /// The coin as an image, for places that draw only images (option rows, menu items).
  @MainActor static func image(asset: WalletAsset, size: CGFloat = 26) -> Image {
    let art = asset.art
    let key = "\(asset.id)|\(asset.symbol)|\(size)|\(art.color)|\(art.logo?.hashValue ?? 0)"
    if let image = images[key] { return image }
    let renderer = ImageRenderer(content: WalletAssetGlyph(asset: asset, size: size))
    renderer.scale = 3
    guard let cgImage = renderer.cgImage else { return Image(systemName: "circle.fill") }
    let image = Image(decorative: cgImage, scale: renderer.scale)
    images[key] = image
    return image
  }
  @MainActor private static var images: [String: Image] = [:]
}

/// A network's mark: a disc in the network's color with its logo or initial.
struct WalletNetworkGlyph: View {
  let name: String
  let art: WalletArt
  var size: CGFloat = 18
  init(name: String, art: WalletArt, size: CGFloat = 18) {
    self.name = name
    self.art = art
    self.size = size
  }
  /// The mark of `chain` as the wallet's settings configure it.
  init(_ state: WalletSnapshot, chain: ChainID, size: CGFloat = 18) {
    self.init(name: state.networkName(chain), art: state.networkArt(chain), size: size)
  }
  var body: some View {
    ZStack {
      Circle().fill(art.fill)
      if let logo = art.logo {
        WalletLogoView(svg: logo)
      } else {
        Text(name.first.map { String($0).uppercased() } ?? "?")
          .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
          .foregroundStyle(WalletAccent.onCard)
      }
    }
    .clipShape(Circle())
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  /// The mark as an image, for places that draw only images (menu items).
  @MainActor static func image(
    chain: ChainID, name: String, art: WalletArt, size: CGFloat = 18
  ) -> Image {
    let key = "\(chain)|\(name)|\(size)|\(art.color)|\(art.logo?.hashValue ?? 0)"
    if let image = images[key] { return image }
    let renderer = ImageRenderer(content: WalletNetworkGlyph(name: name, art: art, size: size))
    renderer.scale = 3
    guard let cgImage = renderer.cgImage else { return Image(systemName: "circle.fill") }
    let image = Image(decorative: cgImage, scale: renderer.scale)
    images[key] = image
    return image
  }
  @MainActor private static var images: [String: Image] = [:]
}

/// A detail line with a label, then a network's mark and name at the trailing side.
struct WalletNetworkRow: View {
  let label: String
  let state: WalletSnapshot
  let chain: ChainID
  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(label).font(.subheadline).foregroundStyle(WalletTheme.muted)
      Spacer(minLength: 8)
      WalletNetworkGlyph(state, chain: chain, size: 18)
      Text(state.networkName(chain)).font(.callout).lineLimit(1)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}
