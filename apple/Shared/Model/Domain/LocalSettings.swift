import Foundation

/// Persisted public preferences. Every key is required when decoding, except those that
/// are optional, which are left out while empty. Networks, endpoints, assets and the
/// API origin are ordinary editable entries.
struct LocalSettings: Codable, Sendable {
  /// 3 merged the device unlock switch and its policy into one optional policy and
  /// moved the store links and the Stor server in. Settings of any other version start
  /// over from the defaults.
  static let schema = 3
  var version = schema
  var networks: [WalletNetwork] = []
  var assets: [WalletAsset] = []
  /// Asset IDs hidden from Wallet and Send. Balances are not deleted.
  var hiddenAssets: [AssetID] = []
  /// Suggested origin when connecting an account to a Payroof API.
  var apiOrigin = ""
  /// Last checked balance per address and asset, keyed by `balanceKey`.
  var balances: [String: CachedBalance] = [:]
  /// Last fetched USD price per asset ID.
  var prices: [AssetID: CachedPrice] = [:]
  var transfers: [LocalTransfer] = []
  /// How the device may unlock the wallet besides the PIN. Nil means the PIN only.
  var deviceUnlock: DeviceUnlockPolicy?
  var connections: [PathConnection] = []
  /// Accent per account: slot (as text) to a preset name or a `#RRGGBB` color.
  var accents: [String: String] = [:]
  /// The Stor server stores are created on. Seeded from the defaults, editable.
  var storServer = ""
  /// Public links of the stores created from this device, by connection ID. Each
  /// store's key lives on its Stor server.
  var storeLinks: [String: [String]] = [:]
  init() {}
  init(defaults: WalletDefaults) {
    networks = defaults.networks
    assets = defaults.assets
    apiOrigin = defaults.apiOrigin
    storServer = defaults.storOrigin
  }
  static func balanceKey(path: String, asset: AssetID) -> String { path + "#" + asset.rawValue }

  /// The local test chain (Anvil), present only in local development builds.
  static let developmentChain = "eip155:31337"

  /// Local development only: the test chain's default tokens this wallet doesn't list yet
  /// (tokens added to the defaults after it was created) are added, so a test wallet
  /// sees what the local stack deploys. Nothing changes without the test network.
  /// Returns whether anything was added.
  mutating func adoptDevelopmentAssets(from defaults: WalletDefaults) -> Bool {
    guard networks.contains(where: { $0.id.rawValue == Self.developmentChain }) else {
      return false
    }
    let known = Set(assets.map(\.id))
    let missing = defaults.assets.filter {
      $0.chain.rawValue == Self.developmentChain && !known.contains($0.id)
    }
    assets.append(contentsOf: missing)
    return !missing.isEmpty
  }
}

enum LocalSettingsCodec {
  struct Version: Decodable { var version: Int }
  /// Decodes the current schema only. Any other version is rejected, and so are entries
  /// whose color or logo is not valid.
  static func decode(_ data: Data) throws -> LocalSettings {
    let decoder = JSONDecoder()
    guard try decoder.decode(Version.self, from: data).version == LocalSettings.schema else {
      throw CocoaError(.coderInvalidValue)
    }
    let settings = try decoder.decode(LocalSettings.self, from: data)
    guard settings.networks.allSatisfy({ $0.art.isValid }),
      settings.assets.allSatisfy({ $0.art.isValid })
    else { throw CocoaError(.coderInvalidValue) }
    return settings
  }
}
