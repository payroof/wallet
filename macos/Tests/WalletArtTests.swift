import XCTest

@testable import PayroofWallet

final class WalletArtTests: XCTestCase {
  private let logo =
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><path d="M0 0H8V8Z"/></svg>"#

  private func network(color: String = "ocean", logo: String? = nil) -> WalletNetwork {
    WalletNetwork(
      id: "eip155:9", name: "Nine", transactionMode: .eip1559, endpoints: [], endpoint: nil,
      enabled: true, explorer: nil, color: color, logo: logo)
  }

  // MARK: Defaults

  /// The core declares a color and a logo for every default network and token. The logo
  /// arrives as SVG text that the app can draw.
  func testEveryDefaultCarriesAColorAndARenderableLogo() throws {
    let defaults = try JSONDecoder().decode(
      WalletDefaults.self, from: Data(defaultConfiguration().utf8))
    XCTAssertFalse(defaults.networks.isEmpty)
    XCTAssertFalse(defaults.assets.isEmpty)
    let arts =
      defaults.networks.map { ($0.id.rawValue, $0.art) }
      + defaults.assets.map { ($0.id.rawValue, $0.art) }
    for (id, art) in arts {
      XCTAssertTrue(AccountAccent.isValid(art.color), "color for \(id)")
      let text = try XCTUnwrap(art.logo, "logo for \(id)")
      let image = try SVGLogo.parse(text)
      XCTAssertEqual(image.width, 32, id)
      XCTAssertEqual(image.height, 32, id)
      XCTAssertLessThan(text.utf8.count, 4096, id)
    }
  }

  func testSeedingCopiesColorAndLogoIntoSettings() throws {
    let defaults = try JSONDecoder().decode(
      WalletDefaults.self, from: Data(defaultConfiguration().utf8))
    let settings = LocalSettings(defaults: defaults)
    XCTAssertEqual(settings.networks.map(\.art), defaults.networks.map(\.art))
    XCTAssertEqual(settings.assets.map(\.art), defaults.assets.map(\.art))
    XCTAssertTrue(settings.networks.allSatisfy { $0.logo != nil })
    XCTAssertTrue(settings.assets.allSatisfy { $0.logo != nil })
    let back = try LocalSettingsCodec.decode(JSONEncoder().encode(settings))
    XCTAssertEqual(back.networks.map(\.art), settings.networks.map(\.art))
    XCTAssertEqual(back.assets.map(\.art), settings.assets.map(\.art))
  }

  // MARK: Colors

  func testRandomColorsComeFromTheSharedPalette() {
    var used: [String] = []
    for _ in 0..<AccountAccent.names.count {
      let pick = AccountAccent.random(avoiding: used)
      XCTAssertTrue(AccountAccent.names.contains(pick))
      XCTAssertFalse(used.contains(pick), "free presets come first")
      used.append(pick)
    }
    XCTAssertTrue(AccountAccent.names.contains(AccountAccent.random(avoiding: used)))
    XCTAssertTrue(
      WalletAccent.presets.map(\.rawValue).contains(WalletAccent.random(avoiding: []).rawValue))
  }

  func testArtResolvesItsColorLikeAnAccount() {
    XCTAssertEqual(WalletArt(color: "ocean", logo: nil).accent, WalletAccent(rawValue: "ocean"))
    XCTAssertEqual(WalletArt(color: "#627eea", logo: nil).accent.rawValue, "#627EEA")
    XCTAssertEqual(WalletArt.neutral.accent, WalletAccent(rawValue: AccountAccent.neutral))
  }

  // MARK: Validation

  func testValidatedLookRefusesBadInput() throws {
    XCTAssertThrowsError(try WalletLook(color: "red", logo: nil).validated())
    XCTAssertThrowsError(try WalletLook(color: "", logo: nil).validated())
    XCTAssertThrowsError(try WalletLook(color: "ocean", logo: "<svg><script/></svg>").validated())
    XCTAssertEqual(try WalletLook(color: "#aabbcc", logo: "  ").validated().logo, nil)
    XCTAssertEqual(try WalletLook(color: "#aabbcc", logo: nil).validated().color, "#AABBCC")
    XCTAssertEqual(try WalletLook(color: "ocean", logo: " \(logo)\n").validated().logo, logo)
  }

  // MARK: Codable

  func testColorIsRequiredAndLogoIsOptional() throws {
    let withoutColor = #"""
      {"id":"eip155:1","name":"Ethereum","transaction_mode":"eip1559","endpoints":[],
       "endpoint":null,"enabled":true,"explorer":null}
      """#
    XCTAssertThrowsError(
      try JSONDecoder().decode(WalletNetwork.self, from: Data(withoutColor.utf8)))
    let asset =
      #"{"id":"eip155:1/slip44:60","chain":"eip155:1","kind":"native","symbol":"ETH","decimals":18}"#
    XCTAssertThrowsError(try JSONDecoder().decode(WalletAsset.self, from: Data(asset.utf8)))
    let withColor =
      #"{"id":"eip155:1/slip44:60","chain":"eip155:1","kind":"native","symbol":"E","decimals":18,"color":"teal"}"#
    XCTAssertNil(try JSONDecoder().decode(WalletAsset.self, from: Data(withColor.utf8)).logo)
  }

  func testColorAndLogoRoundTripThroughSettings() throws {
    var settings = LocalSettings()
    settings.networks = [network(color: "#112233", logo: logo)]
    settings.assets = [
      WalletAsset(
        id: "eip155:9/slip44:60", symbol: "N", decimals: 18,
        name: nil, price: nil, color: "violet", logo: nil)
    ]
    let back = try LocalSettingsCodec.decode(JSONEncoder().encode(settings))
    XCTAssertEqual(back.networks.first?.art, WalletArt(color: "#112233", logo: logo))
    XCTAssertEqual(back.assets.first?.art, WalletArt(color: "violet", logo: nil))
  }

  func testSettingsWithAnInvalidColorOrLogoAreRejected() throws {
    for bad in [network(color: "red"), network(logo: "<script/>")] {
      var settings = LocalSettings()
      settings.networks = [bad]
      XCTAssertThrowsError(try LocalSettingsCodec.decode(JSONEncoder().encode(settings)))
    }
  }

  func testNoLogoStaysAbsentWhenEncoded() throws {
    let object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(network())) as? [String: Any]
    XCTAssertEqual(object?["color"] as? String, "ocean")
    XCTAssertNil(object?["logo"])
  }
}
