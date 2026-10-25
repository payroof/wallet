import Foundation
import Observation

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum WalletLoadState: Equatable { case loading, ready, failed }

/// The app's view of the wallet, on the main actor. Views read `state` and start
/// commands with `run(_:)`. All work happens in `WalletWorker`.
///
/// Commands on different operations run side by side (see `WalletOperation`): a slow
/// one never disables or delays an unrelated one. Views ask `isRunning(_:)` for their
/// own progress and `canRun(_:)` to enable their actions. `busy` means only that the
/// session itself is changing, when nothing else may start.
@MainActor @Observable final class WalletModel {
  /// Every snapshot replaces this, so views that read it are redrawn by each refresh
  /// step. The app's frame reads `session` instead, which changes only with the vault's
  /// own state.
  var state = WalletSnapshot() {
    didSet {
      let next = WalletSession(state)
      if next != session { session = next }
    }
  }
  /// What the app's frame shows (setup, unlock, the wallet, a review sheet).
  private(set) var session = WalletSession(WalletSnapshot())
  var loadState: WalletLoadState = .loading
  var feedback: WalletFeedback?
  /// Recovery words for the view that asked for them (a new wallet's, or revealed with
  /// the PIN). It takes them and clears this. The next session command and lock do too.
  var generatedWords = ""
  /// A newly created API token, handed to the view that asked. Cleared on lock.
  var issuedToken = ""
  /// The project URL issued with a store's key, for the same view. Cleared on lock.
  var issuedStoreURL = ""
  /// The most the current account can send of an asset, from Max or from a review that
  /// asked for more. Send offers it. Cleared on lock and when it no longer applies.
  var sendLimit: SendLimit?
  /// Incremented on every lock. Views reset their drafts when it changes.
  var lockEpoch = 0
  /// The transfer this session last sent: Send follows it from broadcast to its
  /// receipt. Cleared on lock, when dismissed and when the next review starts.
  var submission: TransferSubmission?
  /// Set elsewhere (e.g. Holdings) to open Send on an asset, optionally preferring an address.
  var sendIntent: SendIntent?
  /// The operations whose commands are running.
  private(set) var running: Set<WalletOperation> = []
  /// True while the core is being locked. Distinguishes it from an unlock in progress.
  private(set) var locking = false
  /// The wallet locked while a sheet or alert was open: the hidden screens that own it
  /// stay a moment so it closes normally. False otherwise, so they go at once.
  private(set) var closingSession = false
  /// Public addresses by derivation path, derived on device as views need them.
  private(set) var addresses: [String: String] = [:]
  /// Where each step of the plan being carried out stands. Nil when none is.
  private(set) var progress: [StepProgress]?
  /// What the running refresh is reading. Nil when none runs.
  private(set) var refreshStep: RefreshStep?
  /// The account the running refresh reads. Nil when none runs.
  private(set) var refreshingSlot: UInt32?

  /// The account Home, Activity, Receive and Send work on. Persisted. Reconciled with
  /// the accounts that exist (see `apply`).
  var account: UInt32 = WalletModel.storedAccount {
    didSet {
      guard account != oldValue else { return }
      UserDefaults.standard.set(Int(account), forKey: WalletStorageKey.account.rawValue)
    }
  }

  private static var storedAccount: UInt32 {
    UInt32(exactly: UserDefaults.standard.integer(forKey: WalletStorageKey.account.rawValue)) ?? 0
  }

  @ObservationIgnored private let worker = WalletWorker()
  /// Increments on lock: results of work started before it are dropped.
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var refreshRun: Task<Void, Never>?
  @ObservationIgnored private var transferWatch: Task<Void, Never>?
  @ObservationIgnored private var idleTask: Task<Void, Never>?
  @ObservationIgnored private var authenticating = false
  @ObservationIgnored private var lastInteraction = Date.distantPast
  /// When the app was last minimized, hidden or sent to the background.
  @ObservationIgnored private var leftAt: Date?
  @ObservationIgnored private var pendingPairing = WalletIncomingLink.PendingRequest()
  /// Inactivity before the wallet locks itself. On macOS any input on the Mac counts,
  /// in this app or another. On iOS any touch or typing in the app (see `touch()`).
  /// The timer also waits while an operation runs, so the wallet never locks under a user.
  private var idleTimeout: TimeInterval { WalletAutoLock.current.seconds }

