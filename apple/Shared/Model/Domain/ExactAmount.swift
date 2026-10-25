import Foundation

enum ExactAmount {
  static let maximum =
    "115792089237316195423570985008687907853269984665640564039457584007913129639935"
  static func userInput(
    _ value: String, decimalSeparator: String = Locale.current.decimalSeparator ?? "."
  ) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if decimalSeparator != "." {
      result = result.replacingOccurrences(of: decimalSeparator, with: ".")
    }
    if result.hasPrefix(".") { result = "0" + result }
    if result.hasSuffix(".") { result.removeLast() }
    return result
  }
  static func atomic(_ value: String, decimals: Int) throws -> String {
    guard (0...36).contains(decimals) else { throw CocoaError(.coderInvalidValue) }
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count), !parts[0].isEmpty,
      parts.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) })
    else { throw CocoaError(.coderInvalidValue) }
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    guard fraction.count <= decimals else { throw CocoaError(.coderInvalidValue) }
    let digits =
      String(parts[0]) + fraction + String(repeating: "0", count: decimals - fraction.count)
    let result = String(digits.drop(while: { $0 == "0" }))
    guard !result.isEmpty,
      result.count < maximum.count || (result.count == maximum.count && result <= maximum)
    else { throw CocoaError(.coderInvalidValue) }
    return result
  }
  static func display(_ atomic: String, decimals: Int) -> String {
    guard decimals > 0, decimals <= 36, !atomic.isEmpty,
      atomic.allSatisfy({ $0.isASCII && $0.isNumber })
    else { return atomic }
    let padded = String(repeating: "0", count: max(0, decimals + 1 - atomic.count)) + atomic
    let split = padded.index(padded.endIndex, offsetBy: -decimals)
    let fraction = String(padded[split...].reversed().drop(while: { $0 == "0" }).reversed())
    return String(padded[..<split]) + (fraction.isEmpty ? "" : "." + fraction)
  }
}

extension ExactAmount {
  /// The same atomic value expressed with more decimals (appends zeros). Exact.
  static func scaled(_ atomic: String, from decimals: Int, to target: Int) -> String {
    guard target > decimals, atomic.contains(where: { $0 != "0" }) else { return atomic }
    return atomic + String(repeating: "0", count: target - decimals)
  }
  /// Presentation only: `rounded` toward zero, so a balance or an amount available is
  /// never overstated. `fraction` fixes the number of decimals instead of the policy.
  static func short(_ atomic: String, decimals: Int, fraction: Int? = nil) -> String {
    rounded(atomic, decimals: decimals, rounding: .down, fraction: fraction)
  }

  /// How a presented amount is rounded: toward zero for what is held or available,
  /// away from zero for a maximum such as a fee limit, to the nearest for the rest.
  enum Rounding: Sendable {
    case down, up, nearest
  }

  /// Presentation only, the wallet's one way of showing an amount: grouped, with as
  /// many decimals as the size of the amount deserves (`places`). Two for 1 000 or
  /// more, four from 1, and four significant digits below 1 (down to 0.00000001), so
  /// a fee reads "0.00009187", never "0.00009186500128611". A nonzero value too small
  /// for that is shown as "<0.00000001". Like every exact amount in the wallet it uses
  /// "." for decimals, and thousands are separated by a narrow space, which no locale
  /// reads as a decimal point. The exact value remains available through `display`.
  static func rounded(
    _ atomic: String, decimals: Int, rounding: Rounding = .nearest, fraction: Int? = nil
  ) -> String {
    let full = display(atomic, decimals: decimals)
    guard full.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return full }
    let parts = full.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let integer = parts[0]
    let digits = parts.count > 1 ? parts[1] : ""
    let limit = max(0, fraction ?? places(integer: integer, fraction: digits))
    let kept = Array(digits.prefix(limit))
    let rest = digits.dropFirst(limit)
    let bump: Bool
    switch rounding {
    case .down: bump = false
    case .up: bump = rest.contains { $0 != "0" }
    case .nearest: bump = (rest.first ?? "0") >= "5"
    }
    // `full` holds ASCII digits only, so these are digit codes.
    var all = Array(integer.utf8) + Array(String(kept).utf8)
    if bump {
      let zero = UInt8(ascii: "0")
      let nine = UInt8(ascii: "9")
      var index = all.count - 1
      var carry = true
      while carry && index >= 0 {
        if all[index] == nine {
          all[index] = zero
          index -= 1
        } else {
          all[index] += 1
          carry = false
        }
      }
      if carry { all.insert(UInt8(ascii: "1"), at: 0) }
    }
    let whole = String(decoding: all.prefix(all.count - kept.count), as: UTF8.self)
    var shown = String(decoding: all.suffix(kept.count), as: UTF8.self)
    while shown.hasSuffix("0") { shown.removeLast() }
    let point = "."
    if shown.isEmpty && whole.allSatisfy({ $0 == "0" }) && digits.contains(where: { $0 != "0" }) {
      return "<0" + point + String(repeating: "0", count: max(0, limit - 1)) + "1"
    }
    let separator = "\u{202F}"
    var grouped = ""
    for (offset, character) in whole.enumerated() {
      if offset > 0 && (whole.count - offset) % 3 == 0 { grouped += separator }
      grouped.append(character)
    }
    return grouped + (shown.isEmpty ? "" : point + shown)
  }

  /// Decimals shown for an amount of this size (see `rounded`).
  static func places(integer: String, fraction: String) -> Int {
    if integer.count >= 4 { return 2 }
    if integer.contains(where: { $0 != "0" }) { return 4 }
    let zeros = fraction.prefix { $0 == "0" }.count
    return min(zeros + 4, 8)
  }
}
