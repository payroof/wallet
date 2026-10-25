import Foundation

/// An asset's CAIP-19 style identity: `<chain>/slip44:<coin>` for a network's coin or
/// `<chain>/erc20:<contract>` for a token. The one place that text is built or taken
/// apart. Decoded and stored as the plain string the core produces and consumes.
struct AssetID: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral,
  CodingKeyRepresentable
{
  enum Kind: Hashable, Sendable {
    /// A network's coin, by its SLIP-44 number.
    case native(coin: UInt32)
    /// A token, by its contract.
    case token(EVMAddress)
  }

  /// SLIP-44 number of Ether, the coin a custom network is given until the user edits it.
  static let defaultCoin: UInt32 = 60
  private static let separator = "/"
  private static let nativeLabel = "slip44:"
  private static let tokenLabel = "erc20:"

  let chain: ChainID
  let kind: Kind

  init(chain: ChainID, kind: Kind) {
    self.chain = chain
    self.kind = kind
  }

  /// The network's coin.
  static func native(on chain: ChainID, coin: UInt32 = defaultCoin) -> AssetID {
    AssetID(chain: chain, kind: .native(coin: coin))
  }

  /// A token of the network.
  static func token(_ contract: EVMAddress, on chain: ChainID) -> AssetID {
    AssetID(chain: chain, kind: .token(contract))
  }

  init?(_ raw: String) {
    let parts = raw.components(separatedBy: Self.separator)
    guard parts.count == 2, let chain = ChainID(parts[0]) else { return nil }
    let component = parts[1]
    if component.hasPrefix(Self.nativeLabel),
      let coin = UInt32(component.dropFirst(Self.nativeLabel.count))
    {
      self.init(chain: chain, kind: .native(coin: coin))
    } else if component.hasPrefix(Self.tokenLabel),
      let contract = EVMAddress(String(component.dropFirst(Self.tokenLabel.count)))
    {
      self.init(chain: chain, kind: .token(contract))
    } else {
      return nil
    }
  }

  init(stringLiteral value: String) {
    guard let id = Self(value) else { preconditionFailure("Not an asset ID: \(value)") }
    self = id
  }

  /// The token's contract. Nil for a network's coin.
  var contract: EVMAddress? {
    if case .token(let contract) = kind { return contract }
    return nil
  }
  var isNative: Bool { contract == nil }

  var rawValue: String {
    switch kind {
    case .native(let coin):
      chain.rawValue + Self.separator + Self.nativeLabel + String(coin)
    case .token(let contract):
      chain.rawValue + Self.separator + Self.tokenLabel + contract.text
    }
  }
  var description: String { rawValue }

  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard let id = Self(value) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Not an asset ID: \(value)"))
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
