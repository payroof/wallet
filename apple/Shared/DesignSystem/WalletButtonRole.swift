import SwiftUI

enum WalletButtonRole {
  /// One per view: the action the screen exists for.
  case primary
  case secondary
  /// Low-emphasis text action (navigation, "View all", alternatives).
  case tertiary
  case destructive
}
