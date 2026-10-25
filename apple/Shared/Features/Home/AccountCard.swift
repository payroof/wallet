import SwiftUI

/// One account as a building on the skyline: a rooftop sign on lattice legs, in the
/// account's colors, with the account's own things on its roof (a water tower, chimneys,
/// a turbine vent: the same for an account on every launch). The sign carries the name,
/// the USD total and a one-line status. The antenna on the right is the project
/// connection: its light blinks "on air" while connected, and it connects or opens the
/// project. The chimney smokes while the account is being read. Tapping the current
/// sign turns it round: the back is its total over time, drawn as a skyline. It paints
/// its own colors, so it looks right while the row moves, before the app's accent
/// follows the account.
struct AccountCard: View {
  @Environment(WalletModel.self) private var model
  let account: ProjectCard
  /// A tap on a building that isn't current: the row moves to it.
  let select: () -> Void
  let edit: () -> Void
  /// The antenna's action: connect the account to a project, or open the project's settings.
  let project: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var scheme
  @State private var flipped = false

  static let radius: CGFloat = 20
  /// Below the sign: its legs and the roof's things, standing on the parapet.
  nonisolated static let base: CGFloat = 66
  /// The sign's height for a building of this width.
  nonisolated static func signHeight(_ width: CGFloat) -> CGFloat {
    min(230, max(150, width / 1.85))
  }
  nonisolated static func height(_ width: CGFloat) -> CGFloat { signHeight(width) + base }
  private static let unknown = "$--.--"

  private var accent: WalletAccent { model.accent(for: account.slot) }
  private var current: Bool { model.account == account.slot }
  private struct Summary {
    let holdings: [AssetHolding]
    let groups: [HoldingGroup]
    let total: (usd: Decimal?, excluded: [String])
  }
  private var summary: Summary {
    let holdings = WalletPortfolio.holdings(model.state, account: account)
    let groups = WalletPortfolio.groups(holdings)
    return Summary(
      holdings: holdings, groups: groups,
      total: WalletPortfolio.total(groups, prices: model.state.settings.prices))
  }
  /// This account's own refresh is running. Another account's refresh leaves this
  /// banner as it is.
  private var refreshing: Bool { model.isRefreshing(account.slot) }
  /// Connected to a project with a credential the server still accepts.
  private var connected: Bool {
    model.state.settings.connections.contains {
      $0.slot == account.slot && !model.state.revokedConnections.contains($0.id)
    }
  }
  /// Nothing of this account has been read yet: the sign offers to read it.
  private func unread(_ s: Summary) -> Bool {
    s.holdings.isEmpty && !model.state.usableAssets.isEmpty && !account.paths.isEmpty
  }
  private func totalText(_ s: Summary) -> String {
    if model.state.usableAssets.isEmpty || s.holdings.isEmpty { return Self.unknown }
    if s.groups.isEmpty { return WalletPortfolio.currency(0) }
    return s.total.usd.map(WalletPortfolio.currency) ?? Self.unknown
  }
  /// The account's root, `m/44'/60'/<slot>'/0`. Its addresses are numbered below it.
  private var root: (head: String, slot: String, tail: String) {
    ("m/44'/60'/", "\(account.slot)'", "/0")
  }

