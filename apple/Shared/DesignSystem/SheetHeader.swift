import SwiftUI

/// The close button of every sheet (and the camera): a small round button with a
/// muted cross that brightens on hover, inside a full 44-point target.
struct WalletCloseButton: View {
  var title = "Close"
  /// Escape closes through it (when no footer Cancel takes that role).
  var cancelShortcut = true
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 13, weight: .bold))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(WalletGlyphButtonStyle())
    .keyboardShortcut(cancelShortcut ? .cancelAction : nil)
    .accessibilityLabel(title).help(title)
  }
}

/// The close button's look: a 30-point disc of the text color at low opacity behind the
/// cross. Hover (macOS) deepens the disc and darkens the cross, pressed shrinks it a
/// little, disabled fades it.
private struct WalletGlyphButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    WalletGlyphButtonBody(configuration: configuration)
  }
}

private struct WalletGlyphButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @State private var hovering = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let active = hovering || configuration.isPressed
    configuration.label
      .foregroundStyle(active ? WalletTheme.text : WalletTheme.muted)
      .background {
        Circle().fill(WalletTheme.text.opacity(active ? 0.12 : 0.07))
          .frame(width: 30, height: 30)
      }
      .opacity(isEnabled ? 1 : 0.35)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
      .onHover { hovering = $0 }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: active)
  }
}

/// The one header every sheet has: its icon on the left, the title beside it with an
/// optional subtitle under it (a lone title is centred on the icon, so no line is held
/// empty for a subtitle), and Close in the trailing corner.
struct WalletSheetHeader: View {
  let title: String
  var subtitle = ""
  let icon: String
  var closeTitle = "Close"
  var closeDisabled = false
  var cancelShortcut = true
  let close: (() -> Void)?

  /// Clear of the system sheet's grabber on iOS.
  static var top: CGFloat {
    #if os(iOS)
      18
    #else
      14
    #endif
  }

  var body: some View {
    // Icon, then the title over its one-line description, then Close: all three on one
    // centre line, so a lone title sits level with the icon.
    HStack(alignment: .center, spacing: 14) {
      WalletIconTile(systemName: icon, side: WalletMetrics.tileLarge, style: .emblem)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(RoofFont.sheetTitle).lineLimit(1).truncationMode(.tail)
          .accessibilityAddTraits(.isHeader)
        if !subtitle.isEmpty {
          Text(subtitle).font(.subheadline).foregroundStyle(WalletTheme.muted).lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let close {
        WalletCloseButton(title: closeTitle, cancelShortcut: cancelShortcut, action: close)
          .disabled(closeDisabled)
          // The disc lines up with the content's trailing edge. The target overhangs.
          .padding(.trailing, -7)
      }
    }
    .frame(minHeight: 44)
    .padding(.leading, 20).padding(.trailing, 20)
    .padding(.top, Self.top).padding(.bottom, 12)
  }
}
