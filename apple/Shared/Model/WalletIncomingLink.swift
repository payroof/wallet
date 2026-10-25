import Foundation

/// Deep links carry a review request only. Registration and permission approval
/// still require explicit actions, and Rust validates the pairing URL itself.
enum WalletIncomingLink {
  /// The longest link taken.
  static let maximumLength = 8192
  /// The path of a pairing request on a Payroof API, followed by its ID.
  static let pairingsPath = "/v1/pairings/"
  /// A pairing ID starts with this and is `pairingIDLength` bytes in all.
  static let pairingIDPrefix = "pair_"
  static let pairingIDLength = 48
  struct PendingRequest {
    private var link: String?
    mutating func receive(_ url: URL) -> Bool {
      guard let value = WalletIncomingLink.resolve(url) else { return false }
      link = value
      return true
    }
    mutating func take(unlocked: Bool, busy: Bool, reviewing: Bool) -> String? {
      guard unlocked, !busy, !reviewing else { return nil }
      defer { link = nil }
      return link
    }
  }
  static func resolve(_ url: URL) -> String? {
    guard url.absoluteString.utf8.count <= Self.maximumLength else { return nil }
    let raw: String
    if url.scheme == "payroof" {
      guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
        parts.host == "pair", parts.path.isEmpty || parts.path == "/",
        parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
        let query = parts.queryItems, query.count == 1, query[0].name == "url",
        let value = query[0].value
      else { return nil }
      raw = value
    } else {
      raw = url.absoluteString
    }
    guard let inner = URLComponents(string: raw), let host = inner.host, !host.isEmpty,
      inner.user == nil, inner.password == nil, inner.fragment == nil, inner.query == nil,
      raw.utf8.count <= Self.maximumLength, !raw.contains("\\"),
      raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
      LocalDevelopment.origin(raw) != nil
    else { return nil }
    guard inner.percentEncodedPath.hasPrefix(pairingsPath) else { return nil }
    let id = String(inner.percentEncodedPath.dropFirst(pairingsPath.count))
    guard id.hasPrefix(pairingIDPrefix), id.utf8.count == pairingIDLength,
      id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
    else { return nil }
    return raw
  }
}
