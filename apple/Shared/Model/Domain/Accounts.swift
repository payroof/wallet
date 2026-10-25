import Foundation

/// The colors an account, a network or a token can have: a preset by name (the interface
/// maps each to a tuned color, `WalletAccent`) or a custom color as strict `#RRGGBB`.
enum AccountAccent {
  /// Whether `value` is a preset name or a `#RRGGBB` color.
  static func isValid(_ value: String) -> Bool { names.contains(value) || rgb(hex: value) != nil }
  /// The channels (0...1) of a strict `#RRGGBB`. Nil for anything else.
  static func rgb(hex: String) -> (Double, Double, Double)? {
    let digits = Array(hex.utf8)
    guard digits.count == 7, digits[0] == UInt8(ascii: "#") else { return nil }
    var value: UInt32 = 0
    for byte in digits.dropFirst() {
      let nibble: UInt32
      switch byte {
      case UInt8(ascii: "0")...UInt8(ascii: "9"): nibble = UInt32(byte - UInt8(ascii: "0"))
      case UInt8(ascii: "a")...UInt8(ascii: "f"): nibble = UInt32(byte - UInt8(ascii: "a")) + 10
      case UInt8(ascii: "A")...UInt8(ascii: "F"): nibble = UInt32(byte - UInt8(ascii: "A")) + 10
      default: return nil
      }
      value = value << 4 | nibble
    }
    return (
      Double(value >> 16 & 255) / 255, Double(value >> 8 & 255) / 255, Double(value & 255) / 255
    )
  }

  static let names = ["copper", "ocean", "teal", "indigo", "violet", "rose", "graphite"]
  /// The color of a mark whose network is no longer configured.
  static let neutral = "graphite"
  /// A random accent that none of `used` has yet. Any accent once all are taken.
  static func random(avoiding used: some Collection<String>) -> String {
    let free = names.filter { !used.contains($0) }
    return (free.isEmpty ? names : free).randomElement() ?? names[0]
  }
}

struct ProjectCard: Codable, Identifiable, Sendable {
  var slot: UInt32
  var label: String
  var paths: [String]
  var id: UInt32 { slot }
  /// The account's own addresses, then its payment addresses, each by index.
  var orderedPaths: [String] {
    paths.sorted { Self.position($0) < Self.position($1) }
  }
  /// The address to receive at by default: the newest of the account's own addresses
  /// (the highest index on branch 0), else its newest payment address.
  var latestPath: String? {
    let ordered = orderedPaths
    return ordered.last { Self.position($0).0 == 0 } ?? ordered.last
  }
  private static func position(_ path: String) -> (UInt32, UInt32) {
    let parts = path.split(separator: "/")
    return (UInt32(parts.dropLast().last ?? "") ?? 0, UInt32(parts.last ?? "") ?? 0)
  }
}

struct ReceiveAddress: Codable, Sendable {
  var path: String
  var address: String
}
