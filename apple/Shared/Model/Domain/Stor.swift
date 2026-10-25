import Foundation

/// Stor stores: a project's storefront, kept in the merchant's Google Sheet.
enum Stor {
  /// What a Stor server asks of a new store.
  struct Info: Decodable, Sendable {
    /// The server, as an origin.
    var stor: String
    /// The account a sheet is shared with, as an editor.
    var shareWith: String
    /// A store's address with `{store}` in place of its subdomain.
    var storeURL: String
    enum CodingKeys: String, CodingKey {
      case stor
      case shareWith = "share_with"
      case storeURL = "store_url"
    }
    func url(_ subdomain: String) -> String {
      storeURL.replacingOccurrences(of: "{store}", with: subdomain)
    }
    /// What follows a store's subdomain in its address, e.g. `.stor.top`.
    var suffix: String { storeURL.components(separatedBy: "{store}").last ?? "" }
  }
  /// 3–40 lowercase letters, digits or inner hyphens, as Stor takes them.
  static func validSubdomain(_ s: String) -> Bool {
    (3...40).contains(s.count) && !s.hasPrefix("-") && !s.hasSuffix("-")
      && s.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
  }
  /// What to fix when Stor refuses a store.
  static func message(_ code: String) -> String {
    switch code {
    case "invalid_subdomain": "Use 3–40 lowercase letters, digits or hyphens for the address."
    case "subdomain_reserved": "This address isn't available. Choose another."
    case "subdomain_taken": "This address is taken. Choose another."
    case "invalid_source": "Paste the Google Sheet's link."
    case "source_in_use": "This sheet already has a store."
    case "source_unreachable": "Share the sheet with Stor as Editor first."
    case "source_read_only": "Share the sheet as Editor, not Viewer."
    case "source_invalid": "Two tabs of the sheet look alike. Keep one of each."
    case "source_unavailable": "Google Sheets is unavailable. Try again."
    case "rate_limited": "Too many attempts. Try again later."
    default: "Could not create the store. Try again."
    }
  }
}
