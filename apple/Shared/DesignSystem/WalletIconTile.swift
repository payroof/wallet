import SwiftUI

/// A symbol (or any icon) centred in a rounded tile. Every tile in the app, from a
/// settings row to a sheet's emblem, is this one view, sized by `WalletMetrics.tile`.
struct WalletIconTile<Icon: View>: View {
  enum Style {
    /// The accent, faintly, behind an accent icon.
    case tinted
    /// A raised card surface, for neutral icons.
    case raised
    /// The card surface warmed by the accent with a faint rim of it, so it reads on the
    /// sky in both appearances without a shadow. A sheet's emblem.
    case emblem
  }
  var side = WalletMetrics.tile
  var style = Style.tinted
  var tint = AnyShapeStyle(WalletTheme.accent)
  let icon: Icon

  init(
    side: CGFloat = WalletMetrics.tile, style: Style = .tinted,
    tint: AnyShapeStyle = AnyShapeStyle(WalletTheme.accent), @ViewBuilder icon: () -> Icon
  ) {
    self.side = side
    self.style = style
    self.tint = tint
    self.icon = icon()
  }

  var body: some View {
    let tile = RoundedRectangle(
      cornerRadius: side * WalletMetrics.tileCorner, style: .continuous)
    icon
      .font(.system(size: side * WalletMetrics.tileSymbol, weight: .semibold))
      .foregroundStyle(tint)
      .frame(width: side, height: side)
      .background {
        switch style {
        case .tinted:
          tile.fill(WalletTheme.accent.opacity(0.11))
        case .raised:
          tile.fill(WalletTheme.raised)
        case .emblem:
          tile.fill(WalletTheme.surface.opacity(0.9))
          tile.fill(WalletTheme.accent.opacity(0.12))
        }
      }
      .overlay {
        if style == .emblem { tile.strokeBorder(WalletTheme.accent.opacity(0.22), lineWidth: 1) }
      }
      .accessibilityHidden(true)
  }
}

extension WalletIconTile where Icon == Image {
  /// An SF Symbol in the hierarchical rendering.
  init(
    systemName: String, side: CGFloat = WalletMetrics.tile, style: Style = .tinted,
    tint: AnyShapeStyle = AnyShapeStyle(WalletTheme.accent)
  ) {
    self.init(side: side, style: style, tint: tint) {
      Image(systemName: systemName).symbolRenderingMode(.hierarchical)
    }
  }
}
