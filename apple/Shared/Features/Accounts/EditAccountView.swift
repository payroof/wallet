import SwiftUI

/// Changes an account's name and color.
struct EditAccountView: View {
  @Environment(WalletModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let account: ProjectCard
  @State private var accent: String
  @State private var label: String
  @State private var confirmingDelete = false
  private var saving: Bool { model.isRunning(.accent) }
  private var cleanLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var canSave: Bool {
    model.canRun(.accent) && (1...100).contains(cleanLabel.count)
  }
  init(account: ProjectCard, accent: WalletAccent) {
    self.account = account
    _accent = State(initialValue: accent.rawValue)
    _label = State(initialValue: account.label)
  }
  private var removing: Bool { model.isRunning(.removal) }
  private var isLast: Bool { model.state.projects.count < 2 }
  var body: some View {
    WalletSheet(
      "Edit account", icon: "paintpalette", closeDisabled: saving || removing,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: { dismiss() }
    ) {
      WalletField("Account name") {
        TextField("Account name", text: $label).onSubmit { save() }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Color").font(.callout.weight(.medium))
        WalletColorPicker(selection: $accent)
      }
    } footer: {
      WalletSheetActions(cancelDisabled: saving || removing, cancel: { dismiss() }) {
        deleteButton
      } primary: {
        WalletAction(title: "Save", icon: "checkmark", busy: saving) { save() }
          .disabled(!canSave).keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 420, busy: saving)
  }
  /// Icon only, left of Cancel. Deleting asks first.
  private var deleteButton: some View {
    WalletIconButton(
      title: "Delete account", icon: "trash", busy: removing, destructive: true
    ) { confirmingDelete = true }
    .disabled(isLast || saving || !model.canRun(.removal))
    .opacity(isLast ? 0.4 : 1)
    .help(isLast ? "The last account can't be deleted" : "Delete account")
    .confirmationDialog(
      "Delete \(account.label)?", isPresented: $confirmingDelete, titleVisibility: .visible
    ) {
      Button("Delete account", role: .destructive) { remove() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Funds stay on-chain. Add slot \(account.slot) later to restore it.")
    }
  }
  private func remove() {
    guard !isLast else { return }
    model.run(.removeAccount(account.slot)) { dismiss() }
  }
  private func save() {
    guard canSave else { return }
    model.run(.editAccount(account.slot, cleanLabel, accent)) {
      dismiss()
    }
  }
}
