import SwiftUI

/// Every text button carries an SF Symbol before its title, so actions read the
/// same everywhere. While `busy`, a spinner takes the icon's place.
struct WalletAction: View {
  let title: String
  let icon: String
  var role: WalletButtonRole = .primary
  var expand = true
  var busy = false
  /// Shown in place of the title while `busy`, e.g. "Signing…". The button that
  /// started an operation reports its progress, so no separate status line is needed.
  var busyTitle: String? = nil
  let action: () -> Void
  init(
    title: String, icon: String, secondary: Bool = false, destructive: Bool = false,
    role: WalletButtonRole? = nil, expand: Bool = true, busy: Bool = false,
    busyTitle: String? = nil, action: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.role = role ?? (destructive ? .destructive : (secondary ? .secondary : .primary))
    self.expand = expand
    self.busy = busy
    self.busyTitle = busyTitle
    self.action = action
  }
  private var shownTitle: String { busy ? (busyTitle ?? title) : title }
  var body: some View {
    Button {
      WalletHaptics.tap()
      action()
    } label: {
      HStack(spacing: 8) {
        if busy {
          WalletSpinner()
        } else {
          Image(systemName: icon).imageScale(.medium).accessibilityHidden(true)
        }
        Text(shownTitle)
      }
    }.buttonStyle(WalletButtonStyle(role: role, expand: expand))
      .accessibilityLabel(shownTitle)
  }
}
