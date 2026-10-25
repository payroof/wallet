import Foundation

/// What Send should start with when another screen opens it.
struct SendIntent: Equatable {
  var asset: AssetID
  /// The address to fund the send from first, when the user came from one.
  var prefer: String?
}

struct LocalTransfer: Codable, Identifiable, Sendable {
  var id: String
  var endpoint: String
  var chain: ChainID
  var asset: AssetID
  var recipient: String
  var amount: String
  var status: String
  var date: Date
  var source: String
  var slot: UInt32?
  var assetSnapshot: WalletAsset
  /// The plan step this transaction carried out.
  var kind: PlanStepKind
  /// A top-up or permit: fee plumbing, listed small in Activity.
  var isInternal: Bool { kind.isInternal }
}

/// A transfer just sent from this device: its plan's transactions (a top-up or permit
/// first, then the transfer itself), followed until each has a receipt.
struct TransferSubmission: Equatable, Identifiable, Sendable {
  let id = UUID()
  let slot: UInt32
  let chain: ChainID
  let asset: AssetID
  /// Exact atomic amount the recipient receives.
  let amount: String
  let recipient: String
  /// Transaction hashes in the order they were broadcast.
  let transactions: [String]
  let date: Date

  /// Where the whole transfer stands.
  enum Stage: Equatable, Sendable {
    /// Broadcast, waiting to be included in a block.
    case pending
    /// Every transaction has a successful receipt: the recipient has the funds.
    case confirmed
    /// A transaction was included but reverted: nothing (more) was transferred.
    case failed
  }

  /// The stage from the recorded transfers' statuses: failed as soon as one failed,
  /// confirmed once all are, pending until then (also while a status is unknown).
  func stage(in transfers: [LocalTransfer]) -> Stage {
    let statuses = transactions.map { hash in transfers.first { $0.id == hash }?.status }
    if statuses.contains("failed") { return .failed }
    if !statuses.isEmpty && statuses.allSatisfy({ $0 == "confirmed" }) { return .confirmed }
    return .pending
  }

  /// The transaction that moved the funds: the last one broadcast.
  var transfer: String? { transactions.last }
}

struct CachedBalance: Codable, Sendable {
  var atomic: String
  var date: Date
}

struct CachedPrice: Codable, Sendable {
  /// Canonical decimal USD price per whole unit.
  var usd: String
  var date: Date
}

/// A transfer found on-chain at one of an account's addresses, by the core's local
/// activity scan. Only assets in the wallet's list are ever reported.
struct HistoryEntry: Codable, Identifiable, Sendable {
  var chain: ChainID
  var asset: AssetID
  var transaction: String
  var index: Int
  var from: String
  var to: String
  var amount: String
  var block: UInt64
  var timestamp: UInt64?
  /// `in`, `out` or `self`, relative to the account.
  var direction: String
  var failed: Bool
  /// The account and the time it was first seen. Set when stored.
  var slot: UInt32?
  var seen: Date?
  var id: String {
    "\(slot ?? 0)/\(transaction)/\(index)/\(asset)/\(from)/\(to)/\(amount)"
  }
  var date: Date {
    timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? seen ?? .distantPast
  }
}

/// One network's stored activity for one account, with the core's opaque scan cursor.
struct StoredHistory: Codable, Sendable {
  var cursor = ""
  var entries: [HistoryEntry] = []
}

/// What the core's scan returns: new entries and the cursor to pass next time.
struct HistoryScan: Decodable, Sendable {
  var entries: [HistoryEntry]
  var cursor: String
}

/// One Activity line: a transfer sent from this device, or one found on-chain.
enum ActivityItem: Identifiable, Sendable {
  case sent(LocalTransfer)
  case chain(HistoryEntry)
  var id: String {
    switch self {
    case .sent(let t): "sent " + t.id
    case .chain(let h): "chain " + h.id
    }
  }
  var date: Date {
    switch self {
    case .sent(let t): t.date
    case .chain(let h): h.date
    }
  }
  var chain: ChainID {
    switch self {
    case .sent(let t): t.chain
    case .chain(let h): h.chain
    }
  }
  /// Whether `address` (lowercase) sent or received it.
  func involves(_ address: String) -> Bool {
    switch self {
    case .sent(let t): t.source.lowercased() == address || t.recipient.lowercased() == address
    case .chain(let h): h.from.lowercased() == address || h.to.lowercased() == address
    }
  }
}
