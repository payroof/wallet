import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Tones always pair a color with an icon so state never depends on color alone.
enum WalletTone {
  case neutral, accent, success, warning, danger
  var color: AnyShapeStyle {
    switch self {
    case .neutral: AnyShapeStyle(WalletTheme.muted)
    case .accent: AnyShapeStyle(WalletTheme.accent)
    case .success: AnyShapeStyle(WalletTheme.success)
    case .warning: AnyShapeStyle(WalletTheme.warning)
    case .danger: AnyShapeStyle(WalletTheme.danger)
    }
  }
  var icon: String {
    switch self {
    case .neutral: "info.circle"
    case .accent: "circle.fill"
    case .success: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .danger: "xmark.octagon.fill"
    }
  }
}
