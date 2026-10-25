import XCTest

@testable import PayroofWallet

/// Data-driven configuration: seeded defaults are ordinary settings entries,
/// and decoding stays strict.
final class RPCConfigurationTests: XCTestCase {
  private let defaults = WalletDefaults(
    networks: [
      WalletNetwork(
        id: "eip155:1", name: "Ethereum", transactionMode: .eip1559,
        endpoints: [
          RPCEndpoint(name: "PublicNode", url: "https://ethereum.publicnode.com"),
          RPCEndpoint(name: "dRPC", url: "https://eth.drpc.org"),
        ], endpoint: "https://ethereum.publicnode.com", enabled: true, color: "ocean"),
      WalletNetwork(
        id: "eip155:8453", name: "Base", transactionMode: .eip1559,
        endpoints: [RPCEndpoint(name: "PublicNode", url: "https://base.publicnode.com")],
        endpoint: "https://base.publicnode.com", enabled: true, color: "ocean"),
      WalletNetwork(
        id: "eip155:56", name: "BNB Smart Chain", transactionMode: .legacy,
        endpoints: [RPCEndpoint(name: "BNB", url: "https://bsc-dataseed.bnbchain.org")],
        endpoint: "https://bsc-dataseed.bnbchain.org", enabled: true, color: "ocean"),
    ],
    assets: [
      WalletAsset(
        id: "eip155:1/slip44:60", symbol: "ETH", decimals: 18,
        name: "Ether", color: "ocean"),
      WalletAsset(
        id: "eip155:1/erc20:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", symbol: "USDC",
        decimals: 6, name: "USD Coin", color: "teal"),
      WalletAsset(
        id: "eip155:8453/erc20:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", symbol: "USDC",
        decimals: 6, name: "USD Coin", color: "teal"),
    ],
    apiOrigin: "https://api.example", storOrigin: "https://stor.example")

  private func snapshot(_ settings: LocalSettings) -> WalletSnapshot {
    var snapshot = WalletSnapshot()
    snapshot.settings = settings
    return snapshot
  }

  func testNewWalletStartsFromEditableDefaults() {
    var settings = LocalSettings(defaults: defaults)
    XCTAssertEqual(settings.networks.count, 3)
    XCTAssertEqual(settings.assets.count, 3)
    XCTAssertEqual(settings.apiOrigin, "https://api.example")
    XCTAssertEqual(snapshot(settings).endpoint(for: "eip155:1"), "https://ethereum.publicnode.com")
    // Defaults are plain entries: removing or editing them is ordinary data editing,
    // and nothing re-adds them behind the user's back.
    settings.networks[0].endpoints.removeAll { $0.url == "https://ethereum.publicnode.com" }
    settings.networks[0].endpoint = settings.networks[0].endpoints.first?.url
    settings.assets.removeAll { $0.symbol == "USDC" && $0.chain == "eip155:1" }
    settings.networks.removeAll { $0.id == "eip155:56" }
    let state = snapshot(settings)
    XCTAssertEqual(state.endpoint(for: "eip155:1"), "https://eth.drpc.org")
    XCTAssertEqual(state.endpoints(for: "eip155:1").map(\.url), ["https://eth.drpc.org"])
    XCTAssertNil(state.endpoint(for: "eip155:56"), "A removed network is gone")
    XCTAssertEqual(state.assets.filter { $0.symbol == "USDC" }.map(\.chain), ["eip155:8453"])
  }

  func testEndpointNeedsAnEnabledNetworkAndAConfiguredSelection() {
    var settings = LocalSettings(defaults: defaults)
    settings.networks[1].enabled = false
    settings.networks[2].endpoint = "https://not-in-the-list.example"
    let state = snapshot(settings)
    XCTAssertNil(state.endpoint(for: "eip155:8453"), "Off wins over a selection")
    XCTAssertNil(state.endpoint(for: "eip155:56"), "Only configured endpoints are used")
    XCTAssertNil(state.endpoint(for: "eip155:999"), "Unknown network")
    XCTAssertEqual(state.connectedNetworks.map(\.id), ["eip155:1"])
    XCTAssertEqual(state.usableAssets.map(\.chain), ["eip155:1", "eip155:1"])
  }

