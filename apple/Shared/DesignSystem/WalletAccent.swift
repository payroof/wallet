import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// An account's accent color: a preset (tuned shades) or a custom `#RRGGBB` (shades
/// derived by `AccentMath`). The current account's drives every accent shade (buttons,
/// selection, links and the brand mark's sunrise). Its card paints its own.
/// Status colors (success, warning, danger) never change, so meaning stays fixed.
/// Light-mode accents keep at least 4.5:1 contrast with white button text, and
/// dark-mode accents with the dark text drawn on them.
struct WalletAccent: Hashable, Identifiable {
  /// A preset name or `#RRGGBB`. The value stored for the account.
  let rawValue: String
  static let copper = WalletAccent(preset: "copper")
  static let presets = AccountAccent.names.map { WalletAccent(preset: $0) }
  var id: String { rawValue }
  private init(preset: String) { rawValue = preset }
  /// Nil unless `rawValue` is a preset name or a strict `#RRGGBB`.
  init?(rawValue: String) {
    guard AccountAccent.isValid(rawValue) else { return nil }
    self.rawValue = rawValue.hasPrefix("#") ? rawValue.uppercased() : rawValue
  }
  var isCustom: Bool { rawValue.hasPrefix("#") }
  /// A random preset that no account uses yet. Any preset once all are taken.
  static func random(avoiding used: some Collection<String>) -> WalletAccent {
    WalletAccent(rawValue: AccountAccent.random(avoiding: used)) ?? .copper
  }
  var title: String { isCustom ? "Custom" : rawValue.capitalized }

  private typealias RGB = AccentMath.RGB
  private var custom: RGB { AccountAccent.rgb(hex: rawValue) ?? (0.64, 0.30, 0.11) }
  private var shades: (accent: (RGB, RGB), sunrise: (RGB, RGB)) {
    switch rawValue {
    case "copper":
      return (((0.64, 0.30, 0.11), (0.96, 0.63, 0.36)), ((0.95, 0.63, 0.36), (0.97, 0.67, 0.40)))
    case "ocean":
      return (((0.11, 0.36, 0.70), (0.52, 0.72, 1.00)), ((0.47, 0.69, 0.98), (0.55, 0.75, 1.00)))
    case "teal":
      return (((0.00, 0.43, 0.45), (0.35, 0.82, 0.80)), ((0.36, 0.80, 0.78), (0.40, 0.84, 0.82)))
    case "indigo":
      return (((0.30, 0.27, 0.72), (0.66, 0.64, 1.00)), ((0.63, 0.61, 0.98), (0.68, 0.66, 1.00)))
    case "violet":
      return (((0.52, 0.20, 0.62), (0.84, 0.62, 0.95)), ((0.80, 0.59, 0.93), (0.85, 0.65, 0.96)))
    case "rose":
      return (((0.72, 0.20, 0.45), (0.98, 0.60, 0.78)), ((0.96, 0.58, 0.76), (0.98, 0.64, 0.80)))
    case "graphite":
      return (((0.25, 0.29, 0.35), (0.78, 0.82, 0.88)), ((0.80, 0.84, 0.90), (0.84, 0.87, 0.92)))
    default:
      let derived = AccentMath.shades(custom)
      return ((derived.light, derived.dark), (derived.sunriseLight, derived.sunriseDark))
    }
  }
  private static func color(_ value: RGB) -> Color {
    Color(.sRGB, red: value.0, green: value.1, blue: value.2)
  }
  var accent: Color { WalletTheme.shade(shades.accent.0, shades.accent.1) }
  var sunrise: Color { WalletTheme.shade(shades.sunrise.0, shades.sunrise.1) }
  var onAccent: Color {
    rawValue == "copper"
      ? WalletTheme.shade((1, 0.98, 0.95), (0.13, 0.08, 0.04))
      : WalletTheme.shade(AccentMath.white, AccentMath.darkText)
  }

  // MARK: Payment card

  /// The card's gradient runs from `cardDeep` to `cardBright` in both appearances.
  /// White text on it keeps at least 4.5:1 against the brightest point, with the
  /// card's highlight and sheen (at most 12% white together) on top.
  private var cardShades: (deep: RGB, bright: RGB) {
    switch rawValue {
    case "copper": return ((0.28, 0.11, 0.04), (0.55, 0.26, 0.08))
    case "ocean": return ((0.04, 0.15, 0.36), (0.10, 0.34, 0.66))
    case "teal": return ((0.02, 0.20, 0.22), (0.02, 0.38, 0.39))
    case "indigo": return ((0.14, 0.12, 0.40), (0.32, 0.29, 0.72))
    case "violet": return ((0.26, 0.08, 0.33), (0.52, 0.22, 0.63))
    case "rose": return ((0.38, 0.06, 0.20), (0.64, 0.16, 0.40))
    case "graphite": return ((0.10, 0.12, 0.16), (0.28, 0.32, 0.39))
    default: return AccentMath.card(custom)
    }
  }
  var cardDeep: Color { Self.color(cardShades.deep) }
  var cardBright: Color { Self.color(cardShades.bright) }
  /// Text on the card: the name and total, and the quieter lines.
  static let onCard = Color.white
  static let onCardMuted = Color.white.opacity(0.92)
}

/// The current account's accent, set once at the root. Copper until then.
private struct WalletAccentKey: EnvironmentKey {
  static let defaultValue = WalletAccent.copper
}

extension EnvironmentValues {
  var walletAccent: WalletAccent {
    get { self[WalletAccentKey.self] }
    set { self[WalletAccentKey.self] = newValue }
  }
}

/// Tints controls (switches, prominent buttons, fields) with the environment's accent.
private struct WalletTint: ViewModifier {
  @Environment(\.walletAccent) private var accent
  func body(content: Content) -> some View { content.tint(accent.accent) }
}

extension View {
  func walletTint() -> some View { modifier(WalletTint()) }
}
