import Foundation

enum DeviceUnlockPolicy: String, Codable, Sendable, CaseIterable {
  /// Face ID / Touch ID / Optic ID only. Invalidated when enrollment changes.
  case biometrics
  /// Biometrics or the device passcode / Mac login password, entered in system UI.
  case devicePasscode
}

/// Inactivity before the wallet locks itself, in minutes. A preference of this device,
/// like its appearance. Sleep and device lock always lock at once.
enum WalletAutoLock: Int, CaseIterable, Identifiable {
  case one = 1
  case five = 5
  case fifteen = 15
  case thirty = 30
  case hour = 60
  static let standard = WalletAutoLock.five
  /// The stored choice. The standard one when none, or an unknown one, is stored.
  static var current: WalletAutoLock {
    WalletAutoLock(
      rawValue: UserDefaults.standard.integer(forKey: WalletStorageKey.autoLock.rawValue))
      ?? standard
  }
  var id: Int { rawValue }
  var seconds: TimeInterval { TimeInterval(rawValue * 60) }
  var title: String {
    self == .hour ? "1 hour" : rawValue == 1 ? "1 minute" : "\(rawValue) minutes"
  }
}

/// A failure whose message is specific and safe to show. Never contains secrets.
struct WalletUserError: Error, Sendable {
  let message: String
  /// Set when the failure showed that this device's API access was revoked
  /// (connection id), so the app can offer Reconnect and Disconnect for it.
  var revokedConnection: String? = nil
  /// Set when a send asked for more than the account can send: the most it can.
  var limit: SendLimit? = nil
  init(_ message: String, revokedConnection: String? = nil, limit: SendLimit? = nil) {
    self.message = message
    self.revokedConnection = revokedConnection
    self.limit = limit
  }
}
