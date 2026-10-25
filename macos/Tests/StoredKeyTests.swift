import XCTest

@testable import PayroofWallet

/// Swift property names are camelCase, but stored settings and core/API JSON use
/// snake_case. These keys must never change, or existing settings stop decoding.
final class StoredKeyTests: XCTestCase {
  func testNetworkKeepsSnakeCaseKey() throws {
    let network = WalletNetwork(
      id: "eip155:1", name: "Ethereum", transactionMode: .eip1559, endpoints: [],
      endpoint: nil, enabled: true, color: "ocean")
    let json = String(decoding: try JSONEncoder().encode(network), as: UTF8.self)
    XCTAssertTrue(json.contains("\"transaction_mode\":\"eip1559\""), json)
    XCTAssertFalse(json.contains("transactionMode"), json)
    let decoded = try JSONDecoder().decode(WalletNetwork.self, from: Data(json.utf8))
    XCTAssertEqual(decoded.transactionMode, .eip1559)
  }

  func testCoreAndAPIPayloadsDecode() throws {
    let grant = try JSONDecoder().decode(
      AccessGrant.self,
      from: Data(
        #"{"id":"acc_1","name":"Shop","permissions":["paths"],"created_at":"2026-01-01T00:00:00Z"}"#
          .utf8))
    XCTAssertEqual(grant.createdAt, "2026-01-01T00:00:00Z")
    let scan = try JSONDecoder().decode(
      HistoryScan.self,
      from: Data(
        #"{"entries":[{"chain":"eip155:1","asset":"eip155:1/slip44:60","transaction":"0xab","index":0,"from":"0x1","to":"0x2","amount":"5","block":7,"timestamp":null,"direction":"in","failed":false}],"cursor":"{}"}"#
          .utf8))
    XCTAssertEqual(scan.entries[0].block, 7)
    XCTAssertNil(scan.entries[0].timestamp)
    XCTAssertEqual(scan.entries[0].direction, "in")
    let access = try JSONDecoder().decode(
      AccessReview.self,
      from: Data(
        #"{"id":"p","name":"Shop","permissions":["paths"],"status":"pending","expires_at":"2026-01-01T00:00:00Z"}"#
          .utf8))
    XCTAssertEqual(access.expiresAt, "2026-01-01T00:00:00Z")
  }
}
