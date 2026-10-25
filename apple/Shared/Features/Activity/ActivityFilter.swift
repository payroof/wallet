import SwiftUI

/// What narrows the Activity list: networks left out, one of the account's addresses
/// and a direction. Empty means everything.
struct ActivityFilter: Equatable {
  enum Direction: String, CaseIterable, Identifiable {
    case all = "All"
    case sent = "Sent"
    case received = "Received"
    case moved = "Moved"
    var id: String { rawValue }
  }

  /// Networks left out. New networks are shown.
  var hiddenChains: Set<ChainID> = []
  /// The address (its path) activity is limited to, nil for all.
  var addressPath: String?
  var direction: Direction = .all

  var isActive: Bool { activeCount > 0 }
  /// How many of the three criteria narrow the list, for the toolbar badge.
  var activeCount: Int {
    (hiddenChains.isEmpty ? 0 : 1) + (addressPath == nil ? 0 : 1) + (direction == .all ? 0 : 1)
  }

  /// Whether `item` passes. `address` is the lowercase address of `addressPath`, if any.
  func matches(_ item: ActivityItem, address: String?, state: WalletSnapshot) -> Bool {
    guard !hiddenChains.contains(item.chain) else { return false }
    if addressPath != nil, address.map({ item.involves($0) }) != true { return false }
    switch direction {
    case .all: return true
    case .sent: return ActivityLook(item, state: state).direction == .sent
    case .received: return ActivityLook(item, state: state).direction == .received
    case .moved: return ActivityLook(item, state: state).direction == .moved
    }
  }
}

extension ActivityItem {
  /// Both ends of the transfer, lowercase.
  fileprivate var parties: [String] {
    switch self {
    case .sent(let t): [t.source.lowercased(), t.recipient.lowercased()]
    case .chain(let h): [h.from.lowercased(), h.to.lowercased()]
    }
  }
}

/// The filter, edited as a draft: nothing changes on the page until "Show", and Close
/// discards. Built for accounts with thousands of addresses, so the address list is
/// searchable, lazy and lists the addresses that have activity first.
struct ActivityFilterSheet: View {
  @Environment(WalletModel.self) private var model
  /// The account's whole activity, which the counts and the result are worked out from.
  let items: [ActivityItem]
  let chains: [ChainID]
  let paths: [String]
  let apply: (ActivityFilter) -> Void
  let close: () -> Void
  @State private var draft: ActivityFilter
  @State private var search = ""
  /// How many items involve each address (lowercase), counted once.
  @State private var counts: [String: Int] = [:]

  init(
    current: ActivityFilter, items: [ActivityItem], chains: [ChainID], paths: [String],
    apply: @escaping (ActivityFilter) -> Void, close: @escaping () -> Void
  ) {
    _draft = State(initialValue: current)
    self.items = items
    self.chains = chains
    self.paths = paths
    self.apply = apply
    self.close = close
  }

  private struct AddressRow: Identifiable {
    let path: String
    let name: String
    let address: String?
    let count: Int
    var id: String { path }
  }

  private var result: Int {
    let address = draft.addressPath.flatMap { model.addresses[$0]?.lowercased() }
    return items.filter { draft.matches($0, address: address, state: model.state) }.count
  }

  /// The addresses that match the search, those with activity first, each group in the
  /// account's own order.
  private var rows: [AddressRow] {
    let query = search.trimmingCharacters(in: .whitespaces).lowercased()
    var used: [AddressRow] = []
    var unused: [AddressRow] = []
    for path in paths {
      let address = model.addresses[path]
      let name = WalletText.addressName(path)
      if !query.isEmpty {
        let index = String(path.split(separator: "/").last ?? "")
        let hit =
          name.lowercased().contains(query) || index == query
          || address?.lowercased().contains(query) == true
        if !hit { continue }
      }
      let count = address.flatMap { counts[$0.lowercased()] } ?? 0
      let row = AddressRow(path: path, name: name, address: address, count: count)
      if count > 0 { used.append(row) } else { unused.append(row) }
    }
    return used + unused
  }

  var body: some View {
    WalletSheet(
      "Filter activity", subtitle: "Choose what the list shows",
      icon: "line.3.horizontal.decrease.circle", close: close
    ) {
      if chains.count > 1 { networks }
      direction
      addresses
    } footer: {
      let shown = result
      WalletSheetActions(
        cancelTitle: "Cancel", cancel: close,
        leading: {
          WalletAction(
            title: "Reset", icon: "arrow.counterclockwise", role: .tertiary, expand: false
          ) {
            draft = ActivityFilter()
            search = ""
          }
          .disabled(!draft.isActive)
        },
        primary: {
          WalletAction(
            title: shown == 1 ? "Show 1 transfer" : "Show \(shown) transfers", icon: "checkmark"
          ) { apply(draft) }
          .disabled(shown == 0)
        })
    }
    .walletModal(width: 520)
    .walletDismissOnLock(close)
    .task { counts = Self.counts(items) }
    .task(id: paths) { await model.deriveAddresses(paths) }
  }

