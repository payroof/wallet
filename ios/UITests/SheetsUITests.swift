import XCTest

/// Opens the sheets whose height follows their content and attaches a screenshot of
/// each, with and without the keyboard: Edit account, a network's editor, a token's
/// editor. For visual review of their fit (no band below the content). Start from a
/// clean install, or a wallet opened by the other UI tests (same PIN).
@MainActor
final class SheetsUITests: XCTestCase {
  private var app: XCUIApplication!
  private let pin = "864200"

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
  }

  func testSheets() throws {
    app.launch()
    if app.buttons["Open"].waitForExistence(timeout: 30) {
      app.buttons["Open"].tap()
      let words = element("onboarding.words")
      XCTAssertTrue(words.waitForExistence(timeout: 10))
      words.tap()
      words.typeText(Array(repeating: "abandon", count: 23).joined(separator: " ") + " art")
      app.buttons["Continue"].tap()
      enterPIN()
    } else if app.buttons["8"].waitForExistence(timeout: 30) {
      enterPIN()
    }
    XCTAssertTrue(element("card.0").waitForExistence(timeout: 60), "Wallet home did not appear")
    shot("home")

    // Edit account, from the sign's brush.
    let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Edit '")).firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 10))
    edit.tap()
    XCTAssertTrue(app.staticTexts["Edit account"].waitForExistence(timeout: 5))
    pause(1)
    shot("edit-account")
    app.buttons["Cancel"].tap()
    pause(1)

    // Settings → Networks & tokens.
    app.buttons["tab.Settings"].tap()
    let networks = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Networks & tokens'"))
      .firstMatch
    XCTAssertTrue(networks.waitForExistence(timeout: 10))
    networks.tap()
    pause(1)
    shot("networks")

    let network = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Edit network'"))
      .firstMatch
    XCTAssertTrue(network.waitForExistence(timeout: 10))
    network.tap()
    pause(1.5)
    shot("network-sheet")
    let rpc = app.textFields["RPC URL"]
    if rpc.waitForExistence(timeout: 5) {
      rpc.tap()
      pause(1.5)
      shot("network-sheet-keyboard")
    }
    app.buttons["Done"].firstMatch.tap()
    pause(1.5)
    shot("after-network-sheet")

    let token = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Edit token'"))
      .firstMatch
    XCTAssertTrue(token.waitForExistence(timeout: 10))
    token.tap()
    pause(1.5)
    shot("token-sheet")
    let symbol = app.textFields["e.g. USDC"]
    if symbol.waitForExistence(timeout: 5) {
      symbol.tap()
      pause(1.5)
      shot("token-sheet-keyboard")
    }
    app.buttons["Cancel"].firstMatch.tap()
    pause(1.5)
    shot("after-token-sheet")
  }

  private func enterPIN() {
    XCTAssertTrue(app.buttons["8"].waitForExistence(timeout: 10))
    for digit in pin { app.buttons[String(digit)].tap() }
  }

  private func element(_ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
  }

  private func pause(_ seconds: TimeInterval) {
    _ = XCTWaiter().wait(for: [expectation(description: "settle")], timeout: seconds)
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
