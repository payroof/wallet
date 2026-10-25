import SwiftUI

/// What the current account holds, summed over its addresses, by token or by network:
/// one row each, with its amount or tokens and its USD value, the most valuable first.
/// A token opens where it is held, a network unfolds its tokens in place.
struct HomeHoldings: View {
  @Environment(WalletModel.self) private var model
  let groups: [HoldingGroup]
  let open: (HoldingGroup) -> Void
  @AppStorage(WalletStorageKey.homeHoldings.rawValue) private var grouping = Grouping.tokens
  /// Networks whose tokens are unfolded.
  @State private var unfolded: Set<ChainID> = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  enum Grouping: String, CaseIterable {
    case tokens, networks
    var title: String { self == .tokens ? "Tokens" : "Networks" }
    var icon: String {
      self == .tokens ? "circle.hexagongrid" : "point.3.connected.trianglepath.dotted"
    }
  }

  /// One network's nonzero holdings and their USD value.
  private struct NetworkRow: Identifiable {
    let chain: ChainID
    let holdings: [AssetHolding]
    let usd: USDValue
    var id: ChainID { chain }
  }

  private var prices: [AssetID: CachedPrice] { model.state.settings.prices }
  private var tokens: [(group: HoldingGroup, usd: USDValue)] {
    groups.map { ($0, $0.value(prices: prices)) }.sorted { ($0.usd.usd ?? -1) > ($1.usd.usd ?? -1) }
  }
  private var networks: [NetworkRow] {
    let holdings = groups.flatMap(\.holdings)
    return model.state.networks.compactMap { network in
      let held = holdings.filter { $0.asset.chain == network.id }
      guard !held.isEmpty else { return nil }
      let group = HoldingGroup(symbol: network.id.rawValue, decimals: 0, total: "0", holdings: held)
      return NetworkRow(chain: network.id, holdings: held, usd: group.value(prices: prices))
    }
    .sorted { ($0.usd.usd ?? -1) > ($1.usd.usd ?? -1) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      WalletSectionHeader("Holdings") {
        HoldingsToggle(selection: $grouping)
      }
      WalletCard(padding: 8) {
        VStack(spacing: 0) {
          switch grouping {
          case .tokens:
            ForEach(tokens, id: \.group.id) { item in
              Button {
                open(item.group)
              } label: {
                row(
                  title: item.group.symbol, detail: tokenDetail(item.group), usd: item.usd,
                  chevron: true
                ) {
                  if let asset = item.group.holdings.first?.asset {
                    WalletAssetGlyph(asset: asset, size: 34)
                  }
                }
              }
              .buttonStyle(WalletRowButtonStyle()).accessibilityHint("Shows where it is held")
            }
          case .networks:
            ForEach(networks) { item in
              networkEntry(item)
            }
          }
        }
      }
    }
    .privacySensitive()
  }

