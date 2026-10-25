import SwiftUI

/// Connects the current account to its project on a Payroof server. One action for
/// every case: an account without a project there gets one under the name given. An
/// account that already has one (made on another device, or disconnected here) gets
/// access back to it under its own name. The core tells which, so the user is never
/// asked to choose.
struct ConnectProjectSheet: View {
  @Environment(WalletModel.self) private var model
  let close: () -> Void
  @State private var origin = ""
  @State private var project = ""
  private var cleanOrigin: String { origin.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var cleanProject: String { project.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var operation: WalletOperation { .connection(cleanOrigin + "#" + cleanProject) }
  private var running: Bool { model.isRunning(operation) }
  private var valid: Bool {
    model.canRun(operation) && !cleanOrigin.isEmpty && !cleanProject.isEmpty
  }
  var body: some View {
    WalletSheet(
      "Connect project", subtitle: model.currentAccount?.label ?? "", icon: "link",
      closeDisabled: running,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: close
    ) {
      WalletField("Server") {
        TextField("Server", text: $origin, prompt: Text(verbatim: "https://…"))
          .autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never).keyboardType(.URL)
          #endif
      }
      WalletField("Project") {
        TextField("my-store", text: $project).autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
      }
    } footer: {
      WalletSheetActions(cancelDisabled: running, cancel: close) {
        WalletAction(title: "Connect", icon: "link", busy: running, busyTitle: "Connecting…") {
          connect()
        }
        .disabled(!valid).keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 520, busy: running)
    .onAppear {
      origin = model.state.settings.apiOrigin
      project = defaultProject
    }
  }
  /// The account's name as a project name: lowercase letters, digits and dashes.
  private var defaultProject: String {
    let slug = (model.currentAccount?.label ?? "").lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return slug.isEmpty
      ? "account-\(model.account)"
      : String(slug.prefix(63)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
  private func connect() {
    guard valid else { return }
    model.run(.connect(cleanOrigin, cleanProject, model.account)) { close() }
  }
}
