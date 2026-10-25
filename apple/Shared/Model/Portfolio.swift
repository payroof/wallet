import Foundation

/// One asset's balance across an account's addresses, from cached per-address reads.
struct AssetHolding: Identifiable {
  let asset: WalletAsset
  /// Exact atomic sum of the checked addresses.
  let total: String
  /// Checked addresses, in account order, including zero balances.
  let addresses: [(path: String, balance: CachedBalance)]
  var id: AssetID { asset.id }
  var isZero: Bool { !total.contains { $0 != "0" } }
  var checked: Date? { addresses.map(\.balance.date).min() }
}

/// Holdings that share a symbol (e.g. USDC on several networks), summed exactly at
/// the largest decimal count. Contracts stay separate in the breakdown.
struct HoldingGroup: Identifiable {
  let symbol: String
  let decimals: Int
  let total: String
  let holdings: [AssetHolding]
  var id: String { symbol }
}

/// A USD value in exact decimal arithmetic. `unpriced` is true when some nonzero
/// holding had no price and is therefore left out of `usd`.
struct USDValue: Equatable {
  var usd: Decimal?
  var unpriced: Bool
}

extension ExactAmount {
  /// Atomic amount of `decimals` places times a USD price per whole unit. Nil when
  /// either is not a plain decimal.
  static func usd(_ atomic: String, decimals: Int, price: String) -> Decimal? {
    guard (0...36).contains(decimals), atomic.allSatisfy({ $0.isASCII && $0.isNumber }),
      let amount = Decimal(string: atomic), let price = Decimal(string: price, locale: nil),
      amount.isFinite, price.isFinite, price >= 0
    else { return nil }
    return Decimal(sign: .plus, exponent: -decimals, significand: amount) * price
  }
}

extension HoldingGroup {
  func value(prices: [AssetID: CachedPrice]) -> USDValue {
    var total: Decimal?
    var unpriced = false
    for holding in holdings {
      if let price = prices[holding.asset.id],
        let part = ExactAmount.usd(
          holding.total, decimals: holding.asset.decimals, price: price.usd)
      {
        total = (total ?? 0) + part
      } else {
        unpriced = true
      }
    }
    return USDValue(usd: total, unpriced: unpriced)
  }
}

/// What one address holds, from cached reads: its biggest holding and its USD value.
struct AddressHolding: Identifiable {
  let path: String
  /// The biggest priced holding (else the first nonzero one). Nil when it holds nothing.
  let top: (asset: WalletAsset, atomic: String)?
  /// USD value of the priced holdings. Nil when something is held but nothing is priced.
  let usd: Decimal?
  /// Whether any balance of this address has been read.
  let checked: Bool
  var id: String { path }
}

/// One token on one network with what the account holds of it: the card's back ranks
/// these.
struct NetworkHolding: Identifiable {
  let asset: WalletAsset
  let atomic: String
  /// Nil when the token has no price.
  let usd: Decimal?
  /// Addresses holding some of it.
  let addresses: Int
  var id: AssetID { asset.id }
}

