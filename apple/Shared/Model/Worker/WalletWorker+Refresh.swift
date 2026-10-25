import Foundation

/// Reading balances, activity, receipts, new addresses and prices, only when the user
/// asks (or a sent transfer settles). A refresh is a run of steps planned up front.
/// Each waits on the network in the background, so it never holds up a command.
extension WalletWorker {
  /// What a refresh of these accounts reads. `chains` limits it to some networks.
  func refreshPlan(slots: Set<UInt32>, chains: Set<ChainID>?) -> RefreshPlan {
    let used = Set(snapshot.usableAssets.map(\.chain)).filter { chains?.contains($0) ?? true }
    var plan = RefreshPlan()
    plan.chains = snapshot.networks.map(\.id).filter(used.contains)
    plan.assets = Dictionary(grouping: snapshot.usableAssets.filter { used.contains($0.chain) }) {
      $0.chain
    }.mapValues { $0.map(\.id) }
    plan.slots = snapshot.projects.map(\.slot).filter { slot in
      slots.contains(slot)
        && snapshot.projects.first(where: { $0.slot == slot })?.paths.isEmpty == false
    }
    plan.transfers = snapshot.settings.transfers.contains {
      $0.status == "pending" && used.contains($0.chain)
    }
    guard chains == nil else { return plan }
    plan.connections = snapshot.settings.connections
      .filter { slots.contains($0.slot) && !snapshot.revokedConnections.contains($0.id) }
      .map(\.id)
    plan.prices = snapshot.usableAssets.contains { $0.price != nil }
    return plan
  }

  /// Receipts for sent transfers still pending. Without a reporter it is silent.
  func refreshTransfers(_ report: RefreshReporter?) async -> WalletSnapshot {
    guard let wallet else { return published() }
    for transfer in snapshot.settings.transfers where transfer.status == "pending" {
      let urls = candidates(transfer.chain, first: transfer.endpoint)
      let names = Dictionary(
        urls.map { ($0, snapshot.endpointName($0, chain: transfer.chain)) },
        uniquingKeysWith: { first, _ in first })
      let title = snapshot.networkName(transfer.chain)
      let status = try? await background {
        Self.receipt(wallet, transfer, urls: urls) { report?(title, .transfers, names[$0] ?? "") }
      }
      if let status { setStatus(status, of: transfer.id) }
    }
    try? save()
    return published()
  }

  /// New payment addresses from one API connection. False when the API couldn't be read.
  func refreshAddresses(_ id: String, report: RefreshReporter) async -> (WalletSnapshot, Bool) {
    guard let wallet, let connection = snapshot.settings.connections.first(where: { $0.id == id })
    else { return (published(), false) }
    report(connection.project, .addresses, RPCText.host(connection.origin))
    let read = (try? await discover(wallet, connection, scope: "all", pages: 10)) != nil
    try? save()
    try? refreshProjects(wallet)
    return (published(), read)
  }

  /// The network's endpoints that answer for it, in the user's order (the selected one
  /// first). All are asked at once. Once one has answered the others get a moment more,
  /// so a dead endpoint never holds the refresh back.
  func refreshEndpoints(_ chain: ChainID, report: RefreshReporter) async -> [String] {
    let name = snapshot.networkName(chain)
    let urls = candidates(chain)
    for url in urls { report(name, .connecting, snapshot.endpointName(url, chain: chain)) }
    guard !urls.isEmpty else { return [] }
    // Unstructured, so the answers that are still out never hold the refresh back. They
    // only record the endpoint's health when they arrive. `nil` means the grace is over.
    let (probes, continuation) = AsyncStream.makeStream(of: (url: String, ok: Bool)?.self)
    for url in urls {
      Task { continuation.yield((url, await verify(chain: chain, url: url))) }
    }
    var answered: Set<String> = []
    var waiting = urls.count
    var timer: Task<Void, Never>?
    for await probe in probes {
      guard let probe else { break }
      waiting -= 1
      if probe.ok {
        answered.insert(probe.url)
        if timer == nil {
          timer = Task {
            try? await Task.sleep(for: Self.endpointGrace)
            continuation.yield(nil)
          }
        }
      }
      if waiting == 0 { break }
    }
    timer?.cancel()
    continuation.finish()
    return urls.filter(answered.contains)
  }
  static let endpointGrace = Duration.seconds(1)

  /// One asset's balance at every address of the accounts, asked of `endpoints` in turn
  /// from number `first` on (so assets spread over them). The next answers when one
  /// fails. False when none could read it. The last values stay.
  func refreshBalance(
    _ assetID: AssetID, slots: Set<UInt32>, endpoints: [String], first: Int,
    report: RefreshReporter
  ) async -> (WalletSnapshot, Bool) {
    guard let wallet, let asset = snapshot.usableAssets.first(where: { $0.id == assetID }),
      !endpoints.isEmpty
    else { return (published(), true) }
    let title = snapshot.networkName(asset.chain) + " " + asset.symbol
    var read = true
    for project in snapshot.projects where slots.contains(project.slot) && !project.paths.isEmpty {
      // Per address, so the overview can show where each balance is held.
      let paths = project.paths
      var values: [String]?
      for attempt in 0..<endpoints.count {
        let endpoint = endpoints[(first + attempt) % endpoints.count]
        report(title, .balances, snapshot.endpointName(endpoint, chain: asset.chain))
        let answer = try? await background({
          try wallet.queryAddressBalances(
            endpoint: endpoint, chain: asset.chain.rawValue, asset: asset.id.rawValue,
            paths: paths)
        })
        if let answer, answer.count == paths.count {
          values = answer
          break
        }
      }
      guard let values else {
        read = false
        continue
      }
      let date = Date()
      for (path, atomic) in zip(paths, values) {
        snapshot.settings.balances[LocalSettings.balanceKey(path: path, asset: asset.id)] =
          CachedBalance(atomic: atomic, date: date)
      }
    }
    try? save()
    return (published(), read)
  }

