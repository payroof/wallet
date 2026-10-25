import SwiftUI

/// One configuration page: a sidebar destination on macOS, a Settings subpage on iOS.
/// Each page owns its own state, sheets and alerts.
struct SettingsPage: View {
  @Environment(WalletModel.self) private var model
  let panel: SettingsPanel
  var body: some View {
    // The page's name is the header's title, so the page itself has no heading. An
    // unconnected account's Project page is one empty state, centred in the screen.
    WalletPage("", subtitle: "", fillsHeight: panel == .project && !model.connected) {
      switch panel {
      case .root: EmptyView()
      case .security: SecuritySettings()
      case .networks: NetworkSettings()
      case .project: ProjectSettings()
      }
    }
  }
}

#if os(iOS)
  /// The Settings tab: display preferences, the configuration pages, Lock and the
  /// version. A page opens in place with a back chevron.
  struct WalletSettings: View {
    @Environment(WalletModel.self) private var model
    @AppStorage(WalletStorageKey.settingsPanel.rawValue) private var panelName = SettingsPanel.root
      .rawValue
    private var panel: SettingsPanel { SettingsPanel(rawValue: panelName) ?? .root }
    @State private var capability = DeviceUnlock.capability()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WalletStorageKey.appearance.rawValue) private var appearance = WalletAppearance
      .system
      .rawValue
    @AppStorage(WalletStorageKey.haptics.rawValue) private var haptics = true
    @LightsOut private var lightsOut
    var body: some View {
      Group {
        if panel == .root {
          WalletPage("", subtitle: "") { settingsList }
        } else {
          SettingsPage(panel: panel)
        }
      }
      .toolbar {
        if panel != .root {
          ToolbarItem(placement: .navigation) {
            Button {
              panelName = SettingsPanel.root.rawValue
            } label: {
              Image(systemName: "chevron.left").fontWeight(.semibold)
            }
            .accessibilityLabel("All settings")
          }
        }
      }
      .navigationTitle(panel.title)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: panel)
    }

    private var settingsList: some View {
      VStack(alignment: .leading, spacing: 20) {
        WalletCard {
          VStack(alignment: .leading, spacing: 18) {
            SkyAppearancePicker(selection: $appearance)
            Toggle(isOn: $lightsOut.animation(reduceMotion ? nil : .easeInOut(duration: 0.3))) {
              VStack(alignment: .leading, spacing: 2) {
                Text("Lights out").font(.callout)
                Text(
                  "At night the stars leave the sky, and the city's windows and the signs' bulbs stay dark."
                )
                .font(.caption).foregroundStyle(WalletTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch).walletTint()
            .onChange(of: lightsOut) { _, _ in WalletHaptics.tap() }
            if WalletHaptics.available {
              Toggle(isOn: $haptics) {
                Text("Haptic feedback").font(.callout)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .toggleStyle(.switch).walletTint()
              .onChange(of: haptics) { _, on in if on { WalletHaptics.tap() } }
            }
          }
        }
        WalletCard(padding: 6) {
          VStack(spacing: 0) {
            panelRow(.security, status: securityStatus)
            panelRow(
              .networks,
              status:
                "\(model.state.connectedNetworks.count) of \(model.state.networks.count) on · \(model.state.assets.count) tokens"
            )
            panelRow(
              .project,
              status: model.connection.map { "\($0.project) · \(ProjectSettings.host($0))" }
                ?? "Not connected")
          }
        }
        WalletAction(title: "Lock", icon: "lock", role: .secondary) { model.lock() }
          .accessibilityHint("Hides your wallet until you unlock it again")
        VStack(spacing: 8) {
          PayroofMark(size: 34)
          Text(version).font(.caption).foregroundStyle(WalletTheme.muted)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity).padding(.top, 6)
      }
    }
    /// "0.1.0 (1)": the app's marketing version and build.
    private var version: String {
      let info = Bundle.main.infoDictionary
      let short = info?["CFBundleShortVersionString"] as? String ?? "?"
      let build = info?["CFBundleVersion"] as? String ?? "?"
      return "Payroof Wallet \(short) (\(build))"
    }
    private var securityStatus: String {
      guard let policy = model.state.settings.deviceUnlock else { return "PIN only" }
      return "PIN · \(capability.title(policy))"
    }
    private func panelRow(_ item: SettingsPanel, status: String) -> some View {
      Button {
        panelName = item.rawValue
      } label: {
        HStack(spacing: 12) {
          WalletIconTile { RoofIcon(item.glyph, size: 20, weight: 1.7) }
          VStack(alignment: .leading, spacing: 1) {
            Text(item.title).font(RoofFont.posterMedium(16, relativeTo: .callout))
            Text(status).font(.caption).foregroundStyle(WalletTheme.muted)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            .foregroundStyle(WalletTheme.muted).accessibilityHidden(true)
        }.padding(.horizontal, 10).frame(minHeight: WalletMetrics.control + 14)
      }.buttonStyle(WalletRowButtonStyle()).accessibilityLabel("\(item.title), \(status)")
    }
  }
#endif

#if os(iOS)
  /// The appearance as three skies to choose from: the system's (half day, half night),
  /// day, and night. Each tile is the app's own sky in that appearance.
  struct SkyAppearancePicker: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
      HStack(spacing: 10) {
        ForEach(WalletAppearance.allCases, id: \.self) { option in
          let selected = selection == option.rawValue
          Button {
            WalletHaptics.tap()
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
              selection = option.rawValue
            }
          } label: {
            VStack(spacing: 6) {
              tile(option)
                .frame(height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                    selected
                      ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.border),
                    lineWidth: selected ? 2.5 : 1)
                )
                .scaleEffect(selected ? 1 : 0.96)
              Text(Self.title(option)).roofStencil(10.5, tracking: 1.2)
                .foregroundStyle(
                  selected ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.muted))
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Self.title(option))
          .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Appearance")
    }

    static func title(_ option: WalletAppearance) -> String {
      switch option {
      case .system: "System"
      case .light: "Day"
      case .dark: "Night"
      }
    }

    @ViewBuilder private func tile(_ option: WalletAppearance) -> some View {
      switch option {
      case .light: sky(.light)
      case .dark: sky(.dark)
      case .system:
        ZStack {
          sky(.light)
          sky(.dark).mask(
            GeometryReader { box in
              Path { p in
                p.move(to: CGPoint(x: box.size.width * 0.62, y: 0))
                p.addLine(to: CGPoint(x: box.size.width, y: 0))
                p.addLine(to: CGPoint(x: box.size.width, y: box.size.height))
                p.addLine(to: CGPoint(x: box.size.width * 0.38, y: box.size.height))
                p.closeSubpath()
              }
            })
        }
      }
    }

    private func sky(_ scheme: ColorScheme) -> some View {
      ZStack(alignment: .bottom) {
        SkyBackdrop(
          animated: false, celestial: false, fadesIntoCanvas: false)
        SkylineView(seed: 3, color: WalletTheme.skylineNear, relief: 0.7, windows: true)
          .frame(height: 26)
        GeometryReader { box in
          Group {
            if scheme == .dark { NightMoon(size: 16) } else { DaySun(size: 18) }
          }
          .position(
            x: box.size.width * (scheme == .dark ? 0.78 : 0.24), y: box.size.height * 0.3)
        }
      }
      .environment(\.colorScheme, scheme)
    }
  }
#endif