  var body: some View {
    let summary = summary
    GeometryReader { box in
      VStack(spacing: 0) {
        sign(summary).frame(height: Self.signHeight(box.size.width))
        ZStack(alignment: .bottom) {
          SignLegs(count: 3, color: WalletTheme.steel)
            .padding(.horizontal, box.size.width * 0.18)
          RoofProps(
            slot: account.slot, accent: accent, connected: connected, refreshing: refreshing,
            current: current, project: project)
        }
        .frame(height: Self.base)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { if !current { select() } }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText(summary))
    .accessibilityHint(
      current
        ? (flipped ? "Shows the balance" : "Shows the balance over time") : "Shows this account"
    )
    .accessibilityAddTraits(current ? [.isSelected, .isButton] : .isButton)
    .accessibilityValue(current ? "current" : "")
    .accessibilityIdentifier("card.\(account.slot)")
    .accessibilityAction { tap() }
    .accessibilityActions {
      if unread(summary) && !refreshing {
        Button("Update") { model.refresh(account.slot) }
      }
      Button(connected ? "Project" : "Connect project", action: project)
      Button("Edit", action: edit)
    }
    // A building that is no longer current shows its sign's front again.
    .onChange(of: current) { _, value in if !value { flipped = false } }
    .onChange(of: model.lockEpoch) { _, _ in flipped = false }
  }

  /// The sign: front and back, each turning about the vertical axis.
  private func sign(_ summary: Summary) -> some View {
    ZStack {
      front(summary)
        .modifier(CardSide(angle: flipped ? 180 : 0, calm: reduceMotion))
      AccountValueBack(account: account, accent: accent)
        .modifier(CardSide(angle: flipped ? 0 : -180, calm: reduceMotion))
    }
    .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    .onTapGesture { tap() }
  }

  private func tap() {
    guard current else { return select() }
    WalletHaptics.tap()
    withAnimation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.78)
    ) {
      flipped.toggle()
    }
  }

  /// A plain icon in the sign's corner. White keeps its contrast on every color.
  private var editButton: some View {
    Button(action: edit) {
      Image(systemName: "paintbrush.pointed").font(.body.weight(.semibold))
        .foregroundStyle(WalletAccent.onCard.opacity(0.9))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.top, 8).padding(.trailing, 8)
    .help("Edit account").accessibilityLabel("Edit \(account.label)")
  }

  /// The name at the largest size that fits on one line, then smaller, then squeezed.
  private var title: some View {
    ViewThatFits(in: .horizontal) {
      Text(account.label).font(RoofFont.poster(21, relativeTo: .title3)).lineLimit(1)
      Text(account.label).font(RoofFont.poster(17, relativeTo: .headline)).lineLimit(1)
      Text(account.label).font(RoofFont.poster(15, relativeTo: .headline)).lineLimit(1)
        .minimumScaleFactor(0.7)
    }
  }

  private func front(_ summary: Summary) -> some View {
    let unread = unread(summary) && !refreshing
    let night = scheme == .dark
    return SignBoard(accent: accent, chasing: refreshing, radius: Self.radius) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 8) {
          title
          Spacer(minLength: 44)
        }
        Spacer(minLength: 0)
        HStack(alignment: .center, spacing: 8) {
          footnote(summary).opacity(unread ? 0 : 1)
          Spacer(minLength: 4)
          airBadge
        }
      }
      .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 18)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      // The total sits at the sign's centre. Until the account has been read, Update
      // takes its place there.
      .overlay {
        ZStack {
          Text(totalText(summary))
            .font(RoofFont.sign(64, relativeTo: .largeTitle)).monospacedDigit()
            .offset(y: SignMetrics.centering(64))
            .lineLimit(1).minimumScaleFactor(0.4)
            .shadow(color: night ? accent.cardBright : .clear, radius: 10)
            .shadow(
              color: night ? accent.sunrise.opacity(0.5) : .black.opacity(0.18),
              radius: night ? 2 : 1, y: night ? 0 : 1
            )
            .contentTransition(.numericText())
            .opacity(unread ? 0 : 1)
          if unread { updateButton }
        }
        .padding(.horizontal, 24)
      }
    }
    .foregroundStyle(WalletAccent.onCard)
    .overlay(alignment: .topTrailing) { editButton }
    // Whoever lives on this roof sits on top of the sign, against the open sky.
    .overlay(alignment: .topLeading) {
      GeometryReader { box in
        RoofResident(slot: account.slot)
          .position(x: box.size.width * (account.slot % 2 == 0 ? 0.64 : 0.3), y: 0)
      }
    }
    .privacySensitive()
    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: totalText(summary))
  }

  /// The project connection, painted on the sign: "On air" with a blinking red light
  /// while connected, "Off air" otherwise. It connects or opens the project.
  private var airBadge: some View {
    Button {
      WalletHaptics.tap()
      project()
    } label: {
      HStack(spacing: 5) {
        AirLight(on: connected)
        Text(connected ? "On air" : "Off air").roofStencil(10, tracking: 1.3)
      }
      .foregroundStyle(WalletAccent.onCard.opacity(connected ? 1 : 0.8))
      .padding(.horizontal, 9).frame(height: 24)
      .background(Color.black.opacity(connected ? 0.32 : 0.2), in: Capsule())
      .overlay(Capsule().strokeBorder(Color.white.opacity(connected ? 0.35 : 0.22), lineWidth: 1))
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .allowsHitTesting(current)
    .help(connected ? "Project" : "Connect a project")
    .accessibilityHidden(true)
  }

  /// Shown in the total's place until the account has been read: one tap reads it.
  private var updateButton: some View {
    Button {
      WalletHaptics.tap()
      model.refresh(account.slot)
    } label: {
      Label("Update", systemImage: "arrow.clockwise")
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16).frame(height: 38)
        .background(Color.white.opacity(0.2), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4)))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    // One refresh at a time: while another account is read, this one waits its turn.
    .disabled(model.refreshing)
    .help(model.refreshing ? "Another account is being updated" : "Read this account's balances")
  }

  /// One line under the total: what is being read right now (network, what, from
  /// where), or when it was updated and what it leaves out. Its text changes with the
  /// state. The line itself is always there.
  private func footnote(_ summary: Summary) -> some View {
    Label(footnoteText(summary), systemImage: footnoteIcon(summary))
      .font(.caption).lineLimit(1).truncationMode(.middle).monospacedDigit()
      .foregroundStyle(WalletAccent.onCardMuted)
      .help(footnoteText(summary))
      .contentTransition(.opacity)
  }
  private func oldest(_ summary: Summary) -> Date? {
    summary.holdings.compactMap(\.checked).min()
  }
  private var unreadNetworks: [String] {
    (model.state.staleNetworks[account.slot] ?? []).sorted().map(model.state.networkName)
  }
  private func stale(_ summary: Summary) -> Bool {
    !refreshing
      && (oldest(summary).map { WalletFreshness.isStale($0) } == true || !unreadNetworks.isEmpty)
  }
  private func footnoteIcon(_ summary: Summary) -> String {
    refreshing
      ? "arrow.triangle.2.circlepath" : stale(summary) ? "clock.badge.exclamationmark" : "clock"
  }
  private func footnoteText(_ summary: Summary) -> String {
    if model.state.usableAssets.isEmpty { return "No network is on" }
    if refreshing, let step = model.refreshStep {
      return step.count.isEmpty ? step.text : step.count + " · " + step.text
    }
    let isStale = stale(summary)
    guard let oldest = oldest(summary) else { return "Not updated yet" }
    var text = (isStale ? "Checked " : "Updated ") + WalletFreshness.relative(oldest)
    let excluded = summary.total.excluded
    if !excluded.isEmpty { text += " · excludes " + excluded.joined(separator: ", ") }
    if !unreadNetworks.isEmpty {
      text += " · " + unreadNetworks.joined(separator: ", ") + " not updated"
    }
    return text
  }
  private func accessibilityText(_ summary: Summary) -> String {
    if flipped { return "\(account.label). Balance over time." }
    let balance = unread(summary) ? "Not updated yet" : "Total \(totalText(summary))"
    let root = root
    return
      "\(account.label). \(balance). \(footnoteText(summary)). Path \(root.head)\(root.slot)\(root.tail). Project \(connected ? "connected" : "not connected")"
  }
}

