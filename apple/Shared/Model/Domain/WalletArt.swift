import Foundation

/// How a network or token is told apart at a glance: a color and an optional logo. Both
/// are stored on the entry itself, seeded from the defaults the core supplies (see
/// `LocalSettings.init(defaults:)`), so drawing never looks anything up.
struct WalletArt: Equatable, Sendable {
  /// A preset name or `#RRGGBB`, the value an account's accent takes (`AccountAccent`).
  var color: String
  /// SVG source that passed `SVGLogo`, or nil for none.
  var logo: String?

  /// Whether the color is an accent value and the logo, if any, passes `SVGLogo`.
  var isValid: Bool { AccountAccent.isValid(color) && (logo.map(SVGLogo.isValid) ?? true) }

  /// A mark whose network is no longer configured.
  static let neutral = WalletArt(color: AccountAccent.neutral, logo: nil)
}

extension WalletNetwork {
  var art: WalletArt { WalletArt(color: color, logo: logo) }
}

extension WalletAsset {
  var art: WalletArt { WalletArt(color: color, logo: logo) }
}

/// A color and logo as edited, before they are checked and stored.
struct WalletLook: Equatable, Sendable {
  var color: String
  var logo: String?

  /// The stored fields for an edited look, or the reason it is refused. A color must be a
  /// preset name or `#RRGGBB`. A logo must be valid SVG within the size limit, and blank
  /// text means no logo.
  func validated() throws -> WalletLook {
    let value = color.trimmingCharacters(in: .whitespacesAndNewlines)
    guard AccountAccent.isValid(value) else { throw WalletUserError("Pick a color.") }
    let text = logo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !text.isEmpty {
      do { _ = try SVGLogo.parse(text) } catch {
        throw WalletUserError((error as? SVGLogoError)?.errorDescription ?? "Invalid logo.")
      }
    }
    return WalletLook(
      color: value.hasPrefix("#") ? value.uppercased() : value, logo: text.isEmpty ? nil : text)
  }
}
