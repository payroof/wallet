import XCTest

@testable import PayroofWallet

final class QRScanPurposeTests: XCTestCase {
  private let twelve = Array(repeating: "abandon", count: 11).joined(separator: " ") + " about"
  func testRecoveryWordsAcceptPhrasesOfValidLength() {
    XCTAssertTrue(QRScanPurpose.recoveryWords.accepts(twelve))
    XCTAssertTrue(
      QRScanPurpose.recoveryWords.accepts(twelve.replacingOccurrences(of: " ", with: "\n")))
    let twentyFour = Array(repeating: "zoo", count: 24).joined(separator: " ")
    XCTAssertTrue(QRScanPurpose.recoveryWords.accepts(twentyFour))
  }
  func testRecoveryWordsRejectOtherCodes() {
    XCTAssertFalse(QRScanPurpose.recoveryWords.accepts(""))
    XCTAssertFalse(QRScanPurpose.recoveryWords.accepts("abandon about"))
    XCTAssertFalse(QRScanPurpose.recoveryWords.accepts(twelve + " zoo"))
    XCTAssertFalse(
      QRScanPurpose.recoveryWords.accepts("0x52908400098527886E0F7030069857D2E4169EE7"))
    XCTAssertFalse(QRScanPurpose.recoveryWords.accepts("https://example.com/pair?a=1"))
    XCTAssertFalse(
      QRScanPurpose.recoveryWords.accepts(twelve.replacingOccurrences(of: "about", with: "ab0ut")))
  }
}
