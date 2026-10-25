import Foundation

/// Every device preference kept in `UserDefaults`, which `@AppStorage` reads too. These
/// are about this device and its screens, never the wallet. Public settings that belong
/// with the wallet live in `LocalSettings`.
enum WalletStorageKey: String {
  /// The Settings page open on iOS.
  case settingsPanel = "wallet.settings.panel"
  /// The Home list's grouping.
  case homeHoldings = "wallet.home.holdings"
  case appearance = "wallet.appearance"
  /// Lights out in the scenery (see `LightsOut`).
  case lightsOut = "wallet.scenery.lightsOut"
  case haptics = "wallet.haptics"
  case autoLock = "wallet.autoLock"
  /// The slot of the account the wallet works on.
  case account = "wallet.account"
}
