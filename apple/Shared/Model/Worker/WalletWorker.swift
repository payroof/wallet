import Foundation

/// The wallet's single owner of state and the only caller of the Rust core. No secret
/// and no blocking native call ever reaches a SwiftUI view or the main actor.
///
/// Concurrency. Every core call that waits (a network request, Argon2 key stretching)
/// runs off this actor through `background(_:)`, and the core itself releases its lock
/// before it sends a request. So while one command or refresh step waits on a slow
/// endpoint, any other command runs at once. The price is actor reentrancy: across an
/// `await`, other commands may change `snapshot`. Code after an `await` therefore
/// looks state up again by identity (a chain, a transfer ID), never by a position or a
/// value read before it, and each command reports its own message (`Outcome`)
/// instead of sharing one.
actor WalletWorker {
  var wallet: Wallet?
  var storage: VaultStorage?
  var snapshot = WalletSnapshot()
  /// The account the reviewed plan sends from, for its Activity entries.
  var planSlot: UInt32?
  /// The transaction hash of each plan step already broadcast, by step index.
  var planHashes: [Int: String] = [:]
  /// Stored activity per network and account, keyed `chain#slot`.
  var histories: [String: StoredHistory] = [:]
  /// When a network whose activity could not be read is tried again on its own. A
  /// network with no usable source (no keyed source, a public node that refuses log
  /// queries) would otherwise fail on every refresh.
  var historyRetry: [String: Date] = [:]
  static let historyBackoff: TimeInterval = 900

  /// What a command reports besides the new state.
  struct Outcome {
    var notice = ""
    /// The notice is a problem the user should act on, not a success.
    var warning = false
    /// Recovery words: generated for a new wallet, or revealed again with the PIN.
    var words: String?
    /// The transaction a send step broadcast.
    var hash: String?
    /// A newly created API token, shown once. Never part of the snapshot.
    var token: String?
    /// The project URL that goes with a store's new key.
    var storeURL: String?
    /// The most that can be sent of an asset (atomic), as Review would plan it.
    var maximum: SendLimit?
    /// The slot of the account this command created.
    var created: UInt32?
  }

  func perform(_ command: WalletCommand) async throws -> WorkerResult {
    let outcome: Outcome
    switch command {
    case .load: outcome = try load()
    case .generate: outcome = Outcome(words: try generateMnemonic())
    case .create(let words, let pin): outcome = try await create(words: words, pin: pin)
    case .unlock(let pin): outcome = try await unlock(pin: pin)
    case .deviceUnlock: outcome = try await unlockWithDevice()
    case .enableDeviceUnlock(let policy): outcome = try enableDeviceUnlock(policy)
    case .disableDeviceUnlock: outcome = try disableDeviceUnlock()
    case .lock: outcome = lock()
    case .pin(let old, let new): outcome = try await changePIN(old: old, new: new)
    case .revealWords(let pin): outcome = Outcome(words: try await recoveryWords(pin: pin))
    case .project(let label, let slot, let accent):
      outcome = try addAccount(label: label, slot: slot, accent: accent)
    case .editAccount(let slot, let label, let accent):
      outcome = try editAccount(slot: slot, label: label, accent)
    case .removeAccount(let slot): outcome = try removeAccount(slot: slot)
    case .address(let slot, let index): outcome = try newAddress(slot: slot, index: index)
    case .exact(let path): outcome = try exactAddress(path)
    case .connect(let origin, let project, let slot):
      outcome = try await connect(origin: origin, project: project, slot: slot)
    case .sync(let origin, let project, let slot):
      outcome = try await sync(origin: origin, project: project, slot: slot)
    case .disconnect(let origin, let project):
      outcome = try disconnect(origin: origin, project: project)
    case .pairing(let link, let project, let allow):
      outcome = try await pairing(link: link, project: project, allow: allow)
    case .dismissAccess: outcome = dismissAccess()
    case .grants(let origin, let project):
      outcome = try await grants(origin: origin, project: project)
    case .revokeGrant(let origin, let project, let id):
      outcome = try await revokeGrant(origin: origin, project: project, id: id)
    case .createStore(let origin, let project, let stor, let subdomain, let source, let link):
      outcome = try await createStore(
        origin: origin, project: project, stor: stor, subdomain: subdomain, source: source,
        link: link)
    case .storeKey(let origin, let project, let subdomain, let link):
      outcome = try await storeKey(
        origin: origin, project: project, subdomain: subdomain, link: link)
    case .storServer(let origin): outcome = try setStorServer(origin)
    case .createGrant(let origin, let project, let name, let permissions):
      outcome = try await createGrant(
        origin: origin, project: project, name: name, permissions: permissions)
    case .addEndpoint(let chain, let url, let replacing):
      outcome = try await addEndpoint(chain: chain, url: url, replacing: replacing)
    case .selectEndpoint(let chain, let url): outcome = try selectEndpoint(chain: chain, url: url)
    case .deleteEndpoint(let chain, let url): outcome = try deleteEndpoint(chain: chain, url: url)
    case .probeEndpoints(let chain): outcome = await probeEndpoints(chain: chain)
    case .setNetwork(let chain, let on): outcome = try setNetwork(chain: chain, on: on)
    case .saveNetwork(let chain, let name, let mode, let explorer, let currency, let look):
      outcome = try saveNetwork(
        chain: chain, name: name, mode: mode, explorer: explorer, currency: currency,
        look: look)
    case .removeNetwork(let chain): outcome = try removeNetwork(chain: chain)
    case .providerKey(let provider, let key): outcome = try setProviderKey(provider, key: key)
    case .saveAsset(let asset, let replacing): outcome = try saveAsset(asset, replacing: replacing)
    case .removeAsset(let id): outcome = try removeAsset(id: id)
    case .assetVisible(let id, let visible): outcome = try setAssetVisible(id: id, visible)
    case .sendMaximum(let slot, let asset, let recipient, let endpoint, let prefer):
      outcome = try await sendMaximum(
        slot: slot, assetID: asset, recipient: recipient, endpoint: endpoint, prefer: prefer)
    case .plan(let slot, let asset, let recipient, let amount, let endpoint, let prefer):
      outcome = try await plan(
        slot: slot, assetID: asset, recipient: recipient, amount: amount, endpoint: endpoint,
        prefer: prefer)
    case .confirmPlan(let allow): outcome = try confirmPlan(allow: allow)
    case .step(let index): outcome = try await step(index: index)
    }
    return try result(outcome)
  }

  /// The state as it is now, numbered so a host can tell it from an older one that
  /// arrives later, with what the command reports.
  func result(_ outcome: Outcome = Outcome()) throws -> WorkerResult {
    snapshot.exists = wallet != nil
    if let wallet {
      snapshot.unlocked = wallet.isUnlocked()
      try refreshProjects(wallet)
      refreshProviders(wallet)
    }
    return WorkerResult(
      snapshot: published(), notice: outcome.notice, warning: outcome.warning,
      words: outcome.words, hash: outcome.hash, token: outcome.token,
      storeURL: outcome.storeURL, maximum: outcome.maximum, created: outcome.created)
  }
  /// The snapshot handed to the host, with the next revision.
  func published() -> WalletSnapshot {
    snapshot.revision += 1
    return snapshot
  }

  // MARK: Shared helpers

  /// Runs a blocking core call off this actor, so commands started meanwhile never
  /// wait behind it. `work` must not touch actor state: it gets values, not `self`.
  nonisolated func background<T: Sendable>(
    _ work: @escaping @Sendable () throws -> T
  ) async throws -> T {
    try await Task.detached(priority: .userInitiated) { try work() }.value
  }
  /// The unlocked wallet. Commands that need one fail plainly without it.
  func unlockedWallet() throws -> Wallet {
    guard let wallet else { throw CocoaError(.coderInvalidValue) }
    return wallet
  }
  /// The core's initial configuration, used only to seed a new wallet's settings.
  func defaults() throws -> WalletDefaults {
    try decode(WalletDefaults.self, defaultConfiguration())
  }
  func networkIndex(_ chain: ChainID) throws -> Int {
    guard let index = snapshot.settings.networks.firstIndex(where: { $0.id == chain }) else {
      throw CocoaError(.coderInvalidValue)
    }
    return index
  }
  func decode<T: Decodable>(_ type: T.Type, _ value: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(value.utf8))
  }
  func encode<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }
  /// Writes the vault, the accounts and the settings.
  func save() throws {
    guard let wallet, let storage else { throw CocoaError(.fileWriteNoPermission) }
    try storage.write("vault.json", wallet.vaultJson())
    try storage.write("projects.json", wallet.publicJson())
    try storage.write("settings.json", encode(snapshot.settings))
  }
  func refreshProjects(_ wallet: Wallet) throws {
    struct PublicState: Decodable { var visible: [ProjectCard] }
    snapshot.projects = try decode(PublicState.self, wallet.publicJson()).visible
  }
}

struct WorkerResult: Sendable {
  var snapshot: WalletSnapshot
  /// What the command reports to the user. Empty for none.
  var notice: String
  var warning: Bool
  var words: String?
  /// The transaction a send step broadcast.
  var hash: String?
  var token: String?
  var storeURL: String?
  var maximum: SendLimit?
  /// The slot of the account the command created. The snapshot contains it.
  var created: UInt32?
}
