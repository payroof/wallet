import SwiftUI

struct WalletUnlock: View {
  @Environment(WalletModel.self) private var model
  @State private var pin = ""
  @State private var useCustomPasscode = false
  @State private var capability = DeviceUnlock.capability()
  private var deviceUnlock: DeviceUnlockPolicy? { model.state.settings.deviceUnlock }
  /// Switches between the six-digit PIN pad and a passcode field of any length.
  private func switchEntry() {
    pin = ""
    useCustomPasscode.toggle()
  }
  /// Unlocking (not locking) is in progress. Errors are shown by the page toast.
  private var unlocking: Bool { model.busy && !model.locking }
  var body: some View {
    WalletCentered(width: 400, backdrop: false) {
      VStack(spacing: 22) {
        VStack(spacing: 10) {
          PayroofMark(size: 64)
            .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
          Text("Unlock Payroof").font(RoofFont.title).accessibilityAddTraits(.isHeader)
          Text(Self.greeting(Date())).roofStencil(11, tracking: 2)
            .foregroundStyle(WalletTheme.muted)
        }
        if useCustomPasscode {
          VStack(spacing: 16) {
            WalletField("Passcode") {
              SecureField("Your passcode", text: $pin).onSubmit { unlock() }
            }
            HStack(spacing: 10) {
              WalletIconButton(title: "Use six-digit PIN", icon: "circle.grid.3x3") {
                switchEntry()
              }
              WalletAction(
                title: "Unlock", icon: "lock.open", busy: unlocking, busyTitle: "Unlocking…"
              ) {
                unlock()
              }.disabled(pin.isEmpty || model.busy)
            }
          }.frame(maxWidth: 320)
        } else {
          PINEntry(
            code: $pin, error: isError, progress: unlocking ? "Unlocking…" : nil,
            accessory: .init(icon: "keyboard", label: "Use a different-length passcode") {
              switchEntry()
            }
          ) { _ in
            unlock()
          }
          .disabled(model.busy)
        }
        if let policy = deviceUnlock {
          WalletAction(
            title: capability.unlockTitle(policy), icon: capability.icon(policy),
            secondary: true
          ) { model.run(.deviceUnlock) }.disabled(model.busy).frame(maxWidth: 280)
        }
      }
    }
    .background {
      // Coming home: the sky over the roof, tonight's moon or today's sun, the street.
      ZStack(alignment: .bottom) {
        SkyBackdrop(celestialAnchor: UnitPoint(x: 0.82, y: 0.12), fadesIntoCanvas: false)
        SkylineView(seed: 9, color: WalletTheme.skylineFar, relief: 0.9, animated: true).frame(
          height: 130)
        LinearGradient(
          colors: [.clear, WalletTheme.canvas], startPoint: .top, endPoint: .bottom
        )
        .frame(height: 70)
      }
      .ignoresSafeArea()
    }
    // On the Mac the sky runs up behind a header that draws no background of its own.
    .walletFixedHeader()
    .privacySensitive()
    .onChange(of: model.lockEpoch) { _, _ in pin = "" }
    .onChange(of: pin) { _, value in
      // Typing again clears the previous error in place.
      if !value.isEmpty, model.feedback?.isError == true { model.feedback = nil }
    }
    .onAppear { capability = DeviceUnlock.capability() }
    .onDisappear { pin = "" }
  }
  private var isError: Bool { !model.busy && model.feedback?.isError == true }
  private func unlock() {
    let value = pin
    pin = ""
    model.run(.unlock(value))
  }
  /// A word for the hour, painted above the windows.
  static func greeting(_ date: Date) -> String {
    switch Calendar.current.component(.hour, from: date) {
    case 5..<12: "Good morning"
    case 12..<18: "Good afternoon"
    case 18..<23: "Good evening"
    default: "Late night on the roof"
    }
  }
}
