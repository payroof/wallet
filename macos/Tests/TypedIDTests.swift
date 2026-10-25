import XCTest

@testable import PayroofWallet

/// The typed identities: parsed once, encoded as the plain text the core uses.
final class TypedIDTests: XCTestCase {
  /// A string literal would pick the trapping literal initializer, so parse from a variable.
  private func chain(_ text: String) -> ChainID? { ChainID(text) }
  private func asset(_ text: String) -> AssetID? { AssetID(text) }
  private let usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

  func testChainIDParsesOnlyCanonicalText() throws {
    XCTAssertEqual(chain("eip155:8453")?.number, 8453)
    XCTAssertEqual(chain("eip155:8453")?.rawValue, "eip155:8453")
    for bad in [
      "", "8453", "eip155:", "eip155:0x1", "eip155:01", "eip155:-1", "eip155:1 ",
      "eip155:18446744073709551616", "solana:1",
    ] {
      XCTAssertNil(chain(bad), bad)
    }
    XCTAssertEqual(ChainID(number: "137")?.rawValue, "eip155:137")
    XCTAssertNil(ChainID(number: "0"))
    XCTAssertNil(ChainID(number: "1e3"))
    XCTAssertLessThan(ChainID(number: "1")!, ChainID(number: "10")!)
  }

  func testChainIDCodableIsAPlainStringAndRejectsOthers() throws {
    let data = try JSONEncoder().encode(["chain": chain("eip155:56")!])
    XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"chain":"eip155:56"}"#)
    XCTAssertThrowsError(try JSONDecoder().decode(ChainID.self, from: Data(#""base""#.utf8)))
    let keyed = try JSONDecoder().decode(
      [ChainID: Int].self, from: Data(#"{"eip155:1":2}"#.utf8))
    XCTAssertEqual(keyed[chain("eip155:1")!], 2)
  }

  func testAssetIDParsesNativeAndTokenForms() throws {
    let native = try XCTUnwrap(asset("eip155:1/slip44:60"))
    XCTAssertTrue(native.isNative)
    XCTAssertEqual(native.chain, "eip155:1")
    XCTAssertNil(native.contract)
    let token = try XCTUnwrap(asset("eip155:1/erc20:\(usdc)"))
    XCTAssertEqual(token.contract?.text, usdc)
    XCTAssertEqual(token, .token(try XCTUnwrap(EVMAddress(usdc)), on: "eip155:1"))
    XCTAssertEqual(native, .native(on: "eip155:1"))
    XCTAssertEqual(token.rawValue, "eip155:1/erc20:\(usdc)")
    for bad in [
      "", "eip155:1", "eip155:1/native", "eip155:1/erc20:0xabc", "base/slip44:60",
      "eip155:1/slip44:x", "eip155:1/slip44:60/x",
    ] {
      XCTAssertNil(asset(bad), bad)
    }
  }

  func testAssetIDCodableAndAsDictionaryKey() throws {
    let token = asset("eip155:1/erc20:\(usdc)")!
    let data = try JSONEncoder().encode([token: 1])
    let back = try JSONDecoder().decode([AssetID: Int].self, from: data)
    XCTAssertEqual(back[token], 1)
    XCTAssertThrowsError(try JSONDecoder().decode(AssetID.self, from: Data(#""x""#.utf8)))
  }

  func testEVMAddressChecks() {
    XCTAssertNotNil(EVMAddress(usdc))
    XCTAssertNotNil(EVMAddress(usdc.uppercased().replacingOccurrences(of: "0X", with: "0x")))
    XCTAssertEqual(EVMAddress.check("0x12").failureProblem, .incomplete)
    XCTAssertEqual(EVMAddress.check("0x").failureProblem, .incomplete)
    XCTAssertEqual(EVMAddress.check(usdc + "0").failureProblem, .malformed)
    XCTAssertEqual(
      EVMAddress.check("0x" + String(repeating: "g", count: 40)).failureProblem, .malformed)
    XCTAssertEqual(EVMAddress.check(String(usdc.dropFirst(2))).failureProblem, .malformed)
    let zero = "0x" + String(repeating: "0", count: 40)
    XCTAssertEqual(EVMAddress.check(zero).failureProblem, .zero)
    XCTAssertNotNil(EVMAddress(zero, allowZero: true))
    XCTAssertEqual(
      EVMAddress(usdc.uppercased().replacingOccurrences(of: "0X", with: "0x"))?.normalized.text,
      usdc)
  }

  func testEveryAddressEntryPointAgrees() {
    let cases = [usdc, "0x", "0x1", usdc + "0", "0x" + String(repeating: "0", count: 40)]
    for text in cases {
      XCTAssertEqual(QRScanPurpose.address.accepts(text), EVMAddress(text) != nil, text)
    }
  }

  func testTransactionModeMapsToTheCoresFlag() throws {
    XCTAssertTrue(TransactionMode.legacy.isLegacy)
    XCTAssertFalse(TransactionMode.eip1559.isLegacy)
    XCTAssertEqual(TransactionMode(legacy: true), .legacy)
    XCTAssertEqual(TransactionMode(legacy: false), .eip1559)
    XCTAssertEqual(TransactionMode(rawValue: "eip1559"), .eip1559)
    XCTAssertNil(TransactionMode(rawValue: "type2"))
    XCTAssertThrowsError(
      try JSONDecoder().decode(TransactionMode.self, from: Data(#""Legacy""#.utf8)))
  }

  func testSettingsRoundTripKeepsMergedPolicyAndStoreLinks() throws {
    var settings = LocalSettings()
    settings.deviceUnlock = .devicePasscode
    settings.storServer = "https://stor.example"
    settings.storeLinks = ["https://api.example#p": ["https://sheet.example/1"]]
    settings.hiddenAssets = [asset("eip155:1/slip44:60")!]
    let back = try LocalSettingsCodec.decode(JSONEncoder().encode(settings))
    XCTAssertEqual(back.deviceUnlock, .devicePasscode)
    XCTAssertEqual(back.storServer, "https://stor.example")
    XCTAssertEqual(back.storeLinks, settings.storeLinks)
    XCTAssertEqual(back.hiddenAssets, settings.hiddenAssets)
    var none = LocalSettings()
    none.deviceUnlock = nil
    XCTAssertNil(try LocalSettingsCodec.decode(JSONEncoder().encode(none)).deviceUnlock)
  }

  func testOtherSchemaVersionsAreRejected() throws {
    var settings = LocalSettings()
    settings.version = LocalSettings.schema - 1
    XCTAssertThrowsError(try LocalSettingsCodec.decode(JSONEncoder().encode(settings)))
  }

  func testPairingLinkConstantsDriveValidation() {
    let id =
      WalletIncomingLink.pairingIDPrefix
      + String(
        repeating: "a",
        count: WalletIncomingLink.pairingIDLength - WalletIncomingLink.pairingIDPrefix.utf8.count)
    let url = "https://api.example" + WalletIncomingLink.pairingsPath + id
    XCTAssertNotNil(URL(string: url).flatMap(WalletIncomingLink.resolve))
    XCTAssertNil(URL(string: url + "a").flatMap(WalletIncomingLink.resolve))
  }
}

extension Result {
  fileprivate var failureProblem: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }
}
