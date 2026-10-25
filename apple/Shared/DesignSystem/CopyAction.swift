import SwiftUI

/// The labeled form of the app's one copy action: it copies, says "Copied" with a check
/// for a moment, and tells VoiceOver. `WalletCopyButton` is its icon twin.
struct WalletCopyAction: View {
  let title: String
  let value: String
  var role: WalletButtonRole = .primary
  var expand = true
  var source = WalletCopySource.publicValue
  /// Replaces the source's VoiceOver announcement.
  var announcement: String? = nil
  /// Runs after the copy, e.g. to show a note.
  var onCopy: (() -> Void)? = nil
  @State private var copied = false
  var body: some View {
    WalletAction(
      title: copied ? "Copied" : title, icon: copied ? "checkmark" : "doc.on.doc", role: role,
      expand: expand
    ) {
      source.copy(value, announcement: announcement)
      copied = true
      onCopy?()
    }
    .walletCopyFeedback($copied)
  }
}
