import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// A shade of the environment's accent, resolved where it is drawn.
struct WalletAccentStyle: ShapeStyle {
  let shade: KeyPath<WalletAccent, Color> & Sendable
  init(_ shade: KeyPath<WalletAccent, Color> & Sendable) { self.shade = shade }
  func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
    environment.walletAccent[keyPath: shade]
  }
}
