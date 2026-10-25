import SwiftUI

/// A disclosure section whose whole header row toggles it: title, empty space and
/// chevron alike. Content controls stay outside the header's hit area.
struct WalletDisclosure<Content: View>: View {
  let title: String
  var detail: String = ""
  @Binding var expanded: Bool
  let content: Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  init(
    _ title: String, detail: String = "", expanded: Binding<Bool>,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.detail = detail
    self._expanded = expanded
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { expanded.toggle() }
      } label: {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(WalletTheme.text)
            if !detail.isEmpty {
              Text(detail).font(.caption).foregroundStyle(WalletTheme.muted).lineLimit(1)
            }
          }
          Spacer(minLength: 8)
          Image(systemName: "chevron.right").font(.caption.weight(.bold))
            .foregroundStyle(WalletTheme.muted)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 8).frame(minHeight: WalletMetrics.control + 4)
      }
      .buttonStyle(WalletRowButtonStyle())
      .padding(.horizontal, -8)
      .accessibilityLabel(title)
      .accessibilityValue(expanded ? "Expanded" : "Collapsed")
      .accessibilityHint(expanded ? "Collapses this section" : "Expands this section")
      if expanded {
        content.padding(.top, 8).transition(.opacity)
      }
    }
  }
}

/// What every empty list shows, everywhere: a soft icon badge on top, a short title
/// and an optional line of guidance below, and an optional action. It has no
/// background of its own and is centred horizontally. Give it extra height
/// (`.frame(maxHeight: .infinity)`) and it centres vertically in that space too.
struct WalletEmptyState<Action: View>: View {
  let icon: String
  let title: String
  let detail: String
  let action: Action
  init(icon: String, title: String, detail: String = "", @ViewBuilder action: () -> Action) {
    self.icon = icon
    self.title = title
    self.detail = detail
    self.action = action()
  }
  var body: some View {
    VStack(spacing: 14) {
      // A little house: the icon lives under its own roof.
      // The roof takes the top of the panel, so the icon is centred in the walls below it.
      let pitch: CGFloat = 16
      let height: CGFloat = 70
      ZStack(alignment: .bottom) {
        PitchedPanelShape(pitch: pitch, radius: 14).fill(WalletTheme.accent.opacity(0.09))
        PitchedPanelShape(pitch: pitch, radius: 14)
          .stroke(WalletTheme.accent.opacity(0.28), lineWidth: 1.2)
        Image(systemName: icon).font(.system(size: 24, weight: .medium))
          .symbolRenderingMode(.hierarchical).foregroundStyle(WalletTheme.accent)
          .frame(height: height - pitch)
      }
      .frame(width: 68, height: height)
      .accessibilityHidden(true)
      VStack(spacing: 4) {
        Text(title).font(RoofFont.heading).accessibilityAddTraits(.isHeader)
        if !detail.isEmpty {
          Text(detail).font(.subheadline).foregroundStyle(WalletTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .multilineTextAlignment(.center).frame(maxWidth: 360)
      if Action.self != EmptyView.self { action.padding(.top, 2) }
    }
    .padding(.vertical, 28).padding(.horizontal, 12)
    .frame(maxWidth: .infinity)
  }
}

extension WalletEmptyState where Action == EmptyView {
  init(icon: String, title: String, detail: String = "") {
    self.init(icon: icon, title: title, detail: detail) { EmptyView() }
  }
}

/// Label/value row for reviews and details. Public values can be copied.
///
/// Every row in a card reads the same way: the label on the left, the value (and its
/// copy button) on the right edge, like the network and hex rows beside it. A hex value
/// stays on that line, cut in the middle. Prose that can't fit on one line goes under
/// its label instead of squeezing.
struct WalletDetailRow: View {
  let label: String
  let value: String
  var monospaced = false
  var copyable = false
  var emphasis = false
  var body: some View {
    HStack(spacing: 6) {
      if monospaced {
        inline
      } else {
        ViewThatFits(in: .horizontal) {
          inline
          stacked
        }
      }
      if copyable { WalletCopyButton(label: label, value: value, size: 28) }
    }
    .accessibilityElement(children: .contain)
  }

  private var labelText: some View {
    Text(label).font(.subheadline).foregroundStyle(WalletTheme.muted)
  }

  private var valueText: Text {
    Text(value)
      .font(
        monospaced
          ? .system(.callout, design: .monospaced).weight(emphasis ? .semibold : .regular)
          : .callout.weight(emphasis ? .semibold : .regular)
      )
  }

  private var inline: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      labelText.lineLimit(1).fixedSize()
      Spacer(minLength: 8)
      valueText
        .textSelection(.enabled)
        // A hex value (address, hash) stays on one line: shrunk a little, then cut in
        // the middle, never broken across lines. Copy and hover give it in full.
        .modifier(DetailValueLines(singleLine: monospaced, full: value))
        .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 6)
  }

  private var stacked: some View {
    VStack(alignment: .leading, spacing: 2) {
      labelText
      valueText
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 6)
  }
}

/// How a detail row's value takes its lines on the shared line: a hex value is cut in
/// the middle, prose keeps its one line (or the row stacks).
private struct DetailValueLines: ViewModifier {
  let singleLine: Bool
  let full: String
  func body(content: Content) -> some View {
    if singleLine {
      content.lineLimit(1).minimumScaleFactor(0.7).truncationMode(.middle).help(full)
    } else {
      content.lineLimit(1).fixedSize()
    }
  }
}

/// A copyable public value (address, hash, origin, contract).
struct PublicValue: View {
  let label: String
  let value: String
  var body: some View {
    WalletDetailRow(label: label, value: value, monospaced: true, copyable: true)
  }
}
