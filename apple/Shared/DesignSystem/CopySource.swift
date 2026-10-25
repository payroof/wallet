import SwiftUI

/// Where a copied value goes. Public values (address, hash, URL) use the plain clipboard.
/// Secrets (recovery words, tokens) use the local-only clipboard that clears itself, and
/// must never be routed through the public one.
enum WalletCopySource {
  case publicValue
  case secret

  /// What VoiceOver hears after the copy.
  var announcement: String {
    switch self {
    case .publicValue: "Copied"
    case .secret: "Copied. The clipboard clears in a minute."
    }
  }

  /// Puts `value` on the right clipboard and tells VoiceOver.
  @MainActor func copy(_ value: String, announcement: String? = nil) {
    switch self {
    case .publicValue: PublicClipboard.copy(value)
    case .secret: SecretClipboard.copy(value)
    }
    AccessibilityNotification.Announcement(announcement ?? self.announcement).post()
  }
}