  /// A network's row, which unfolds its tokens below it.
  @ViewBuilder private func networkEntry(_ item: NetworkRow) -> some View {
    let open = unfolded.contains(item.chain)
    let name = model.state.networkName(item.chain)
    Button {
      withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
        if open { unfolded.remove(item.chain) } else { unfolded.insert(item.chain) }
      }
    } label: {
      row(
        title: name, detail: item.holdings.map(\.asset.symbol).joined(separator: " · "),
        usd: item.usd, chevron: true, chevronOpen: open
      ) {
        WalletNetworkGlyph(model.state, chain: item.chain, size: 34)
      }
    }
    .buttonStyle(WalletRowButtonStyle())
    .accessibilityValue(open ? "Expanded" : "Collapsed")
    .accessibilityHint(open ? "Hides its tokens" : "Shows its tokens")
    if open {
      ForEach(item.holdings) { holding in
        let value = HoldingGroup(
          symbol: holding.asset.symbol, decimals: holding.asset.decimals, total: holding.total,
          holdings: [holding]
        ).value(prices: prices)
        HStack(spacing: 10) {
          WalletAssetGlyph(asset: holding.asset, size: 22)
          Text(holding.asset.symbol).font(.callout.weight(.medium)).lineLimit(1)
          Text(ExactAmount.short(holding.total, decimals: holding.asset.decimals))
            .font(.caption).foregroundStyle(WalletTheme.muted).monospacedDigit().lineLimit(1)
          Spacer(minLength: 8)
          Text(value.usd.map(WalletPortfolio.currency) ?? "—")
            .font(.callout).monospacedDigit().foregroundStyle(WalletTheme.muted)
        }
        .padding(.leading, 30).padding(.trailing, 8).frame(minHeight: WalletMetrics.control - 4)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
      }
    }
  }

  /// "1 204.5 · Base" for one network, "1 204.5 · 3 networks" for several.
  private func tokenDetail(_ group: HoldingGroup) -> String {
    let amount = ExactAmount.short(group.total, decimals: group.decimals)
    let chains = Set(group.holdings.map(\.asset.chain))
    let place =
      chains.count == 1
      ? chains.first.map(model.state.networkName) ?? "" : "\(chains.count) networks"
    return amount + " · " + place
  }

  private func row<Mark: View>(
    title: String, detail: String, usd: USDValue, chevron: Bool, chevronOpen: Bool = false,
    @ViewBuilder mark: () -> Mark
  ) -> some View {
    HStack(spacing: 12) {
      mark()
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.callout.weight(.semibold)).lineLimit(1)
        Text(detail).font(.caption).foregroundStyle(WalletTheme.muted).monospacedDigit()
          .lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: 8)
      Text(usd.usd.map(WalletPortfolio.currency) ?? "—")
        .font(RoofFont.sign(20, relativeTo: .callout)).monospacedDigit().lineLimit(1)
        .offset(y: SignMetrics.centering(20))
      if chevron {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          .foregroundStyle(WalletTheme.muted).rotationEffect(.degrees(chevronOpen ? 90 : 0))
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 4).frame(minHeight: WalletMetrics.control + 6)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

/// Tokens or Networks: a capsule track with the chosen segment as an accent-tinted
/// capsule that slides between the two. VoiceOver reads it as a picker.
private struct HoldingsToggle: View {
  @Binding var selection: HomeHoldings.Grouping
  @Namespace private var slide
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      ForEach(HomeHoldings.Grouping.allCases, id: \.self) { option in
        Segment(option: option, selected: selection == option, slide: slide) {
          withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selection = option }
        }
      }
    }
    .padding(2)
    .background(WalletTheme.surface, in: Capsule(style: .continuous))
    .overlay(Capsule(style: .continuous).strokeBorder(WalletTheme.border, lineWidth: 1))
    .fixedSize()
    .accessibilityRepresentation {
      Picker("Group holdings by", selection: $selection) {
        ForEach(HomeHoldings.Grouping.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
    }
  }

  private struct Segment: View {
    let option: HomeHoldings.Grouping
    let selected: Bool
    let slide: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
      Button(action: action) {
        HStack(spacing: 5) {
          Image(systemName: option.icon).font(.caption.weight(.semibold))
          Text(option.title).font(.callout.weight(.semibold))
        }
        .foregroundStyle(
          selected ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.muted)
        )
        .padding(.horizontal, 12)
        .frame(minHeight: WalletMetrics.control - 8)
        .background {
          if selected {
            Capsule(style: .continuous).fill(WalletTheme.accent.opacity(0.14))
              .matchedGeometryEffect(id: "selected", in: slide)
          } else if hovering {
            Capsule(style: .continuous).fill(WalletTheme.text.opacity(0.05))
          }
        }
        .contentShape(Capsule(style: .continuous))
      }
      .buttonStyle(SegmentPress())
      .onHover { hovering = $0 }
      .accessibilityAddTraits(selected ? .isSelected : [])
    }
  }

  /// Dips slightly while pressed, without changing the segment's colors.
  private struct SegmentPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .opacity(configuration.isPressed ? 0.6 : 1)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: configuration.isPressed)
    }
  }
}
