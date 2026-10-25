import Foundation

/// The wallet's assets: a network's coin and the tokens the user adds, with their
/// optional price oracles. Local edits only.
extension WalletWorker {
  /// Adds or updates an asset, where `replacing` is the ID of the entry being edited. A token
  /// is identified by its contract, never by its symbol.
  func saveAsset(_ input: WalletAsset, replacing: AssetID?) throws -> Outcome {
    var asset = input
    asset.symbol = asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
    asset.name = asset.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    if asset.name?.isEmpty == true { asset.name = nil }
    if var price = asset.price {
      price.url = price.url.trimmingCharacters(in: .whitespacesAndNewlines)
      price.field = price.field.trimmingCharacters(in: .whitespacesAndNewlines)
      asset.price = price.url.isEmpty && price.field.isEmpty ? nil : price
    }
    let look = try WalletLook(color: asset.color, logo: asset.logo).validated()
    asset.color = look.color
    asset.logo = look.logo
    guard snapshot.network(asset.chain) != nil, !asset.symbol.isEmpty, asset.symbol.count <= 20,
      (asset.name?.count ?? 0) <= 60, (0...36).contains(asset.decimals),
      asset.price.map({ RPCText.validURL($0.url) && !$0.field.isEmpty }) ?? true
    else { throw CocoaError(.coderInvalidValue) }
    if let contract = asset.contract {
      // A token is identified by its contract in lowercase.
      asset.id = .token(contract.normalized, on: asset.chain)
    } else {
      guard snapshot.assets.contains(where: { $0.id == asset.id }) else {
        throw CocoaError(.coderInvalidValue)
      }
    }
    if asset.id != replacing, snapshot.assets.contains(where: { $0.id == asset.id }) {
      throw WalletUserError(
        "This token is already in your list for \(snapshot.networkName(asset.chain)).")
    }
    let notice: String
    if let replacing {
      guard let index = snapshot.settings.assets.firstIndex(where: { $0.id == replacing }) else {
        throw CocoaError(.coderInvalidValue)
      }
      if snapshot.settings.assets[index].price != asset.price {
        snapshot.settings.prices.removeValue(forKey: replacing)
      }
      snapshot.settings.assets[index] = asset
      if replacing != asset.id {
        // A different contract is a different asset: its old balances don't apply.
        forgetBalances(of: replacing)
        snapshot.settings.hiddenAssets.removeAll { $0 == replacing }
      }
      notice = "\(asset.symbol) updated."
    } else {
      snapshot.settings.assets.append(asset)
      notice = "Token added. Its contract, not its symbol, identifies the asset."
    }
    try save()
    return Outcome(notice: notice)
  }

  func removeAsset(id: AssetID) throws -> Outcome {
    guard snapshot.assets.contains(where: { $0.id == id }) else {
      throw CocoaError(.coderInvalidValue)
    }
    snapshot.settings.assets.removeAll { $0.id == id }
    snapshot.settings.hiddenAssets.removeAll { $0 == id }
    snapshot.settings.prices.removeValue(forKey: id)
    forgetBalances(of: id)
    try save()
    return Outcome(notice: "Removed from this wallet. On-chain funds are unaffected.")
  }

  /// Shows or hides an asset on Home and in Send. Its settings are kept.
  func setAssetVisible(id: AssetID, _ visible: Bool) throws -> Outcome {
    guard snapshot.assets.contains(where: { $0.id == id }) else {
      throw CocoaError(.coderInvalidValue)
    }
    snapshot.settings.hiddenAssets.removeAll { $0 == id }
    if !visible { snapshot.settings.hiddenAssets.append(id) }
    try save()
    return Outcome()
  }

  private func forgetBalances(of asset: AssetID) {
    for key in snapshot.settings.balances.keys where key.hasSuffix("#" + asset.rawValue) {
      snapshot.settings.balances.removeValue(forKey: key)
    }
  }
}
