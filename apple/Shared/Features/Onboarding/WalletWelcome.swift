import SwiftUI
import UniformTypeIdentifiers

struct WalletWelcome: View {
  @Environment(WalletModel.self) private var model
  private enum Step { case welcome, importWords, pin, confirmPIN, backup, verify }
  @State private var step: Step = .welcome
  @State private var importing = false
  @State private var pin = ""
  @State private var confirmation = ""
  @State private var words = ""
  @State private var answer3 = ""
  @State private var answer9 = ""
  @State private var answer18 = ""
  @State private var pinMismatch = false
  @State private var exporting = false
  /// The system Paste button's height, which the QR button beside it matches.
  @State private var pasteHeight: CGFloat = 24
  @State private var scanning = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var phrase: [String] { words.split(whereSeparator: \.isWhitespace).map(String.init) }
  var body: some View {
    WalletCentered(width: step == .backup ? 740 : 440, backdrop: step != .welcome) {
      VStack(spacing: 20) {
        if step == .welcome {
          welcome
        } else {
          header
          if step == .pin || step == .confirmPIN {
            // The PIN pad stands on the page, without a card around it.
            content
          } else {
            WalletCard(padding: 20) { content }
          }
        }
      }
    }
    .background {
      if step == .welcome {
        ZStack(alignment: .bottom) {
          SkyBackdrop(celestialAnchor: UnitPoint(x: 0.8, y: 0.16), fadesIntoCanvas: false)
          SkylineView(seed: 31, color: WalletTheme.skylineFar, relief: 1, animated: true).frame(
            height: 190)
          SkylineView(seed: 8, color: WalletTheme.skylineNear, relief: 0.55, animated: true).frame(
            height: 110)
        }
        .ignoresSafeArea()
        .transition(.opacity)
      }
    }
    .privacySensitive()
    .walletStatus(status, dismiss: dismissStatus)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: step)
    .onChange(of: model.lockEpoch) { _, _ in reset() }
    .onChange(of: confirmation) { _, value in
      // Typing again clears the mismatch, as on the unlock screen.
      if !value.isEmpty { pinMismatch = false }
    }
    .onChange(of: model.feedback?.id) { _, _ in
      guard model.feedback?.isError == true else { return }
      if importing && step == .pin {
        pin = ""
        step = .importWords
      } else if step == .confirmPIN {
        // Re-entering the confirmation retries. No extra button appears.
        confirmation = ""
      }
    }
    .onDisappear { reset() }
    .sheet(isPresented: $scanning) {
      QRScanner(purpose: .recoveryWords, onCancel: { scanning = false }) { value in
        words = Self.normalized(value)
        scanning = false
      }
    }
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
  }

  private var welcome: some View {
    // The mark rising like the moon, the name on its sign, then Open and Create.
    VStack(spacing: 26) {
      PayroofMark(size: 112)
        .shadow(color: WalletTheme.lamp.opacity(0.35), radius: 30)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        .phaseAnimator([false, true]) { mark, up in
          mark.offset(y: up && !reduceMotion ? -6 : 0)
        } animation: { _ in
          .easeInOut(duration: 2.6)
        }
      VStack(spacing: 10) {
        PayroofWordmark(size: titleSize)
          .accessibilityAddTraits(.isHeader)
          .accessibilityLabel("Payroof Wallet")
        Text("Your keys stay under your own roof.")
          .font(.callout).foregroundStyle(WalletTheme.muted)
          .multilineTextAlignment(.center)
      }
      HStack(spacing: 12) {
        WalletAction(title: "Open", icon: "key", secondary: true) {
          importing = true
          step = .importWords
        }
        .accessibilityHint("Open an existing wallet with its recovery words")
        WalletAction(title: "Create", icon: "plus") {
          importing = false
          step = .pin
        }
        .accessibilityHint("Create a new wallet")
      }
      .padding(.top, 8)
    }
    .frame(maxWidth: 360)
  }

  private var titleSize: CGFloat {
    #if os(iOS)
      30
    #else
      36
    #endif
  }

  private var header: some View {
    VStack(spacing: 14) {
      HStack {
        if let back = backAction {
          Button(action: back) {
            Label("Back", systemImage: "chevron.left").font(.callout.weight(.medium))
              .frame(minHeight: WalletMetrics.control).contentShape(Rectangle())
          }.buttonStyle(.plain).foregroundStyle(WalletTheme.accent).disabled(model.busy)
        }
        Spacer()
      }
      StairsProgress(count: stepCount, current: progress).accessibilityHidden(true)
      Text(title).font(RoofFont.title).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Step \(progress + 1) of \(stepCount)")
    }
  }
  private func announceCopy() {
    model.feedback = WalletFeedback(
      message: "Copied. The clipboard clears in a minute.", kind: .info)
  }
  private var stepCount: Int { importing ? 3 : 4 }
  private var progress: Int {
    switch step {
    case .welcome, .importWords: 0
    case .pin: importing ? 1 : 0
    case .confirmPIN: importing ? 2 : 1
    case .backup: 2
    case .verify: 3
    }
  }
  private var title: String {
    switch step {
    case .welcome: "Payroof"
    case .importWords: "Open your wallet"
    case .pin: "Choose a PIN"
    case .confirmPIN: "Confirm your PIN"
    case .backup: "Write down your recovery words"
    case .verify: "Check your backup"
    }
  }
  private var backAction: (() -> Void)? {
    switch step {
    case .welcome, .backup: nil
    case .importWords:
      {
        words = ""
        step = .welcome
      }
    case .pin: { reset() }
    case .confirmPIN:
      {
        confirmation = ""
        pin = ""
        step = .pin
      }
    case .verify: { step = .backup }
    }
  }
  @ViewBuilder private var content: some View {
    VStack(spacing: 18) {
      switch step {
      case .welcome:
        EmptyView()
      case .importWords:
        importForm
      case .pin:
        PINEntry(
          code: $pin, progress: importing && model.busy ? "Encrypting your wallet…" : nil
        ) { _ in
          if importing {
            create()
          } else {
            confirmation = ""
            pinMismatch = false
            step = .confirmPIN
          }
        }
      case .confirmPIN:
        PINEntry(code: $confirmation, error: pinMismatch, progress: confirmProgress) { value in
          guard value == pin else {
            pinMismatch = true
            confirmation = ""
            return
          }
          pinMismatch = false
          finishPIN()
        }
      case .backup:
        RecoveryWordsGrid(words: phrase)
        #if os(iOS)
          // One row: the two ways to keep a copy as icons, then the step's action.
          HStack(spacing: 10) {
            WalletCopyButton(
              label: "recovery words", value: phrase.joined(separator: " "), style: .plate,
              source: .secret
            ) { announceCopy() }
            WalletIconButton(title: "Save to file", icon: "square.and.arrow.down") {
              exporting = true
            }
            WalletAction(title: "I've saved them", icon: "checkmark") { step = .verify }
          }
        #else
          WalletActionRow {
            WalletCopyAction(
              title: "Copy", value: phrase.joined(separator: " "), role: .secondary,
              expand: false, source: .secret
            ) { announceCopy() }
            WalletAction(
              title: "Save to file", icon: "square.and.arrow.down", secondary: true, expand: false
            ) { exporting = true }
            WalletAction(title: "I've saved them", icon: "checkmark", expand: false) {
              step = .verify
            }
          }
        #endif
      case .verify:
        // A word that doesn't match is flagged by its field's border alone, without a
        // message, until it is corrected.
        WalletField("Word 3", invalid: wordWrong(answer3, 2)) { wordField("Third word", $answer3) }
        WalletField("Word 9", invalid: wordWrong(answer9, 8)) { wordField("Ninth word", $answer9) }
        WalletField("Word 18", invalid: wordWrong(answer18, 17)) {
          wordField("Eighteenth word", $answer18)
        }
        WalletAction(
          title: "Create my wallet", icon: "arrow.right", busy: model.busy,
          busyTitle: "Creating your wallet…"
        ) { create() }
        .disabled(!backupMatches)
      }
    }.disabled(model.busy)
  }
  // MARK: Import

  private static let phraseLengths = QRScanPurpose.phraseLengths
  /// Words only, lowercased, single-spaced. Numbering, line breaks and punctuation
  /// from a pasted or typed list ("1. word") are dropped.
  private static func normalized(_ raw: String) -> String {
    raw.lowercased().components(separatedBy: CharacterSet.letters.inverted)
      .filter { !$0.isEmpty }.joined(separator: " ")
  }
  private var importCount: Int {
    Self.normalized(words).split(separator: " ").count
  }
  private var importValid: Bool { Self.phraseLengths.contains(importCount) }
  /// One short status line under the box: progress toward a valid length.
  private var importStatus: (text: String, icon: String, tone: WalletTone) {
    let count = importCount
    if importValid { return ("\(count) words", "checkmark.circle.fill", .success) }
    if count > 24 {
      return ("\(count) words. Phrases have at most 24.", "exclamationmark.circle.fill", .danger)
    }
    let next = Self.phraseLengths.first { $0 > count } ?? 24
    return (
      count == 0 ? "12 or 24 words" : "\(count) of \(next) words",
      "text.word.spacing", .neutral
    )
  }
  private var importForm: some View {
    VStack(alignment: .leading, spacing: 12) {
      // A vertical text field draws its prompt with exactly the typed text's insets,
      // unlike a placeholder laid over a TextEditor.
      TextField(
        "Recovery phrase", text: $words,
        prompt: Text("Type or paste your words, separated by spaces")
          .foregroundStyle(WalletTheme.muted.opacity(0.8)),
        axis: .vertical
      )
      .textFieldStyle(.plain)
      .lineLimit(4, reservesSpace: true)
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.never)
      #endif
      .accessibilityIdentifier("onboarding.words")
      .accessibilityHint("\(importStatus.text). Words stay on this device.")
      .font(.system(.callout, design: .monospaced))
      .padding(12)
      .background(WalletTheme.surface, in: WalletShape.field)
      .overlay(
        WalletShape.field
          .strokeBorder(importStatus.tone == .danger ? WalletTheme.danger : WalletTheme.border)
      )
      HStack(spacing: 10) {
        let status = importStatus
        Label(status.text, systemImage: status.icon)
          .font(.footnote.weight(.medium))
          .foregroundStyle(
            status.tone == .neutral ? AnyShapeStyle(WalletTheme.muted) : status.tone.color
          )
          .contentTransition(.numericText())
        Spacer(minLength: 8)
        if !words.isEmpty {
          Button {
            words = ""
          } label: {
            Label("Clear", systemImage: "xmark.circle")
          }
          .buttonStyle(.plain).font(.footnote.weight(.medium))
          .foregroundStyle(WalletTheme.muted)
        }
        // Recovery words from a QR code, e.g. shown by this wallet on another device.
        Button {
          scanning = true
        } label: {
          // Exactly as tall as the system Paste button beside it, measured: a bordered
          // icon-only button is shorter than one with a title on both platforms.
          Image(systemName: "qrcode.viewfinder").font(.footnote.weight(.semibold))
            .frame(width: pasteHeight + 8, height: pasteHeight)
            .background(WalletTheme.accent.opacity(0.15), in: Capsule())
            .foregroundStyle(WalletTheme.accent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).help("Scan QR code").accessibilityLabel("Scan QR code")
        PasteButton(payloadType: String.self) { values in
          if let value = values.first { words = Self.normalized(value) }
        }
        .labelStyle(.titleAndIcon).buttonBorderShape(.capsule).controlSize(.small)
        .walletTint()
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          if $0 > 0 { pasteHeight = $0 }
        }
      }
      WalletAction(title: "Continue", icon: "arrow.right") {
        words = Self.normalized(words)
        step = .pin
      }
      .disabled(!importValid)
      .keyboardShortcut(.defaultAction)
    }
  }
  private var confirmProgress: String? {
    model.busy ? (importing ? "Encrypting your wallet…" : "Preparing words…") : nil
  }
  /// Setup feedback: a PIN mismatch, or the model's result for the current step.
  private var status: WalletStatus {
    if step == .confirmPIN && pinMismatch {
      return .message("PINs don't match. Enter them again.", .danger)
    }
    guard let feedback = model.feedback, !model.busy else { return .idle }
    if step == .confirmPIN && feedback.isError {
      return .message(feedback.message + " Enter the PIN again to retry.", .danger)
    }
    return feedback.status
  }
  private func dismissStatus() {
    pinMismatch = false
    model.feedback = nil
  }
  /// Shown once all three words are entered, so a half-typed word is not an error.
  private func wordWrong(_ answer: String, _ index: Int) -> Bool {
    phrase.count == 24 && !answer3.isEmpty && !answer9.isEmpty && !answer18.isEmpty
      && answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != phrase[index]
  }
  private func wordField(_ prompt: String, _ text: Binding<String>) -> some View {
    TextField(prompt, text: text).autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.never)
      #endif
  }
  private var backupMatches: Bool {
    guard phrase.count == 24 else { return false }
    return [(answer3, 2), (answer9, 8), (answer18, 17)].allSatisfy {
      $0.0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == phrase[$0.1]
    }
  }
  private func create() { model.run(.create(words, pin)) { reset() } }
  private func finishPIN() {
    guard !model.busy else { return }
    if importing {
      create()
    } else {
      model.run(.generate) {
        words = model.generatedWords
        model.generatedWords = ""
        step = .backup
      }
    }
  }
  private func reset() {
    pin = ""
    confirmation = ""
    words = ""
    scanning = false
    answer3 = ""
    answer9 = ""
    answer18 = ""
    step = .welcome
  }
}
