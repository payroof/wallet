import Foundation

/// Exact presentation arithmetic for a send plan: fees are atomic digit strings
/// (wei), summed and multiplied without floating point. The core is the authority.
/// These checks and texts only show what it reviewed.
extension SendPlan {
  /// The sum of the steps' maximum fees.
  var stepFeeTotal: String? {
    steps.reduce("0" as String?) { sum, step in
      sum.flatMap { AtomicText.add($0, step.maximumFee) }
    }
  }
  /// Every step's fee is its gas limit times the quoted price, and they add up to the
  /// plan's maximum fee.
  var feesAreConsistent: Bool {
    guard let total = stepFeeTotal, AtomicText.compare(total, maximumFee) == 0 else {
      return false
    }
    return steps.allSatisfy { step in
      AtomicText.multiply(step.gasLimit, maxFeePerGas).map {
        AtomicText.compare($0, step.maximumFee) == 0
      } ?? false
    }
  }
  /// The step's fee in the network's coin with the formula behind it, e.g.
  /// "21 000 gas × 32.1 gwei".
  func formula(_ step: PlanStep) -> String {
    ExactAmount.short(step.gasLimit, decimals: 0) + " gas × "
      + ExactAmount.short(maxFeePerGas, decimals: 9, fraction: 3) + " gwei"
  }
}

extension SendProblem {
  /// A short message for the user. `asset` is what is being sent, `native` the coin
  /// that pays fees on its network.
  func message(asset: WalletAsset, native: WalletAsset?) -> String {
    let coin = native ?? asset
    switch self {
    case .insufficientFunds(let held, _):
      let most = ExactAmount.short(held, decimals: asset.decimals)
      guard AtomicText.compare(held, "0") == 1 else {
        return asset.isNative
          ? "Not enough \(asset.symbol) to cover the network fee."
          : "No \(asset.symbol) to send in this account."
      }
      // A network's coin pays its own transfer fees, so less than it holds can be sent.
      return asset.isNative
        ? "You can send up to \(most) \(asset.symbol): the network fee is paid from the same balance."
        : "You can send up to \(most) \(asset.symbol): that's all this account holds."
    case .noSponsor(_, let needed):
      return
        "No address holds enough \(coin.symbol) for fees (needs up to \(ExactAmount.rounded(needed, decimals: coin.decimals, rounding: .up)))."
    case .noAddresses:
      return "This account has no addresses yet."
    }
  }
}
