import XCTest

/// Account selection survives leaving and returning to Wallet, and an app relaunch.
/// Start from a clean install: `xcrun simctl uninstall <udid> top.payroof.wallet`.
@MainActor
final class AccountSelectionUITests: XCTestCase {
  private var app: XCUIApplication!
  private let pin = "864200"

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
  }

  func testSelectedAccountStaysActiveAcrossTabsAndRelaunch() throws {
    app.launch()
    if app.buttons["Open"].waitForExistence(timeout: 30) {
      try onboard()
    } else {
      unlock()
    }
    let first = element("card.0")
    XCTAssertTrue(first.waitForExistence(timeout: 60), "Wallet home did not appear")
    if !element("card.2").exists {
      createAccount("Two", after: "card.0")
      createAccount("Three", after: "card.1")
    }
    // Select account 2 (slot 1) from the newest account by swiping back.
    swipeTo(slot: 1)
    assertCurrent(slot: 1, "after switching")
    shot("1-switched")

    for tab in ["Send", "Settings", "Receive", "Activity"] {
      app.buttons["tab." + tab].tap()
      XCTAssertTrue(app.buttons["tab." + tab].isSelected, "\(tab) tab not selected")
    }
    shot("2-other-screen")
    app.buttons["tab.Wallet"].tap()
    assertCurrent(slot: 1, "after returning to Wallet")
    shot("3-returned")

    app.terminate()
    app.launch()
    unlock()
    XCTAssertTrue(element("card.1").waitForExistence(timeout: 60))
    shot("4-relaunched")
    assertCurrent(slot: 1, "after relaunch")
  }

  // MARK: Steps

  private func onboard() throws {
    app.buttons["Open"].tap()
    let words = element("onboarding.words")
    XCTAssertTrue(words.waitForExistence(timeout: 10))
    words.tap()
    words.typeText(Array(repeating: "abandon", count: 23).joined(separator: " ") + " art")
    app.buttons["Continue"].tap()
    enterPIN()
  }

  private func unlock() {
    if app.buttons["8"].waitForExistence(timeout: 30) { enterPIN() }
  }

  private func enterPIN() {
    XCTAssertTrue(app.buttons["8"].waitForExistence(timeout: 10))
    for digit in pin { app.buttons[String(digit)].tap() }
  }

  private func createAccount(_ name: String, after card: String) {
    swipeLeftFrom(card)
    // The building site creates the account at once, with a random name.
    app.buttons["New account"].firstMatch.tap()
    let next = card == "card.0" ? "card.1" : "card.2"
    XCTAssertTrue(element(next).waitForExistence(timeout: 60))
    assertCurrent(
      slot: next == "card.1" ? 1 : 2, "after creating \(name)", of: next == "card.1" ? 3 : 4)
  }

  private func swipeLeftFrom(_ id: String) { element(id).swipeLeft() }

  /// Swipes the row until the dots report `slot`. Right moves to lower slots.
  private func swipeTo(slot: Int) {
    for _ in 0..<4 {
      let shown = dots.value as? String ?? ""
      if shown == "Account \(slot + 1) of 4", isCurrent(slot) { return }
      let position = Int(shown.split(separator: " ").dropFirst().first ?? "") ?? 1
      if position - 1 > slot {
        element("card.\(position - 1)").swipeRight()
      } else if position - 1 < slot {
        element("card.\(position - 1)").swipeLeft()
      } else {
        _ = XCTWaiter().wait(for: [expectation(description: "settle")], timeout: 0.5)
      }
    }
  }

  // MARK: Assertions

  private var dots: XCUIElement { element("account.dots") }

  private func isCurrent(_ slot: Int) -> Bool {
    let card = element("card.\(slot)")
    return card.exists && (card.value as? String) == "current"
  }

  /// The card is the model's current account, sits centred in the window, and the dots
  /// agree.
  private func assertCurrent(slot: Int, _ when: String, of total: Int = 4) {
    let card = element("card.\(slot)")
    XCTAssertTrue(card.waitForExistence(timeout: 10), "card.\(slot) missing \(when)")
    // Polls the app's accessibility tree. Each query can take a moment on a busy
    // simulator, so the time to settle is measured and logged rather than inferred.
    let start = Date()
    var centered = false
    while !centered && Date().timeIntervalSince(start) < 5 {
      centered = abs(card.frame.midX - app.frame.midX) < 20 && (card.value as? String) == "current"
      if !centered { usleep(100_000) }
    }
    let elapsed = Date().timeIntervalSince(start)
    print("card.\(slot) \(when): settled \(centered) after \(String(format: "%.2f", elapsed)) s")
    let others = (0..<4).filter { $0 != slot }.filter { isCurrent($0) }
    XCTAssertTrue(
      centered,
      "card.\(slot) \(when): midX \(card.frame.midX) of \(app.frame.midX), value "
        + "\(String(describing: card.value)), other current cards \(others), dots "
        + "\(String(describing: dots.value))")
    XCTAssertEqual(
      dots.value as? String, "Account \(slot + 1) of \(total)", "dots \(when)")
  }

  private func element(_ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
