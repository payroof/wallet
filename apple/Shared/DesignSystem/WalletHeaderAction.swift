import SwiftUI

/// An action in the header's trailing corner, opposite the title. On macOS 26 and later,
/// toolbar items follow the leading ones unless a flexible space pushes them to the
/// window's trailing edge.
struct WalletHeaderAction<Content: View>: ToolbarContent {
  @ViewBuilder let content: Content
  var body: some ToolbarContent {
    #if os(macOS)
      if #available(macOS 26, *) {
        ToolbarSpacer(.flexible)
        ToolbarItem { content }
      } else {
        ToolbarItem { content }
      }
    #else
      ToolbarItem(placement: .topBarTrailing) { content }
    #endif
  }
}
