import XCTest

/// Walks the main screens and attaches a screenshot of each state, for visual review:
/// the card (front, back, menu), Send as it reveals its steps, Receive and Activity
/// with their header controls. Start from a clean install (see AccountSelectionUITests).
@MainActor
final class ScreensUITests: XCTestCase {
  private var app: XCUIApplication!
  private let pin = "864200"

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
  }

  func testScreens() throws {
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
    let card = element("card.0")
    XCTAssertTrue(card.waitForExistence(timeout: 60), "Wallet home did not appear")
    shot("home")

    // The card turns over and back.
    card.tap()
    pause(1)
    XCTAssertTrue((card.label).contains("Balance over time"), card.label)
    shot("card-back")
    card.tap()
    pause(1)
    XCTAssertFalse(card.label.contains("Balance over time"))

    // An account that was never read offers one tap to read it.
    let update = app.buttons["Update"].firstMatch
    if update.exists {
      update.tap()
      let start = Date()
      while card.label.contains("Not updated yet") && Date().timeIntervalSince(start) < 120 {
        usleep(500_000)
      }
      pause(3)
      shot("home-updated")
      card.tap()
      pause(1)
      shot("card-back-updated")
      card.tap()
      pause(1)
    }

    // Its menu: Send, Receive, Edit, Delete.
    card.press(forDuration: 1.2)
    for title in ["Send", "Receive", "Edit", "Delete"] {
      XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), "\(title) missing")
    }
    shot("card-menu")
    app.buttons["Edit"].tap()
    XCTAssertTrue(app.staticTexts["Edit account"].waitForExistence(timeout: 5))
    shot("edit-account")
    app.buttons["Cancel"].tap()

    // Send: the amount alone, then the recipient, then Review.
    app.buttons["tab.Send"].tap()
    let amount = app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Amount'"))
      .firstMatch
    XCTAssertTrue(amount.waitForExistence(timeout: 10))
    XCTAssertFalse(recipient.exists, "recipient shown before an amount")
    shot("send-empty")
    amount.tap()
    amount.typeText("1")
    pause(1)
    shot("send-amount")
    if recipient.exists {
      recipient.tap()
      recipient.typeText("0x000000000000000000000000000000000000dEaD")
      pause(1)
      XCTAssertTrue(app.buttons["Review"].waitForExistence(timeout: 5))
      shot("send-recipient")
    }
    amount.tap()
    amount.typeText("999999999999999999999")
    pause(1)
    shot("send-too-much")
    amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
    amount.typeText("0.0000000000000000001")
    pause(1)
    shot("send-too-precise")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    pause(1)
    shot("send-too-precise-blurred")
    let network = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Network'"))
      .firstMatch
    XCTAssertTrue(network.exists)
    network.tap()
    pause(1)
    shot("send-network-menu")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()

    app.buttons["tab.Receive"].tap()
    pause(2)
    shot("receive")

    app.buttons["tab.Activity"].tap()
    pause(1)
    shot("activity")
    let filter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filter'")).firstMatch
    if filter.exists {
      filter.tap()
      pause(1)
      shot("activity-filter")
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
    }

    app.buttons["tab.Wallet"].tap()
    pause(1)
    shot("home-again")
  }

  private var recipient: XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label == 'Recipient address' AND (elementType == %d OR elementType == %d)",
        XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)
    ).firstMatch
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
