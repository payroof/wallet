import SwiftUI

private struct WalletButtonFillKey: EnvironmentKey {
  static let defaultValue = false
}

private struct WalletLockedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Buttons fill the height their row offers, so peers in a footer stay equal
  /// even when one title wraps. Only set inside rows sized by `fixedSize`.
  var walletButtonFill: Bool {
    get { self[WalletButtonFillKey.self] }
    set { self[WalletButtonFillKey.self] = newValue }
  }
  /// True from the moment the wallet locks until its screens are taken down.
  /// Sheets inherit it from the view that presented them.
  var walletLocked: Bool {
    get { self[WalletLockedKey.self] }
    set { self[WalletLockedKey.self] = newValue }
  }
}

private struct WalletDismissOnLock: ViewModifier {
  @Environment(\.walletLocked) private var locked
  let action: () -> Void
  func body(content: Content) -> some View {
    content.onChange(of: locked) { _, now in if now { action() } }
  }
}

extension View {
  /// Closes this view's sheet, popover or alert when the wallet locks. Locking
  /// first closes every presentation, then removes the unlocked screens, so no
  /// sheet or alert is ever left attached to a view that no longer exists.
  func walletDismissOnLock(_ action: @escaping () -> Void) -> some View {
    modifier(WalletDismissOnLock(action: action))
  }
}

private struct WalletBackdropProvidedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// The screen's container already paints the sky behind this page (the app's tabs and
  /// the Mac's detail column do, once, so switching pages never shows a bare canvas
  /// first). Pages then add none of their own. Sheets always paint theirs.
  var walletBackdropProvided: Bool {
    get { self[WalletBackdropProvidedKey.self] }
    set { self[WalletBackdropProvidedKey.self] = newValue }
  }
}

private struct WalletPageBackground: ViewModifier {
  @Environment(\.walletBackdropProvided) private var provided
  func body(content: Content) -> some View {
    content.background { if !provided { WalletBackdrop() } }
  }
}

extension View {
  /// A page's sky, unless its container already paints it.
  func walletPageBackground() -> some View { modifier(WalletPageBackground()) }
}