  init() { load() }

  // MARK: Current account

  var currentAccount: ProjectCard? { state.projects.first { $0.slot == account } }
  /// The current account's project connection, if it has one.
  var connection: PathConnection? { state.settings.connections.first { $0.slot == account } }
  var connected: Bool { connection != nil }
  /// An account's accent color. Copper until a valid one is stored.
  func accent(for slot: UInt32) -> WalletAccent { session.accent(for: slot) }

  // MARK: Operations

  /// The session is changing (opening, unlocking, locking, the PIN): nothing else starts.
  var busy: Bool { locking || running.contains(.session) }
  /// A refresh is running, for any account. Only one runs at a time, so this is what
  /// disables starting another.
  var refreshing: Bool { refreshStep != nil }
  /// Whether the running refresh reads this account. Progress (the sign's bulbs, the
  /// turning vent, spinners, step text) belongs to that account alone: another account's
  /// banner or the toolbar of a page showing another account stays still.
  func isRefreshing(_ slot: UInt32?) -> Bool { refreshStep != nil && refreshingSlot == slot }
  /// The current account is being read.
  var refreshingCurrent: Bool { isRefreshing(account) }
  func isRunning(_ operation: WalletOperation) -> Bool { running.contains(operation) }
  /// Whether a command on `operation` can start now.
  func canRun(_ operation: WalletOperation) -> Bool { !busy && !running.contains(operation) }

  /// Starts a command unless its operation is already running (or the session is
  /// changing), then the request is ignored, and the view's disabled control says why.
  func run(_ command: WalletCommand, onSuccess: (@MainActor () -> Void)? = nil) {
    let operation = command.operation
    guard canRun(operation) else { return }
    running.insert(operation)
    feedback = nil
    switch command {
    case .load: loadState = .loading
    case .deviceUnlock, .enableDeviceUnlock: authenticating = true
    case .plan, .confirmPlan(false): progress = nil
    default: break
    }
    if operation == .session { generatedWords = "" }
    let ticket = generation
    Task {
      defer { finished(operation) }
      do {
        // In the local test app, work that may reach the LAN waits for iOS's answer to
        // the Local Network prompt, so it isn't refused while the prompt is up.
        if operation != .session { await networkReady() }
        let result = try await worker.perform(command)
        guard generation == ticket else { return }
        apply(result.snapshot, selecting: result.created)
        // Unlocked: ask for Local Network access now, before anything needs it.
        if state.unlocked { LocalNetworkPermission.prepare() }
        if let words = result.words { generatedWords = words }
        if let token = result.token { issuedToken = token }
        if let url = result.storeURL { issuedStoreURL = url }
        if let limit = result.maximum { sendLimit = limit }
        if case .load = command { loadState = .ready }
        if !result.notice.isEmpty {
          feedback = WalletFeedback(
            message: result.notice, kind: result.warning ? .warning : .success)
        }
        onSuccess?()
      } catch {
        guard generation == ticket else { return }
        failed(command, error)
      }
    }
  }
  /// Replaces the state with a newer one from the worker. An older one (a result that
  /// arrives after a later one) is ignored.
  /// `selecting` is an account the command created: it becomes current in the same
  /// update as the snapshot that contains it, so no frame shows another account first.
  private func apply(_ snapshot: WalletSnapshot, selecting created: UInt32? = nil) {
    guard snapshot.revision > state.revision else { return }
    let previous = state.projects.map(\.slot)
    state = snapshot
    if let created, state.projects.contains(where: { $0.slot == created }) {
      account = created
    }
    if !state.projects.isEmpty, !state.projects.contains(where: { $0.slot == account }) {
      // The nearest remaining account: the one that took its place, else the one before.
      let index = previous.firstIndex(of: account) ?? 0
      account = state.projects[min(index, state.projects.count - 1)].slot
    }
  }
  private func failed(_ command: WalletCommand, _ error: Error) {
    switch command {
    case .load:
      // Sealed by a device lock: not a failure. It is read again on unlock.
      guard dataAvailable else {
        loadState = .loading
        return
      }
      loadState = .failed
    case .assetVisible(let id, let visible):
      setHidden(id, visible)
    case .plan, .confirmPlan:
      state.plan = nil
      state.planEndpoint = nil
      state.planAsset = nil
      progress = nil
    default: break
    }
    if let key = (error as? WalletUserError)?.revokedConnection {
      state.revokedConnections.insert(key)
    }
    if let limit = (error as? WalletUserError)?.limit { sendLimit = limit }
    feedback = WalletFeedback(
      message: (error as? WalletUserError)?.message ?? command.failureMessage, isError: true)
  }
  private func finished(_ operation: WalletOperation) {
    running.remove(operation)
    if operation == .session { authenticating = false }
    resetIdleTimer()
    resumePairing()
  }

