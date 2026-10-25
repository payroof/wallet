import XCTest

@testable import PayroofWallet

/// The core's plan JSON (snake_case, atomic strings) and the exact fee arithmetic the
/// review shows: no floating point anywhere.
final class SendPlanTests: XCTestCase {
  /// Two sources: one signs an authorization the sponsor submits, the other is topped
  /// up by the sponsor and then sends itself. 30 gwei.
  private static let json = #"""
    {"plan":{"network":"eip155:137","asset":"eip155:137/erc20:0x1111111111111111111111111111111111111111","recipient":"0x00000000000000000000000000000000000000r1",
    "amount":"100000000","mode":"eip1559","max_fee_per_gas":"30000000000","maximum_fee":"7080000000000000",
    "sponsor":{"path":"m/44'/60'/0'/0/2","address":"0xsponsor"},
    "sources":[{"path":"m/44'/60'/0'/0/0","address":"0xa","amount":"60000000"},
               {"path":"m/44'/60'/0'/0/1","address":"0xb","amount":"40000000"}],
    "steps":[
     {"kind":"authorization","payer_path":"m/44'/60'/0'/0/2","payer":"0xsponsor","owner_path":"m/44'/60'/0'/0/0","owner":"0xa","to":"0xr","amount":"60000000","gas_limit":"150000","maximum_fee":"4500000000000000","after":[]},
     {"kind":"top_up","payer_path":"m/44'/60'/0'/0/2","payer":"0xsponsor","owner_path":"m/44'/60'/0'/0/2","owner":"0xsponsor","to":"0xb","amount":"1950000000000000","gas_limit":"21000","maximum_fee":"630000000000000","after":[]},
     {"kind":"transfer","payer_path":"m/44'/60'/0'/0/1","payer":"0xb","owner_path":"m/44'/60'/0'/0/1","owner":"0xb","to":"0xr","amount":"40000000","gas_limit":"65000","maximum_fee":"1950000000000000","after":[1]}]}}
    """#

  private func plan() throws -> SendPlan {
    guard
      case .plan(let plan) = try JSONDecoder().decode(
        SendPlanResponse.self, from: Data(Self.json.utf8))
    else { throw CocoaError(.coderInvalidValue) }
    return plan
  }

  func testPlanDecodes() throws {
    let plan = try plan()
    XCTAssertEqual(plan.sources.count, 2)
    XCTAssertEqual(plan.steps.map(\.kind), [.authorization, .topUp, .transfer])
    XCTAssertEqual(plan.steps[2].after, [1])
    XCTAssertEqual(plan.sponsor?.address, "0xsponsor")
    XCTAssertEqual(plan.steps.map(\.sponsored), [true, false, false])
    XCTAssertTrue(plan.needsFlow)
  }

  func testProblemsDecode() throws {
    func problem(_ text: String) throws -> SendProblem {
      guard
        case .problem(let value) = try JSONDecoder().decode(
          SendPlanResponse.self, from: Data(text.utf8))
      else { throw CocoaError(.coderInvalidValue) }
      return value
    }
    XCTAssertEqual(
      try problem(#"{"problem":{"code":"insufficient_funds","held":"5","needed":"9"}}"#),
      .insufficientFunds(held: "5", needed: "9"))
    XCTAssertEqual(
      try problem(#"{"problem":{"code":"no_sponsor","held":"0","needed":"1000000000000000"}}"#),
      .noSponsor(held: "0", needed: "1000000000000000"))
    XCTAssertEqual(try problem(#"{"problem":{"code":"no_addresses"}}"#), .noAddresses)
    XCTAssertThrowsError(try problem(#"{"problem":{"code":"other"}}"#))
    XCTAssertThrowsError(
      try JSONDecoder().decode(SendPlanResponse.self, from: Data("{}".utf8)))
  }

  func testFeeBreakdownIsExact() throws {
    var plan = try plan()
    XCTAssertEqual(plan.stepFeeTotal, "7080000000000000")
    XCTAssertTrue(plan.feesAreConsistent)
    XCTAssertEqual(plan.formula(plan.steps[1]), "21\u{202F}000 gas × 30 gwei")
    // One wei off anywhere breaks the check.
    plan.steps[0].maximumFee = "4500000000000001"
    XCTAssertFalse(plan.feesAreConsistent)
    plan = try self.plan()
    plan.maximumFee = "7080000000000001"
    XCTAssertFalse(plan.feesAreConsistent)
  }

  func testMultiplyIsExact() {
    XCTAssertEqual(AtomicText.multiply("21000", "32100000000"), "674100000000000")
    XCTAssertEqual(AtomicText.multiply("0", "123"), "0")
    XCTAssertEqual(AtomicText.multiply("007", "0006"), "42")
    let big = "340282366920938463463374607431768211455"
    XCTAssertEqual(
      AtomicText.multiply(big, big),
      "115792089237316195423570985008687907852589419931798687112530834793049593217025")
    XCTAssertNil(AtomicText.multiply("1.5", "2"))
    XCTAssertNil(AtomicText.multiply("", "2"))
  }

  func testProblemMessages() {
    let usdc = WalletAsset(
      id: "eip155:137/erc20:0x1111111111111111111111111111111111111111", symbol: "USDC",
      decimals: 6, name: nil,
      color: "teal")
    let pol = WalletAsset(
      id: "eip155:137/slip44:60", symbol: "POL", decimals: 18, name: nil,
      color: "ocean")
    XCTAssertEqual(
      SendProblem.noSponsor(held: "0", needed: "1500000000000000000").message(
        asset: usdc, native: pol),
      "No address holds enough POL for fees (needs up to 1.5).")
    XCTAssertEqual(
      SendProblem.insufficientFunds(held: "1500000", needed: "2000000").message(
        asset: usdc, native: pol),
      "You can send up to 1.5 USDC: that's all this account holds.")
    // The network's coin pays its own fee: the most it can send is less than it holds,
    // and the message says why (the report: 0.04116 shown, 0.04113 sendable, rounded down).
    XCTAssertEqual(
      SendProblem.insufficientFunds(held: "41138849999632500", needed: "41164000000000000")
        .message(asset: pol, native: pol),
      "You can send up to 0.04113 POL: the network fee is paid from the same balance."
    )
    XCTAssertEqual(
      SendProblem.insufficientFunds(held: "0", needed: "1").message(asset: pol, native: pol),
      "Not enough POL to cover the network fee.")
    XCTAssertEqual(
      SendProblem.insufficientFunds(held: "0", needed: "1").message(asset: usdc, native: pol),
      "No USDC to send in this account.")
  }

  func testTransfersRecordTheirStepKind() throws {
    XCTAssertTrue(PlanStepKind.topUp.isInternal)
    XCTAssertTrue(PlanStepKind.permit.isInternal)
    XCTAssertFalse(PlanStepKind.authorization.isInternal)
    XCTAssertFalse(PlanStepKind.transferFrom.isInternal)
    // The kind is required in stored transfers.
    XCTAssertThrowsError(try JSONDecoder().decode(LocalTransfer.self, from: Data("{}".utf8)))
  }
}
