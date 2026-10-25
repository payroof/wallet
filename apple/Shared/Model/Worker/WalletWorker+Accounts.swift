import Foundation

/// Accounts, receive addresses and the Payroof API: connections, address discovery
/// and access approvals. API requests run in the background.
extension WalletWorker {
  // MARK: Accounts and addresses

  func addAccount(label: String, slot: UInt32?, accent: String) throws -> Outcome {
    let wallet = try unlockedWallet()
    let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...100).contains(name.count), AccountAccent.isValid(accent) else {
      throw CocoaError(.coderInvalidValue)
    }
    let added = try wallet.addProject(label: name, slot: slot)
    _ = try wallet.address(slot: added, index: nil)
    snapshot.settings.accents[String(added)] = accent
    try save()
    return Outcome(
      notice: "Account created. It has its own receive addresses.", created: added)
  }

  /// The account's name (kept by the core) and accent color. The app follows the color
  /// while the account is current.
  func editAccount(slot: UInt32, label: String, _ accent: String) throws -> Outcome {
    let wallet = try unlockedWallet()
    let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let project = snapshot.projects.first(where: { $0.slot == slot }),
      (1...100).contains(name.count), AccountAccent.isValid(accent)
    else { throw CocoaError(.coderInvalidValue) }
    if project.label != name { try wallet.renameProject(slot: slot, label: name) }
    snapshot.settings.accents[String(slot)] = accent
    try save()
    return Outcome()
  }

  /// Deletes an account from this device: its color, cached balances, stored activity,
  /// API connections (credentials forgotten) and pending plan. Funds stay on-chain and
  /// the slot can be restored later.
  func removeAccount(slot: UInt32) throws -> Outcome {
    let wallet = try unlockedWallet()
    guard let project = snapshot.projects.first(where: { $0.slot == slot }),
      snapshot.projects.count > 1
    else { throw CocoaError(.coderInvalidValue) }
    for connection in snapshot.settings.connections where connection.slot == slot {
      _ = try disconnect(origin: connection.origin, project: connection.project)
    }
    try wallet.removeProject(slot: slot)
    snapshot.settings.accents.removeValue(forKey: String(slot))
    for key in snapshot.settings.balances.keys
    where project.paths.contains(where: { key.hasPrefix($0 + "#") }) {
      snapshot.settings.balances.removeValue(forKey: key)
    }
    for key in histories.keys where key.hasSuffix("#" + String(slot)) {
      histories.removeValue(forKey: key)
      historyRetry.removeValue(forKey: key)
    }
    try? storage?.write("history.json", encode(histories))
    snapshot.history = histories.values.flatMap(\.entries)
    if snapshot.values.removeValue(forKey: String(slot)) != nil {
      try? storage?.write("values.json", encode(snapshot.values))
    }
    if planSlot == slot {
      snapshot.plan = nil
      snapshot.planEndpoint = nil
      snapshot.planAsset = nil
      planSlot = nil
      planHashes = [:]
    }
    try save()
    return Outcome(
      notice: "Deleted \(project.label). Funds stay on-chain. Add slot \(slot) to restore it.")
  }

  /// The account's next address, or the one at `index`.
  func newAddress(slot: UInt32, index: UInt32?) throws -> Outcome {
    let wallet = try unlockedWallet()
    snapshot.address = try decode(ReceiveAddress.self, wallet.address(slot: slot, index: index))
    try save()
    return Outcome()
  }

  /// The public addresses of these derivation paths. Derivation only: nothing is added.
  func deriveAddresses(_ paths: [String]) async -> [String: String] {
    guard let wallet else { return [:] }
    let found = try? await background {
      var found: [String: String] = [:]
      for path in paths {
        guard let json = try? wallet.exactPath(path: path),
          let address = try? JSONDecoder().decode(ReceiveAddress.self, from: Data(json.utf8))
        else { continue }
        found[path] = address.address
      }
      return found
    }
    return found ?? [:]
  }

  /// The address at an exact derivation path. It is remembered for the address picker.
  func exactAddress(_ path: String) throws -> Outcome {
    let wallet = try unlockedWallet()
    let address = try decode(ReceiveAddress.self, wallet.exactPath(path: path))
    snapshot.address = address
    var paths = try decode([String: String].self, try storage?.readChecked("paths.json") ?? "{}")
    paths[address.path] = address.address
    try storage?.write("paths.json", encode(paths))
    return Outcome()
  }

  // MARK: Payroof API connections

  /// Registers the account's project, or recovers access to the one it already has
  /// (the core decides. The result says which).
  /// An account has one project: its addresses are numbered from the same root on every
  /// server, so a second project would hand out the same addresses again.
  func connect(origin: String, project: String, slot: UInt32) async throws -> Outcome {
    struct Connected: Decodable { var recovered: Bool }
    if let other = snapshot.settings.connections.first(where: {
      $0.slot == slot && $0.id != origin + "#" + project
    }) {
      throw WalletUserError(
        "This account is already connected to \(other.project). Disconnect it first.")
    }
    let wallet = try unlockedWallet()
    let json = try await background {
      try wallet.connect(origin: origin, project: project, slot: slot)
    }
    let connection = try decode(PathConnection.self, json)
    let recovered = try decode(Connected.self, json).recovered
    snapshot.settings.connections.removeAll { $0.id == connection.id }
    snapshot.settings.connections.append(connection)
    snapshot.revokedConnections.remove(connection.id)
    snapshot.settings.apiOrigin = connection.origin
    try save()
    _ = try? await discover(wallet, connection, scope: "all", pages: 10)
    try save()
    return Outcome(
      notice: recovered
        ? "Access to \(connection.project) recovered. The public watch root was verified."
        : "Account connected. The public watch root was verified.")
  }

  /// Adds the addresses the project handed out since the last look.
  func sync(origin: String, project: String, slot: UInt32) async throws -> Outcome {
    let wallet = try unlockedWallet()
    guard
      let connection = snapshot.settings.connections.first(where: {
        $0.origin == origin && $0.project == project && $0.slot == slot
      })
    else { throw CocoaError(.coderInvalidValue) }
    let added = try await discover(wallet, connection, scope: "all", pages: 10)
    try save()
    return Outcome(
      notice: added == 0
        ? "No new addresses." : "Found \(added) new \(added == 1 ? "address" : "addresses").")
  }

  /// Forgets this device's credential for a project. The project stays on the API.
  func disconnect(origin: String, project: String) throws -> Outcome {
    let wallet = try unlockedWallet()
    let key = origin + "#" + project
    try wallet.disconnect(origin: origin, project: project)
    snapshot.settings.connections.removeAll { $0.id == key }
    try save()
    var sources = try importedSources()
    if sources.removeValue(forKey: key) != nil {
      try storage?.write("sources.json", encode(sources))
    }
    snapshot.revokedConnections.remove(key)
    if snapshot.grantsConnection == key {
      snapshot.grants = []
      snapshot.grantsConnection = ""
    }
    return Outcome(
      notice:
        "Disconnected \(project). It stays on the server, so you can connect again anytime."
    )
  }

  /// Adds the project's allocated addresses to the account, a page at a time, until a
  /// page adds nothing new. Returns how many addresses were added.
  @discardableResult
  func discover(_ wallet: Wallet, _ connection: PathConnection, scope: String, pages: Int)
    async throws -> Int
  {
    struct Imported: Decodable { var addresses: [String: String] }
    var added = 0
    for _ in 0..<pages {
      let previous = try importedSources()[connection.id] ?? ""
      let before = try previous.isEmpty ? 0 : decode(Imported.self, previous).addresses.count
      let page = try await withAPIAccess(
        wallet, origin: connection.origin, project: connection.project
      ) {
        try wallet.sync(
          origin: connection.origin, project: connection.project, slot: connection.slot,
          importedJson: previous, scope: scope)
      }
      // The core added the payment addresses to the account. Only count them here.
      let imported = try decode(Imported.self, page)
      // Read again: another connection's discovery may have written meanwhile.
      var sources = try importedSources()
      sources[connection.id] = page
      try storage?.write("sources.json", encode(sources))
      let count = imported.addresses.count - before
      added += max(0, count)
      if count <= 0 { break }
    }
    return added
  }
  private func importedSources() throws -> [String: String] {
    try decode([String: String].self, try storage?.readChecked("sources.json") ?? "{}")
  }

  /// Runs an authenticated API call in the background. If it fails because the API no
  /// longer accepts this device's credential, says so plainly and how to recover,
  /// instead of a generic failure the user cannot act on.
  func withAPIAccess<T: Sendable>(
    _ wallet: Wallet, origin: String, project: String,
    _ body: @escaping @Sendable () throws -> T
  ) async throws -> T {
    do {
      return try await background(body)
    } catch {
      let key = origin + "#" + project
      let status = try? await background {
        try wallet.connectionStatus(origin: origin, project: project)
      }
      if status == "revoked" {
        snapshot.revokedConnections.insert(key)
        throw WalletUserError(
          "This device's access to \(project) was revoked. Reconnect or disconnect it.",
          revokedConnection: key)
      }
      throw error
    }
  }

  // MARK: Access requests

  /// Reviews a pairing request (`allow` false) or approves the reviewed one.
  func pairing(link: String, project: String, allow: Bool) async throws -> Outcome {
    let wallet = try unlockedWallet()
    guard allow else {
      let metadata = try await background {
        try wallet.pairing(link: link, project: project, allow: false)
      }
      let access = try decode(AccessReview.self, metadata)
      guard access.status == "pending", !access.permissions.isEmpty,
        Set(access.permissions).isSubset(of: ["references", "paths", "webhooks", "access"])
      else { throw CocoaError(.coderInvalidValue) }
      snapshot.access = access
      snapshot.accessLink = link
      snapshot.accessProject = project
      return Outcome()
    }
    guard let origin = LocalDevelopment.origin(link),
      snapshot.settings.connections.contains(where: {
        $0.project == project && $0.origin == origin
      })
    else { throw CocoaError(.coderInvalidValue) }
    _ = try await withAPIAccess(wallet, origin: origin, project: project) {
      try wallet.pairing(link: link, project: project, allow: true)
    }
    snapshot.access = nil
    return Outcome(notice: "Access approved for the permissions you reviewed.")
  }

  func dismissAccess() -> Outcome {
    snapshot.access = nil
    snapshot.accessLink = ""
    snapshot.accessProject = ""
    return Outcome()
  }

  func grants(origin: String, project: String) async throws -> Outcome {
    let wallet = try unlockedWallet()
    let json = try await withAPIAccess(wallet, origin: origin, project: project) {
      try wallet.grants(origin: origin, project: project)
    }
    snapshot.grants = try decode([AccessGrant].self, json)
    snapshot.grantsConnection = origin + "#" + project
    return Outcome()
  }

  /// Creates a credential with a subset of this device's permissions. The token goes
  /// back only in the outcome. It is neither stored nor logged.
  func createGrant(origin: String, project: String, name: String, permissions: [String])
    async throws -> Outcome
  {
    struct Created: Decodable { var token: String }
    let wallet = try unlockedWallet()
    let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !label.isEmpty, !permissions.isEmpty,
      Set(permissions).isSubset(of: ["references", "paths", "webhooks", "access"])
    else { throw CocoaError(.coderInvalidValue) }
    let json = try await withAPIAccess(wallet, origin: origin, project: project) {
      try wallet.createGrant(
        origin: origin, project: project, name: label, permissions: permissions)
    }
    let token = try decode(Created.self, json).token
    if let list = try? await withAPIAccess(
      wallet, origin: origin, project: project,
      { try wallet.grants(origin: origin, project: project) }),
      let grants = try? decode([AccessGrant].self, list)
    {
      snapshot.grants = grants
      snapshot.grantsConnection = origin + "#" + project
    }
    return Outcome(token: token)
  }

  /// Creates a Stor store for the project: the core makes a key that can only create
  /// payment addresses and hands it to Stor with the sheet. Stor's refusals become
  /// what to fix.
  func createStore(
    origin: String, project: String, stor: String, subdomain: String, source: String,
    link: String
  ) async throws -> Outcome {
    struct Created: Decodable {
      var url: String?
      var error: String?
    }
    let wallet = try unlockedWallet()
    let json = try await withAPIAccess(wallet, origin: origin, project: project) {
      try wallet.createStore(
        origin: origin, project: project, stor: stor, subdomain: subdomain, source: source)
    }
    let created = try decode(Created.self, json)
    if let error = created.error { throw WalletUserError(Stor.message(error)) }
    let kept = (try? keepStoreLink(link, origin: origin, project: project)) != nil
    // The store's key now shows under Access.
    if let list = try? await withAPIAccess(
      wallet, origin: origin, project: project,
      { try wallet.grants(origin: origin, project: project) }),
      let grants = try? decode([AccessGrant].self, list)
    {
      snapshot.grants = grants
      snapshot.grantsConnection = origin + "#" + project
    }
    guard kept else {
      return Outcome(
        notice:
          "Store created, but its link could not be saved on this device. Edit it in your Google Sheet.",
        warning: true)
    }
    return Outcome(notice: "Store created. Edit it in your Google Sheet.")
  }

  /// The URL and a new key for a store that already exists, to paste into its sheet's
  /// Payments tab. The key goes back only in the outcome. It is neither stored nor logged.
  func storeKey(origin: String, project: String, subdomain: String, link: String?) async throws
    -> Outcome
  {
    struct Issued: Decodable {
      var url: String
      var key: String
    }
    guard Stor.validSubdomain(subdomain) else {
      throw WalletUserError(Stor.message("invalid_subdomain"))
    }
    let wallet = try unlockedWallet()
    let json = try await withAPIAccess(wallet, origin: origin, project: project) {
      try wallet.createStoreKey(origin: origin, project: project, subdomain: subdomain)
    }
    let issued = try decode(Issued.self, json)
    let kept =
      link.map { (try? keepStoreLink($0, origin: origin, project: project)) != nil } ?? true
    // The store's key now shows under Access.
    if let list = try? await withAPIAccess(
      wallet, origin: origin, project: project,
      { try wallet.grants(origin: origin, project: project) }),
      let grants = try? decode([AccessGrant].self, list)
    {
      snapshot.grants = grants
      snapshot.grantsConnection = origin + "#" + project
    }
    return Outcome(
      notice: kept ? "" : "The store's link could not be saved on this device.", warning: !kept,
      token: issued.key, storeURL: issued.url)
  }

  /// Who to share a store's Google Sheet with, and where stores live.
  /// What the Stor server at `origin` asks of a new store. Nil when none answers there.
  func stor(_ origin: String) async -> Stor.Info? {
    guard let json = try? await background({ try storInfo(stor: origin) }) else {
      return nil
    }
    return try? decode(Stor.Info.self, json)
  }
  /// Remembers the Stor server stores are created on, once it has answered.
  func setStorServer(_ origin: String) throws -> Outcome {
    guard RPCText.validURL(origin) else { throw CocoaError(.coderInvalidValue) }
    snapshot.settings.storServer = origin
    try save()
    return Outcome()
  }
  /// Keeps a store's public link with its connection.
  private func keepStoreLink(_ link: String, origin: String, project: String) throws {
    let key = origin + "#" + project
    guard !(snapshot.settings.storeLinks[key]?.contains(link) ?? false) else { return }
    snapshot.settings.storeLinks[key, default: []].append(link)
    try save()
  }

  func revokeGrant(origin: String, project: String, id: String) async throws -> Outcome {
    let wallet = try unlockedWallet()
    let key = origin + "#" + project
    try await withAPIAccess(wallet, origin: origin, project: project) {
      try wallet.revokeGrant(origin: origin, project: project, id: id)
    }
    snapshot.grants.removeAll { $0.id == id }
    snapshot.grantsConnection = key
    // The credential may have been the one this device itself uses.
    let status = try? await background {
      try wallet.connectionStatus(origin: origin, project: project)
    }
    guard status == "revoked" else { return Outcome(notice: "Access revoked.") }
    snapshot.revokedConnections.insert(key)
    return Outcome(
      notice:
        "Access revoked. It was this device's own access, so reconnect \(project) to keep using it.",
      warning: true)
  }
}
