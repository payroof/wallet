import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Payroof's lettering, taken from the street: DIN Condensed is the rooftop sign (the
/// balance, amounts, the PIN), DIN Alternate the stencilled labels painted on parapets
/// and doors, Futura the headlines of the posters below. Body text stays the system
/// font, so reading and Dynamic Type are unchanged. All three faces ship with iOS and
/// macOS. Nothing is bundled. Every size follows Dynamic Type through `relativeTo`.
enum RoofFont {
  /// The sign face's PostScript name, also read by `SignMetrics`.
  static let signName = "DINCondensed-Bold"
  private static let stencil = "DINAlternate-Bold"
  private static let poster = "Futura-Bold"
  private static let posterMedium = "Futura-Medium"

  /// Big sign numerals: totals, amounts, PIN digits. DIN Condensed sits high in its
  /// line box, so lettering beside an icon or in a frame uses `signLettering(_:)`.
  static func sign(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
    .custom(signName, size: size, relativeTo: style)
  }
  /// Uppercase labels with tracking: eyebrows, tab names, plaques.
  static func stencil(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
    .custom(stencil, size: size, relativeTo: style)
  }
  /// Screen and sheet titles.
  static func poster(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
    .custom(poster, size: size, relativeTo: style)
  }
  /// Section headings and emphasized row titles.
  static func posterMedium(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
    .custom(posterMedium, size: size, relativeTo: style)
  }

  static var title: Font { poster(24, relativeTo: .title2) }
  static var sheetTitle: Font { poster(20, relativeTo: .title3) }
  static var heading: Font { posterMedium(17, relativeTo: .headline) }
  static var eyebrow: Font { stencil(11, relativeTo: .caption2) }
  static var label: Font { stencil(13, relativeTo: .footnote) }
}

extension View {
  /// Stencilled uppercase: DIN Alternate with open tracking.
  func roofStencil(_ size: CGFloat = 11, tracking: CGFloat = 1.4) -> some View {
    font(RoofFont.stencil(size)).tracking(tracking).textCase(.uppercase)
  }
}

/// DIN Condensed's capitals and figures fill its ascent, and its descent is deep, so they
/// sit above the centre of their line box. `centering(_:)` is how far to move sign
/// lettering down so its capitals are centred in their frame, next to an icon or in a
/// key. It is worked out from the font's own metrics, not measured by eye.
enum SignMetrics {
  /// The downward offset for sign lettering of `size` points.
  static func centering(_ size: CGFloat) -> CGFloat { size * share }

  /// Half of (descent − ascent + cap height), as a share of the point size.
  private static let share: CGFloat = {
    #if os(macOS)
      let font = NSFont(name: RoofFont.signName, size: 100)
    #else
      let font = UIFont(name: RoofFont.signName, size: 100)
    #endif
    guard let font else { return 0 }
    return (abs(font.descender) - font.ascender + font.capHeight) / 2 / font.pointSize
  }()
}

extension View {
  /// Sign lettering (`RoofFont.sign`) at `size`, optically centred in its frame.
  func signLettering(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle)
    -> some View
  {
    font(RoofFont.sign(size, relativeTo: style)).offset(y: SignMetrics.centering(size))
  }
}