  /// One account's activity on one network: new transfers from the network's activity
  /// sources, added to the stored history. False when it could not be read. The
  /// history keeps its last state. After a failure the network is left alone for a
  /// while unless `force`.
  func refreshActivity(
    _ chain: ChainID, slot: UInt32, endpoint: String, force: Bool, report: RefreshReporter
  ) async -> (WalletSnapshot, Bool) {
    guard let wallet, let project = snapshot.projects.first(where: { $0.slot == slot }) else {
      return (published(), true)
    }
    let assets = snapshot.usableAssets.filter { $0.chain == chain }.map(\.id.rawValue)
    guard !assets.isEmpty, !project.paths.isEmpty else { return (published(), true) }
    let key = chain.rawValue + "#" + String(slot)
    if !force, let retry = historyRetry[key], retry > Date() { return (published(), false) }
    let cursor = histories[key]?.cursor ?? ""
    let name = snapshot.networkName(chain)
    let sources = historySources(chain: chain.rawValue, keys: Array(snapshot.providers))
    let paths = project.paths
    var json: String?
    // The verified endpoint first, then the network's others: endpoints differ in
    // which log queries they serve. Keyed sources come before the RPC on the first try.
    for (attempt, url) in candidates(chain, first: endpoint).enumerated() {
      let first = sources.first ?? "RPC"
      report(
        name, .activity,
        attempt == 0 && first != "RPC" ? first : snapshot.endpointName(url, chain: chain))
      json = try? await background {
        try wallet.history(
          endpoint: url, chain: chain.rawValue, assets: assets, paths: paths,
          cursor: cursor)
      }
      if json != nil { break }
    }
    guard let json, let scan = try? decode(HistoryScan.self, json) else {
      historyRetry[key] = Date().addingTimeInterval(Self.historyBackoff)
      return (published(), false)
    }
    // Read again after the request: the stored history may have changed meanwhile.
    var record = histories[key] ?? StoredHistory()
    var entries = Dictionary(uniqueKeysWithValues: record.entries.map { ($0.id, $0) })
    let now = Date()
    for var entry in scan.entries {
      entry.slot = slot
      entry.seen = entries[entry.id]?.seen ?? now
      entries[entry.id] = entry
    }
    record.entries = Array(entries.values.sorted { $0.date > $1.date }.prefix(500))
    record.cursor = scan.cursor
    histories[key] = record
    historyRetry[key] = nil
    try? storage?.write("history.json", encode(histories))
    snapshot.history = histories.values.flatMap(\.entries)
    return (published(), true)
  }

  /// USD prices of every priced asset, one request per oracle URL. True when prices
  /// were wanted and none could be read.
  func refreshPrices(_ report: RefreshReporter) async -> (WalletSnapshot, Bool) {
    let sourced = snapshot.usableAssets.compactMap { asset in asset.price.map { (asset.id, $0) } }
    var read = 0
    for (url, group) in Dictionary(grouping: sourced, by: { $0.1.url }) {
      report("", .prices, RPCText.host(url))
      let fields = Array(Set(group.map { $0.1.field })).sorted()
      guard let values = try? await background({ try prices(url: url, fields: fields) }),
        values.count == fields.count
      else { continue }
      let date = Date()
      for (id, source) in group {
        guard let index = fields.firstIndex(of: source.field), let usd = values[index] else {
          continue
        }
        snapshot.settings.prices[id] = CachedPrice(usd: usd, date: date)
        read += 1
      }
    }
    try? save()
    return (published(), !sourced.isEmpty && read == 0)
  }

  /// Marks which of the refreshed networks could not be read, and records the account's
  /// USD total for its balance history.
  func refreshFinished(slot: UInt32, chains: [ChainID], stale: Set<ChainID>) -> WalletSnapshot {
    var unread = snapshot.staleNetworks[slot] ?? []
    unread.subtract(chains)
    unread.formUnion(stale)
    snapshot.staleNetworks[slot] = unread.isEmpty ? nil : unread
    if let account = snapshot.projects.first(where: { $0.slot == slot }),
      let total = WalletPortfolio.value(snapshot, account: account)
    {
      let key = String(slot)
      snapshot.values[key] = ValueHistory.record(
        total, at: Date(), in: snapshot.values[key] ?? [])
      try? storage?.write("values.json", encode(snapshot.values))
    }
    return published()
  }
}
