import SwiftUI

extension View {
  /// Presents a modal as the system sheet. On iOS it shows the system grabber, is
  /// dismissed by the system's own drag (unless the modal is busy, see `walletModal`),
  /// paints the app's surface behind its content, and is exactly as tall as that
  /// content: `WalletSheet` sets a height detent from its natural height. On macOS it is
  /// the system sheet, sized by its content.
  func walletSheet<Sheet: View>(
    isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Sheet
  ) -> some View {
    sheet(isPresented: isPresented, onDismiss: onDismiss) {
      content().walletSheetSurface()
    }
  }

  /// `walletSheet(isPresented:)` for an optional item.
  func walletSheet<Item: Identifiable, Sheet: View>(
    item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (Item) -> Sheet
  ) -> some View {
    sheet(item: item, onDismiss: onDismiss) { item in
      content(item).walletSheetSurface()
    }
  }

  /// The sheet's height on iOS: `height` is the content's natural height, measured
  /// independently of the space the sheet offers, so it never feeds back on itself. A
  /// height detent excludes the bottom safe area, which the system adds. Until the
  /// content has been measured the sheet starts at medium height. No effect on macOS,
  /// where the sheet takes its content's size.
  @ViewBuilder func walletFittedDetent(_ height: CGFloat) -> some View {
    #if os(iOS)
      presentationDetents(height > 0 ? [.height(height.rounded(.up))] : [.medium])
    #else
      self
    #endif
  }

  /// Every modal's surface, the same in all of them: the sheet's band of sky (with the
  /// moon's night, stars unless Lights out is on) fading into the canvas. On iOS the
  /// presentation paints it, under the grabber too. On macOS the sheet's root view does.
  @ViewBuilder func walletSheetBackdrop() -> some View {
    #if os(macOS)
      background { WalletSheetBackdrop() }
    #else
      self
    #endif
  }

  @ViewBuilder fileprivate func walletSheetSurface() -> some View {
    #if os(iOS)
      presentationDragIndicator(.visible)
        .presentationBackground { WalletSheetBackdrop() }
    #else
      self
    #endif
  }
}

/// The one backdrop every sheet wears, so no modal looks different from another. Its
/// clouds are a faint haze (a third of a page's), so they never compete with the
/// sheet's title and first card.
struct WalletSheetBackdrop: View {
  var body: some View { WalletBackdrop(skyHeight: 150, clouds: 0.35) }
}
