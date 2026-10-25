import SwiftUI

/// The icon form of the app's one copy action. The icon turns into a green check for a
/// moment and VoiceOver hears "Copied". `WalletCopyAction` is its labeled twin, and both
/// choose the clipboard through `WalletCopySource`, so every copy looks, sounds and
/// behaves the same.
struct WalletCopyButton: View {
  enum Style {
    /// A bare icon beside a value.
    case inline
    /// A bare icon at the end of a field.
    case field
    /// The round plate of `WalletIconButton`, among other icon actions.
    case plate
  }
  /// What is copied, for the tooltip and VoiceOver: "Copy \(label)".
  let label: String
  let value: String
  var size: CGFloat = 32
  var style = Style.inline
  var source = WalletCopySource.publicValue
  /// Runs after the copy, e.g. to show a note.
  var onCopy: (() -> Void)? = nil
  @State private var copied = false

  private var icon: String { copied ? "checkmark" : "doc.on.doc" }
  private var tint: AnyShapeStyle {
    copied ? AnyShapeStyle(WalletTheme.success) : AnyShapeStyle(WalletTheme.accent)
  }
  private var title: String { copied ? "Copied \(label)" : "Copy \(label)" }
  private func perform() {
    source.copy(value)
    copied = true
    onCopy?()
  }

  var body: some View {
    Group {
      switch style {
      case .inline:
        Button(action: perform) {
          Image(systemName: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("Copy \(label)")
        .accessibilityLabel(title)
      case .field, .plate:
        WalletIconButton(
          title: title, icon: icon, quiet: style == .field, tint: tint, action: perform)
      }
    }
    .onChange(of: value) { _, _ in copied = false }
    .walletCopyFeedback($copied, for: .seconds(1.5))
  }
}
