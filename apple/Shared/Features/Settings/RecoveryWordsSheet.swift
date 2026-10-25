import SwiftUI

/// Security → Recovery words: shown again after the passcode, to copy, save
/// to a file, or show as a QR code that opens this wallet on another device. The words
/// live only in this sheet's state, and are cleared when it closes or the wallet locks.
struct RecoveryWordsSheet: View {
  @Environment(WalletModel.self) private var model
  let close: () -> Void
  @State private var pin = ""
  @State private var words = ""
  @State private var showingQR = false
  @State private var exporting = false
  private var phrase: [String] { words.split(whereSeparator: \.isWhitespace).map(String.init) }
  var body: some View {
    WalletSheet(
      "Recovery words", icon: "list.bullet.rectangle", closeDisabled: model.busy,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: close
    ) {
      if words.isEmpty {
        WalletNote(
          "Make sure no one can see your screen. Anyone with these words can take your funds.",
          tone: .warning, icon: "eye.slash.fill")
        WalletField("Passcode") {
          SecureField("PIN or passcode", text: $pin).onSubmit { reveal() }
        }
      } else if showingQR {
        WalletNote(
          "Scan it with Payroof Wallet on your other device, then hide it. Anyone who scans it can take your funds.",
          tone: .warning, icon: "qrcode.viewfinder")
        qrCode
      } else {
        RecoveryWordsGrid(words: phrase)
      }
    } footer: {
      if words.isEmpty {
        WalletSheetActions(cancelDisabled: model.busy, cancel: close) {
          WalletAction(title: "Show", icon: "eye", busy: model.busy, busyTitle: "Checking…") {
            reveal()
          }
          .disabled(pin.isEmpty || model.busy).keyboardShortcut(.defaultAction)
        }
      } else {
        HStack(spacing: 10) {
          WalletCopyAction(
            title: "Copy", value: phrase.joined(separator: " "), role: .secondary, source: .secret
          ) { announceCopy() }
          WalletAction(title: "Save", icon: "square.and.arrow.down", secondary: true) {
            exporting = true
          }
          WalletAction(
            title: showingQR ? "Words" : "QR code", icon: showingQR ? "list.number" : "qrcode",
            secondary: true
          ) { showingQR.toggle() }
        }
      }
    }
    .walletModal(width: 560, busy: model.busy).privacySensitive()
    .fileExporter(
      isPresented: $exporting, document: RecoveryWordsDocument(words: phrase),
      contentType: .plainText, defaultFilename: "Payroof Wallet recovery words"
    ) { result in
      if case .success = result {
        model.feedback = WalletFeedback(
          message: "Saved. Keep the file offline, and delete any copies you don't need.",
          kind: .info)
      }
    }
    .onChange(of: pin) { _, _ in model.touch() }
    .onChange(of: model.lockEpoch) { _, _ in clear() }
    .onDisappear { clear() }
  }

  private var qrCode: some View {
    Group {
      if let image = QRCode.image(phrase.joined(separator: " "), secret: true) {
        Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
          .padding(14)
          .background(.white, in: WalletShape.tile)
          .frame(maxWidth: 300).frame(maxWidth: .infinity)
          .accessibilityLabel("Recovery words QR code")
      }
    }
  }
  private func reveal() {
    guard !pin.isEmpty, !model.busy else { return }
    model.feedback = nil
    model.run(.revealWords(pin)) {
      words = model.generatedWords
      model.generatedWords = ""
      pin = ""
    }
  }
  private func announceCopy() {
    model.feedback = WalletFeedback(
      message: "Copied. The clipboard clears in a minute.", kind: .info)
  }
  private func clear() {
    pin = ""
    words = ""
    showingQR = false
    exporting = false
  }
}
