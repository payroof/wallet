import Foundation

/// Everything the app shows, as the worker last left it. The model replaces its copy
/// only with a newer one (`revision`): results of concurrent commands may arrive in any
/// order.
struct WalletSnapshot: Sendable {
  var revision = 0
  var exists = false
  var unlocked = false
  var projects: [ProjectCard] = []
  var settings = LocalSettings()
  var address: ReceiveAddress?
  /// The plan under review, with the endpoint it was made on and the asset it sends.
  var plan: SendPlan?
  var planEndpoint: String?
  var planAsset: WalletAsset?
  var access: AccessReview?
  var accessLink = ""
  var accessProject = ""
  var grants: [AccessGrant] = []
  var grantsConnection = ""
  /// Connections whose stored credential the API no longer accepts. Kept in
  /// memory only: the next failed call after a restart detects it again.
  var revokedConnections: Set<String> = []
  var endpointHealth: [String: EndpointHealth] = [:]
  /// Per account (by slot), the networks whose balances or activity could not be read
  /// in that account's last refresh. One account's failed read never marks another's.
  var staleNetworks: [UInt32: Set<ChainID>] = [:]
  /// Transfers found on-chain at the accounts' addresses.
  var history: [HistoryEntry] = []
  /// Each account's USD total over time (`ValueHistory`), keyed by slot.
  var values: [String: [ValuePoint]] = [:]
  /// Ids of the providers that have a key of the user's. Never the keys themselves.
  var providers: Set<String> = []
  /// Ids of the providers with a built-in key on at least one of the networks.
  var presetProviders: Set<String> = []
  /// The virtual endpoints those keys (or built-in ones) add, by chain.
  var providerEndpoints: [ChainID: [RPCEndpoint]] = [:]
  /// Sent and found activity, newest first. One account's, or every account's. A
  /// transfer this device signed is listed once, from its own record.
  func activity(slot: UInt32? = nil) -> [ActivityItem] {
    let sent = settings.transfers.filter { slot == nil || $0.slot == slot }
    let signed = Set(settings.transfers.map { $0.id.lowercased() })
    let known = Set(assets.map(\.id))
    let found = history.filter {
      (slot == nil || $0.slot == slot) && known.contains($0.asset)
        && !signed.contains($0.transaction)
    }
    return (sent.map(ActivityItem.sent) + found.map(ActivityItem.chain)).sorted {
      $0.date > $1.date
    }
  }
  func historyAmount(_ entry: HistoryEntry) -> String {
    assetAmount(entry.amount, asset: entry.asset)
  }
  var networks: [WalletNetwork] { settings.networks }
  var assets: [WalletAsset] { settings.assets }
  func network(_ chain: ChainID) -> WalletNetwork? { settings.networks.first { $0.id == chain } }
  func networkName(_ chain: ChainID) -> String { network(chain)?.name ?? chain.rawValue }
  /// The color and logo of a network, neutral when it isn't configured.
  func networkArt(_ chain: ChainID) -> WalletArt {
    network(chain)?.art ?? .neutral
  }
  /// The single endpoint used for balances, review, signing and receipts on a chain:
  /// the selected one, if the network is on and the endpoint is still configured.
  func endpoint(for chain: ChainID) -> String? {
    guard let network = network(chain), network.enabled, let url = network.endpoint,
      endpoints(for: chain).contains(where: { $0.url == url })
    else { return nil }
    return url
  }
  /// The network's own endpoints, then those its provider keys add.
  func endpoints(for chain: ChainID) -> [RPCEndpoint] {
    (network(chain)?.endpoints ?? []) + (providerEndpoints[chain] ?? [])
  }
  /// Key of an endpoint's last check in `endpointHealth`.
  static func healthKey(_ chain: ChainID, _ url: String) -> String { chain.rawValue + " " + url }
  func health(_ url: String, chain: ChainID) -> EndpointHealth? {
    endpointHealth[Self.healthKey(chain, url)]
  }
  func endpointName(_ url: String, chain: ChainID) -> String {
    endpoints(for: chain).first { $0.url == url }?.name ?? RPCText.host(url)
  }
  /// Assets on networks that have an endpoint and that the user hasn't hidden.
  var usableAssets: [WalletAsset] {
    assets.filter {
      endpoint(for: $0.chain) != nil && !settings.hiddenAssets.contains($0.id)
    }
  }
  var connectedNetworks: [WalletNetwork] { networks.filter { endpoint(for: $0.id) != nil } }
  func nativeAsset(_ chain: ChainID) -> WalletAsset? {
    assets.first { $0.chain == chain && $0.isNative }
  }
  func cachedBalance(path: String, asset: AssetID) -> CachedBalance? {
    settings.balances[LocalSettings.balanceKey(path: path, asset: asset)]
  }
  /// An amount of an asset as the wallet shows it: rounded (`ExactAmount.rounded`).
  func assetAmount(
    _ atomic: String, asset id: AssetID, rounding: ExactAmount.Rounding = .nearest
  ) -> String {
    guard let asset = assets.first(where: { $0.id == id }) else { return atomic + " atomic units" }
    return ExactAmount.rounded(atomic, decimals: asset.decimals, rounding: rounding) + " "
      + asset.symbol
  }
  /// An amount's USD value, when the asset has a price oracle and a price was read.
  func usd(_ atomic: String, asset: WalletAsset) -> String? {
    guard asset.price != nil, let price = settings.prices[asset.id],
      let value = ExactAmount.usd(atomic, decimals: asset.decimals, price: price.usd)
    else { return nil }
    return WalletPortfolio.currency(value)
  }
  func feeAmount(_ atomic: String, chain: ChainID) -> String {
    guard let asset = nativeAsset(chain) else { return atomic + " atomic units" }
    // Fees shown are limits or costs: never understated.
    return assetAmount(atomic, asset: asset.id, rounding: .up)
  }
  func transferAmount(_ transfer: LocalTransfer) -> String {
    let asset = transfer.assetSnapshot
    if asset.id == transfer.asset, (0...36).contains(asset.decimals) {
      return ExactAmount.rounded(transfer.amount, decimals: asset.decimals) + " " + asset.symbol
    }
    return transfer.amount + " atomic units"
  }
}
