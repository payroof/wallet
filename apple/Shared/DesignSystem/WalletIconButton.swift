import SwiftUI

/// Icon-only buttons are reserved for universally familiar actions (copy,
/// refresh, close, scan, show/hide). The title is the tooltip and VoiceOver label.
/// `quiet` drops the raised background for a bare icon in `tint`, for actions that sit
/// in a header or beside a row.
struct WalletIconButton: View {
  let title: String
  let icon: String
  /// A spinner takes the icon's place. The button keeps its size.
  var busy = false
  var quiet = false
  var tint = AnyShapeStyle(WalletTheme.accent)
  /// Drawn in the danger color (Delete), on the same round plate as the others.
  var destructive = false
  let action: () -> Void
  init(
    title: String, icon: String, busy: Bool = false, quiet: Bool = false,
    tint: AnyShapeStyle = AnyShapeStyle(WalletTheme.accent), destructive: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.busy = busy
    self.quiet = quiet
    self.tint = tint
    self.destructive = destructive
    self.action = action
  }
  private var foreground: AnyShapeStyle {
    if destructive { return AnyShapeStyle(WalletTheme.danger) }
    return quiet ? tint : AnyShapeStyle(WalletTheme.text)
  }
  var body: some View {
    Button {
      WalletHaptics.tap()
      action()
    } label: {
      ZStack {
        if busy { WalletSpinner(size: 16) }
        Image(systemName: icon).font(.body.weight(.medium)).opacity(busy ? 0 : 1)
      }
      .frame(width: WalletMetrics.control, height: WalletMetrics.control)
      .background(quiet ? Color.clear : WalletTheme.raised, in: Circle())
      .overlay {
        if !quiet { Circle().strokeBorder(WalletTheme.border.opacity(0.7)) }
      }
      .foregroundStyle(foreground)
      .contentShape(Circle())
    }
    .buttonStyle(WalletRowButtonStyle(radius: WalletMetrics.control / 2))
    .accessibilityLabel(title).help(title)
  }
}
