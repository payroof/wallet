import Foundation

/// One RPC endpoint of a network. Every endpoint is an ordinary, editable entry:
/// the ones a new wallet starts with are not treated differently from added ones.
struct RPCEndpoint: Codable, Hashable, Identifiable, Sendable {
  var name: String
  var url: String
  var id: String { url }
  /// A virtual endpoint a provider key adds. The core resolves it, no URL is stored.
  var isProvider: Bool { KeyProvider(reference: url) != nil }
}

/// A service whose API key, kept only in the encrypted vault, adds endpoints.
enum KeyProvider: String, CaseIterable, Identifiable, Sendable {
  case alchemy, infura, ankr, etherscan
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  /// What settings and endpoint lists hold instead of a URL.
  var reference: String { "provider:" + rawValue }
  init?(reference: String) {
    guard reference.hasPrefix("provider:"),
      let value = Self(rawValue: String(reference.dropFirst(9)))
    else { return nil }
    self = value
  }
}

/// A configured EVM network. Its chain identity is checked before every request.
struct WalletNetwork: Codable, Identifiable, Sendable {
  var id: ChainID
  var name: String
  var transactionMode: TransactionMode
  var endpoints: [RPCEndpoint]
  /// The selected endpoint. Always one of `endpoints`, or nil when there is none.
  var endpoint: String?
  var enabled: Bool
  /// Block explorer base URL, e.g. `https://etherscan.io`, for transaction links.
  var explorer: String?
  /// A preset name or `#RRGGBB`, the same values an account's accent takes.
  var color: String
  /// The SVG logo's text (see `SVGLogo`). Nil means no logo.
  var logo: String?
  /// Keys are snake_case, as the core writes and reads them.
  enum CodingKeys: String, CodingKey {
    case id, name, endpoints, endpoint, enabled, explorer, color, logo
    case transactionMode = "transaction_mode"
  }
}

/// Where an asset's USD price comes from: a JSON document and a dot path into it
/// (e.g. `ethereum.usd`) that leads to a number or numeric string.
struct PriceSource: Codable, Hashable, Sendable {
  var url: String
  var field: String
}

struct WalletAsset: Codable, Identifiable, Sendable {
  var id: AssetID
  var symbol: String
  var decimals: Int
  var name: String?
  var price: PriceSource?
  /// A preset name or `#RRGGBB`, the same values an account's accent takes.
  var color: String
  /// The SVG logo's text (see `SVGLogo`). Nil means no logo.
  var logo: String?
  var chain: ChainID { id.chain }
  var isNative: Bool { id.isNative }
  var contract: EVMAddress? { id.contract }

  init(
    id: AssetID, symbol: String, decimals: Int, name: String? = nil, price: PriceSource? = nil,
    color: String, logo: String? = nil
  ) {
    self.id = id
    self.symbol = symbol
    self.decimals = decimals
    self.name = name
    self.price = price
    self.color = color
    self.logo = logo
  }

  /// The core's stored form repeats the network and the kind of the ID. Both are checked
  /// against it and written again, so the JSON keeps the core's shape.
  private enum CodingKeys: String, CodingKey {
    case id, chain, kind, symbol, decimals, name, price, color, logo
  }
  private static let nativeKind = "native"
  private static let tokenKind = "erc20"

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(AssetID.self, forKey: .id)
    let kind = try container.decode(String.self, forKey: .kind)
    guard try container.decode(ChainID.self, forKey: .chain) == id.chain,
      kind == (id.isNative ? Self.nativeKind : Self.tokenKind)
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .id, in: container,
        debugDescription: "The asset's network or kind differs from its ID")
    }
    self.init(
      id: id, symbol: try container.decode(String.self, forKey: .symbol),
      decimals: try container.decode(Int.self, forKey: .decimals),
      name: try container.decodeIfPresent(String.self, forKey: .name),
      price: try container.decodeIfPresent(PriceSource.self, forKey: .price),
      color: try container.decode(String.self, forKey: .color),
      logo: try container.decodeIfPresent(String.self, forKey: .logo))
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(chain, forKey: .chain)
    try container.encode(isNative ? Self.nativeKind : Self.tokenKind, forKey: .kind)
    try container.encode(symbol, forKey: .symbol)
    try container.encode(decimals, forKey: .decimals)
    try container.encodeIfPresent(name, forKey: .name)
    try container.encodeIfPresent(price, forKey: .price)
    try container.encode(color, forKey: .color)
    try container.encodeIfPresent(logo, forKey: .logo)
  }
}

/// Transaction links on a network's block explorer: `<explorer>/tx/<hash>`, the layout
/// Etherscan-style explorers and Blockscout share.
enum Explorer {
  static func transaction(_ hash: String, _ network: WalletNetwork?) -> URL? {
    guard var base = network?.explorer, !base.isEmpty else { return nil }
    while base.hasSuffix("/") { base.removeLast() }
    return URL(string: base + "/tx/" + hash)
  }
}

/// Initial configuration supplied by the core, declared in `assets/defaults.json`. Every
/// entry carries its color and its logo as SVG text. It is copied into `LocalSettings`
/// exactly once, when a wallet is created.
struct WalletDefaults: Codable, Sendable {
  var networks: [WalletNetwork]
  var assets: [WalletAsset]
  var apiOrigin: String
  /// The Stor server suggested for new stores. The user may enter another.
  var storOrigin: String
}

/// Result of the last explicit connectivity and chain-identity check. Not persisted.
struct EndpointHealth: Sendable, Equatable {
  var verified: Bool
  var date: Date
}

enum RPCText {
  static func host(_ url: String) -> String {
    guard let components = URLComponents(string: url), let host = components.host else {
      return url
    }
    return host + (components.port.map { ":\($0)" } ?? "")
  }
  /// Host plus an elided path, so provider keys embedded in paths are not displayed.
  static func redacted(_ url: String) -> String {
    if let provider = KeyProvider(reference: url) { return provider.title }
    guard let components = URLComponents(string: url), let scheme = components.scheme,
      components.host != nil
    else { return "Invalid URL" }
    let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return "\(scheme)://\(host(url))" + (path.isEmpty && components.query == nil ? "" : "/…")
  }
}

extension RPCText {
  /// Shape check before the core's own HTTPS/loopback policy and chain check.
  static func validURL(_ value: String) -> Bool {
    guard let url = URLComponents(string: value), let host = url.host, !host.isEmpty,
      LocalDevelopment.permitsEndpoint(url), url.user == nil, url.password == nil,
      url.fragment == nil
    else { return false }
    return true
  }
}
