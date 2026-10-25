import XCTest

@testable import PayroofWallet

final class ValueHistoryTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  func testOnePointPerHourTheLatestKept() {
    var points = ValueHistory.record(Decimal(string: "10.5")!, at: start, in: [])
    points = ValueHistory.record(12, at: start.addingTimeInterval(600), in: points)
    XCTAssertEqual(points, [ValuePoint(date: start.addingTimeInterval(600), usd: "12")])
    points = ValueHistory.record(
      Decimal(string: "0.000001")!, at: start.addingTimeInterval(4000), in: points)
    XCTAssertEqual(points.map(\.usd), ["12", "0.000001"])
    XCTAssertEqual(points.last?.value, Decimal(string: "0.000001"))
  }

  func testClockMovedBackDropsLaterPoints() {
    let points = [
      ValuePoint(date: start, usd: "1"),
      ValuePoint(date: start.addingTimeInterval(7200), usd: "2"),
    ]
    let recorded = ValueHistory.record(3, at: start.addingTimeInterval(3600), in: points)
    XCTAssertEqual(recorded.map(\.usd), ["1", "3"])
  }

  func testKeepsTheNewestWithinTheLimit() {
    var points: [ValuePoint] = []
    for hour in 0..<(ValueHistory.limit + 5) {
      points = ValueHistory.record(
        Decimal(hour), at: start.addingTimeInterval(Double(hour) * 3600), in: points)
    }
    XCTAssertEqual(points.count, ValueHistory.limit)
    XCTAssertEqual(points.first?.usd, "5")
  }

  func testActivityMatchesEitherSideOfAnAddress() {
    let entry = HistoryEntry(
      chain: "eip155:8453", asset: "eip155:8453/slip44:60", transaction: "0x1", index: 0,
      from: "0xAbC",
      to: "0xdef", amount: "1", block: 1, timestamp: nil, direction: "in", failed: false)
    XCTAssertTrue(ActivityItem.chain(entry).involves("0xabc"))
    XCTAssertTrue(ActivityItem.chain(entry).involves("0xdef"))
    XCTAssertFalse(ActivityItem.chain(entry).involves("0x123"))
    XCTAssertEqual(ActivityItem.chain(entry).chain, "eip155:8453")
  }
}
