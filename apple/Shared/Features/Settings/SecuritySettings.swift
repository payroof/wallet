import SwiftUI

/// Security: how the wallet unlocks, the passcode, recovery words, auto-lock.
struct SecuritySettings: View {
  @Environment(WalletModel.self) private var model
  @State private var oldPIN = ""
  @State private var newPIN = ""
  @State private var repeatPIN = ""
  @State private var changingPIN = false
  @State private var showingWords = false
  @State private var capability = DeviceUnlock.capability()
  @AppStorage(WalletStorageKey.autoLock.rawValue) private var autoLock = WalletAutoLock.standard
    .rawValue
  /// The device unlock in use. Nil when only the PIN unlocks.
  private var current: DeviceUnlockPolicy? { model.state.settings.deviceUnlock }
  private var policies: [DeviceUnlockPolicy] {
    DeviceUnlockPolicy.allCases.filter(capability.available)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        WalletSectionHeader("Unlock with")
        WalletCard(padding: 6) {
          VStack(spacing: 2) {
            option(nil, title: "PIN only", subtitle: nil, icon: "circle.grid.3x3")
            ForEach(policies, id: \.self) { policy in
              option(
                policy, title: capability.title(policy), subtitle: capability.detail(policy),
                icon: capability.icon(policy))
            }
          }
        }
        if !capability.keychainReady {
          caption(DeviceUnlock.unsignedReason)
        } else if policies.isEmpty {
          caption(capability.biometryIssue ?? "No passcode or biometrics set up on this device.")
        } else if let issue = capability.biometryIssue {
          caption(issue)
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        WalletSectionHeader("Passcode")
        WalletCard(padding: 6) {
          Button {
            changingPIN = true
          } label: {
            row(icon: "key", title: "Change passcode", detail: "Your PIN always unlocks Payroof") {
              Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(WalletTheme.muted).accessibilityHidden(true)
            }
          }
          .buttonStyle(WalletRowButtonStyle()).disabled(model.busy)
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        WalletSectionHeader("Recovery words")
        WalletCard(padding: 6) {
          Button {
            model.feedback = nil
            showingWords = true
          } label: {
            row(
              icon: "list.bullet.rectangle", title: "Show recovery words",
              detail: "Copy, save to a file, or show as a QR code"
            ) {
              Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(WalletTheme.muted).accessibilityHidden(true)
            }
          }
          .buttonStyle(WalletRowButtonStyle()).disabled(model.busy)
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        WalletSectionHeader("Auto-lock")
        WalletCard(padding: 6) {
          row(icon: "lock", title: "Lock after", detail: "And when the device sleeps or locks") {
            Picker("Lock after", selection: $autoLock) {
              ForEach(WalletAutoLock.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
          }
        }
      }
    }
    .onAppear {
      capability = DeviceUnlock.capability()
      if WalletAutoLock(rawValue: autoLock) == nil { autoLock = WalletAutoLock.standard.rawValue }
    }
    .onChange(of: autoLock) { _, _ in model.autoLockChanged() }
    .walletSheet(isPresented: $changingPIN) { changePINSheet }
    .walletSheet(isPresented: $showingWords) { RecoveryWordsSheet { showingWords = false } }
    .walletDismissOnLock {
      changingPIN = false
      showingWords = false
    }
    .onChange(of: oldPIN) { _, _ in model.touch() }
    .onChange(of: newPIN) { _, _ in model.touch() }
    .onChange(of: repeatPIN) { _, _ in model.touch() }
    .onChange(of: model.lockEpoch) { _, _ in
      oldPIN = ""
      newPIN = ""
      repeatPIN = ""
      changingPIN = false
      showingWords = false
    }
  }

  /// Choosing applies at once. The system confirms it's you before turning it on.
  private func option(
    _ policy: DeviceUnlockPolicy?, title: String, subtitle: String?, icon: String
  ) -> some View {
    WalletOptionRow(
      option: WalletOption(value: policy, title: title, subtitle: subtitle, icon: icon),
      selected: current == policy
    ) {
      guard current != policy, !model.busy else { return }
      model.run(policy.map { .enableDeviceUnlock($0) } ?? .disableDeviceUnlock)
    }
    .disabled(model.busy)
  }
  private func row<Trailing: View>(
    icon: String, title: String, detail: String, @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(spacing: 12) {
      WalletIconTile(systemName: icon)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.callout.weight(.medium))
        Text(detail).font(.caption).foregroundStyle(WalletTheme.muted)
      }
      Spacer()
      trailing()
    }
    .padding(.horizontal, 10).frame(minHeight: WalletMetrics.control + 14)
    .contentShape(Rectangle())
  }
  private func caption(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(WalletTheme.muted)
      .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
  }

  private var pinFormValid: Bool {
    !model.busy && !oldPIN.isEmpty && newPIN.count >= 6 && newPIN == repeatPIN
  }
  private var changePINSheet: some View {
    WalletSheet(
      "Change passcode", icon: "key", closeDisabled: model.busy,
      status: model.feedback?.status ?? .idle,
      dismissStatus: { model.feedback = nil }, close: { changingPIN = false }
    ) {
      WalletField("Current passcode") {
        SecureField("Current PIN or passcode", text: $oldPIN)
      }
      WalletField(
        "New passcode",
        error: !newPIN.isEmpty && newPIN.count < 6 ? "Use at least six characters." : nil
      ) {
        SecureField("At least 6 characters", text: $newPIN)
      }
      WalletField(
        "Confirm new passcode",
        error: !repeatPIN.isEmpty && newPIN != repeatPIN ? "Passcodes don't match." : nil
      ) {
        SecureField("Repeat new passcode", text: $repeatPIN).onSubmit { updatePIN() }
      }
    } footer: {
      WalletSheetActions(cancelDisabled: model.busy, cancel: { changingPIN = false }) {
        WalletAction(
          title: "Update passcode", icon: "checkmark.shield", busy: model.busy,
          busyTitle: "Updating…"
        ) {
          updatePIN()
        }.disabled(!pinFormValid).keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 480, busy: model.busy).privacySensitive()
    .onDisappear {
      oldPIN = ""
      newPIN = ""
      repeatPIN = ""
    }
  }
  private func updatePIN() {
    guard pinFormValid else { return }
    model.run(.pin(oldPIN, newPIN)) {
      changingPIN = false
      oldPIN = ""
      newPIN = ""
      repeatPIN = ""
    }
  }
}
