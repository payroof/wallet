import Foundation

/// A message for the user about something they did: shown once in the app's toast.
struct WalletFeedback: Identifiable {
  enum Kind { case info, success, warning, error }
  let id = UUID()
  let message: String
  let kind: Kind
  init(message: String, kind: Kind) {
    self.message = message
    self.kind = kind
  }
  init(message: String, isError: Bool) {
    self.init(message: message, kind: isError ? .error : .success)
  }
  var isError: Bool { kind == .error }
  /// Presentation for the shared toast.
  var status: WalletStatus {
    switch kind {
    case .info: .message(message, .neutral)
    case .success: .message(message, .success)
    case .warning: .message(message, .warning)
    case .error: .message(message, .danger)
    }
  }
}