  /// Shows or hides a token at once, then saves it. Each token has its own operation, so
  /// no other token's switch waits or is disabled meanwhile. A failure puts it back.
  func setAssetVisible(_ id: AssetID, _ visible: Bool) {
    guard canRun(.visibility(id)) else { return }
    setHidden(id, !visible)
    run(.assetVisible(id, visible))
  }
  private func setHidden(_ id: AssetID, _ hidden: Bool) {
    guard state.settings.hiddenAssets.contains(id) != hidden else { return }
    if hidden {
      state.settings.hiddenAssets.append(id)
    } else {
      state.settings.hiddenAssets.removeAll { $0 == id }
    }
  }

  /// iOS is showing (or about to show) its Local Network prompt and work is waiting on it.
  private(set) var awaitingLocalNetwork = false
  /// Waits for the Local Network answer in the local test app, saying so meanwhile.
  private func networkReady() async {
    guard LocalNetworkPermission.pending else { return }
    awaitingLocalNetwork = true
    await LocalNetworkPermission.ready()
    awaitingLocalNetwork = false
  }

  /// Whether the provider accepts the key. A key is saved only after it does.
  func accepts(_ provider: KeyProvider, key: String) async -> Bool {
    await networkReady()
    return await worker.accepts(provider, key: key)
  }
  /// Who to share a store's Google Sheet with. Nil when Stor can't be reached.
  func stor(_ origin: String) async -> Stor.Info? {
    await networkReady()
    return await worker.stor(origin)
  }
  /// A token contract's symbol, name and decimals, read from the network's endpoint.
  func readToken(chain: ChainID, contract: EVMAddress) async -> TokenDetails? {
    await networkReady()
    return await worker.readToken(chain: chain, contract: contract)
  }

  /// Derives the addresses of these paths that are not known yet.
  func deriveAddresses(_ paths: [String]) async {
    let missing = paths.filter { addresses[$0] == nil }
    guard state.unlocked, !missing.isEmpty else { return }
    let ticket = generation
    let found = await worker.deriveAddresses(missing)
    guard generation == ticket else { return }
    addresses.merge(found) { _, new in new }
  }

  // MARK: Opening

  /// Opens the vault. On iOS its files are sealed while the device is locked (complete
  /// file protection), and the system may launch the app then: in the background, or
  /// on install. The read then waits for the device to unlock instead of failing.
  func load() {
    guard dataAvailable else {
      loadState = .loading
      return
    }
    run(.load)
  }
  /// The device was unlocked, or the user returned to the app: a vault that couldn't be
  /// read only because it was sealed is read now.
  func dataBecameAvailable() {
    guard loadState != .ready, !busy, dataAvailable else { return }
    load()
  }
  private var dataAvailable: Bool {
    #if os(iOS)
      UIApplication.shared.isProtectedDataAvailable
    #else
      true
    #endif
  }

  // MARK: Refresh

