import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum WalletMetrics {
  static let radiusSmall: CGFloat = 10
  static let radius: CGFloat = 16
  static let radiusLarge: CGFloat = 24
  /// Icon tiles: a row's icon, and a sheet's emblem. Corner and symbol are shares of the side.
  static let tile: CGFloat = 36
  static let tileLarge: CGFloat = 40
  static let tileCorner: CGFloat = 0.3
  static let tileSymbol: CGFloat = 0.46
  #if os(macOS)
    /// Desktop controls stay compact. Pointer precision does not need 44pt targets.
    /// Fields and buttons share one height so inputs and actions on a row line up.
    static let control: CGFloat = 32
    static let field: CGFloat = 32
    static let chip: CGFloat = 32
    static let page: CGFloat = 28
  #else
    static let control: CGFloat = 50
    static let field: CGFloat = 48
    static let chip: CGFloat = 44
    static let page: CGFloat = 18
  #endif
}
