import Foundation

/// Networks, their RPC endpoints and provider keys. Endpoint checks run in the
/// background. Checking all of a network's endpoints asks them all at once.
extension WalletWorker {
  // MARK: Endpoints

  /// Adds an endpoint, or replaces `replacing`, after checking it serves the chain,
  /// and selects it.
  func addEndpoint(chain: ChainID, url raw: String, replacing: String?) async throws -> Outcome {
    let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard url.count <= 2048, RPCText.validURL(url) else {
      throw WalletUserError("Enter a full HTTPS URL, for example https://rpc.example.com.")
    }
    try checkEndpointChange(chain: chain, url: url, replacing: replacing)
    guard await verify(chain: chain, url: url) else {
      throw WalletUserError(
        "Couldn't verify this endpoint. It is unreachable or doesn't serve \(snapshot.networkName(chain)). Nothing was saved."
      )
    }
    // The list may have changed while the endpoint was checked: validate it again.
    try checkEndpointChange(chain: chain, url: url, replacing: replacing)
    let index = try networkIndex(chain)
    var network = snapshot.settings.networks[index]
    if let replacing, let position = network.endpoints.firstIndex(where: { $0.url == replacing }) {
      let previous = network.endpoints[position]
      // A name the user never changed follows the host. A chosen name is kept.
      let name = previous.name == RPCText.host(previous.url) ? RPCText.host(url) : previous.name
      network.endpoints[position] = RPCEndpoint(name: name, url: url)
      if network.endpoint == replacing || network.endpoint == nil { network.endpoint = url }
    } else {
      network.endpoints.append(RPCEndpoint(name: RPCText.host(url), url: url))
      network.endpoint = url
    }
    network.enabled = true
    snapshot.settings.networks[index] = network
    try save()
    return Outcome(
      notice:
        "Endpoint verified for \(network.name) and selected. Chain identity is still checked before every request."
    )
  }
  private func checkEndpointChange(chain: ChainID, url: String, replacing: String?) throws {
    let network = snapshot.settings.networks[try networkIndex(chain)]
    if let replacing, !network.endpoints.contains(where: { $0.url == replacing }) {
      throw CocoaError(.coderInvalidValue)
    }
    guard !network.endpoints.contains(where: { $0.url == url && $0.url != replacing }) else {
      throw WalletUserError("This endpoint is already in the list.")
    }
  }

  func selectEndpoint(chain: ChainID, url: String) throws -> Outcome {
    let index = try networkIndex(chain)
    guard snapshot.endpoints(for: chain).contains(where: { $0.url == url }) else {
      throw CocoaError(.coderInvalidValue)
    }
    snapshot.settings.networks[index].endpoint = url
    snapshot.settings.networks[index].enabled = true
    try save()
    return Outcome(
      notice: "\(snapshot.networkName(chain)) now uses \(snapshot.endpointName(url, chain: chain))."
    )
  }

  func deleteEndpoint(chain: ChainID, url: String) throws -> Outcome {
    let index = try networkIndex(chain)
    var network = snapshot.settings.networks[index]
    guard network.endpoints.contains(where: { $0.url == url }) else {
      throw CocoaError(.coderInvalidValue)
    }
    network.endpoints.removeAll { $0.url == url }
    if network.endpoint == url { network.endpoint = network.endpoints.first?.url }
    snapshot.settings.networks[index] = network
    try save()
    let notice =
      snapshot.endpoint(for: chain).map {
        "Endpoint removed. \(network.name) now uses \(snapshot.endpointName($0, chain: chain))."
      }
      ?? "Endpoint removed. \(network.name) has no endpoint, so its balances and sending are off."
    return Outcome(notice: notice)
  }

