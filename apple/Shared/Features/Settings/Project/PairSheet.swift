import SwiftUI

/// Paste or scan a pairing link. Review hands it to the access confirmation.
struct PairSheet: View {
  @Environment(WalletModel.self) private var model
  let project: String
  let close: () -> Void
  @State private var link = ""
  @State private var scanning = false
  private var value: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
  var body: some View {
    WalletSheet("Pair", icon: "qrcode", close: close) {
      WalletField("Pairing link") {
        TextField("Pairing link", text: $link).autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
      } accessory: {
        #if os(iOS)
          WalletIconButton(title: "Scan pairing QR code", icon: "qrcode.viewfinder") {
            scanning = true
          }
        #endif
      }
    } footer: {
      WalletSheetActions(cancel: close) {
        WalletAction(title: "Review", icon: "checkmark.shield") { review(value) }
          .disabled(!model.canRun(.access) || value.isEmpty).keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 480)
    .onChange(of: link) { _, _ in model.touch() }
    .onChange(of: model.lockEpoch) { _, _ in link = "" }
    .onDisappear { link = "" }
    #if os(iOS)
      .sheet(isPresented: $scanning) {
        QRScanner(purpose: .pairing, onCancel: { scanning = false }) { scanned in
          scanning = false
          review(scanned)
        }
      }
    #endif
  }
  private func review(_ raw: String) {
    model.reviewPairing(raw, project: project)
    close()
  }
}
