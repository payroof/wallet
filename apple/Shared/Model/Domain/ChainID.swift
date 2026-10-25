import Foundation

/// A network's CAIP-2 identity, `eip155:<number>`: the one place that text is built or
/// taken apart. Decoded and stored as the plain string the core produces and consumes.
struct ChainID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible,
  ExpressibleByStringLiteral, CodingKeyRepresentable
{
  static let namespace = "eip155"
  private static let separator = ":"
  /// The core reads the number as a `u64`, so 20 digits at most.
  static let maximumDigits = 20

  /// The EIP-155 chain number.
  let number: UInt64

  /// From the number as a user types it: digits only, no leading zero, within `u64`.
  init?(number text: String) {
    guard !text.isEmpty, text.utf8.count <= Self.maximumDigits,
      text.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
      !text.hasPrefix("0"), let value = UInt64(text)
    else { return nil }
    number = value
  }

  /// From the stored text, `eip155:<number>`.
  init?(_ raw: String) {
    let prefix = Self.namespace + Self.separator
    guard raw.hasPrefix(prefix), let id = Self(number: String(raw.dropFirst(prefix.count))) else {
      return nil
    }
    self = id
  }

  init(stringLiteral value: String) {
    guard let id = Self(value) else { preconditionFailure("Not a chain ID: \(value)") }
    self = id
  }

  var rawValue: String { Self.namespace + Self.separator + String(number) }
  var description: String { rawValue }
  static func < (lhs: ChainID, rhs: ChainID) -> Bool { lhs.number < rhs.number }

  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard let id = Self(value) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Not a chain ID: \(value)"))
    }
    self = id
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var codingKey: any CodingKey { RawKey(rawValue) }
  init?<T: CodingKey>(codingKey: T) { self.init(codingKey.stringValue) }
}

/// A dictionary key that is only its text.
struct RawKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init(_ value: String) { stringValue = value }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) { nil }
}
