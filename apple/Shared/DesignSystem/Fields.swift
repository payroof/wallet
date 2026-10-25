import SwiftUI

/// A labelled input. Its message line holds the hint, a warning or an error in
/// the same place, so validation replaces text instead of inserting new rows.
/// An optional accessory (e.g. an Add button) sits on the input's own row, so it is
/// aligned with the input itself rather than with the label or the message line.
struct WalletField<Content: View, Accessory: View>: View {
  @FocusState private var focused: Bool
  let label: String
  var hint: String = ""
  var error: String? = nil
  var warning: String? = nil
  /// Marks the input wrong with its border alone, without a message below it.
  var invalid = false
  let content: Content
  let accessory: Accessory
  init(
    _ label: String, hint: String = "", error: String? = nil, warning: String? = nil,
    invalid: Bool = false,
    @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory
  ) {
    self.label = label
    self.hint = hint
    self.error = error
    self.warning = warning
    self.invalid = invalid
    self.content = content()
    self.accessory = accessory()
  }
  @State private var width: CGFloat = 0
  @State private var accessoryWidth: CGFloat = 0
  /// Accessory buttons sit beside the input, and move below it only when beside it
  /// they would leave the input too narrow to read: an icon button always fits on a
  /// phone. Several text buttons may not.
  private var stacksAccessory: Bool {
    Accessory.self != EmptyView.self && width > 0 && width - accessoryWidth - 8 < 180
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).roofStencil(11, tracking: 1.2).foregroundStyle(WalletTheme.muted)
      let layout =
        stacksAccessory
        ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
        : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
      layout {
        content.textFieldStyle(.plain)
          .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: WalletMetrics.field)
          .background(
            WalletTheme.surface,
            in: RoundedRectangle(cornerRadius: WalletMetrics.radius, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: WalletMetrics.radius, style: .continuous).strokeBorder(
              error != nil || invalid
                ? AnyShapeStyle(WalletTheme.danger)
                : (focused ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.border)),
              lineWidth: focused || error != nil || invalid ? 1.5 : 1)
          )
          .focused($focused)
          .frame(maxWidth: .infinity).accessibilityLabel(label)
          .accessibilityHint(error ?? warning ?? (invalid ? "Doesn't match your backup" : hint))
        // No accessory, no gap: the input keeps the full width.
        if Accessory.self != EmptyView.self {
          HStack(spacing: 8) { accessory }.fixedSize()
            .onGeometryChange(for: CGFloat.self) {
              $0.size.width
            } action: {
              accessoryWidth = $0
            }
        }
      }
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        width = $0
      }
      if let error {
        Label(error, systemImage: "exclamationmark.circle.fill").font(.footnote)
          .foregroundStyle(WalletTheme.danger).fixedSize(horizontal: false, vertical: true)
      } else if let warning {
        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.footnote)
          .foregroundStyle(WalletTheme.warning).fixedSize(horizontal: false, vertical: true)
      } else if !hint.isEmpty {
        Text(hint).font(.footnote).foregroundStyle(WalletTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

extension WalletField where Accessory == EmptyView {
  init(
    _ label: String, hint: String = "", error: String? = nil, warning: String? = nil,
    invalid: Bool = false, @ViewBuilder content: () -> Content
  ) {
    self.init(
      label, hint: hint, error: error, warning: warning, invalid: invalid, content: content
    ) {
      EmptyView()
    }
  }
}

/// Inputs that belong together on one row: side by side, top-aligned so labels and
/// inputs line up, when there is room. Stacked on narrow sheets and phones. The
/// layout switches without rebuilding the inputs, so focus and text are kept.
struct WalletFormRow<Content: View>: View {
  var minimumWidth: CGFloat = 360
  let content: Content
  @State private var width: CGFloat = .infinity
  init(minimumWidth: CGFloat = 360, @ViewBuilder content: () -> Content) {
    self.minimumWidth = minimumWidth
    self.content = content()
  }
  var body: some View {
    let layout =
      width >= minimumWidth
      ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
    layout { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        width = $0
      }
  }
}

/// A label above a non-text control (segmented choice, selector) so it lines up
/// with neighbouring `WalletField`s: same label style, same spacing, same height.
struct WalletLabeled<Content: View>: View {
  let label: String
  let content: Content
  init(_ label: String, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).roofStencil(11, tracking: 1.2).foregroundStyle(WalletTheme.muted)
        .accessibilityHidden(true)
      content
    }
  }
}
