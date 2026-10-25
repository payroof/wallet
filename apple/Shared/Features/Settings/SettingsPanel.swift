import Foundation

/// The Settings pages. Raw values are stored. Titles are presentation only.
enum SettingsPanel: String, CaseIterable {
  case root = "Settings"
  case security = "Security"
  case networks = "Networks"
  case project = "Project"
  /// The name in the Settings list and in the header while the page is open.
  var title: String {
    switch self {
    case .root: "Settings"
    case .security: "Security"
    case .networks: "Networks & tokens"
    case .project: "Project"
    }
  }
  /// The roof's object for this page: the shield, the satellite dish that reaches the
  /// networks, and the antenna that also marks an account's project on its card.
  var glyph: RoofGlyph {
    switch self {
    case .security: .shield
    case .networks: .dish
    case .project: .antenna
    case .root: .vent
    }
  }
}

/// Which configuration sheet is open. `nil` IDs mean "add new". A new token may
/// start on a given network.
enum ConfigSheet: Identifiable {
  case network(ChainID?)
  case asset(AssetID?, chain: ChainID?)
  var id: String {
    switch self {
    case .network(let chain): "network:" + (chain?.rawValue ?? "+")
    case .asset(let asset, let chain):
      "asset:" + (asset?.rawValue ?? "+" + (chain?.rawValue ?? ""))
    }
  }
}