  /// Reads new addresses, balances, activity and prices of one account (the current one
  /// unless given), only when asked: never on unlock or on a timer. (A sent transfer
  /// also re-reads its own network once it settles, quietly.) Networks are read side by
  /// side, and a network's endpoints and balances too. It runs as worker steps that wait
  /// on the network in the background, so the user's own actions never wait behind it,
  /// and `refreshStep` tells what it read last.
  func refresh(_ slot: UInt32? = nil, chains: Set<ChainID>? = nil, notify: Bool = true) {
    let slot = slot ?? account
    guard state.unlocked, !locking, refreshRun == nil, !state.usableAssets.isEmpty,
      state.projects.first(where: { $0.slot == slot })?.paths.isEmpty == false
    else { return }
    let ticket = generation
    refreshStep = RefreshStep()
    refreshingSlot = slot
    refreshRun = Task {
      defer { refreshRun = nil }
      await networkReady()
      let (steps, continuation) = AsyncStream.makeStream(
        of: RefreshStep.self, bufferingPolicy: .bufferingNewest(1))
      let shown = Task {
        for await step in steps where generation == ticket { refreshStep = step }
      }
      let worker = worker
      let plan = await worker.refreshPlan(slots: [slot], chains: chains)
      let report = RefreshReporter(continuation: continuation, total: plan.steps)
      var stale: Set<ChainID> = []
      var incomplete = false
      // Receipts and new addresses first: balances read the addresses they add.
      await withTaskGroup(of: Bool.self) { group in
        if plan.transfers {
          group.addTask {
            await self.take(await worker.refreshTransfers(report), ticket)
            report.finished()
            return true
          }
        }
        for id in plan.connections {
          group.addTask {
            guard await self.current(ticket) else { return true }
            let (snapshot, read) = await worker.refreshAddresses(id, report: report)
            await self.take(snapshot, ticket)
            report.finished()
            return read
          }
        }
        for await read in group where !read { incomplete = true }
      }
      await withTaskGroup(of: RefreshResult.self) { group in
        for chain in plan.chains {
          group.addTask {
            .network(
              chain,
              read: await self.refreshNetwork(
                chain, assets: plan.assets[chain] ?? [], slot: slot, force: notify,
                report: report, ticket: ticket))
          }
        }
        if plan.prices {
          group.addTask {
            guard await self.current(ticket) else { return .prices(failed: false) }
            let (snapshot, failed) = await worker.refreshPrices(report)
            await self.take(snapshot, ticket)
            report.finished()
            return .prices(failed: failed)
          }
        }
        for await result in group {
          switch result {
          case .network(let chain, let read): if !read { stale.insert(chain) }
          case .prices(let failed): if failed { incomplete = true }
          }
        }
      }
      continuation.finish()
      await shown.value
      guard current() else { return }
      take(await worker.refreshFinished(slot: slot, chains: plan.chains, stale: stale))
      guard current() else { return }
      refreshStep = nil
      refreshingSlot = nil
      if notify, !stale.isEmpty {
        let names = plan.chains.filter(stale.contains).map(state.networkName)
        feedback = WalletFeedback(
          message: "Couldn't update " + names.joined(separator: ", ") + ".", kind: .error)
      } else if notify, incomplete {
        feedback = WalletFeedback(message: "Some data couldn't be updated.", kind: .error)
      }
    }
  }

  private enum RefreshResult: Sendable {
    case network(ChainID, read: Bool)
    case prices(failed: Bool)
  }

