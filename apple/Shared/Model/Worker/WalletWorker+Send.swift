import Foundation

/// Sending: the plan the user reviews, then its steps one by one, and receipts. The core
/// decides which of the account's addresses fund a send and who pays the gas. This only
/// asks, shows and carries out. Every request runs in the background.
extension WalletWorker {
  /// How long a step waits for the steps it depends on, and how often it looks.
  static let dependencyTimeout: TimeInterval = 300
  static let dependencyPoll: Duration = .seconds(3)

  private struct PlanRequest: Encodable {
    var chain: ChainID
    var asset: AssetID
    var to: String
    var amount: String
    var slot: UInt32
    var prefer: String?
  }

  /// The most the account can send of an asset, as Review would plan it: the core reads
  /// every address's balance and, for a network's coin, the fee of its transfer. The
  /// recipient may still be empty. Nothing is planned or kept.
  func sendMaximum(
    slot: UInt32, assetID: AssetID, recipient: String, endpoint: String, prefer: String?
  ) async throws -> Outcome {
    struct Maximum: Decodable { var maximum: String }
    let wallet = try unlockedWallet()
    guard let asset = snapshot.assets.first(where: { $0.id == assetID }),
      let network = snapshot.networks.first(where: { $0.id == asset.chain }),
      snapshot.projects.contains(where: { $0.slot == slot }),
      snapshot.endpoint(for: asset.chain) == endpoint
    else { throw CocoaError(.coderInvalidValue) }
    let request = try encode(
      PlanRequest(
        chain: asset.chain, asset: asset.id, to: recipient, amount: "1", slot: slot,
        prefer: prefer))
    let legacy = network.transactionMode.isLegacy
    let json = try await background {
      try wallet.sendMaximum(endpoint: endpoint, requestJson: request, legacy: legacy)
    }
    let maximum = try decode(Maximum.self, json).maximum
    return Outcome(maximum: SendLimit(slot: slot, asset: asset.id, atomic: maximum))
  }

  /// Plans a send from the account for review. Nothing is signed: the core keeps the
  /// plan until the user confirms or cancels it.
  func plan(
    slot: UInt32, assetID: AssetID, recipient: String, amount: String, endpoint: String,
    prefer: String?
  ) async throws -> Outcome {
    clearPlan()
    let wallet = try unlockedWallet()
    guard let asset = snapshot.assets.first(where: { $0.id == assetID }),
      let network = snapshot.networks.first(where: { $0.id == asset.chain }),
      snapshot.projects.contains(where: { $0.slot == slot })
    else { throw CocoaError(.coderInvalidValue) }
    // Never plan against an endpoint other than the one currently selected and shown.
    guard snapshot.endpoint(for: asset.chain) == endpoint else {
      throw WalletUserError(
        "The \(network.name) endpoint changed. Check the details and review the transfer again.")
    }
    let request = try encode(
      PlanRequest(
        chain: asset.chain, asset: asset.id, to: recipient,
        amount: try ExactAmount.atomic(amount, decimals: asset.decimals), slot: slot,
        prefer: prefer))
    let legacy = network.transactionMode.isLegacy
    func quote(_ url: String) async throws -> String {
      try await background {
        try wallet.planSend(endpoint: url, requestJson: request, legacy: legacy)
      }
    }
    // The selected endpoint plans. If it is down, the first other endpoint that serves
    // this chain does. Execution and receipts use the one shown in the review.
    var used = endpoint
    let json: String
    do { json = try await quote(endpoint) } catch {
      guard !(await verify(chain: asset.chain, url: endpoint)),
        let backup = await firstReachable(candidates(asset.chain).dropFirst(), chain: asset.chain)
      else { throw error }
      used = backup
      json = try await quote(backup)
    }
    switch try decode(SendPlanResponse.self, json) {
    case .problem(let problem):
      // More than can be sent, but something can: the message says how much, and Send
      // offers that amount.
      var limit: SendLimit?
      if case .insufficientFunds(let held, _) = problem,
        AtomicText.compare(held, "0") == 1
      {
        limit = SendLimit(slot: slot, asset: asset.id, atomic: held)
      }
      throw WalletUserError(
        problem.message(asset: asset, native: snapshot.nativeAsset(asset.chain)), limit: limit)
    case .plan(let plan):
      snapshot.plan = plan
      snapshot.planEndpoint = used
      snapshot.planAsset = asset
      planSlot = slot
      return Outcome()
    }
  }
  private func firstReachable(_ urls: ArraySlice<String>, chain: ChainID) async -> String? {
    for url in urls where await verify(chain: chain, url: url) { return url }
    return nil
  }

  /// The user's decision on the reviewed plan: `false` drops it, `true` lets its steps
  /// be signed (one `step` at a time).
  func confirmPlan(allow: Bool) throws -> Outcome {
    guard allow else {
      clearPlan()
      _ = try? wallet?.confirmPlan(allow: false)
      return Outcome()
    }
    guard snapshot.plan != nil else { throw CocoaError(.coderInvalidValue) }
    try unlockedWallet().confirmPlan(allow: true)
    return Outcome()
  }

