import SwiftUI

/// The rooftop. Above the parapet, the sky (tonight's moon, or the sun and clouds by
/// day) over a far skyline, and the accounts as buildings, each with its rooftop sign:
/// the USD total. Tapping the current sign turns it round to its total over time. Below
/// the parapet, inside the building: Send and Receive, what the account holds (by token
/// or network. Where a token is held is one more tap) and its latest activity on the
/// fire stairs.
struct WalletHome: View {
  @Environment(WalletModel.self) private var model
  let navigate: (WalletSection) -> Void
  let openNetworks: () -> Void
  let editAccount: (UInt32) -> Void
  let createAccount: () -> Void
  /// A new account with a chosen name, color or slot (the old sheet).
  let createCustomAccount: () -> Void
  /// An antenna's project action.
  let openProject: (UInt32) -> Void
  /// The token group whose holdings are shown.
  @State private var detailGroup: String?
  @State private var viewport: CGFloat = 0
  @State private var heroHeight: CGFloat = 0
  @State private var detailItem: ActivityItem?
  @Environment(\.colorScheme) private var scheme
  private var account: ProjectCard? { model.currentAccount }
  private var holdings: [AssetHolding] { WalletPortfolio.holdings(model.state, account: account) }
  private var groups: [HoldingGroup] { WalletPortfolio.groups(holdings) }
  /// This account's sent and found activity, newest first.
  private var recent: [ActivityItem] { model.state.activity(slot: model.account) }
  private var pending: Int {
    recent.filter {
      if case .sent(let t) = $0 { t.status == "pending" } else { false }
    }.count
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        hero
        VStack(spacing: 24) {
          actions
          if !groups.isEmpty {
            HomeHoldings(groups: groups) { detailGroup = $0.id }
          }
          activity
        }
        .padding(.horizontal, WalletMetrics.page).padding(.top, 22).padding(.bottom, 16)
        // At least the rest of the screen tall, so an empty activity state sits centred
        // in the space below the roof rather than pressed against it.
        .frame(minHeight: max(0, viewport - heroHeight), alignment: .top)
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
        .background(alignment: .top) { facade }
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      viewport = $0
    }
    .background(WalletTheme.canvas)
    #if os(iOS)
      .refreshable { refresh() }
      .toolbarBackground(.hidden, for: .navigationBar)
    #endif
    // In the window's title bar (macOS) or navigation bar (iOS), not on the page.
    .toolbar {
      #if os(iOS)
        // Lock opposite Refresh: the roof's hatch closes behind you.
        ToolbarItem(placement: .topBarLeading) {
          Button {
            WalletHaptics.tap()
            model.lock()
          } label: {
            RoofIcon(.lock, size: 21, weight: 1.8).foregroundStyle(WalletTheme.accent)
              .frame(width: 30, height: 30)
          }
          .accessibilityLabel("Lock")
          .accessibilityHint("Hides your wallet until you unlock it again")
        }
        ToolbarItem(placement: .principal) { PayroofWordmark(size: 15) }
      #endif
      WalletRefreshToolbarItem(
        refreshing: refreshing, enabled: canRefresh,
        label: refreshing ? model.refreshStep?.text ?? "Refresh" : "Refresh",
        help: "Read balances and activity for this account", action: refresh)
    }
    .walletDismissOnLock {
      detailGroup = nil
      detailItem = nil
    }
    .walletSheet(item: $detailItem) { item in
      ActivityDetailView(item: item) { detailItem = nil }
    }
    .walletSheet(
      item: Binding(
        get: { detailGroup.map(GroupID.init) }, set: { detailGroup = $0?.id })
    ) { item in
      if let group = groups.first(where: { $0.id == item.id }) {
        HoldingDetailSheet(
          group: group, account: account,
          send: { asset, path in
            detailGroup = nil
            model.sendIntent = SendIntent(asset: asset.id, prefer: path)
            navigate(.send)
          }
        ) { detailGroup = nil }
      }
    }
  }

  private var refreshing: Bool { model.refreshingCurrent }
  private var canRefresh: Bool {
    !model.refreshing && !model.state.usableAssets.isEmpty && !(account?.paths.isEmpty ?? true)
  }
  private func refresh() { model.refresh() }

  // MARK: Roof

  /// The accounts' buildings against the sky. The sky reaches far above the row, under
  /// the bars and into the pull-to-refresh bounce, so it never shows an edge.
  private var hero: some View {
    AccountCarousel(
      account: model.account, navigate: navigate, edit: editAccount, create: createAccount,
      createCustom: createCustomAccount, project: openProject
    )
    .padding(.top, 6)
    // The sun or moon rises behind the current sign's corner (on a phone). On the Mac,
    // where the sign keeps a card's width, it hangs in the open sky beside it, clear of
    // the window's header so its glow is never cut.
    .background(alignment: .topTrailing) {
      Group {
        if scheme == .dark { NightMoon(size: 46) } else { DaySun(size: 54) }
      }
      .frame(width: 60, height: 60)
      #if os(macOS)
        .padding(.trailing, 70)
        .offset(y: 80)
      #else
        .padding(.trailing, 46)
        .offset(y: -30)
      #endif
    }
    .background(alignment: .bottom) {
      ZStack(alignment: .bottom) {
        SkyBackdrop(celestial: false, fadesIntoCanvas: false)
        SkylineView(seed: 11, color: WalletTheme.skylineFar, relief: 1, animated: true)
          .frame(height: 150)
        SkylineView(seed: 4, color: WalletTheme.skylineNear.opacity(0.55), relief: 0.6)
          .frame(height: 80)
      }
      .frame(height: 1100)
      // The sky ends at the parapet's top.
      .padding(.bottom, 24)
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      heroHeight = $0
    }
  }

  /// Under the parapet the building's brick face shows a little, then plain plaster.
  private var facade: some View {
    BrickWall(brick: CGSize(width: 40, height: 14), color: WalletTheme.mortar)
      .frame(height: 90)
      .mask(
        LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
      )
      .accessibilityHidden(true)
  }

  // MARK: Actions

  private var actions: some View {
    HStack(spacing: 12) {
      ActionTile(title: "Send", glyph: .plane, primary: true) { navigate(.send) }
      ActionTile(title: "Receive", glyph: .mailbox, primary: false) { navigate(.receive) }
    }
  }

  // MARK: Activity

  /// Under the holdings: this account's latest transfers on the fire stairs, or a quiet
  /// empty state.
  @ViewBuilder private var activity: some View {
    if !recent.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        WalletSectionHeader(
          "Recent activity", detail: pending > 0 ? "\(pending) pending" : ""
        ) {
          WalletAction(
            title: "View all", icon: "list.bullet", role: .tertiary, expand: false,
            action: { navigate(.activity) })
        }
        WalletCard(padding: 8) {
          VStack(spacing: 0) {
            let latest = Array(recent.prefix(3))
            ForEach(latest) { item in
              Button {
                detailItem = item
              } label: {
                ActivityRow(item: item, showsDay: true).padding(.horizontal, 8)
              }
              .buttonStyle(WalletRowButtonStyle()).accessibilityHint("Shows details")
            }
          }
          .background(alignment: .leading) { FireStairs().padding(.leading, 8) }
        }
      }
    } else {
      WalletEmptyState(icon: "tray", title: "No activity yet").frame(maxHeight: .infinity)
    }
  }
}

/// Send and Receive: wide tiles with their roof icons. The plane lifts off when pressed.
private struct ActionTile: View {
  let title: String
  let glyph: RoofGlyph
  let primary: Bool
  let action: () -> Void
  @State private var launches = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Button {
      WalletHaptics.tap()
      if !reduceMotion { launches += 1 }
      action()
    } label: {
      HStack(spacing: 10) {
        RoofIcon(glyph, size: 24, weight: 1.9, active: true, play: launches)
        Text(title).font(.body.weight(.semibold))
      }
      .frame(minHeight: 58)
    }
    .buttonStyle(WalletButtonStyle(role: primary ? .primary : .secondary))
    .accessibilityLabel(title)
  }
}

/// A holding group's ID as a sheet item.
private struct GroupID: Identifiable { let id: String }
