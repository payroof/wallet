import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// One coherent modal surface: the shared header (`WalletSheetHeader`: icon, title,
/// optional subtitle, Close), scrolling content, and a pinned footer. Its feedback goes to the app's toast, outside the modal, so
/// nothing inside it moves and no space is reserved.
struct WalletSheet<Content: View, Footer: View>: View {
  let title: String
  var subtitle: String = ""
  /// Every sheet has one: it says at a glance what the sheet is about.
  let icon: String
  var closeTitle = "Close"
  var closeDisabled = false
  /// Nil when this modal reports no feedback of its own.
  var status: WalletStatus? = nil
  var dismissStatus: (() -> Void)? = nil
  let close: (() -> Void)?
  let content: Content
  let footer: Footer
  init(
    _ title: String, subtitle: String = "", icon: String, closeTitle: String = "Close",
    closeDisabled: Bool = false, status: WalletStatus? = nil,
    dismissStatus: (() -> Void)? = nil, close: (() -> Void)?,
    @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
  ) {
    self.title = title
    self.subtitle = subtitle
    self.icon = icon
    self.closeTitle = closeTitle
    self.closeDisabled = closeDisabled
    self.status = status
    self.dismissStatus = dismissStatus
    self.close = close
    self.content = content()
    self.footer = footer()
  }
  private var hasFooter: Bool { Footer.self != EmptyView.self }
  /// The natural heights of the header, the scrolling content and the footer: together
  /// the sheet's height on iOS (`walletFittedDetent`).
  @State private var headerHeight: CGFloat = 0
  @State private var contentHeight: CGFloat = 0
  @State private var footerHeight: CGFloat = 0
  var body: some View {
    VStack(spacing: 0) {
      WalletSheetHeader(
        title: title, subtitle: subtitle, icon: icon, closeTitle: closeTitle,
        closeDisabled: closeDisabled,
        // Without a footer Cancel, Escape closes through the header's button.
        cancelShortcut: !hasFooter, close: close
      )
      .overlay(alignment: .bottom) { Divider() }
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        headerHeight = $0
      }
      WalletFittedScroll(fitted: $contentHeight) {
        VStack(alignment: .leading, spacing: 14) { content }
          .padding(.horizontal, 20).padding(.vertical, 16)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if hasFooter {
        // The sheet's own background continues behind its actions.
        footer.padding(.horizontal, 20).padding(.vertical, 12)
          .overlay(alignment: .top) { Divider() }
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: {
            footerHeight = $0
          }
      }
    }
    .walletFittedDetent(
      contentHeight > 0 ? headerHeight + contentHeight + (hasFooter ? footerHeight : 0) : 0
    )
    .walletSheetBackdrop()
    .walletTint().foregroundStyle(WalletTheme.text)
    .walletStatus(status ?? .idle, dismiss: dismissStatus, modal: status != nil)
  }
}