  /// Checks every endpoint of a network at the same time: the wait is the slowest
  /// endpoint's, not their sum.
  func probeEndpoints(chain: ChainID) async -> Outcome {
    let urls = snapshot.endpoints(for: chain).map(\.url)
    let results = await withTaskGroup(
      of: (String, Bool).self, returning: [String: Bool].self
    ) { group in
      for url in urls {
        group.addTask { (url, await self.reachable(chain: chain, url: url)) }
      }
      var found: [String: Bool] = [:]
      for await (url, verified) in group { found[url] = verified }
      return found
    }
    let date = Date()
    for (url, verified) in results {
      snapshot.endpointHealth[WalletSnapshot.healthKey(chain, url)] = EndpointHealth(
        verified: verified, date: date)
    }
    let verified = results.values.filter { $0 }.count
    return Outcome(
      notice:
        "\(verified) of \(urls.count) endpoints reachable and serving \(snapshot.networkName(chain))."
    )
  }

  /// Whether `url` answers for `chain`, recorded for the endpoint list.
  func verify(chain: ChainID, url: String) async -> Bool {
    let verified = await reachable(chain: chain, url: url)
    snapshot.endpointHealth[WalletSnapshot.healthKey(chain, url)] = EndpointHealth(
      verified: verified, date: Date())
    return verified
  }
  /// Connectivity and chain identity only: the core validates the URL policy and
  /// checks `eth_chainId`. No address or secret is involved.
  private func reachable(chain: ChainID, url: String) async -> Bool {
    guard let wallet else { return false }
    return
      (try? await background { try wallet.checkEndpoint(endpoint: url, chain: chain.rawValue) })
      != nil
  }

  /// The given or selected endpoint first, then the network's others: every RPC of a
  /// network is a fallback for the rest. The core checks the chain on every request.
  func candidates(_ chain: ChainID, first: String? = nil) -> [String] {
    let lead = first ?? snapshot.endpoint(for: chain)
    return (lead.map { [$0] } ?? [])
      + snapshot.endpoints(for: chain).map(\.url).filter { $0 != lead }
  }

  // MARK: Networks

  func setNetwork(chain: ChainID, on: Bool) throws -> Outcome {
    let index = try networkIndex(chain)
    snapshot.settings.networks[index].enabled = on
    try save()
    let name = snapshot.networkName(chain)
    return Outcome(
      notice: on ? "\(name) is on." : "\(name) is off. Funds and addresses are unchanged.")
  }

  /// Adds a network, or updates its name, fee mode, and explorer. A new
  /// network may also get its coin, as the network's native asset.
  func saveNetwork(
    chain: ChainID, name rawName: String, mode: TransactionMode, explorer rawExplorer: String,
    currency: String?, look rawLook: WalletLook? = nil
  ) throws -> Outcome {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    let explorerText = rawExplorer.trimmingCharacters(in: .whitespacesAndNewlines)
    let explorer = explorerText.isEmpty ? nil : explorerText
    guard explorer.map(RPCText.validURL) ?? true else {
      throw WalletUserError("Use an HTTPS explorer URL.")
    }
    guard !name.isEmpty, name.count <= 60 else { throw CocoaError(.coderInvalidValue) }
    let look = try rawLook?.validated()
    let notice: String
    if let index = snapshot.settings.networks.firstIndex(where: { $0.id == chain }) {
      snapshot.settings.networks[index].name = name
      snapshot.settings.networks[index].transactionMode = mode
      snapshot.settings.networks[index].explorer = explorer
      if let look {
        snapshot.settings.networks[index].color = look.color
        snapshot.settings.networks[index].logo = look.logo
      }
      notice = "\(name) updated."
    } else {
      let color = look?.color ?? AccountAccent.random(avoiding: snapshot.networks.map(\.color))
      snapshot.settings.networks.append(
        WalletNetwork(
          id: chain, name: name, transactionMode: mode, endpoints: [], endpoint: nil,
          enabled: true, explorer: explorer, color: color, logo: look?.logo))
      let symbol = currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !symbol.isEmpty, symbol.count <= 20, snapshot.nativeAsset(chain) == nil {
        snapshot.settings.assets.append(
          WalletAsset(
            id: .native(on: chain), symbol: symbol, decimals: 18, color: color))
      }
      notice = "\(name) added. Add an RPC endpoint to use it."
    }
    try save()
    return Outcome(notice: notice)
  }

