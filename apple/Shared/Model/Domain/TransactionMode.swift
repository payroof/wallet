import Foundation

/// How a network's transactions are priced. The raw values are the core's names, which
/// settings files keep. The core's send calls take a `legacy` flag, mapped here and
/// nowhere else.
enum TransactionMode: String, Codable, Sendable, CaseIterable {
  /// A single gas price.
  case legacy
  /// A base fee and a priority fee (EIP-1559).
  case eip1559

  init(legacy: Bool) { self = legacy ? .legacy : .eip1559 }
  /// The flag the core's planning calls take.
  var isLegacy: Bool { self == .legacy }
}
