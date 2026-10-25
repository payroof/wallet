import SwiftUI

struct CreateAccountView: View {
  @Environment(WalletModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  /// The color starts on a random unused one.
  @State private var accent: String
  @State private var label = ""
  @State private var exactSlot = ""
  @State private var choosingSlot = false
  init(accent: WalletAccent) { _accent = State(initialValue: accent.rawValue) }
  private var creating: Bool { model.isRunning(.account) }
  private var slotError: String? {
    !exactSlot.isEmpty && UInt32(exactSlot) == nil ? "Enter a whole number, or leave blank." : nil
  }
  private var canCreate: Bool {
    model.canRun(.account) && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && slotError == nil
  }
  var body: some View {
    WalletSheet(
      "New account", icon: "person.badge.plus", closeDisabled: creating,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: { dismiss() }
    ) {
      WalletField("Account name", hint: "Only on this device.") {
        TextField("e.g. Personal or My store", text: $label).onSubmit { create() }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Color").font(.callout.weight(.medium))
        WalletColorPicker(selection: $accent)
      }
      WalletDisclosure(
        "Choose a specific slot", detail: exactSlot.isEmpty ? "Automatic" : "Slot \(exactSlot)",
        expanded: $choosingSlot
      ) {
        WalletField(
          "Account slot", hint: "Blank picks the next unused one.",
          error: slotError
        ) { TextField("Automatic", text: $exactSlot) }
      }
    } footer: {
      WalletSheetActions(cancelDisabled: creating, cancel: { dismiss() }) {
        WalletAction(
          title: "Create account", icon: "plus", busy: creating, busyTitle: "Creating…"
        ) { create() }
        .disabled(!canCreate).keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 500, busy: creating)
  }
  private func create() {
    guard canCreate else { return }
    // The model selects the new account together with the snapshot that holds it. Its
    // balances are read right away: the user just asked for it (an existing slot may
    // already hold funds).
    model.run(.project(label, UInt32(exactSlot), accent)) {
      dismiss()
      model.refresh()
    }
  }
}
