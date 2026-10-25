import SwiftUI

/// Turns a "copied" flag back off after a moment, so a Copy control can say "Copied" and
/// then return to itself. Used by every copy control in the app.
private struct WalletCopyFeedback: ViewModifier {
  @Binding var copied: Bool
  var duration: Duration
  func body(content: Content) -> some View {
    content.task(id: copied) {
      guard copied else { return }
      try? await Task.sleep(for: duration)
      if !Task.isCancelled { copied = false }
    }
  }
}

extension View {
  func walletCopyFeedback(_ copied: Binding<Bool>, for duration: Duration = .seconds(2))
    -> some View
  {
    modifier(WalletCopyFeedback(copied: copied, duration: duration))
  }
}
