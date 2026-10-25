import XCTest

@testable import PayroofWallet

final class TransferSubmissionTests: XCTestCase {
  private let asset = WalletAsset(
    id: "eip155:1/slip44:60", symbol: "ETH", decimals: 18,
    name: nil, color: "ocean")

  private func transfer(_ id: String, _ status: String, _ kind: PlanStepKind = .transfer)
    -> LocalTransfer
  {
    LocalTransfer(
      id: id, endpoint: "https://rpc.example", chain: "eip155:1", asset: asset.id,
      recipient: "0x" + String(repeating: "a", count: 40), amount: "1", status: status,
      date: Date(), source: "m/44'/60'/0'/0/0", slot: 0, assetSnapshot: asset, kind: kind)
  }

  private func submission(_ hashes: [String]) -> TransferSubmission {
    TransferSubmission(
      slot: 0, chain: "eip155:1", asset: asset.id, amount: "1",
      recipient: "0x" + String(repeating: "a", count: 40), transactions: hashes, date: Date())
  }

  func testStageFollowsEveryTransactionOfThePlan() {
    let sent = submission(["0x1", "0x2"])
    XCTAssertEqual(
      sent.stage(in: [transfer("0x1", "confirmed", .topUp), transfer("0x2", "pending")]),
      .pending)
    XCTAssertEqual(
      sent.stage(in: [transfer("0x1", "confirmed", .topUp), transfer("0x2", "confirmed")]),
      .confirmed)
    XCTAssertEqual(
      sent.stage(in: [transfer("0x1", "failed", .topUp), transfer("0x2", "pending")]), .failed,
      "One failed step fails the transfer")
    XCTAssertEqual(sent.transfer, "0x2", "The last transaction moved the funds")
  }

  func testUnknownOrEmptyIsNeverConfirmed() {
    XCTAssertEqual(submission(["0x1"]).stage(in: []), .pending)
    XCTAssertEqual(submission([]).stage(in: [transfer("0x1", "confirmed")]), .pending)
  }
}
