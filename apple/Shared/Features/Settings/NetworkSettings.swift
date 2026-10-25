import SwiftUI

/// Networks & tokens: one card per network, its endpoint state and on/off
/// switch in the header and its tokens below. Long token lists show the first few and expand.
/// With many tokens a search narrows every network at once.
struct NetworkSettings: View {
  @Environment(WalletModel.self) private var model
  @State private var configuring: ConfigSheet?
  @State private var query = ""
  /// Networks whose full token list is shown.
  @State private var expanded: Set<ChainID> = []
  /// Tokens listed per network before "Show all".
  private static let preview = 4
  private var needle: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
  @ViewBuilder private var search: some View {
    if !model.state.assets.isEmpty {
      WalletSearchField(prompt: "Search \(model.state.assets.count) tokens", text: $query)
    }
  }
  @ViewBuilder private func addActions(expand: Bool) -> some View {
    WalletAction(title: "Add network", icon: "network", secondary: true, expand: expand) {
      configuring = .network(nil)
    }.disabled(model.busy)
    WalletAction(title: "Add token", icon: "plus", secondary: true, expand: expand) {
      configuring = .asset(nil, chain: nil)
    }.disabled(model.busy || model.state.networks.isEmpty)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      #if os(iOS)
        // A phone is too narrow for all three on one line: search first, then the two
        // actions sharing the width.
        VStack(spacing: 10) {
          search
          HStack(spacing: 10) { addActions(expand: true) }
        }
      #else
        HStack(spacing: 8) {
          search
          Spacer(minLength: 0)
          addActions(expand: false)
        }
      #endif
      ProviderKeys()
      if model.state.networks.isEmpty {
        WalletEmptyState(icon: "network", title: "No networks")
      }
      ForEach(model.state.networks) { network in
        let tokens = tokens(network)
        if needle.isEmpty || !tokens.isEmpty || network.name.lowercased().contains(needle) {
          networkCard(network, tokens: tokens)
        }
      }
    }
    .walletSheet(item: $configuring) { item in
      switch item {
      case .network(let chain):
        NetworkSheet(chain: chain) { configuring = nil }
      case .asset(let id, let chain):
        TokenSheet(id: id, network: chain) { configuring = nil }
      }
    }
    .walletDismissOnLock { configuring = nil }
  }

  private func tokens(_ network: WalletNetwork) -> [WalletAsset] {
    model.state.assets.filter { asset in
      asset.chain == network.id
        && (needle.isEmpty || asset.symbol.lowercased().contains(needle)
          || (asset.name?.lowercased().contains(needle) ?? false)
          || (asset.contract?.lowercased.contains(needle) ?? false))
    }
  }

  private func networkCard(_ network: WalletNetwork, tokens: [WalletAsset]) -> some View {
    let all = !needle.isEmpty || expanded.contains(network.id) || tokens.count <= Self.preview + 1
    let shown = all ? tokens : Array(tokens.prefix(Self.preview))
    return WalletCard(padding: 6) {
      VStack(spacing: 0) {
        networkRow(network)
        ForEach(shown) { asset in tokenRow(asset) }
        if shown.count < tokens.count {
          Button {
            expanded.insert(network.id)
          } label: {
            Text("Show all \(tokens.count)").font(.callout.weight(.medium))
              .foregroundStyle(WalletTheme.accent)
              .frame(maxWidth: .infinity, minHeight: WalletMetrics.control)
          }
          .buttonStyle(WalletRowButtonStyle())
        }
      }
    }
  }

  private func networkRow(_ network: WalletNetwork) -> some View {
    let endpoint = model.state.endpoint(for: network.id)
    let count = model.state.endpoints(for: network.id).count
    let detail =
      endpoint.map {
        "\(model.state.endpointName($0, chain: network.id)) · \(count) RPC\(count == 1 ? "" : "s")"
      }
      ?? (network.enabled && count == 0 ? "No RPC" : "Off")
    return HStack(spacing: 6) {
      Button {
        configuring = .network(network.id)
      } label: {
        HStack(spacing: 12) {
          WalletNetworkGlyph(model.state, chain: network.id, size: 28)
            .opacity(network.enabled ? 1 : 0.5)
            .overlay(alignment: .bottomTrailing) {
              // Whether the network can be used right now (it has a working endpoint).
              Image(systemName: endpoint == nil ? "circle.dashed" : "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(endpoint == nil ? WalletTheme.muted : WalletTheme.success)
                .background(WalletTheme.surface, in: Circle())
                .offset(x: 3, y: 3).accessibilityHidden(true)
            }
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 1) {
            Text(network.name).font(.callout.weight(.semibold))
              .foregroundStyle(network.enabled ? WalletTheme.text : WalletTheme.muted)
            Text(detail).font(.caption).foregroundStyle(WalletTheme.muted).lineLimit(1)
          }
          Spacer(minLength: 8)
        }
        .padding(.horizontal, 10).frame(minHeight: WalletMetrics.control + 14)
      }
      .buttonStyle(WalletRowButtonStyle())
      .accessibilityLabel("\(network.name), \(detail). Edit network")
      // A token on this network: the same sheet as "Add token", starting here.
      Button {
        configuring = .asset(nil, chain: network.id)
      } label: {
        Image(systemName: "plus").font(.callout.weight(.semibold))
          .foregroundStyle(WalletTheme.accent)
          .frame(width: WalletMetrics.control, height: WalletMetrics.control)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain).disabled(!model.canRun(.asset))
      .accessibilityLabel("Add token on \(network.name)")
      .help("Add a token on \(network.name)")
      // On and off in place, like a token's visibility: off makes no requests and
      // leaves funds and addresses as they are.
      Button {
        model.run(.setNetwork(network.id, !network.enabled))
      } label: {
        Image(systemName: "power").font(.callout.weight(.semibold))
          .foregroundStyle(network.enabled ? WalletTheme.success : WalletTheme.muted)
          .frame(width: WalletMetrics.control, height: WalletMetrics.control)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain).disabled(!model.canRun(.network(network.id)))
      .accessibilityLabel(network.enabled ? "Turn off \(network.name)" : "Turn on \(network.name)")
      .help(
        network.enabled
          ? "On. Click to turn off. Funds stay as they are."
          : "Off, no requests are made. Click to turn on.")
    }
  }

  private func tokenRow(_ asset: WalletAsset) -> some View {
    let hidden = model.state.settings.hiddenAssets.contains(asset.id)
    let network = model.state.networkName(asset.chain)
    return HStack(spacing: 6) {
      Button {
        configuring = .asset(asset.id, chain: nil)
      } label: {
        HStack(spacing: 12) {
          WalletAssetGlyph(asset: asset, size: 26).frame(width: 24).opacity(hidden ? 0.4 : 1)
          Text(asset.symbol).font(.callout.weight(.medium))
            .foregroundStyle(hidden ? WalletTheme.muted : WalletTheme.text)
          Text(asset.name ?? asset.contract.map { WalletText.short($0.text) } ?? "")
            .font(.caption).foregroundStyle(WalletTheme.muted).lineLimit(1)
          Spacer(minLength: 8)
        }
        .padding(.horizontal, 10).frame(minHeight: WalletMetrics.control + 4)
      }
      .buttonStyle(WalletRowButtonStyle())
      .accessibilityLabel("\(asset.symbol) on \(network)\(hidden ? ", hidden" : ""). Edit token")
      // Takes effect at once, saving it involves only this token's switch.
      Button {
        model.setAssetVisible(asset.id, hidden)
      } label: {
        Image(systemName: hidden ? "eye.slash" : "eye").font(.callout)
          .foregroundStyle(hidden ? WalletTheme.muted : WalletTheme.text)
          .contentTransition(.symbolEffect(.replace))
          .frame(width: WalletMetrics.control, height: WalletMetrics.control)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Show \(asset.symbol) on \(network)")
      .accessibilityValue(hidden ? "Off" : "On")
      .accessibilityAddTraits(.isToggle)
      .help(hidden ? "Hidden from Wallet and Send. Click to show." : "Hide from Wallet and Send")
    }
  }
}