  private static func counts(_ items: [ActivityItem]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for item in items {
      for party in Set(item.parties) { counts[party, default: 0] += 1 }
    }
    return counts
  }

  // MARK: Networks

  private var networks: some View {
    VStack(alignment: .leading, spacing: 8) {
      WalletEyebrow("Networks")
      WalletFlowLayout(spacing: 8) {
        ActivityFilterChip(title: "All", selected: draft.hiddenChains.isEmpty) {
          draft.hiddenChains = []
        }
        ForEach(chains, id: \.self) { chain in
          let name = model.state.networkName(chain)
          ActivityFilterChip(
            title: name, glyph: (chain, name, model.state.networkArt(chain)),
            selected: !draft.hiddenChains.contains(chain)
          ) { toggle(chain) }
        }
      }
    }
  }

  /// A network is shown or hidden, but the last one shown stays.
  private func toggle(_ chain: ChainID) {
    if draft.hiddenChains.contains(chain) {
      draft.hiddenChains.remove(chain)
    } else if chains.count - draft.hiddenChains.count > 1 {
      draft.hiddenChains.insert(chain)
    }
  }

  // MARK: Direction

  private var direction: some View {
    VStack(alignment: .leading, spacing: 8) {
      WalletEyebrow("Direction")
      WalletFlowLayout(spacing: 8) {
        ForEach(ActivityFilter.Direction.allCases) { option in
          ActivityFilterChip(title: option.rawValue, selected: draft.direction == option) {
            draft.direction = option
          }
        }
      }
    }
  }

  // MARK: Addresses

  private var addresses: some View {
    let rows = rows
    return VStack(alignment: .leading, spacing: 8) {
      WalletEyebrow("Address")
      WalletSearchField(prompt: "Search name, number or address", text: $search)
      ScrollView {
        LazyVStack(spacing: 0) {
          if search.isEmpty {
            WalletOptionRow(
              option: WalletOption(
                value: String?.none, title: "All addresses",
                subtitle: paths.count == 1 ? "1 address" : "\(paths.count) addresses"),
              selected: draft.addressPath == nil
            ) { draft.addressPath = nil }
          }
          ForEach(rows) { row in
            WalletOptionRow(
              option: WalletOption(
                value: Optional(row.path), title: row.name, subtitle: subtitle(row)),
              selected: draft.addressPath == row.path
            ) { draft.addressPath = row.path }
          }
          if rows.isEmpty {
            Text("No address matches “\(search)”.").font(.callout)
              .foregroundStyle(WalletTheme.muted).padding(.vertical, 16)
          }
        }
      }
      .frame(height: 252)
      .background(WalletTheme.surface.opacity(0.5), in: WalletShape.field)
      .overlay(WalletShape.field.strokeBorder(WalletTheme.border))
    }
  }

  private func subtitle(_ row: AddressRow) -> String {
    let activity =
      row.count == 0 ? "No activity" : row.count == 1 ? "1 transfer" : "\(row.count) transfers"
    guard let address = row.address else { return activity }
    return "\(WalletText.short(address)) · \(activity)"
  }
}

/// A toggle chip, optionally with a network's mark.
private struct ActivityFilterChip: View {
  let title: String
  var glyph: (chain: ChainID, name: String, art: WalletArt)? = nil
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let glyph {
          WalletNetworkGlyph(name: glyph.name, art: glyph.art, size: 18)
        }
        Text(title).font(.callout.weight(selected ? .semibold : .medium)).lineLimit(1)
        if selected {
          Image(systemName: "checkmark").font(.caption.weight(.bold))
            .foregroundStyle(WalletTheme.accent).accessibilityHidden(true)
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 4)
      .frame(minHeight: WalletMetrics.chip)
      .background(
        selected
          ? AnyShapeStyle(WalletTheme.accent.opacity(0.12)) : AnyShapeStyle(WalletTheme.surface),
        in: Capsule(style: .continuous)
      )
      .overlay(
        Capsule(style: .continuous).strokeBorder(
          selected ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.border),
          lineWidth: selected ? 1.5 : 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}
