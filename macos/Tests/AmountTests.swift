import XCTest

@testable import PayroofWallet

final class AmountTests: XCTestCase {
  func testExactDecimalConversion() throws {
    XCTAssertEqual(
      try ExactAmount.atomic("1.000000000000000001", decimals: 18), "1000000000000000001")
    XCTAssertEqual(try ExactAmount.atomic("0.000001", decimals: 6), "1")
    XCTAssertEqual(try ExactAmount.atomic("0001.5", decimals: 6), "1500000")
    XCTAssertEqual(ExactAmount.display("1000000000000000001", decimals: 18), "1.000000000000000001")
    XCTAssertEqual(ExactAmount.display("1", decimals: 6), "0.000001")
    XCTAssertEqual(ExactAmount.display("0", decimals: 18), "0")
    XCTAssertEqual(ExactAmount.display("1500000", decimals: 6), "1.5")
  }
  func testFailClosedAmounts() {
    for input in ["", "0", "-1", "+1", "1e18", "1,5", ".5", "1.2.3", "0.0000001", "١"] {
      XCTAssertThrowsError(try ExactAmount.atomic(input, decimals: 6), input)
    }
    XCTAssertThrowsError(try ExactAmount.atomic("1", decimals: 37))
  }
  func testLargeIntegersAreNotRounded() throws {
    let value = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
    XCTAssertEqual(try ExactAmount.atomic(value, decimals: 0), value)
    XCTAssertEqual(ExactAmount.display(value, decimals: 0), value)
  }
  func testRoundedAmountsForDisplay() {
    let space = "\u{202F}"
    // Four significant digits below 1: a fee, never its full wei precision.
    XCTAssertEqual(ExactAmount.rounded("91865001286110", decimals: 18), "0.00009187")
    XCTAssertEqual(
      ExactAmount.rounded("91865001286110", decimals: 18, rounding: .down), "0.00009186")
    XCTAssertEqual(ExactAmount.rounded("91860000000001", decimals: 18, rounding: .up), "0.00009187")
    // Four decimals from 1, two from 1 000.
    XCTAssertEqual(ExactAmount.rounded("1234567890000000000", decimals: 18), "1.2346")
    XCTAssertEqual(ExactAmount.rounded("1234567890", decimals: 6), "1\(space)234.57")
    // Carries into the integer and drops trailing zeros.
    XCTAssertEqual(ExactAmount.rounded("9999950", decimals: 6), "10")
    XCTAssertEqual(ExactAmount.rounded("999999995", decimals: 6), "1\(space)000")
    XCTAssertEqual(ExactAmount.rounded("1500000", decimals: 6), "1.5")
    // Too small to show: a floor, or the smallest step when rounding up.
    XCTAssertEqual(ExactAmount.rounded("1", decimals: 18), "<0.00000001")
    XCTAssertEqual(ExactAmount.rounded("1", decimals: 18, rounding: .up), "0.00000001")
    XCTAssertEqual(ExactAmount.rounded("0", decimals: 18), "0")
    // An explicit number of decimals overrides the policy.
    XCTAssertEqual(ExactAmount.rounded("32123456789", decimals: 9, fraction: 3), "32.123")
    // Whole-unit values are untouched, however large.
    XCTAssertEqual(ExactAmount.rounded("1000", decimals: 0), "1\(space)000")
  }
}
