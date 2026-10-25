import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// The app's few shapes, so every control of a kind has the same corners: actions and
/// chips are capsules (`Capsule`), icon actions circles (`Circle`), inputs and cards
/// these continuous rounded rectangles.
enum WalletShape {
  /// Text fields, selectors, search, cards and panels.
  static var field: RoundedRectangle {
    RoundedRectangle(cornerRadius: WalletMetrics.radius, style: .continuous)
  }
  /// Small tiles inside cards: QR plates, flow nodes, option rows.
  static var tile: RoundedRectangle {
    RoundedRectangle(cornerRadius: WalletMetrics.radiusSmall, style: .continuous)
  }
}
