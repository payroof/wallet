import XCTest

@testable import PayroofWallet

final class SendDraftTests: XCTestCase {
  private let chain: ChainID = "eip155:1"
  private var coin: WalletAsset {
    WalletAsset(id: .native(on: chain), symbol: "ETH", decimals: 18, color: "ocean")
  }
  private var token: WalletAsset {
    WalletAsset(
      id: "eip155:1/erc20:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", symbol: "USDC",
      decimals: 6, color: "teal")
  }

  private func draft(
    asset: WalletAsset? = nil, amount: String = "", recipient: String = "",
    hidden: [AssetID] = [], limit: SendLimit? = nil
  ) -> SendDraft {
    var state = WalletSnapshot()
    state.settings.assets = [coin, token]
    state.settings.hiddenAssets = hidden
    let account = ProjectCard(slot: 0, label: "Main", paths: ["m/44'/60'/0'/0/0"])
    return SendDraft(
      state: state, account: account, addresses: [:], sendLimit: limit,
      assetID: (asset ?? coin).id, amount: amount, recipient: recipient, recentPick: nil)
  }

  func testRecipientChecks() {
    XCTAssertNil(draft(recipient: "0xabc").recipientError, "Still being typed")
    XCTAssertNotNil(draft(recipient: "hello").recipientError)
    XCTAssertNotNil(draft(recipient: "0x" + String(repeating: "0", count: 40)).recipientError)
    let valid = draft(recipient: " 0x" + String(repeating: "a", count: 40) + " ")
    XCTAssertTrue(valid.recipientValid)
    XCTAssertNil(valid.recipientError)
  }

  func testAmountChecks() {
    XCTAssertFalse(draft(amount: "").amountInvalid)
    XCTAssertTrue(draft(amount: "1.2.3").amountInvalid)
    XCTAssertTrue(draft(asset: token, amount: "0.0000001").amountInvalid, "More decimals than USDC")
    XCTAssertFalse(draft(asset: token, amount: "0.000001").amountInvalid)
    XCTAssertEqual(draft(asset: token, amount: "1.5").atomicAmount, "1500000")
  }

  func testLimitCapsTheAmount() {
    let limit = SendLimit(slot: 0, asset: coin.id, atomic: "1000000000000000000")
    XCTAssertTrue(draft(amount: "2", limit: limit).exceedsAvailable)
    XCTAssertFalse(draft(amount: "1", limit: limit).exceedsAvailable)
    let other = SendLimit(slot: 1, asset: coin.id, atomic: "1")
    XCTAssertFalse(draft(amount: "2", limit: other).exceedsAvailable, "Another account's limit")
  }

  func testHiddenTokensAreNotOfferedUnlessSelected() {
    XCTAssertEqual(draft(hidden: [token.id]).sendTokens.map(\.id), [coin.id])
    XCTAssertEqual(
      draft(asset: token, hidden: [token.id]).sendTokens.map(\.id), [coin.id, token.id])
  }
}
