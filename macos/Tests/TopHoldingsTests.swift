import XCTest

@testable import PayroofWallet

final class TopHoldingsTests: XCTestCase {
  /// A token whose contract is 40 times `digit`, on the chain.
  private func token(_ chain: ChainID, _ digit: Character) -> AssetID {
    .token(EVMAddress("0x" + String(repeating: digit, count: 40))!, on: chain)
  }

  private func holding(_ id: AssetID, decimals: Int, _ balances: [String]) -> AssetHolding {
    let asset = WalletAsset(id: id, symbol: id.rawValue, decimals: decimals, color: "ocean")
    let addresses = balances.enumerated().map {
      (path: "m/44'/60'/0'/0/\($0.offset)", balance: CachedBalance(atomic: $0.element, date: .now))
    }
    let total = balances.reduce("0") { AtomicText.add($0, $1) ?? $0 }
    return AssetHolding(asset: asset, total: total, addresses: addresses)
  }

  func testRanksByUSDDropsZeroAndCountsHoldingAddresses() {
    let holdings = [
      holding(token("eip155:1", "a"), decimals: 0, ["5", "0", "5"]),
      holding(token("eip155:1", "b"), decimals: 0, ["0", "0"]),
      holding(token("eip155:56", "c"), decimals: 0, ["1"]),
      holding(token("eip155:8453", "d"), decimals: 0, ["7"]),
      holding(token("eip155:137", "e"), decimals: 0, ["2"]),
    ]
    let prices = [
      token("eip155:1", "a"): CachedPrice(usd: "1", date: .now),
      token("eip155:56", "c"): CachedPrice(usd: "100", date: .now),
      token("eip155:137", "e"): CachedPrice(usd: "3", date: .now),
    ]
    let top = WalletPortfolio.top(holdings, prices: prices, limit: 3)

    XCTAssertEqual(top[1].addresses, 2)
    XCTAssertEqual(top[1].atomic, "10")
  }

  func testUnpricedFollowAndNothingHeldIsEmpty() {
    let unpriced = [holding(token("eip155:1", "f"), decimals: 0, ["3"])]
    XCTAssertEqual(
      WalletPortfolio.top(unpriced, prices: [:], limit: 3).map(\.id), [token("eip155:1", "f")])
    let empty = [holding(token("eip155:1", "9"), decimals: 0, ["0"])]
    XCTAssertTrue(WalletPortfolio.top(empty, prices: [:], limit: 3).isEmpty)
  }
}