/// A building redraws when its account does. The model's own changes reach it through
/// the environment. The actions are the same for the same account.
extension AccountCard: Equatable {
  nonisolated static func == (lhs: AccountCard, rhs: AccountCard) -> Bool {
    lhs.account.slot == rhs.account.slot && lhs.account.label == rhs.account.label
      && lhs.account.paths == rhs.account.paths
  }
}

/// One side of a sign turning about its vertical axis: `angle` 0 faces the viewer. The
/// side shows only while it faces forward, so the other takes its place halfway through.
/// With Reduce Motion the sides only swap.
struct CardSide: ViewModifier, Animatable {
  var angle: Double
  let calm: Bool
  nonisolated var animatableData: Double {
    get { angle }
    set { angle = newValue }
  }
  func body(content: Content) -> some View {
    content
      .opacity(abs(angle) < 90 ? 1 : 0)
      .rotation3DEffect(.degrees(calm ? 0 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
      .allowsHitTesting(abs(angle) < 90)
      .accessibilityHidden(abs(angle) >= 90)
  }
}

/// The sign's "on air" lamp: a red light that pulses while connected, an empty ring
/// otherwise.
private struct AirLight: View {
  let on: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 20, paused: !on || reduceMotion)) { context in
      let pulse =
        reduceMotion
        ? 1 : 0.45 + 0.55 * max(0, sin(context.date.timeIntervalSinceReferenceDate * 3.2))
      if on {
        Circle().fill(Color(red: 1, green: 0.3, blue: 0.25))
          .shadow(color: Color.red.opacity(0.9 * pulse), radius: 4)
          .opacity(0.55 + 0.45 * pulse)
      } else {
        Circle().strokeBorder(.foreground, lineWidth: 1.2)
      }
    }
    .frame(width: 7, height: 7)
  }
}
