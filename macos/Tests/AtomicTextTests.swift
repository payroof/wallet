import XCTest

@testable import PayroofWallet

/// Review totals and balance warnings must be exact for full uint256-sized values.
final class AtomicTextTests: XCTestCase {
  func testAdditionIsExact() {
    XCTAssertEqual(AtomicText.add("0", "0"), "0")
    XCTAssertEqual(AtomicText.add("999", "1"), "1000")
    XCTAssertEqual(AtomicText.add("1000000000000000001", "21000000000000"), "1000021000000000001")
    XCTAssertEqual(AtomicText.add("00042", "8"), "50")
    XCTAssertEqual(
      AtomicText.add(ExactAmount.maximum, "1"),
      "115792089237316195423570985008687907853269984665640564039457584007913129639936")
  }
  func testComparisonIgnoresLeadingZeros() {
    XCTAssertEqual(AtomicText.compare("10", "9"), 1)
    XCTAssertEqual(AtomicText.compare("9", "10"), -1)
    XCTAssertEqual(AtomicText.compare("000123", "123"), 0)
    XCTAssertEqual(AtomicText.compare("0", "000"), 0)
    XCTAssertEqual(AtomicText.compare("1500000", "1499999"), 1)
  }
  func testRejectsNonDigitInput() {
    for bad in ["", "-1", "1.5", "1e3", "0x10", " 1", "١"] {
      XCTAssertNil(AtomicText.add(bad, "1"), bad)
      XCTAssertNil(AtomicText.compare("1", bad), bad)
    }
  }
}
