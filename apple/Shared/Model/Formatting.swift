import Foundation

/// Presentation of cached balance age. Values are never recomputed here.
enum WalletFreshness {
  static let staleAfter: TimeInterval = 15 * 60
  static func isStale(_ date: Date, now: Date = Date()) -> Bool {
    now.timeIntervalSince(date) > staleAfter
  }
  static func relative(_ date: Date) -> String {
    date.formatted(.relative(presentation: .named))
  }
}

/// The API's timestamps: ISO 8601 with or without fractional seconds.
enum WalletDate {
  static func parse(_ raw: String) -> Date? {
    (try? Date(raw, strategy: .iso8601)) ?? (try? Date(raw, strategy: fractional))
  }
  private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

enum WalletText {
  /// Shortened only for scanning lists. Full values are always one tap away.
  static func short(_ address: String) -> String {
    address.count > 14 ? "\(address.prefix(6))…\(address.suffix(4))" : address
  }
  /// "Address 3" for the account's own addresses (`…'/0/3`), "Payment 3" for those a
  /// Payroof project handed out (`…'/1/3`).
  static func addressName(_ path: String) -> String {
    let parts = path.split(separator: "/")
    let index = parts.last ?? ""
    return parts.dropLast().last == "1" ? "Payment \(index)" : "Address \(index)"
  }
}

/// Presentation-only arithmetic on exact atomic decimal strings (no floating point).
/// Numbers are worked on as arrays of digits, most significant first.
enum AtomicText {
  private static let zeroCode = UInt8(ascii: "0")
  private static let nineCode = UInt8(ascii: "9")

  /// The digits (0 to 9) of a plain digit string without leading zeros. Nil for anything else.
  private static func digits(_ value: String) -> [UInt8]? {
    guard !value.isEmpty else { return nil }
    var result: [UInt8] = []
    result.reserveCapacity(value.utf8.count)
    for byte in value.utf8 {
      guard (zeroCode...nineCode).contains(byte) else { return nil }
      result.append(byte - zeroCode)
    }
    let trimmed = result.drop { $0 == 0 }
    return trimmed.isEmpty ? [0] : Array(trimmed)
  }
  private static func text(_ digits: [UInt8]) -> String {
    String(decoding: digits.map { $0 + zeroCode }, as: UTF8.self)
  }
  /// -1, 0 or 1. Nil when either value is not a plain digit string.
  static func compare(_ lhs: String, _ rhs: String) -> Int? {
    guard let a = digits(lhs), let b = digits(rhs) else { return nil }
    if a.count != b.count { return a.count < b.count ? -1 : 1 }
    if a == b { return 0 }
    return a.lexicographicallyPrecedes(b) ? -1 : 1
  }
  static func add(_ lhs: String, _ rhs: String) -> String? {
    guard let a = digits(lhs), let b = digits(rhs) else { return nil }
    let x = Array(a.reversed())
    let y = Array(b.reversed())
    var result: [UInt8] = []
    var carry: UInt8 = 0
    for index in 0..<max(x.count, y.count) {
      let sum = (index < x.count ? x[index] : 0) + (index < y.count ? y[index] : 0) + carry
      result.append(sum % 10)
      carry = sum / 10
    }
    if carry > 0 { result.append(carry) }
    return text(result.reversed())
  }
  /// Exact product of two digit strings. Nil when either is not a plain digit string.
  static func multiply(_ lhs: String, _ rhs: String) -> String? {
    guard let a = digits(lhs), let b = digits(rhs) else { return nil }
    if a == [0] || b == [0] { return "0" }
    let x = Array(a.reversed())
    let y = Array(b.reversed())
    var cells = Array(repeating: 0, count: x.count + y.count)
    for (i, left) in x.enumerated() {
      var carry = 0
      for (j, right) in y.enumerated() {
        let total = cells[i + j] + Int(left) * Int(right) + carry
        cells[i + j] = total % 10
        carry = total / 10
      }
      cells[i + y.count] += carry
    }
    return text(cells.reversed().drop { $0 == 0 }.map { UInt8($0) })
  }
}