  /// Removes a network with its assets, cached balances and activity.
  func removeNetwork(chain: ChainID) throws -> Outcome {
    let index = try networkIndex(chain)
    let name = snapshot.settings.networks[index].name
    snapshot.settings.networks.remove(at: index)
    let removed = Set(snapshot.settings.assets.filter { $0.chain == chain }.map(\.id))
    snapshot.settings.assets.removeAll { removed.contains($0.id) }
    snapshot.settings.hiddenAssets.removeAll { removed.contains($0) }
    for key in snapshot.settings.balances.keys
    where removed.contains(where: { key.hasSuffix("#" + $0.rawValue) }) {
      snapshot.settings.balances.removeValue(forKey: key)
    }
    for key in histories.keys where key.hasPrefix(chain.rawValue + "#") {
      histories.removeValue(forKey: key)
    }
    try? storage?.write("history.json", encode(histories))
    snapshot.history = histories.values.flatMap(\.entries)
    try save()
    return Outcome(notice: "\(name) removed from this wallet. On-chain funds are unaffected.")
  }

  // MARK: Provider keys

  /// Stores a provider key in the vault (already accepted by the provider), or removes
  /// it when nil. Networks that used its endpoint fall back to their first one.
  func setProviderKey(_ provider: KeyProvider, key: String?) throws -> Outcome {
    let wallet = try unlockedWallet()
    let value = key?.trimmingCharacters(in: .whitespacesAndNewlines)
    try wallet.setProviderKey(provider: provider.id, key: value?.isEmpty == true ? nil : value)
    guard value?.isEmpty ?? true else { return Outcome(notice: "\(provider.title) key saved.") }
    for index in snapshot.settings.networks.indices
    where snapshot.settings.networks[index].endpoint == provider.reference {
      snapshot.settings.networks[index].endpoint =
        snapshot.settings.networks[index].endpoints.first?.url
    }
    try save()
    return Outcome(notice: "\(provider.title) key removed.")
  }

  /// Which providers have a key, and the endpoints those keys add: the user's own on
  /// every chain the provider serves, built-in ones only where they serve. Keys stay
  /// in Rust.
  func refreshProviders(_ wallet: Wallet) {
    guard snapshot.unlocked, let ids = try? wallet.providerKeys() else {
      snapshot.providers = []
      snapshot.presetProviders = []
      snapshot.providerEndpoints = [:]
      return
    }
    snapshot.providers = Set(ids)
    snapshot.presetProviders = []
    snapshot.providerEndpoints = snapshot.networks.reduce(into: [:]) { result, network in
      let presets = presetProviders(chain: network.id.rawValue)
      snapshot.presetProviders.formUnion(presets)
      result[network.id] = rpcProviders(chain: network.id.rawValue)
        .filter { ids.contains($0) || presets.contains($0) }
        .compactMap {
          KeyProvider(rawValue: $0).map { RPCEndpoint(name: $0.title, url: $0.reference) }
        }
    }
  }

  /// Whether the provider itself accepts the key. Nothing is stored.
  func accepts(_ provider: KeyProvider, key: String) async -> Bool {
    (try? await background { try verifyProviderKey(provider: provider.id, key: key) }) != nil
  }

  /// A token contract's own details from the network's selected endpoint.
  func readToken(chain: ChainID, contract: EVMAddress) async -> TokenDetails? {
    guard let wallet, let endpoint = snapshot.endpoint(for: chain) else { return nil }
    return try? await background {
      try wallet.readToken(
        endpoint: endpoint, chain: chain.rawValue, contract: contract.text)
    }
  }
}
