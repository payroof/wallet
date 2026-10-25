import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Payroof's rooftop palette. Day is sunlit limestone under a pale sky, with ink-navy
/// text. Night is the same roof after dark: deep indigo sky, slate surfaces, warm
/// window light. The two are designed separately, not inverted.
enum WalletTheme {
  private static func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double))
    -> Color
  {
    #if os(macOS)
      Color(
        nsColor: NSColor(name: nil) { appearance in
          let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
          return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    #else
      Color(
        uiColor: UIColor { traits in
          let value = traits.userInterfaceStyle == .dark ? dark : light
          return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    #endif
  }
  private static func adaptiveAlpha(
    _ light: (Double, Double, Double, Double), _ dark: (Double, Double, Double, Double)
  ) -> Color {
    #if os(macOS)
      Color(
        nsColor: NSColor(name: nil) { appearance in
          let v = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
          return NSColor(srgbRed: v.0, green: v.1, blue: v.2, alpha: v.3)
        })
    #else
      Color(
        uiColor: UIColor { traits in
          let v = traits.userInterfaceStyle == .dark ? dark : light
          return UIColor(red: v.0, green: v.1, blue: v.2, alpha: v.3)
        })
    #endif
  }
  /// The chosen accent (copper by default). Interactive and selected states only.
  /// Accent shades are styles resolved against `\.walletAccent` at render time, so a
  /// change of accent recolors the views in place. Nothing is rebuilt.
  static let accent = WalletAccentStyle(\.accent)
  static let onAccent = WalletAccentStyle(\.onAccent)
  static let canvas = adaptive((0.961, 0.941, 0.906), (0.047, 0.063, 0.118))
  static let surface = adaptive((0.996, 0.988, 0.973), (0.086, 0.110, 0.180))
  static let raised = adaptive((0.918, 0.894, 0.851), (0.129, 0.157, 0.235))
  static let text = adaptive((0.106, 0.133, 0.200), (0.949, 0.929, 0.890))
  static let muted = adaptive((0.392, 0.408, 0.451), (0.627, 0.655, 0.737))
  static let border = adaptive((0.851, 0.824, 0.776), (0.173, 0.204, 0.294))
  /// Slate roofing: the tab bar, sign boards by day and the brand mark's panel.
  static let roof = adaptive((0.137, 0.165, 0.239), (0.106, 0.133, 0.208))
  static let roofEdge = adaptive((0.247, 0.278, 0.361), (0.231, 0.267, 0.369))
  static let onRoof = adaptive((0.965, 0.945, 0.910), (0.965, 0.945, 0.910))
  /// The accent's light shade, used for the brand mark's roofline.
  static let sunrise = WalletAccentStyle(\.sunrise)
  static let success = adaptive((0.10, 0.46, 0.30), (0.45, 0.85, 0.62))
  static let danger = adaptive((0.72, 0.16, 0.18), (1.0, 0.52, 0.52))
  static let warning = adaptive((0.55, 0.36, 0.0), (0.98, 0.78, 0.36))
  /// Warm window light: lit PIN windows, sign bulbs, the moon's glow.
  static let lamp = adaptive((0.96, 0.66, 0.20), (1.0, 0.80, 0.42))
  /// Fired brick and the mortar between: recovery words, the parapet.
  static let brick = adaptive((0.64, 0.27, 0.19), (0.50, 0.22, 0.17))
  static let brickDeep = adaptive((0.52, 0.20, 0.14), (0.38, 0.16, 0.13))
  static let mortar = adaptive((0.89, 0.85, 0.79), (0.20, 0.22, 0.30))
  /// The sky behind the roof: zenith, then horizon.
  static let skyTop = adaptive((0.55, 0.74, 0.92), (0.020, 0.031, 0.090))
  static let skyBottom = adaptive((0.99, 0.87, 0.74), (0.165, 0.149, 0.302))
  /// Buildings against the sky, far and near.
  static let skylineFar = adaptive((0.72, 0.74, 0.80), (0.090, 0.106, 0.196))
  static let skylineNear = adaptive((0.47, 0.50, 0.59), (0.059, 0.071, 0.137))
  /// Steel against the sky: sign legs, scaffolding, the crane.
  static let steel = adaptive((0.36, 0.39, 0.47), (0.30, 0.33, 0.45))
  /// Things standing on a roof. By night a shade lighter than the skyline behind them,
  /// so they still read against the dark.
  static let silhouette = adaptive((0.33, 0.36, 0.45), (0.22, 0.24, 0.36))
  /// The iOS tab bar: pale sandstone brick by day, slate at night, and its joints.
  static let barFill = adaptive((0.975, 0.945, 0.9), (0.106, 0.133, 0.208))
  static let barJoints = adaptiveAlpha((0.62, 0.5, 0.4, 0.22), (1, 1, 1, 0.045))
  static func shade(
    _ light: (Double, Double, Double), _ dark: (Double, Double, Double)
  ) -> Color { adaptive(light, dark) }
}
