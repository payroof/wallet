import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum WalletAppearance: String, CaseIterable {
  case system, light, dark
  /// Nil follows the operating system.
  var scheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
  var icon: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .light: "sun.max"
    case .dark: "moon.stars"
    }
  }
}
