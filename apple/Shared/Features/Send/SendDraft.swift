import Foundation

/// The Send form as values: what is typed and chosen, read against the wallet's state.
/// Everything the screen decides (is the amount valid, does the account cover it, which
/// networks and tokens are offered, what is held) is worked out here, apart from the
/// view, so it can be tested on its own.
struct SendDraft {
  let state: WalletSnapshot
  let account: ProjectCard?
  /// Public addresses by path, derived so far (`WalletModel.addresses`).
  let addresses: [String: String]
  /// The most the account can send, when Max or a review worked it out.
  let sendLimit: SendLimit?
  let assetID: AssetID?
  let amount: String
  let recipient: String
  /// Recipient chosen from recent transfers.
  let recentPick: LocalTransfer?

  var asset: WalletAsset? { state.assets.first { $0.id == assetID } }
  var endpoint: String { asset.flatMap { state.endpoint(for: $0.chain) } ?? "" }
  var networkName: String {
    asset.map { state.networkName($0.chain) } ?? "the network"
  }
  var cleanRecipient: String { recipient.trimmingCharacters(in: .whitespacesAndNewlines) }
  var cleanAmount: String { ExactAmount.userInput(amount) }
  var recipientCheck: Result<EVMAddress, EVMAddress.Problem> {
    EVMAddress.check(cleanRecipient)
  }
  var recipientValid: Bool { (try? recipientCheck.get()) != nil }
  var recipientError: String? {
    guard !cleanRecipient.isEmpty, case .failure(let problem) = recipientCheck else { return nil }
    switch problem {
    case .incomplete: return nil
    case .malformed: return "Enter a full EVM address: 0x followed by 40 hexadecimal characters."
    case .zero: return "The zero address can't receive funds."
    }
  }
  var ownAddressWarning: String? {
    guard recipientValid, let paths = account?.paths,
      let own = paths.first(where: {
        addresses[$0]?.lowercased() == cleanRecipient.lowercased()
      })
    else { return nil }
    return "This is your \(WalletText.addressName(own)): the funds stay in this account."
  }
  var recentWarning: String? {
    guard let pick = recentPick, pick.recipient == cleanRecipient, let asset,
      pick.chain != asset.chain
    else { return nil }
    return
      "Last used on \(state.networkName(pick.chain)), but you're sending on \(networkName). Check the recipient supports \(networkName)."
  }
  var atomicAmount: String? {
    guard let asset else { return nil }
    return try? ExactAmount.atomic(cleanAmount, decimals: asset.decimals)
  }
  /// More than the account holds, or not an amount of this token (a second point, more
  /// decimals than it has): the digits turn red. A zero, or a point still being typed,
  /// is incomplete, not wrong.
  var amountInvalid: Bool {
    guard !cleanAmount.isEmpty, let asset else { return false }
    let parts = cleanAmount.split(separator: ".", omittingEmptySubsequences: false)
    let malformed =
      parts.count > 2 || !parts.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
      || (parts.count == 2 && parts[1].count > asset.decimals)
    return malformed || exceedsAvailable
  }
  /// A positive amount the account covers (when its balance hasn't been read, the
  /// review checks it): the recipient comes next.
  var amountValid: Bool { atomicAmount != nil && !exceedsAvailable }
  var valid: Bool {
    guard asset != nil, account != nil, !endpoint.isEmpty, recipientValid else { return false }
    return amountValid
  }
  /// What the whole account holds of the asset, from the last balance reads.
  var holding: AssetHolding? {
    WalletPortfolio.holdings(state, account: account).first { $0.asset.id == assetID }
  }
  var available: CachedBalance? {
    holding.flatMap { item in item.checked.map { CachedBalance(atomic: item.total, date: $0) } }
  }
  /// The most this account can send of the asset, when Max or a review worked it out:
  /// for a network's coin, its balance less the fees of its transfers.
  var limit: SendLimit? {
    guard let limit = sendLimit, limit.asset == assetID, limit.slot == account?.slot
    else { return nil }
    return limit
  }
  var isNative: Bool { asset?.isNative == true }
  var exceedsAvailable: Bool {
    guard let atomicAmount else { return false }
    if let limit, AtomicText.compare(atomicAmount, limit.atomic) == 1 { return true }
    guard let available else { return false }
    return AtomicText.compare(atomicAmount, available.atomic) == 1
  }
  var recentRecipients: [LocalTransfer] {
    var seen = Set<String>()
    return state.settings.transfers.filter {
      !$0.isInternal && seen.insert($0.recipient.lowercased()).inserted
    }
  }
  /// Networks offered: those with an endpoint, and the current one even when off.
  var sendNetworks: [WalletNetwork] {
    state.networks.filter { network in
      (network.id == asset?.chain || state.endpoint(for: network.id) != nil)
        && state.assets.contains { $0.chain == network.id }
    }
  }
  /// Tokens of the chosen network that are not hidden.
  var sendTokens: [WalletAsset] {
    state.assets.filter {
      $0.chain == asset?.chain
        && (!state.settings.hiddenAssets.contains($0.id) || $0.id == assetID)
    }
  }
  /// What the account holds on a network (last check): its USD value, else its biggest
  /// holding.
  func held(on chain: ChainID) -> String? {
    let items = WalletPortfolio.holdings(state, account: account).filter {
      $0.asset.chain == chain && !$0.isZero
    }
    var usd: Decimal?
    for item in items {
      if let price = state.settings.prices[item.asset.id],
        let value = ExactAmount.usd(item.total, decimals: item.asset.decimals, price: price.usd)
      {
        usd = (usd ?? 0) + value
      }
    }
    if let usd { return WalletPortfolio.currency(usd) }
    return items.first.map {
      ExactAmount.short($0.total, decimals: $0.asset.decimals) + " " + $0.asset.symbol
    }
  }
  /// What the account holds of a token (last check).
  func held(_ item: WalletAsset) -> String? {
    let total = WalletPortfolio.holdings(state, account: account)
      .first { $0.asset.id == item.id }?.total
    guard let total, total.contains(where: { $0 != "0" }) else { return nil }
    return ExactAmount.short(total, decimals: item.decimals)
  }
  /// The token to start on for a network: the best held, else its native coin.
  func bestToken(on chain: ChainID) -> AssetID? {
    let usable = state.assets.filter {
      $0.chain == chain && !state.settings.hiddenAssets.contains($0.id)
    }
    func value(_ item: AssetHolding) -> Decimal {
      state.settings.prices[item.asset.id].flatMap {
        ExactAmount.usd(item.total, decimals: item.asset.decimals, price: $0.usd)
      } ?? 0
    }
    let best = WalletPortfolio.holdings(state, account: account)
      .filter { $0.asset.chain == chain && !$0.isZero }
      .max { value($0) < value($1) }
    return best?.asset.id ?? usable.first { $0.isNative }?.id ?? usable.first?.id
  }
}