  func testSettingsDecodingStaysStrict() throws {
    let encoded = try JSONEncoder().encode(LocalSettings(defaults: defaults))
    XCTAssertNoThrow(try LocalSettingsCodec.decode(encoded))
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "networks")
    XCTAssertThrowsError(
      try LocalSettingsCodec.decode(
        JSONSerialization.data(withJSONObject: object)))
    object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["version"] = LocalSettings.schema + 1
    XCTAssertThrowsError(
      try LocalSettingsCodec.decode(
        JSONSerialization.data(withJSONObject: object)))
    XCTAssertThrowsError(
      try LocalSettingsCodec.decode(Data(#"{"version":1}"#.utf8)))
  }

  func testDisplayedEndpointsHideEmbeddedKeys() {
    XCTAssertEqual(
      RPCText.redacted("https://mainnet.infura.io/v3/0123456789abcdef"),
      "https://mainnet.infura.io/…")
    XCTAssertEqual(
      RPCText.redacted("https://rpc.example.com?key=secret"), "https://rpc.example.com/…")
    XCTAssertEqual(RPCText.redacted("https://eth.drpc.org"), "https://eth.drpc.org")
    XCTAssertEqual(RPCText.host("https://arb1.arbitrum.io/rpc"), "arb1.arbitrum.io")
    XCTAssertEqual(RPCText.redacted("provider:alchemy"), "Alchemy")
  }

  func testProviderReferencesAreOpaqueAndNeverUserURLs() {
    for provider in KeyProvider.allCases {
      XCTAssertEqual(KeyProvider(reference: provider.reference), provider)
      XCTAssertTrue(RPCEndpoint(name: provider.title, url: provider.reference).isProvider)
      XCTAssertFalse(RPCText.validURL(provider.reference))
    }
    XCTAssertNil(KeyProvider(reference: "provider:unknown"))
    XCTAssertNil(KeyProvider(reference: "https://eth.drpc.org"))
  }

  func testEndpointURLShapeIsCheckedBeforeTheCore() {
    XCTAssertTrue(RPCText.validURL("https://rpc.example.com/path"))
    for bad in [
      "http://rpc.example.com", "https://user:pass@rpc.example.com", "https://rpc.example.com#x",
      "ftp://rpc.example.com", "rpc.example.com", "https://",
    ] {
      XCTAssertFalse(RPCText.validURL(bad), bad)
    }
  }

  /// The shipped seed decodes into the same types the settings persist.
  func testShippedDefaultsDecodeIntoSettingsTypes() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("assets/defaults.json")
    let raw = try Data(contentsOf: url)
    let text = try XCTUnwrap(String(data: raw, encoding: .utf8)).lowercased()
    for secret in ["apikey", "api_key", "api-key", "/v2/", "key="] {
      XCTAssertFalse(text.contains(secret), "defaults carry no provider keys: \(secret)")
    }
    let shipped = try JSONDecoder().decode(WalletDefaults.self, from: raw)
    let state = snapshot(LocalSettings(defaults: shipped))
    XCTAssertFalse(shipped.networks.isEmpty)
    for network in shipped.networks {
      XCTAssertNotNil(state.endpoint(for: network.id), "\(network.name) works out of the box")
      XCTAssertNotNil(state.nativeAsset(network.id), "\(network.name) has a native coin entry")
    }
  }

  // MARK: Portfolio

  func testHoldingsSumPerAddressAndGroupBySymbolExactly() throws {
    var settings = LocalSettings(defaults: defaults)
    let bsc = WalletAsset(
      id: "eip155:56/erc20:0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d", symbol: "USDC",
      decimals: 18, name: nil, color: "rose")
    settings.assets.append(bsc)
    let date = Date()
    let a = "m/44'/60'/0'/0/0"
    let b = "m/44'/60'/0'/0/1"
    func put(_ path: String, _ asset: AssetID, _ atomic: String) {
      settings.balances[LocalSettings.balanceKey(path: path, asset: asset)] = CachedBalance(
        atomic: atomic, date: date)
    }
    put(a, defaults.assets[1].id, "1500000")  // 1.5 USDC on Ethereum
    put(b, defaults.assets[1].id, "250000")  // 0.25
    put(a, defaults.assets[2].id, "0")  // Base USDC, zero
    put(b, bsc.id, "1000000000000000001")  // 1.000000000000000001 on BSC
    put(a, defaults.assets[0].id, "0")
    put(b, defaults.assets[0].id, "0")
    let state = snapshot(settings)
    let account = ProjectCard(slot: 0, label: "Main", paths: [b, a])
    let holdings = WalletPortfolio.holdings(state, account: account)
    XCTAssertEqual(holdings.first { $0.asset.id == defaults.assets[1].id }?.total, "1750000")
    let groups = WalletPortfolio.groups(holdings)
    XCTAssertEqual(groups.map(\.symbol), ["USDC"], "Zero balances are not part of the total")
    let usdc = try XCTUnwrap(groups.first)
    XCTAssertEqual(usdc.decimals, 18)
    XCTAssertEqual(ExactAmount.display(usdc.total, decimals: 18), "2.750000000000000001")
    XCTAssertEqual(usdc.holdings.map(\.asset.chain), ["eip155:1", "eip155:56"])
  }

  func testUSDTotalUsesExactDecimalsAndExcludesUnpricedHoldings() throws {
    var settings = LocalSettings(defaults: defaults)
    let ether = defaults.assets[0]
    let dai = WalletAsset(
      id: "eip155:1/erc20:0x6b175474e89094c44da98b954eedeac495271d0f", symbol: "DAI", decimals: 18,
      name: nil, color: "rose")
    let odd = WalletAsset(
      id: "eip155:1/erc20:0x1111111111111111111111111111111111111111", symbol: "TEST", decimals: 8,
      name: nil, color: "rose")
    settings.assets += [dai, odd]
    let path = "m/44'/60'/0'/0/0"
    func put(_ asset: WalletAsset, _ atomic: String) {
      settings.balances[LocalSettings.balanceKey(path: path, asset: asset.id)] = CachedBalance(
        atomic: atomic, date: Date())
    }
    put(dai, "59000000000000000000")
    put(ether, "2000000000000000")
    put(odd, "100000000")
    settings.prices[dai.id] = CachedPrice(usd: "1", date: Date())
    settings.prices[ether.id] = CachedPrice(usd: "3000.00", date: Date())
    let state = snapshot(settings)
    let groups = WalletPortfolio.groups(
      WalletPortfolio.holdings(state, account: ProjectCard(slot: 0, label: "Main", paths: [path])))
    let total = WalletPortfolio.total(groups, prices: settings.prices)
    XCTAssertEqual(total.usd, 65)
    XCTAssertEqual(WalletPortfolio.currency(65), "$65.00")
    XCTAssertEqual(WalletPortfolio.currency(Decimal(string: "1234.567")!), "$1,234.57")
    XCTAssertEqual(WalletPortfolio.currency(Decimal(string: "0.004")!), "<$0.01")
    XCTAssertEqual(WalletPortfolio.currency(0), "$0.00")
    XCTAssertEqual(total.excluded, ["TEST"])
    XCTAssertEqual(WalletPortfolio.total(groups, prices: [:]).usd, nil)
    XCTAssertEqual(ExactAmount.usd("1", decimals: 6, price: "0.5"), Decimal(string: "0.0000005"))
    XCTAssertNil(ExactAmount.usd("1", decimals: 6, price: "-1"))
  }

  func testShortAmountsTruncateAndGroupForDisplayOnly() {
    let space = "\u{202F}"
    XCTAssertEqual(ExactAmount.short("1234567890", decimals: 6), "1\(space)234.56")
    XCTAssertEqual(ExactAmount.short("123456789", decimals: 8), "1.2345")
    XCTAssertEqual(ExactAmount.short("1", decimals: 18), "<0.00000001")
    XCTAssertEqual(ExactAmount.short("0", decimals: 18), "0")
    XCTAssertEqual(ExactAmount.short("5000000", decimals: 6), "5")
    XCTAssertEqual(ExactAmount.short("1234567000", decimals: 3), "1\(space)234\(space)567")
    XCTAssertEqual(ExactAmount.short("19999999", decimals: 6), "19.9999")
    XCTAssertEqual(
      ExactAmount.short("1999999999", decimals: 6), "1\(space)999.99", "Truncated, never rounded up"
    )
    XCTAssertEqual(ExactAmount.scaled("15", from: 6, to: 18), "15000000000000")
    XCTAssertEqual(ExactAmount.scaled("0", from: 6, to: 18), "0")
  }
}
