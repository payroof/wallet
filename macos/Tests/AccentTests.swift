import XCTest

@testable import PayroofWallet

final class AccentTests: XCTestCase {
  private let samples = [
    "#FFFFFF", "#000000", "#FFFF00", "#00FF00", "#FF0000", "#0000FF", "#808080", "#FFD700",
    "#1A2B3C", "#E91E63", "#00BCD4", "#FFEB3B", "#7F7F7F", "#123456",
  ]

  func testStrictHex() {
    XCTAssertTrue(AccountAccent.isValid("#1a2B3c"))
    XCTAssertTrue(AccountAccent.isValid("ocean"))
    for bad in [
      "", "#", "#12345", "#1234567", "123456", "#GGGGGG", " #123456", "#123456\n", "Ocean",
    ] {
      XCTAssertFalse(AccountAccent.isValid(bad), bad)
    }
    XCTAssertEqual(WalletAccent(rawValue: "#1a2b3c")?.rawValue, "#1A2B3C")
    XCTAssertNil(WalletAccent(rawValue: "#nope"))
  }

  func testCustomShadesKeepContrast() throws {
    for hex in samples {
      let c = try XCTUnwrap(AccountAccent.rgb(hex: hex))
      let shades = AccentMath.shades(c)
      XCTAssertGreaterThanOrEqual(AccentMath.contrast(shades.light, AccentMath.white), 4.5, hex)
      XCTAssertGreaterThanOrEqual(AccentMath.contrast(shades.dark, AccentMath.darkText), 4.5, hex)
      let card = AccentMath.card(c)
      let lit = AccentMath.lit(card.bright)
      XCTAssertGreaterThanOrEqual(AccentMath.contrast(lit, AccentMath.white), 4.5, hex)
      XCTAssertGreaterThanOrEqual(
        AccentMath.contrast(lit, AccentMath.mix(lit, AccentMath.white, 0.92)), 4.5, hex)
      XCTAssertGreaterThanOrEqual(
        AccentMath.contrast(AccentMath.lit(card.deep), AccentMath.white), 4.5, hex)
    }
  }
}
