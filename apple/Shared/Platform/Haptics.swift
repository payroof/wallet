import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// A light tap felt when an action button is pressed (iPhone only). It is a device
/// preference, on unless turned off in Settings, and works while locked.
enum WalletHaptics {
  /// On unless turned off in Settings.
  private static var enabled: Bool {
    UserDefaults.standard.object(forKey: WalletStorageKey.haptics.rawValue) as? Bool ?? true
  }
  /// Whether this device can play haptics. Elsewhere the setting is not shown.
  @MainActor static var available: Bool {
    #if os(iOS)
      UIDevice.current.userInterfaceIdiom == .phone
    #else
      false
    #endif
  }
  @MainActor static func tap() {
    #if os(iOS)
      guard enabled else { return }
      generator.impactOccurred()
    #endif
  }
  /// Success or warning, e.g. a QR code read or rejected.
  @MainActor static func notify(success: Bool) {
    #if os(iOS)
      guard enabled else { return }
      notifier.notificationOccurred(success ? .success : .warning)
    #endif
  }
  #if os(iOS)
    @MainActor private static let generator = UIImpactFeedbackGenerator(style: .light)
    @MainActor private static let notifier = UINotificationFeedbackGenerator()
  #endif
}
