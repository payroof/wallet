import Foundation
import Synchronization

/// What a refresh read last: which network (or account), what, and from where (an RPC,
/// a keyed history source, the Payroof API or a price oracle), with the steps finished so far. Shown while it runs, so a slow source never looks like a frozen app.
struct RefreshStep: Equatable, Sendable {
  enum Kind: Sendable {
    case preparing, connecting, balances, activity, addresses, transfers, prices
    var phrase: String {
      switch self {
      case .preparing: "Preparing"
      case .connecting: "Connecting to"
      case .balances: "Balance via"
      case .activity: "Activity via"
      case .addresses: "New addresses via"
      case .transfers: "Transfer status via"
      case .prices: "Prices from"
      }
    }
  }
  var scope = ""
  var task = Kind.preparing
  var source = ""
  var position = 0
  var total = 0
  /// "Polygon · Activity via Etherscan", "Base USDC · Balance via PublicNode".
  var text: String {
    let action = source.isEmpty ? task.phrase + "…" : task.phrase + " " + source
    return scope.isEmpty ? action : scope + " · " + action
  }
  /// "3/7" finished, once the run's steps are known.
  var count: String { total > 0 ? "\(position)/\(total)" : "" }
}

/// Counts the finished steps of a run and remembers the latest thing read.
private final class RefreshProgress: Sendable {
  private let step = Mutex(RefreshStep())
  func update(_ change: (inout RefreshStep) -> Void) -> RefreshStep {
    step.withLock {
      change(&$0)
      return $0
    }
  }
}

/// Reports a refresh run: the latest source read, and how many of its steps have
/// finished. Steps run side by side, so it is shared by all of them.
struct RefreshReporter: Sendable {
  private let continuation: AsyncStream<RefreshStep>.Continuation
  private let progress = RefreshProgress()
  init(continuation: AsyncStream<RefreshStep>.Continuation, total: Int) {
    self.continuation = continuation
    _ = progress.update { $0.total = total }
  }
  func callAsFunction(_ scope: String, _ task: RefreshStep.Kind, _ source: String) {
    continuation.yield(
      progress.update {
        $0.scope = scope
        $0.task = task
        $0.source = source
      })
  }
  /// One step is done.
  func finished() {
    continuation.yield(progress.update { $0.position += 1 })
  }
}

/// The steps of a refresh run, decided before any network is read.
struct RefreshPlan: Sendable {
  /// API connections (`origin#project`) whose new addresses are fetched first.
  var connections: [String] = []
  /// Networks in the user's order, and the assets read on each.
  var chains: [ChainID] = []
  var assets: [ChainID: [AssetID]] = [:]
  /// The accounts read, those with addresses.
  var slots: [UInt32] = []
  /// Sent transfers waiting for a receipt on those networks.
  var transfers = false
  var prices = false
  var steps: Int { (transfers ? 1 : 0) + connections.count + chains.count + (prices ? 1 : 0) }
}
