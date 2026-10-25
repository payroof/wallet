import SwiftUI

/// What a screen is about (the network to send on, the address to receive at), set as
/// its title with a chevron: it opens a sheet. On macOS it leads the window's
/// header. On iOS it is the navigation bar's centred title, which is always shown in
/// full (leading items may be folded into an overflow menu). It sits on the bar itself,
/// without the glass capsule and hover highlight of toolbar buttons, so it reads as a
/// title. Actions keep the trailing corner.
struct WalletHeaderTitle<Content: View>: ToolbarContent {
  @ViewBuilder let content: Content
  #if os(macOS)
    private let placement = ToolbarItemPlacement.navigation
  #else
    private let placement = ToolbarItemPlacement.principal
  #endif
  var body: some ToolbarContent {
    if #available(iOS 26, macOS 26, *) {
      ToolbarItem(placement: placement) { content.fixedSize() }
        .sharedBackgroundVisibility(.hidden)
    } else {
      ToolbarItem(placement: placement) { content.fixedSize() }
    }
  }
}
