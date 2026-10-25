import SwiftUI

/// Refresh in the header's trailing corner (window title bar on macOS, navigation bar on
/// iOS): a plain toolbar button. While it runs, the system progress indicator takes the icon's
/// place inside the same button, so the button keeps its size.
struct WalletRefreshToolbarItem: ToolbarContent {
  let refreshing: Bool
  let enabled: Bool
  let label: String
  let help: String
  let action: () -> Void
  var body: some ToolbarContent {
    WalletHeaderAction {
      Button {
        guard !refreshing else { return }
        WalletHaptics.tap()
        action()
      } label: {
        Image(systemName: "arrow.clockwise")
          .opacity(refreshing ? 0 : 1)
          .overlay {
            // The roof's turbine vent turns while the account is read.
            if refreshing { WalletSpinner(size: 18).foregroundStyle(WalletTheme.accent) }
          }
      }
      .disabled(!enabled && !refreshing)
      .help(refreshing ? label : help)
      .accessibilityLabel(refreshing ? label : "Refresh")
    }
  }
}
