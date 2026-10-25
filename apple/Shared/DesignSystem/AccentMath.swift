import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Contrast math for custom accents (sRGB channels 0...1, WCAG relative luminance).
enum AccentMath {
  typealias RGB = (Double, Double, Double)
  static let white: RGB = (1, 1, 1)
  static let black: RGB = (0, 0, 0)
  /// The text drawn on accents in dark appearance.
  static let darkText: RGB = (0.06, 0.07, 0.09)
  /// The contrast the derived shades aim for. A little above the 4.5:1 requirement.
  static let target = 4.8

  static func luminance(_ c: RGB) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
  }
  static func contrast(_ a: RGB, _ b: RGB) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
  }
  static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
  }
  /// `c` moved toward `end` in small steps until `ok` holds (or fully there).
  private static func move(_ c: RGB, toward end: RGB, until ok: (RGB) -> Bool) -> RGB {
    for step in 0...50 {
      let candidate = mix(c, end, Double(step) / 50)
      if ok(candidate) { return candidate }
    }
    return end
  }
  /// White seen through the card's highlight and sheen over `c` (12% at most).
  static func lit(_ c: RGB) -> RGB { mix(c, white, 0.12) }

  /// Accent for light appearance (white text on it) and dark (dark text on it), and the
  /// brand mark's sunrise for each.
  static func shades(_ c: RGB) -> (light: RGB, dark: RGB, sunriseLight: RGB, sunriseDark: RGB) {
    let light = move(c, toward: black) { contrast($0, white) >= target }
    let dark = move(c, toward: white) { contrast($0, darkText) >= target }
    return (light, dark, mix(dark, white, 0.08), mix(dark, white, 0.12))
  }
  /// Card gradient ends: white text keeps `target` on the brightest point, highlights
  /// included, and the deep end is the same hue much darker.
  static func card(_ c: RGB) -> (deep: RGB, bright: RGB) {
    let bright = move(c, toward: black) {
      // The quieter text is white at 92%, a little lower than the name and total.
      contrast(lit($0), mix(lit($0), white, 0.92)) >= target
    }
    return (mix(bright, black, 0.5), bright)
  }
}
