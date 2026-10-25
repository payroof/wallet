import Foundation
import LocalAuthentication
import Security

/// Why a Keychain-backed device unlock did not return the vault key.
enum DeviceUnlockError: Error, Equatable {
  /// No item: never enabled, removed, or invalidated by a biometric enrollment change.
  case missing
  case cancelled
  case failed
  case unavailable
  /// This build may not keep protected Keychain items: it isn't signed for this
  /// device with a provisioning profile (an unsigned local build, for example).
  case unsigned
  var unlockMessage: String {
    switch self {
    case .unsigned: DeviceUnlock.unsignedReason
    case .missing:
      "Device unlock was reset, for example after a biometric change. Unlock with your PIN, then turn it on again in Security."
    case .cancelled: "Device unlock cancelled. Enter your PIN, or try again."
    case .failed: "Device unlock didn't recognize you. Enter your PIN, or try again."
    case .unavailable: "Device unlock isn't available right now. Use your PIN."
    }
  }
  var enableMessage: String {
    switch self {
    case .cancelled: "Device unlock wasn't turned on because the system prompt was cancelled."
    case .failed: "Device unlock wasn't turned on because authentication failed."
    case .unsigned: DeviceUnlock.unsignedReason
    case .missing, .unavailable:
      "Device unlock isn't available on this device. Your PIN still works."
    }
  }
}

/// What the operating system can offer. Only these methods are shown.
struct DeviceUnlockCapability: Equatable {
  enum Biometry: Equatable { case none, touchID, faceID, opticID }
  var biometry: Biometry
  /// Biometrics enrolled and usable now.
  var biometricsReady: Bool
  /// A device passcode or login password is set, so system authentication can fall back to it.
  var passcodeReady: Bool
  /// Why biometrics are not ready, when the hardware exists.
  var biometryIssue: String?
  /// This build may keep protected Keychain items, which device unlock needs.
  var keychainReady = true

  var biometryName: String {
    switch biometry {
    case .touchID: "Touch ID"
    case .faceID: "Face ID"
    case .opticID: "Optic ID"
    case .none: "Biometrics"
    }
  }
  var biometryIcon: String {
    switch biometry {
    case .touchID: "touchid"
    case .faceID: "faceid"
    case .opticID: "opticid"
    case .none: "lock.shield"
    }
  }
  var passcodeName: String {
    #if os(macOS)
      "Mac login password"
    #else
      "device passcode"
    #endif
  }
  var capitalizedPasscodeName: String {
    passcodeName.prefix(1).uppercased() + passcodeName.dropFirst()
  }
  func available(_ policy: DeviceUnlockPolicy) -> Bool {
    guard keychainReady else { return false }
    return switch policy {
    case .biometrics: biometricsReady
    case .devicePasscode: passcodeReady
    }
  }
  func title(_ policy: DeviceUnlockPolicy) -> String {
    switch policy {
    case .biometrics: biometryName
    case .devicePasscode:
      biometricsReady ? "\(biometryName) or \(passcodeName)" : capitalizedPasscodeName
    }
  }
  func detail(_ policy: DeviceUnlockPolicy) -> String {
    switch policy {
    case .biometrics:
      "Turns off if enrolled fingerprints or faces change"
    case .devicePasscode:
      "Checked by the system. Payroof never sees it"
    }
  }
  /// The method used for the unlock button label.
  func unlockTitle(_ policy: DeviceUnlockPolicy) -> String {
    switch policy {
    case .biometrics: "Unlock with \(biometryName)"
    case .devicePasscode:
      biometricsReady ? "Unlock with \(biometryName)" : "Unlock with \(passcodeName)"
    }
  }
  func icon(_ policy: DeviceUnlockPolicy) -> String {
    policy == .biometrics || biometricsReady ? biometryIcon : "lock.shield"
  }
}

struct DeviceUnlock {
  static let service = "top.payroof.wallet.device-unlock"
  static let unsignedReason =
    "Touch ID and the login password need a build signed for this Mac. This build isn't, so use your PIN."

  /// Whether this build carries the application identifier the data protection
  /// Keychain requires. Unsigned and ad hoc builds don't, and every Keychain call
  /// with access control fails for them. iOS builds that run are always provisioned.
  static var keychainReady: Bool {
    #if os(macOS)
      guard let task = SecTaskCreateFromSelf(nil) else { return false }
      return SecTaskCopyValueForEntitlement(
        task, "com.apple.application-identifier" as CFString, nil) != nil
    #else
      true
    #endif
  }

  static func capability() -> DeviceUnlockCapability {
    let context = LAContext()
    var error: NSError?
    let biometrics = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &error)
    let biometryError = error
    let biometry: DeviceUnlockCapability.Biometry =
      switch context.biometryType {
      case .touchID: .touchID
      case .faceID: .faceID
      case .opticID: .opticID
      default: .none
      }
    var issue: String?
    if !biometrics, biometry != .none,
      let code = biometryError.map({ LAError.Code(rawValue: $0.code) })
    {
      switch code {
      case .biometryNotEnrolled: issue = "No fingerprint or face is enrolled in system settings."
      case .biometryLockout:
        issue = "Biometrics are locked after failed attempts. Unlock the device first."
      default: issue = "Biometrics aren't available right now."
      }
    }
    let passcode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    return DeviceUnlockCapability(
      biometry: biometry, biometricsReady: biometrics, passcodeReady: passcode,
      biometryIssue: issue, keychainReady: keychainReady)
  }

  private static func base(_ account: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    #if os(macOS)
      // Access-control (biometry/user presence) items require the data protection keychain.
      query[kSecUseDataProtectionKeychain as String] = true
    #endif
    return query
  }

  /// Stores the vault data key behind an OS-enforced access control. The OS password,
  /// passcode and biometrics are never seen or stored by Payroof.
  static func store(_ key: Data, account: String, policy: DeviceUnlockPolicy) throws {
    guard key.count == 32 else { throw CocoaError(.coderInvalidValue) }
    let flags: SecAccessControlCreateFlags =
      policy == .biometrics ? .biometryCurrentSet : .userPresence
    guard
      let acl = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, flags, nil)
    else { throw DeviceUnlockError.unavailable }
    delete(account: account)
    var add = base(account)
    add[kSecAttrAccessControl as String] = acl
    add[kSecValueData as String] = key
    switch SecItemAdd(add as CFDictionary, nil) {
    case errSecSuccess: return
    case errSecMissingEntitlement: throw DeviceUnlockError.unsigned
    default: throw DeviceUnlockError.unavailable
    }
  }

  static func read(account: String, reason: String) throws -> Data {
    let context = LAContext()
    context.localizedReason = reason
    var query = base(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data, data.count == 32 else { throw DeviceUnlockError.failed }
      return data
    case errSecItemNotFound: throw DeviceUnlockError.missing
    case errSecUserCanceled: throw DeviceUnlockError.cancelled
    case errSecAuthFailed: throw DeviceUnlockError.failed
    case errSecMissingEntitlement: throw DeviceUnlockError.unsigned
    default: throw DeviceUnlockError.unavailable
    }
  }

  static func delete(account: String) {
    SecItemDelete(base(account) as CFDictionary)
  }
}
