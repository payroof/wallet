import Foundation

/// How a transfer's outcome reads: its badge and its tone.
struct TransferStatusStyle {
  let title: String
  let tone: WalletTone
  let icon: String
  init(_ status: String) {
    switch status {
    case "pending": (title, tone, icon) = ("Pending", .warning, "clock")
    case "confirmed": (title, tone, icon) = ("Confirmed", .success, "checkmark")
    case "failed": (title, tone, icon) = ("Failed", .danger, "xmark")
    default: (title, tone, icon) = (status.capitalized, .neutral, "questionmark")
    }
  }
}

/// Everything Activity shows about one item, worked out once from the item and the
/// wallet's state, so a line in the list and its detail always tell the same story:
/// what happened, how much, between whom, where, when and whether it went through.
struct ActivityLook {
  enum Direction {
    /// Into one of the account's addresses from elsewhere.
    case received
    /// Out of the account.
    case sent
    /// Between two of the account's own addresses.
    case moved
    /// A gas top-up or permit that made a send possible: plumbing, shown small.
    case fee
  }

  let direction: Direction
  /// "Received", "Sent", "Moved", "Gas top-up"…
  let title: String
  let icon: String
  let tone: WalletTone
  /// The exact amount with its symbol, unsigned ("12.5 USDC").
  let amount: String
  /// The same amount rounded for reading ("12.5 USDC", "<0.000001 ETH"), unsigned.
  let shortAmount: String
  /// "+", "−" or "" (moves and fee steps carry no sign).
  let sign: String
  /// The asset's symbol, when the asset is known.
  let symbol: String?
  /// The amount's value at today's price, when the asset has one.
  let usd: String?
  let status: TransferStatusStyle
  /// Still waiting for a receipt.
  let pending: Bool
  let failed: Bool
  let from: String
  let to: String
  let chain: ChainID
  let network: String
  /// Nil when the chain did not report a time.
  let date: Date?
  let transaction: String
  /// The asset's ID (`<chain>/native` or `<chain>/erc20:<contract>`).
  let asset: AssetID
  let contract: EVMAddress?
  let block: UInt64?
  /// The RPC a transfer signed here was sent through.
  let endpoint: String?
  let slot: UInt32?

  var signedAmount: String { sign + amount }
  var signedShortAmount: String { sign + shortAmount }
  /// The other side, as seen from the account: who paid it in, or where it went.
  var counterpart: (role: String, address: String) {
    direction == .received ? ("From", from) : ("To", to)
  }

  /// An amount rounded for display, nil when the asset's decimals are not known.
  private static func rounded(_ atomic: String, asset: WalletAsset, id: AssetID) -> String? {
    guard asset.id == id, (0...36).contains(asset.decimals) else { return nil }
    return ExactAmount.short(atomic, decimals: asset.decimals) + " " + asset.symbol
  }

  init(_ item: ActivityItem, state: WalletSnapshot) {
    switch item {
    case .sent(let transfer): self.init(sent: transfer, state: state)
    case .chain(let entry): self.init(found: entry, state: state)
    }
  }

  private init(sent transfer: LocalTransfer, state: WalletSnapshot) {
    let internalStep = transfer.isInternal
    direction = internalStep ? .fee : .sent
    title = internalStep ? TransferConfirmationView.title(transfer.kind) : "Sent"
    icon = TransferConfirmationView.icon(transfer.kind)
    status = TransferStatusStyle(transfer.status)
    pending = transfer.status == "pending"
    failed = transfer.status == "failed"
    tone = failed ? .danger : pending ? .warning : .neutral
    amount = state.transferAmount(transfer)
    shortAmount =
      Self.rounded(transfer.amount, asset: transfer.assetSnapshot, id: transfer.asset)
      ?? amount
    sign = internalStep ? "" : "−"
    let asset = transfer.assetSnapshot
    let known = asset.id == transfer.asset
    symbol = known ? asset.symbol : nil
    usd = known && !internalStep ? state.usd(transfer.amount, asset: asset) : nil
    from = transfer.source
    to = transfer.recipient
    chain = transfer.chain
    network = state.networkName(transfer.chain)
    date = transfer.date
    transaction = transfer.id
    self.asset = transfer.asset
    contract = known ? asset.contract : nil
    block = nil
    endpoint = transfer.endpoint
    slot = transfer.slot
  }

  private init(found entry: HistoryEntry, state: WalletSnapshot) {
    switch entry.direction {
    case "in": (direction, title, icon, sign) = (.received, "Received", "arrow.down.left", "+")
    case "out": (direction, title, icon, sign) = (.sent, "Sent", "arrow.up.right", "−")
    default: (direction, title, icon, sign) = (.moved, "Moved", "arrow.left.arrow.right", "")
    }
    failed = entry.failed
    pending = false
    status = TransferStatusStyle(entry.failed ? "failed" : "confirmed")
    tone = entry.failed ? .danger : direction == .received ? .success : .neutral
    amount = state.historyAmount(entry)
    let asset = state.assets.first { $0.id == entry.asset }
    shortAmount =
      asset.flatMap { Self.rounded(entry.amount, asset: $0, id: entry.asset) } ?? amount
    symbol = asset?.symbol
    usd = asset.flatMap { state.usd(entry.amount, asset: $0) }
    from = entry.from
    to = entry.to
    chain = entry.chain
    network = state.networkName(entry.chain)
    date = entry.date == .distantPast ? nil : entry.date
    transaction = entry.transaction
    self.asset = entry.asset
    contract = asset?.contract
    block = entry.block
    endpoint = nil
    slot = entry.slot
  }
}

extension WalletModel {
  /// This wallet's own name for an address it has derived: "Address 3", with the
  /// account's name first when it belongs to another account. Nil for anyone else's.
  func ownName(of address: String) -> String? {
    let needle = address.lowercased()
    guard let path = addresses.first(where: { $0.value.lowercased() == needle })?.key else {
      return nil
    }
    let name = WalletText.addressName(path)
    guard let owner = state.projects.first(where: { $0.paths.contains(path) }),
      owner.slot != account
    else { return name }
    return "\(owner.label) · \(name)"
  }

  /// An address as Activity shows it: its own name, or the shortened address.
  func activityName(of address: String) -> String {
    ownName(of: address) ?? WalletText.short(address)
  }
}
