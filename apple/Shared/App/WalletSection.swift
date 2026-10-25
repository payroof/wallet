import Foundation

enum WalletSection: String, CaseIterable, Identifiable {
  case home = "Wallet"
  case send = "Send"
  case receive = "Receive"
  case activity = "Activity"
  /// iOS only: a tab listing the configuration pages.
  case settings = "Settings"
  /// macOS only: configuration pages opened from the sidebar's footer icons.
  case security = "Security"
  case networks = "Networks & tokens"
  case project = "Project"
  var id: String { rawValue }
  /// The sidebar's list (macOS).
  static let destinations: [WalletSection] = [.home, .send, .receive, .activity]
  /// The sidebar's footer icons (macOS), before Lock.
  static let configuration: [WalletSection] = [.security, .networks, .project]
  /// The tab bar (iOS).
  static let tabs: [WalletSection] = [.home, .send, .receive, .activity, .settings]
  /// The configuration page this section shows, if any.
  var panel: SettingsPanel? {
    switch self {
    case .security: .security
    case .networks: .networks
    case .project: .project
    default: nil
    }
  }
  /// The app's own drawing for this place (tab bar, sidebar).
  var glyph: RoofGlyph {
    switch self {
    case .home: .house
    case .send: .plane
    case .receive: .mailbox
    case .activity: .stairs
    case .settings: .vent
    case .security, .networks, .project: panel?.glyph ?? .vent
    }
  }
}