  /// One network: the endpoints that answer (all asked at once), then its asset
  /// balances and the account's activity at once, the balances spread over the endpoints
  /// that answered. False when the network could not be read in full.
  private func refreshNetwork(
    _ chain: ChainID, assets: [AssetID], slot: UInt32, force: Bool, report: RefreshReporter,
    ticket: Int
  ) async -> Bool {
    let worker = worker
    let endpoints = await worker.refreshEndpoints(chain, report: report)
    defer { report.finished() }
    guard !endpoints.isEmpty, current(ticket) else { return false }
    return await withTaskGroup(of: Bool.self) { group in
      for (index, asset) in assets.enumerated() {
        group.addTask {
          guard await self.current(ticket) else { return true }
          let (snapshot, read) = await worker.refreshBalance(
            asset, slots: [slot], endpoints: endpoints, first: index, report: report)
          await self.take(snapshot, ticket)
          return read
        }
      }
      group.addTask {
        guard await self.current(ticket) else { return true }
        let (snapshot, read) = await worker.refreshActivity(
          chain, slot: slot, endpoint: endpoints[0], force: force, report: report)
        await self.take(snapshot, ticket)
        return read
      }
      var all = true
      for await read in group where !read { all = false }
      return all
    }
  }
  private func current(_ ticket: Int? = nil) -> Bool { generation == (ticket ?? generation) }
  private func take(_ snapshot: WalletSnapshot, _ ticket: Int? = nil) {
    if current(ticket) { apply(snapshot) }
  }
  /// Carries out the reviewed plan: confirms it, then signs and broadcasts its steps in
  /// order (a step waits in the worker for the ones it depends on). The send operation
  /// runs throughout, so the idle lock never interrupts it. Locking by hand drops the
  /// plan. `progress` shows each step. A failure stops here and keeps the review open
  /// to show which step it was.
  func send() {
    guard canRun(.send), let plan = state.plan else { return }
    let slot = account
    running.insert(.send)
    feedback = nil
    progress = Array(repeating: .pending, count: plan.steps.count)
    let ticket = generation
    Task {
      defer { finished(.send) }
      await networkReady()
      var index = -1
      var hashes: [String] = []
      do {
        apply(try await worker.perform(.confirmPlan(true)).snapshot)
        for position in plan.steps.indices {
          index = position
          progress?[position] = .working
          let result = try await worker.perform(.step(position))
          guard generation == ticket else { return }
          apply(result.snapshot)
          progress?[position] = .sent(result.hash ?? "")
          if let hash = result.hash, !hash.isEmpty { hashes.append(hash) }
        }
        progress = nil
        submission = TransferSubmission(
          slot: slot, chain: plan.network, asset: plan.asset, amount: plan.amount,
          recipient: plan.recipient, transactions: hashes, date: Date())
        feedback = WalletFeedback(message: "Transfer sent.", kind: .success)
        followSent(slot: slot, chain: plan.network)
      } catch {
        guard generation == ticket else { return }
        if index >= 0 {
          progress?[index] = .failed
          failed(.step(index), error)
        } else {
          failed(.confirmPlan(true), error)
        }
      }
    }
  }

  /// After a send: pending receipts are checked every few seconds (for up to ten
  /// minutes), then the network is read once so the balance follows.
  private func followSent(slot: UInt32, chain: ChainID) {
    guard state.settings.transfers.contains(where: { $0.status == "pending" }) else {
      refresh(slot, chains: [chain], notify: false)
      return
    }
    guard transferWatch == nil else { return }
    let ticket = generation
    transferWatch = Task {
      defer { transferWatch = nil }
      for _ in 0..<60 {
        let waiting = Set(state.settings.transfers.filter { $0.status == "pending" }.map(\.id))
        if waiting.isEmpty { break }
        try? await Task.sleep(for: .seconds(10))
        guard generation == ticket else { break }
        let snapshot = await worker.refreshTransfers(nil)
        guard generation == ticket else { break }
        apply(snapshot)
        for transfer in snapshot.settings.transfers
        where waiting.contains(transfer.id) && transfer.status != "pending" {
          if let slot = transfer.slot { refresh(slot, chains: [transfer.chain], notify: false) }
        }
      }
    }
  }

  // MARK: Locking

