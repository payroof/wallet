import XCTest

@testable import PayroofWallet

final class AccountNamesTests: XCTestCase {
  func testNameIsAdjectiveAndAnimal() {
    let name = AccountNames.random(avoiding: [String]())
    let parts = name.split(separator: " ").map(String.init)
    XCTAssertEqual(parts.count, 2)
    XCTAssertTrue(AccountNames.adjectives.contains(parts[0]))
    XCTAssertTrue(AccountNames.animals.contains(parts[1]))
  }

  func testNeverRepeatsANameInUse() {
    var used: [String] = []
    for _ in 0..<100 { used.append(AccountNames.random(avoiding: used)) }
    XCTAssertEqual(Set(used.map { $0.lowercased() }).count, 100)
  }

  func testNumbersOnceEveryNameIsTaken() {
    let all = AccountNames.adjectives.flatMap { a in AccountNames.animals.map { "\(a) \($0)" } }
    let name = AccountNames.random(avoiding: all.map { $0.uppercased() })
    XCTAssertTrue(name.hasSuffix(" 2"), name)
  }
}