enum WalletPortfolio {
  /// The largest nonzero holdings by USD value, each token on each network on its own.
  /// Unpriced ones follow the priced, in configuration order.
  static func top(_ holdings: [AssetHolding], prices: [AssetID: CachedPrice], limit: Int)
    -> [NetworkHolding]
  {
    let rows = holdings.filter { !$0.isZero }.map { holding in
      NetworkHolding(
        asset: holding.asset, atomic: holding.total,
        usd: prices[holding.asset.id].flatMap {
          ExactAmount.usd(holding.total, decimals: holding.asset.decimals, price: $0.usd)
        },
        addresses: holding.addresses.filter { $0.balance.atomic.contains { $0 != "0" } }.count)
    }
    return rows.enumerated().sorted {
      let (a, b) = ($0.element.usd ?? -1, $1.element.usd ?? -1)
      return a == b ? $0.offset < $1.offset : a > b
    }.prefix(limit).map(\.element)
  }
  /// The sum of every priced group, and the symbols of groups left out (wholly or
  /// partly) because they have no price.
  static func total(_ groups: [HoldingGroup], prices: [AssetID: CachedPrice]) -> (
    usd: Decimal?, excluded: [String]
  ) {
    var total: Decimal?
    var excluded: [String] = []
    for group in groups {
      let value = group.value(prices: prices)
      if let usd = value.usd { total = (total ?? 0) + usd }
      if value.unpriced { excluded.append(group.symbol) }
    }
    return (total, excluded)
  }
  /// US dollars written the US way on every device: `$1,234.56`, never `US$`.
  static func currency(_ value: Decimal) -> String {
    if value > 0 && value < Decimal(string: "0.01")! { return "<$0.01" }
    return "$"
      + value.formatted(
        .number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
  }
  /// The account's USD total from the cached balances and prices, for its balance
  /// history: nil until a balance has been read, or when something is held but nothing
  /// is priced.
  static func value(_ state: WalletSnapshot, account: ProjectCard) -> Decimal? {
    let holdings = holdings(state, account: account)
    guard !holdings.isEmpty else { return nil }
    let groups = groups(holdings)
    if groups.isEmpty { return 0 }
    return total(groups, prices: state.settings.prices).usd
  }
  static func holdings(_ state: WalletSnapshot, account: ProjectCard?) -> [AssetHolding] {
    guard let account else { return [] }
    let paths = account.orderedPaths
    return state.usableAssets.compactMap { asset in
      let checked = paths.compactMap { path in
        state.cachedBalance(path: path, asset: asset.id).map { (path: path, balance: $0) }
      }
      guard !checked.isEmpty else { return nil }
      let total = checked.reduce("0") { AtomicText.add($0, $1.balance.atomic) ?? $0 }
      return AssetHolding(asset: asset, total: total, addresses: checked)
    }
  }
  /// Nonzero holdings grouped by symbol, in configuration order.
  static func groups(_ holdings: [AssetHolding]) -> [HoldingGroup] {
    var order: [String] = []
    var members: [String: [AssetHolding]] = [:]
    for holding in holdings where !holding.isZero {
      let key = holding.asset.symbol.uppercased()
      if members[key] == nil { order.append(key) }
      members[key, default: []].append(holding)
    }
    return order.compactMap { key in
      guard let items = members[key], let first = items.first else { return nil }
      let decimals = items.map(\.asset.decimals).max() ?? first.asset.decimals
      let total = items.reduce("0") {
        AtomicText.add(
          $0, ExactAmount.scaled($1.total, from: $1.asset.decimals, to: decimals)) ?? $0
      }
      return HoldingGroup(
        symbol: first.asset.symbol, decimals: decimals, total: total, holdings: items)
    }
  }
  /// The account's addresses with what each holds, the most valuable first.
  static func addresses(_ state: WalletSnapshot, account: ProjectCard?) -> [AddressHolding] {
    guard let account else { return [] }
    let rows = account.orderedPaths.map { path -> AddressHolding in
      var top: (asset: WalletAsset, atomic: String, usd: Decimal?)?
      var total: Decimal?
      var checked = false
      for asset in state.usableAssets {
        guard let balance = state.cachedBalance(path: path, asset: asset.id) else { continue }
        checked = true
        guard balance.atomic.contains(where: { $0 != "0" }) else { continue }
        let value = state.settings.prices[asset.id].flatMap {
          ExactAmount.usd(balance.atomic, decimals: asset.decimals, price: $0.usd)
        }
        if let value { total = (total ?? 0) + value }
        if top == nil || (value ?? -1) > (top?.usd ?? -1) {
          top = (asset, balance.atomic, value)
        }
      }
      return AddressHolding(
        path: path, top: top.map { ($0.asset, $0.atomic) },
        usd: top == nil ? 0 : total, checked: checked)
    }
    return rows.enumerated().sorted {
      let (a, b) = ($0.element.usd ?? -1, $1.element.usd ?? -1)
      return a == b ? $0.offset < $1.offset : a > b
    }.map(\.element)
  }
}