  /// Signs and broadcasts one step of the confirmed plan and records it. A step that
  /// depends on earlier ones waits (looking every few seconds, for a few minutes) until
  /// their receipts say success. The core keeps the plan meanwhile. A failure ends the
  /// plan, and says which step it was. The plan is gone after its last step.
  func step(index: Int) async throws -> Outcome {
    let wallet = try unlockedWallet()
    guard let plan = snapshot.plan, let asset = snapshot.planAsset,
      let endpoint = snapshot.planEndpoint, plan.steps.indices.contains(index)
    else { throw CocoaError(.coderInvalidValue) }
    let step = plan.steps[index]
    let slot = planSlot
    let place = "Step \(index + 1) of \(plan.steps.count)"
    let deadline = Date().addingTimeInterval(Self.dependencyTimeout)
    do {
      var hash: String?
      while hash == nil {
        try await waitForDependencies(step, in: plan, endpoint: endpoint, deadline: deadline)
        do {
          hash = try await background { try wallet.executeStep(index: UInt32(index)) }
        } catch {
          // Only a dependency that is not mined yet keeps the plan. Ask again then.
          guard try await dependenciesPending(step, plan: plan, endpoint: endpoint) else {
            throw error
          }
        }
      }
      guard let hash else { throw CocoaError(.coderInvalidValue) }
      // Broadcast: always recorded from the values read above, even when a lock
      // cleared the plan meanwhile. The steps after it are then not sent.
      let moved =
        step.kind == .topUp ? (snapshot.nativeAsset(plan.network) ?? asset) : asset
      snapshot.settings.transfers.insert(
        LocalTransfer(
          id: hash, endpoint: endpoint, chain: plan.network, asset: moved.id,
          recipient: step.to, amount: step.amount, status: "pending", date: Date(),
          source: step.owner, slot: slot, assetSnapshot: moved, kind: step.kind),
        at: 0)
      let stopped = snapshot.plan == nil
      if !stopped { planHashes[index] = hash }
      if stopped || index == plan.steps.count - 1 { clearPlan() }
      try save()
      return Outcome(hash: hash)
    } catch {
      clearPlan()
      _ = try? wallet.confirmPlan(allow: false)
      if error is WalletUserError { throw error }
      throw WalletUserError(
        "\(place) failed, so nothing further was sent. Check Activity and the addresses on-chain before trying again."
      )
    }
  }

  /// Waits until every step this one depends on has a successful receipt.
  private func waitForDependencies(
    _ step: PlanStep, in plan: SendPlan, endpoint: String, deadline: Date
  ) async throws {
    while try await dependenciesPending(step, plan: plan, endpoint: endpoint) {
      guard Date() < deadline else {
        throw WalletUserError(
          "A previous step is taking too long to confirm. Check Activity before trying again.")
      }
      try await Task.sleep(for: Self.dependencyPoll)
    }
  }

  /// Whether a dependency of the step is still unmined (or its status unreadable). A
  /// failed one ends the plan.
  private func dependenciesPending(
    _ step: PlanStep, plan: SendPlan, endpoint: String
  ) async throws -> Bool {
    guard let wallet, snapshot.plan != nil else { throw CocoaError(.coderInvalidValue) }
    var pending = false
    for dependency in step.after {
      guard let hash = planHashes[dependency] else { throw CocoaError(.coderInvalidValue) }
      // An unanswered status read counts as pending: the caller's deadline bounds it.
      guard
        let status = try? await background({
          try wallet.transactionStatus(
            endpoint: endpoint, chain: plan.network.rawValue, transaction: hash)
        })
      else {
        pending = true
        continue
      }
      setStatus(status, of: hash)
      switch status {
      case "confirmed": continue
      case "failed":
        throw WalletUserError("A previous step failed on-chain. Nothing further was sent.")
      default: pending = true
      }
    }
    return pending
  }

  func clearPlan() {
    snapshot.plan = nil
    snapshot.planEndpoint = nil
    snapshot.planAsset = nil
    planSlot = nil
    planHashes = [:]
  }

  /// A sent transfer's status from the first of `urls` that answers. Nil when none
  /// does. Blocking: call it in the background.
  nonisolated static func receipt(
    _ wallet: Wallet, _ transfer: LocalTransfer, urls: [String], report: ((String) -> Void)?
  ) -> String? {
    for url in urls {
      report?(url)
      if let status = try? wallet.transactionStatus(
        endpoint: url, chain: transfer.chain.rawValue, transaction: transfer.id)
      {
        return status
      }
    }
    return nil
  }
  func setStatus(_ status: String, of id: String) {
    if let index = snapshot.settings.transfers.firstIndex(where: { $0.id == id }) {
      snapshot.settings.transfers[index].status = status
    }
  }
}