  func lock() {
    // Loading an encrypted vault never unlocks it. Do not discard its load
    // result and strand the UI on a spinner when the app initially loses focus.
    if loadState == .loading && !state.exists { return }
    idleTask?.cancel()
    generation += 1
    lockEpoch += 1
    refreshStep = nil
    refreshingSlot = nil
    transferWatch?.cancel()
    transferWatch = nil
    if Self.presenting {
      closingSession = true
      Task {
        // Long enough for sheet and alert dismissal to finish.
        try? await Task.sleep(for: .milliseconds(700))
        closingSession = false
      }
    }
    state.unlocked = false
    state.address = nil
    state.plan = nil
    state.access = nil
    state.planEndpoint = nil
    state.planAsset = nil
    progress = nil
    addresses = [:]
    generatedWords = ""
    issuedToken = ""
    issuedStoreURL = ""
    sendLimit = nil
    submission = nil
    feedback = nil
    locking = true
    let ticket = generation
    Task {
      let result: Result<WorkerResult, Error>
      do { result = .success(try await worker.perform(.lock)) } catch { result = .failure(error) }
      guard ticket == generation else { return }
      switch result {
      case .success(let result):
        apply(result.snapshot)
      case .failure:
        // The core is locked and the screens are gone. Only the refreshed accounts could
        // not be read, so say so instead of showing stale ones silently.
        feedback = WalletFeedback(
          message:
            "The wallet is locked, but its accounts could not be refreshed. Unlock to read them again.",
          kind: .warning)
      }
      locking = false
      authenticating = false
    }
  }
  /// Whether a sheet or alert is on screen.
  private static var presenting: Bool {
    #if os(macOS)
      NSApplication.shared.windows.contains { $0.attachedSheet != nil }
    #else
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows).contains { $0.rootViewController?.presentedViewController != nil }
    #endif
  }
  private func resetIdleTimer() {
    idleTask?.cancel()
    guard state.unlocked else { return }
    idleTask = Task {
      var wait = idleTimeout
      while true {
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        // Something the user started is running: wait for it to finish (its end
        // restarts the timer) rather than locking in the middle of it.
        if !running.isEmpty { return }
        if let idle = UserIdle.seconds, idle < idleTimeout {
          wait = idleTimeout - idle
          continue
        }
        lock()
        return
      }
    }
  }
  /// A new auto-lock time counts from now.
  func autoLockChanged() {
    lastInteraction = Date()
    resetIdleTimer()
  }
  /// Any user input. Throttled: the timer restarts at most every few seconds.
  func touch() {
    guard state.unlocked, Date().timeIntervalSince(lastInteraction) > 5 else { return }
    lastInteraction = Date()
    resetIdleTimer()
  }
  /// Minimizing, hiding or switching away does not lock. Sleep, screen lock and
  /// device lock still lock at once (the app hosts call `lock()` for those).
  func leftApp() {
    if state.unlocked && leftAt == nil { leftAt = Date() }
  }
  /// Back in the app: where only in-app input is known (iOS, which also suspends the
  /// timer in the background), time away counts as inactivity.
  func returnedToApp() {
    dataBecameAvailable()
    defer { leftAt = nil }
    guard UserIdle.seconds == nil, let leftAt, state.unlocked, !authenticating else { return }
    if Date().timeIntervalSince(leftAt) >= idleTimeout { lock() }
  }

  // MARK: Pairing links

  func receive(_ url: URL) {
    guard pendingPairing.receive(url) else {
      feedback = WalletFeedback(message: "Invalid pairing link.", isError: true)
      return
    }
    // A cold-launch request waits in memory for normal unlock, never on disk.
    resumePairing()
  }
  func reviewPairing(_ raw: String, project: String = "") {
    guard let url = URL(string: raw), let link = WalletIncomingLink.resolve(url) else {
      feedback = WalletFeedback(message: "Invalid pairing link.", isError: true)
      return
    }
    let origin = LocalDevelopment.origin(link)
    let connections = state.settings.connections.filter { $0.origin == origin }
    // Access is granted to a project on this API. Without one there is nothing to
    // review, so say what to set up instead of opening a request that can't be approved.
    guard !connections.isEmpty else {
      let host = origin.flatMap { URL(string: $0)?.host } ?? "this server"
      feedback = WalletFeedback(
        message: "Connect a project on \(host) first, in Project.",
        kind: .error)
      return
    }
    let selected =
      connections.first { $0.project == project }?.project ?? connections.first?.project ?? ""
    run(.pairing(link, selected, false))
  }
  private func resumePairing() {
    guard
      let link = pendingPairing.take(
        unlocked: state.unlocked, busy: !canRun(.access),
        reviewing: state.plan != nil || state.access != nil)
    else { return }
    reviewPairing(link)
  }
}

/// The part of the snapshot the app's frame depends on. Equatable, so the frame is
/// redrawn only when one of these changes, not with every balance read.
struct WalletSession: Equatable {
  var exists: Bool
  var unlocked: Bool
  var reviewingPlan: Bool
  var reviewingAccess: Bool
  var accents: [String: String]
  init(_ snapshot: WalletSnapshot) {
    exists = snapshot.exists
    unlocked = snapshot.unlocked
    reviewingPlan = snapshot.plan != nil
    reviewingAccess = snapshot.access != nil
    accents = snapshot.settings.accents
  }
  func accent(for slot: UInt32) -> WalletAccent {
    accents[String(slot)].flatMap { WalletAccent(rawValue: $0) } ?? .copper
  }
}
