import SwiftUI

#if os(macOS)
  /// The Mac's sidebar: the mark, the destinations, and below them, always in the same
  /// place, the display options (appearance and Lights out), then the configuration
  /// pages and Lock, each a row of round icons whose names are their tooltips.
  struct WalletSidebar: View {
    @Binding var section: WalletSection
    @Binding var appearance: String
    let lock: () -> Void
    @LightsOut private var lightsOut
    var body: some View {
      List(selection: $section) {
        ForEach(WalletSection.destinations) { item in
          SidebarRow(item: item, selected: section == item).tag(item)
        }
      }
      .listStyle(.sidebar)
      .safeAreaInset(edge: .top, spacing: 0) {
        HStack(spacing: 10) {
          PayroofMark(size: 30)
          PayroofWordmark(size: 15)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: 8) {
          iconRow { display }
          iconRow { configuration }
        }
        .padding(10)
      }
    }

    /// System, Light, Dark and Lights out: one look, the chosen ones in the accent.
    @ViewBuilder private var display: some View {
      ForEach(WalletAppearance.allCases, id: \.self) { option in
        let title = option.rawValue.capitalized
        Button {
          appearance = option.rawValue
        } label: {
          Image(systemName: option.icon)
        }
        .buttonStyle(SidebarIconStyle(on: appearance == option.rawValue))
        .help("Appearance: \(title)")
        .accessibilityLabel("Appearance: \(title)")
        .accessibilityAddTraits(appearance == option.rawValue ? .isSelected : [])
      }
      Button {
        lightsOut.toggle()
      } label: {
        Image(systemName: lightsOut ? "lightbulb.slash" : "lightbulb")
      }
      .buttonStyle(SidebarIconStyle(on: lightsOut))
      .help("Lights out: no stars, window lights or sign bulbs at night")
      .accessibilityLabel("Lights out")
      .accessibilityValue(lightsOut ? "On" : "Off")
      .accessibilityAddTraits(.isToggle)
    }

    /// The configuration pages, then Lock, which never navigates.
    @ViewBuilder private var configuration: some View {
      ForEach(WalletSection.configuration) { item in
        Button {
          section = item
        } label: {
          RoofIcon(item.glyph, size: 19, weight: 1.6)
        }
        .buttonStyle(SidebarIconStyle(on: section == item, plate: true))
        .help(item.rawValue).accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(section == item ? .isSelected : [])
      }
      Button(action: lock) {
        RoofIcon(.lock, size: 19, weight: 1.6)
      }
      .buttonStyle(SidebarIconStyle(on: false))
      .keyboardShortcut("l", modifiers: [.command, .shift])
      .help("Lock now (⇧⌘L)").accessibilityLabel("Lock wallet")
    }

    /// Icons spread evenly across the sidebar's width.
    private func iconRow(@ViewBuilder _ content: () -> some View) -> some View {
      HStack(spacing: 0) {
        Group(subviews: content()) { icons in
          ForEach(icons) { icon in
            icon
            if icon.id != icons.last?.id { Spacer(minLength: 0) }
          }
        }
      }
    }
  }

  /// A destination in the sidebar's list. The system draws the selection. Hovering any
  /// other row lays a soft wash over its full width, as the footer's icons do, so the
  /// pointer always shows what a click would open.
  private struct SidebarRow: View {
    let item: WalletSection
    let selected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
      Label {
        Text(item.rawValue)
      } icon: {
        RoofIcon(item.glyph, size: 18, active: selected || hovering)
          .foregroundStyle(WalletTheme.accent)
      }
      .padding(.vertical, 3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(WalletTheme.text.opacity(hovering && !selected ? 0.07 : 0))
          // Out to the edges of the system's selection highlight.
          .padding(.horizontal, -8).padding(.vertical, -2)
      }
      .onHover { hovering = $0 }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
      .help(item.rawValue)
    }
  }

  /// A round icon control in the sidebar's footer: muted, or in the accent while `on`
  /// (the current page also gets a soft plate behind it). A wash on hover and press.
  private struct SidebarIconStyle: ButtonStyle {
    let on: Bool
    var plate = false
    func makeBody(configuration: Configuration) -> some View {
      SidebarIcon(configuration: configuration, on: on, plate: plate)
    }
  }

  private struct SidebarIcon: View {
    let configuration: ButtonStyleConfiguration
    let on: Bool
    let plate: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.walletAccent) private var accent
    var body: some View {
      configuration.label
        .font(.body)
        .foregroundStyle(on ? accent.accent : WalletTheme.muted)
        .frame(width: WalletMetrics.control, height: WalletMetrics.control)
        .background(fill, in: Circle())
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: on)
    }
    private var fill: Color {
      if configuration.isPressed { return WalletTheme.text.opacity(0.07) }
      if hovering && isEnabled {
        return on ? accent.accent.opacity(plate ? 0.2 : 0.1) : WalletTheme.text.opacity(0.08)
      }
      if on && plate { return accent.accent.opacity(0.14) }
      return .clear
    }
  }
#endif
