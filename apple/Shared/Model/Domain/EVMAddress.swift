import Foundation

/// A plain EVM address: `0x` and 40 hexadecimal digits. Checked once, here, so every
/// place that takes an address (a recipient, a token contract, a scanned code) agrees.
/// The text keeps the case it was given. The checksum is not checked, the core does.
struct EVMAddress: Hashable, Sendable, Codable, CustomStringConvertible {
  static let prefix = "0x"
  static let digitCount = 40
  static let length = prefix.utf8.count + digitCount

  /// Why a text is not (yet) an address.
  enum Problem: Error, Equatable, Sendable {
    /// Starts like an address but is shorter than one, as while typing.
    case incomplete
    /// Not `0x` and 40 hexadecimal digits.
    case malformed
    /// The all-zero address, which cannot be a recipient or a contract.
    case zero
  }

  /// The address as given: `0x` and 40 digits.
  let text: String

  /// The address, or the reason the text is not one. The zero address is a `Problem`
  /// unless `allowZero`.
  static func check(_ text: String, allowZero: Bool = false) -> Result<EVMAddress, Problem> {
    let bytes = Array(text.utf8)
    guard text.hasPrefix(prefix) else { return .failure(.malformed) }
    let digits = bytes.dropFirst(prefix.utf8.count)
    guard digits.allSatisfy(Self.isHexDigit) else { return .failure(.malformed) }
    guard digits.count == digitCount else {
      return .failure(digits.count < digitCount ? .incomplete : .malformed)
    }
    guard allowZero || digits.contains(where: { $0 != UInt8(ascii: "0") }) else {
      return .failure(.zero)
    }
    return .success(EVMAddress(validated: text))
  }

  init?(_ text: String, allowZero: Bool = false) {
    guard case .success(let address) = Self.check(text, allowZero: allowZero) else {
      return nil
    }
    self = address
  }

  private init(validated text: String) { self.text = text }

  var lowercased: String { text.lowercased() }
  /// The same address in lowercase, the form the wallet stores contracts in.
  var normalized: EVMAddress { EVMAddress(validated: lowercased) }
  var description: String { text }

  private static func isHexDigit(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
      || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
      || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
  }

  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard let address = EVMAddress(value) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Not an EVM address"))
    }
    self = address
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(text)
  }
}