/// A scroll view exactly as tall as its content, up to a cap. Short content leaves
/// no empty band below it. Long content scrolls. Modals built from it therefore
/// size to what they show instead of to a fixed height. `fitted` receives that height
/// (the content's, capped), which does not depend on the space offered.
struct WalletFittedScroll<Content: View>: View {
  var maxHeight: CGFloat = WalletModalSize.maxScroll
  @Binding var fitted: CGFloat
  let content: Content
  @State private var height: CGFloat?
  init(
    maxHeight: CGFloat = WalletModalSize.maxScroll, fitted: Binding<CGFloat> = .constant(0),
    @ViewBuilder content: () -> Content
  ) {
    self.maxHeight = maxHeight
    self._fitted = fitted
    self.content = content()
  }
  var body: some View {
    ScrollView {
      content.onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        height = $0
        fitted = min($0, maxHeight)
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    #if os(iOS)
      // Content height, but it gives way when the sheet has less room than that
      // (e.g. above the keyboard) instead of pushing the header off screen.
      .frame(maxHeight: height.map { min($0, maxHeight) })
    #else
      .frame(height: height.map { min($0, maxHeight) })
    #endif
  }
}

enum WalletModalSize {
  /// The tallest a modal's scrolling region grows before it scrolls.
  @MainActor static var maxScroll: CGFloat {
    #if os(macOS)
      let screen = NSScreen.main?.visibleFrame.height ?? 800
      return max(320, min(640, screen - 260))
    #else
      let screen =
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height ?? 700
      // Room for the header, the footer and the screen's safe areas.
      return max(280, screen - 290)
    #endif
  }
}

/// Fits a sheet to its content: natural height on macOS. On iOS `WalletSheet` sets the
/// sheet's height detent. A busy modal cannot be swiped or clicked away.
private struct WalletModal: ViewModifier {
  let width: CGFloat
  let busy: Bool
  @Environment(\.walletLocked) private var locked
  func body(content: Content) -> some View {
    covered(content)
  }
  /// While a locked wallet closes this sheet, its content is already hidden.
  private func covered(_ content: Content) -> some View {
    sized(content).overlay {
      if locked { WalletTheme.canvas.ignoresSafeArea().accessibilityHidden(true) }
    }
  }
  @ViewBuilder private func sized(_ content: Content) -> some View {
    #if os(macOS)
      content
        .frame(minWidth: min(width, 420), idealWidth: width, maxWidth: width + 160)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(busy)
    #else
      content.interactiveDismissDisabled(busy)
    #endif
  }
}

extension WalletSheet where Footer == EmptyView {
  init(
    _ title: String, subtitle: String = "", icon: String, closeTitle: String = "Close",
    closeDisabled: Bool = false, status: WalletStatus? = nil,
    dismissStatus: (() -> Void)? = nil, close: (() -> Void)?,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      title, subtitle: subtitle, icon: icon, closeTitle: closeTitle, closeDisabled: closeDisabled,
      status: status, dismissStatus: dismissStatus, close: close, content: content
    ) { EmptyView() }
  }
}

/// Standard modal footer: Cancel and the primary action are peers that share the
/// footer width equally and always match in height, on both platforms. Cancel is
/// the quiet bordered button. The primary is the single filled one. An optional
/// leading action (e.g. a destructive Remove) keeps its natural width, set apart.
/// Escape cancels. Return triggers the primary only where the call site opts in
/// (never for signing or approvals).
struct WalletSheetActions<Leading: View, Primary: View>: View {
  var cancelTitle = "Cancel"
  var cancelIcon = "xmark"
  var cancelDisabled = false
  let cancel: () -> Void
  let leading: Leading
  let primary: Primary
  init(
    cancelTitle: String = "Cancel", cancelIcon: String = "xmark", cancelDisabled: Bool = false,
    cancel: @escaping () -> Void, @ViewBuilder leading: () -> Leading,
    @ViewBuilder primary: () -> Primary
  ) {
    self.cancelTitle = cancelTitle
    self.cancelIcon = cancelIcon
    self.cancelDisabled = cancelDisabled
    self.cancel = cancel
    self.leading = leading()
    self.primary = primary()
  }
  var body: some View {
    HStack(spacing: 10) {
      if Leading.self != EmptyView.self {
        // Natural width, set apart from the Cancel/primary pair.
        leading.fixedSize(horizontal: true, vertical: false).padding(.trailing, 6)
      }
      WalletAction(title: cancelTitle, icon: cancelIcon, secondary: true, action: cancel)
        .disabled(cancelDisabled).keyboardShortcut(.cancelAction)
        .frame(maxWidth: .infinity)
      primary.frame(maxWidth: .infinity)
    }
    .environment(\.walletButtonFill, true)
    .fixedSize(horizontal: false, vertical: true)
  }
}

extension WalletSheetActions where Leading == EmptyView {
  init(
    cancelTitle: String = "Cancel", cancelIcon: String = "xmark", cancelDisabled: Bool = false,
    cancel: @escaping () -> Void, @ViewBuilder primary: () -> Primary
  ) {
    self.init(
      cancelTitle: cancelTitle, cancelIcon: cancelIcon, cancelDisabled: cancelDisabled,
      cancel: cancel,
      leading: { EmptyView() }, primary: primary)
  }
}

extension View {
  /// Consistent modal sizing: the width suits the task, the height fits the content.
  func walletModal(width: CGFloat, busy: Bool = false) -> some View {
    modifier(WalletModal(width: width, busy: busy))
  }
}
