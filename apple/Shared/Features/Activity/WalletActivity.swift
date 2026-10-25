import SwiftUI

/// The current account's activity, newest first by day. A filter in the header narrows
/// it by network, direction and address, chosen in a sheet. While it does, a bar above
/// the list says what is hidden and clears it in one tap. Each line opens its detail.
struct WalletActivity: View {
  @Environment(WalletModel.self) private var model
  @State private var selected: ActivityItem?
  @State private var filter = ActivityFilter()
  @State private var choosingFilter = false
  private var all: [ActivityItem] { model.state.activity(slot: model.account) }
  /// Networks the account has activity on, in the user's order.
  private var chains: [ChainID] {
    let used = Set(all.map(\.chain))
    return model.state.networks.map(\.id).filter(used.contains)
  }
  private var paths: [String] { model.currentAccount?.orderedPaths ?? [] }
  private var filtering: Bool { filter.isActive }
  private var items: [ActivityItem] {
    guard filtering else { return all }
    let address = filter.addressPath.flatMap { model.addresses[$0]?.lowercased() }
    return all.filter { filter.matches($0, address: address, state: model.state) }
  }
  /// Sent and found activity, newest first, grouped by calendar day.
  private var days: [(day: Date, items: [ActivityItem])] {
    var groups: [(day: Date, items: [ActivityItem])] = []
    for item in items {
      let day = Calendar.current.startOfDay(for: item.date)
      if let index = groups.firstIndex(where: { $0.day == day }) {
        groups[index].items.append(item)
      } else {
        groups.append((day, [item]))
      }
    }
    return groups
  }
  var body: some View {
    WalletPage("", subtitle: "", fillsHeight: items.isEmpty) {
      if filtering { filterSummary }
      if items.isEmpty {
        WalletEmptyState(
          icon: filtering ? "line.3.horizontal.decrease" : "stairs",
          title: filtering ? "No matching activity" : "No activity yet",
          detail: filtering
            ? "Nothing here matches the filter."
            : "Payments to and from this account's addresses appear here."
        )
        .frame(maxHeight: .infinity)
      } else {
        ForEach(days, id: \.day) { group in
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              RoofIcon(.stairs, size: 13, weight: 1.6).foregroundStyle(WalletTheme.accent)
              WalletEyebrow(dayTitle(group.day))
              Spacer(minLength: 8)
              Text(group.items.count == 1 ? "1 transfer" : "\(group.items.count) transfers")
                .font(.caption).foregroundStyle(WalletTheme.muted)
            }
            WalletCard(padding: 8) {
              VStack(spacing: 0) {
                ForEach(group.items) { item in
                  Button {
                    selected = item
                  } label: {
                    HStack(spacing: 8) {
                      ActivityRow(item: item)
                      Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(WalletTheme.muted).accessibilityHidden(true)
                    }.padding(.horizontal, 8)
                  }.buttonStyle(WalletRowButtonStyle()).accessibilityHint("Shows details")
                }
              }
              // The day's transfers hang on the fire stairs, one landing each.
              .background(alignment: .leading) { FireStairs().padding(.leading, 8) }
            }
          }
        }
      }
    }
    // In the window's title bar (macOS) or navigation bar (iOS), not on the page.
    .toolbar {
      if !all.isEmpty { ToolbarItem(placement: .navigation) { filterButton } }
      WalletRefreshToolbarItem(
        refreshing: model.refreshingCurrent,
        enabled: canRefresh,
        label: model.refreshingCurrent ? model.refreshStep?.text ?? "Refresh" : "Refresh",
        help: "Read balances and activity for this account"
      ) { model.refresh() }
    }
    #if os(iOS)
      .refreshable { if canRefresh { model.refresh() } }
    #endif
    .walletSheet(item: $selected) { item in
      ActivityDetailView(item: item) { selected = nil }
    }
    .walletSheet(isPresented: $choosingFilter) {
      ActivityFilterSheet(
        current: filter, items: all, chains: chains, paths: paths,
        apply: {
          filter = $0
          choosingFilter = false
        },
        close: { choosingFilter = false })
    }
    .walletDismissOnLock {
      selected = nil
      choosingFilter = false
    }
    // Addresses are matched by their public form, derived on device.
    .task(id: paths) { await model.deriveAddresses(paths) }
    .onChange(of: model.account) { _, _ in filter = ActivityFilter() }
  }

  /// The toolbar button: filled while a filter is on, with how many criteria it uses.
  private var filterButton: some View {
    Button {
      choosingFilter = true
    } label: {
      HStack(spacing: 3) {
        Image(
          systemName: filtering
            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        if filtering {
          Text("\(filter.activeCount)").font(.caption2.weight(.bold)).monospacedDigit()
        }
      }
    }
    .help("Filter activity")
    .accessibilityLabel(filtering ? "Filter, on" : "Filter")
    .accessibilityValue(filtering ? "\(filter.activeCount) active" : "")
  }
  private var canRefresh: Bool { !model.refreshing && !model.state.usableAssets.isEmpty }

  /// What the filter hides, in words, with the way back to everything.
  private var filterSummary: some View {
    let shown = chains.filter { !filter.hiddenChains.contains($0) }.map(model.state.networkName)
    let networks =
      filter.hiddenChains.isEmpty
      ? nil : shown.isEmpty ? "no networks" : ListFormatter.localizedString(byJoining: shown)
    let direction = filter.direction == .all ? nil : filter.direction.rawValue.lowercased()
    let address = filter.addressPath.map(WalletText.addressName)
    let subject =
      direction.map { "\($0) transfers" + (address.map { " for \($0)" } ?? "") }
      ?? address ?? "all transfers"
    let text = "Showing " + subject + (networks.map { " on \($0)" } ?? "")
    return HStack(spacing: 10) {
      Image(systemName: "line.3.horizontal.decrease.circle.fill")
        .foregroundStyle(WalletTheme.accent).accessibilityHidden(true)
      Text(text).font(.callout).lineLimit(2)
      Spacer(minLength: 8)
      WalletAction(title: "Show all", icon: "xmark", role: .tertiary, expand: false) {
        clearFilter()
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 6)
    .background(WalletTheme.accent.opacity(0.08), in: WalletShape.field)
    .overlay(WalletShape.field.strokeBorder(WalletTheme.accent.opacity(0.25)))
    .accessibilityElement(children: .combine)
  }

  private func clearFilter() {
    filter = ActivityFilter()
  }
  private func dayTitle(_ day: Date) -> String {
    if Calendar.current.isDateInToday(day) { return "Today" }
    if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(date: .abbreviated, time: .omitted)
  }
}
