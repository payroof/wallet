import SwiftUI

/// Send is two things, one after the other: how much, then to whom. The screen starts
/// with only the amount. The recipient appears once the account covers the amount, and
/// Review once the recipient is a valid address. The network is chosen in the header,
/// the token on it beside the amount. The core plans which of the account's addresses fund it and who
/// pays the gas. The plan, fees and exact identities are shown on the review, before
/// anything is signed.
struct WalletSend: View {
  @Environment(WalletModel.self) private var model
  let openNetworks: () -> Void
  /// An address to fund from first, when another screen opened Send from one.
  @State private var prefer: String?
  /// The asset being sent. Nil until a default is chosen (`defaults()`).
  @State private var assetID: AssetID?
  @State private var recipient = ""
  @State private var amount = ""
  /// The amount field has focus: the caret shows after the digits.
  @FocusState private var amountFocused: Bool
  @State private var amountSelection: TextSelection?
  @State private var scanning = false
  /// The network or token list is open.
  @State private var choosingNetwork = false
  @State private var choosingToken = false
  @State private var preparing = false
  /// Recipient chosen from recent transfers. Cleared as soon as the text is edited.
  @State private var recentPick: LocalTransfer?
  /// Counts submitted transfers. Each one launches a paper plane off the roof.
  @State private var flights = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The form's values and every decision drawn from them (`SendDraft`).
  private var draft: SendDraft {
    SendDraft(
      state: model.state, account: model.currentAccount, addresses: model.addresses,
      sendLimit: model.sendLimit, assetID: assetID, amount: amount, recipient: recipient,
      recentPick: recentPick)
  }
  private var account: ProjectCard? { draft.account }
  private var asset: WalletAsset? { draft.asset }
  private var endpoint: String { draft.endpoint }
  private var networkName: String { draft.networkName }
  private var limit: SendLimit? { draft.limit }
  private var available: CachedBalance? { draft.available }
  private var isNative: Bool { draft.isNative }
  private var exceedsAvailable: Bool { draft.exceedsAvailable }
  private var recipientValid: Bool { draft.recipientValid }
  private var amountValid: Bool { draft.amountValid }
  private var atomicAmount: String? { draft.atomicAmount }
  private var networkChoice: Binding<ChainID?> {
    Binding(
      get: { asset?.chain },
      set: { chain in
        guard let chain, chain != asset?.chain, let next = draft.bestToken(on: chain) else {
          return
        }
        assetID = next
      })
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        if let submission = model.submission, submission.slot == account?.slot {
          TransferStatusCard(submission: submission)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        VStack(spacing: 10) {
          amountField
          balanceLine
          if let limit, exceedsAvailable, let asset { limitNote(limit, asset) }
          if let prefer { preferChip(prefer) }
        }
        if amountValid {
          recipientBlock.transition(.opacity.combined(with: .move(edge: .top)))
        }
        if let asset, endpoint.isEmpty { networkOff(asset) }
        if amountValid && recipientValid {
          reviewButton.transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: amountValid)
      .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: recipientValid)
      .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: model.submission?.id)
      .padding(.horizontal, WalletMetrics.page).padding(.vertical, 28)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    // While the form is shorter than the screen, it sits in the middle.
    .defaultScrollAnchor(.center, for: .alignment)
    .walletPageBackground()
    .overlay {
      if flights > 0 && !reduceMotion {
        PaperPlaneFlight().id(flights).allowsHitTesting(false)
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      WalletHeaderTitle { networkMenu }
      // Balances decide what can be sent, so they can be read again from here.
      WalletRefreshToolbarItem(
        refreshing: model.refreshingCurrent,
        enabled: !model.refreshing && !model.state.usableAssets.isEmpty,
        label: model.refreshingCurrent ? model.refreshStep?.text ?? "Refresh" : "Refresh",
        help: "Read balances for this account"
      ) { model.refresh() }
    }
    .onAppear {
      defaults()
      takeIntent()
    }
    .onChange(of: model.sendIntent) { _, _ in takeIntent() }
    // A submitted transfer clears the form for the next one.
    .onChange(of: model.state.settings.transfers.first?.id) { old, new in
      guard new != nil, new != old else { return }
      amount = ""
      recipient = ""
      recentPick = nil
      flights += 1
    }
    .onChange(of: model.account) { _, _ in
      prefer = nil
      amount = ""
      model.sendLimit = nil
      defaults()
    }
    .onChange(of: assetID) { _, _ in
      amount = ""
      model.sendLimit = nil
    }
    // A new balance makes the last maximum stale.
    .onChange(of: available?.atomic) { _, _ in model.sendLimit = nil }
    // Own addresses are known once derived, so a send to oneself can be noticed.
    .task(id: account?.paths.count) { await model.deriveAddresses(account?.paths ?? []) }
    .onChange(of: recipient) { _, value in
      model.touch()
      // The field wraps to two lines for reading. An address never contains a break.
      if value.contains(where: \.isNewline) {
        recipient = value.filter { !$0.isNewline }
        return
      }
      if recentPick?.recipient != value.trimmingCharacters(in: .whitespacesAndNewlines) {
        recentPick = nil
      }
    }
    .onChange(of: amount) { _, _ in model.touch() }
    .onChange(of: amountSelection) { _, selection in
      let end = TextSelection(insertionPoint: amount.endIndex)
      if selection != end { amountSelection = end }
    }
    .onChange(of: model.isRunning(.send)) { _, running in if !running { preparing = false } }
    .onChange(of: model.lockEpoch) { _, _ in
      recipient = ""
      amount = ""
      prefer = nil
      scanning = false
      choosingNetwork = false
      choosingToken = false
      recentPick = nil
    }
    .walletSheet(isPresented: $choosingNetwork) {
      WalletOptionSheet(
        title: "Network", subtitle: "Where the transfer goes out",
        icon: "point.3.connected.trianglepath.dotted", options: networkOptions,
        selection: networkChoice)
    }
    .walletSheet(isPresented: $choosingToken) {
      WalletOptionSheet(
        title: "Token", subtitle: "On \(networkName)", icon: "circle.hexagongrid",
        options: tokenOptions, selection: $assetID)
    }
    .walletDismissOnLock {
      choosingNetwork = false
      choosingToken = false
    }
    #if os(iOS)
      .sheet(isPresented: $scanning) {
        QRScanner(purpose: .address, onCancel: { scanning = false }) { value in
          recipient = value
          scanning = false
        }
      }
    #endif
  }

  // MARK: Header and amount

  /// The network as the header's title, the token on it beside the amount. Each opens
  /// a sheet listing the choices, with what the account holds there (last check).
  private var networkMenu: some View {
    Button {
      choosingNetwork = true
    } label: {
      HStack(spacing: 8) {
        if let asset {
          WalletNetworkGlyph(model.state, chain: asset.chain)
        }
        WalletChoiceLabel(title: asset.map { model.state.networkName($0.chain) } ?? "Network")
      }
    }
    .buttonStyle(.plain)
    .help("Choose a network")
    .accessibilityLabel("Network: \(networkName)")
    .accessibilityHint("Shows the networks to send on")
  }
  /// The networks as sheet options: each with its mark, what is held there, and Off
  /// when it has no endpoint.
  private var networkOptions: [WalletOption<ChainID?>] {
    draft.sendNetworks.map { item in
      let on = model.state.endpoint(for: item.id) != nil
      return WalletOption(
        value: item.id, title: item.name, subtitle: draft.held(on: item.id),
        badge: on ? nil : "Off", badgeTone: .warning,
        artwork: WalletNetworkGlyph.image(
          chain: item.id, name: item.name, art: model.state.networkArt(item.id), size: 26))
    }
  }
  /// The network's tokens as sheet options: the symbol, its name and what is held.
  private var tokenOptions: [WalletOption<AssetID?>] {
    draft.sendTokens.map { item in
      WalletOption(
        value: item.id, title: item.symbol,
        subtitle: [item.name, draft.held(item).map { "\($0) held" }].compactMap { $0 }
          .joined(separator: " · "),
        artwork: WalletAssetGlyph.image(asset: item))
    }
  }
  private var tokenMenu: some View {
    Button {
      choosingToken = true
    } label: {
      HStack(alignment: .center, spacing: 6) {
        if let asset { WalletAssetGlyph(asset: asset, size: Self.amountSize * 0.5) }
        WalletChoiceLabel(
          title: asset?.symbol ?? "Token", signSize: Self.amountSize * 0.42,
          color: WalletTheme.muted)
      }
    }
    .buttonStyle(.plain)
    .fixedSize()
    .disabled(asset == nil)
    .help("Choose a token")
    .accessibilityLabel("Token: \(asset?.symbol ?? "none")")
    .accessibilityHint("Shows the tokens on this network")
  }

  /// The amount, large and centred, shrinking to fit what is typed, with its token to
  /// the right. Red when the account doesn't cover it or it isn't an amount of this
  /// token. Nothing else is said. The "0" placeholder gives way to the caret while the
  /// field has focus, keeping its place, so focus moves nothing. The digits are drawn here, over the field that takes the typing:
  /// a text field being edited keeps the color and size it started with.
  private var amountField: some View {
    let empty = amount.isEmpty
    return ZStack {
      // Typing always goes at the end, where the caret is drawn.
      TextField("", text: $amount, selection: $amountSelection)
        .focused($amountFocused)
        .allowsHitTesting(false)
        .textFieldStyle(.plain)
        .font(.system(size: 24))
        .foregroundStyle(.clear).tint(.clear)
        .multilineTextAlignment(.center)
        .autocorrectionDisabled()
        .accessibilityLabel("Amount in \(asset?.symbol ?? "the selected asset")")
        .accessibilityValue(draft.amountInvalid ? "\(amount), not available" : amount)
        #if os(iOS)
          .keyboardType(.decimalPad)
        #endif
      // The digits and the token (its coin and symbol) are centred on one line.
      HStack(alignment: .center, spacing: 12) {
        HStack(spacing: 3) {
          Text(empty ? "0" : amount)
            .font(RoofFont.sign(Self.amountSize, relativeTo: .largeTitle)).monospacedDigit()
            .offset(y: SignMetrics.centering(Self.amountSize))
            .lineLimit(1).minimumScaleFactor(0.3)
            .contentTransition(.numericText())
            .foregroundStyle(
              draft.amountInvalid
                ? WalletTheme.danger : empty ? WalletTheme.muted : WalletTheme.text
            )
            .opacity(empty && amountFocused ? 0 : 1)
            .overlay { if empty && amountFocused { caret } }
          // The caret's slot after the digits is always there. Only the caret comes and goes.
          Color.clear.frame(width: AmountCaret.width, height: Self.amountSize * 0.78)
            .overlay { if amountFocused && !empty { caret } }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        tokenMenu
      }
    }
    .frame(maxWidth: .infinity, minHeight: Self.amountSize * 1.25)
    .contentShape(Rectangle())
    .onTapGesture { amountFocused = true }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: draft.amountInvalid)
  }
  private static let amountSize: CGFloat = 92

  /// Under the amount, one quiet line: what the typed amount is worth, and what this
  /// account can send of the token (in red when the amount is more). Max fills in the
  /// whole balance of a token. For a network's coin, which also pays the fees, it asks
  /// the core for the balance less those fees, exactly as Review will plan it.
  @ViewBuilder private var balanceLine: some View {
    if let asset {
      HStack(spacing: 8) {
        Text(balanceText(asset))
          .foregroundStyle(exceedsAvailable ? WalletTheme.danger : WalletTheme.muted)
          .lineLimit(1).minimumScaleFactor(0.8)
        if let max = maxAmount(asset) {
          Button("Max") {
            WalletHaptics.tap()
            amount = max
          }
          .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(WalletTheme.accent)
          .accessibilityLabel("Send the whole balance")
        } else if canAskMaximum(asset) {
          Button {
            WalletHaptics.tap()
            askMaximum()
          } label: {
            if model.isRunning(.send) && !preparing {
              WalletSpinner(size: 12)
            } else {
              Text("Max")
            }
          }
          .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(WalletTheme.accent)
          .disabled(!model.canRun(.send))
          .accessibilityLabel("Send the most possible after network fees")
        }
      }
      .font(.footnote).monospacedDigit()
      .accessibilityElement(children: .combine)
    }
  }
  private func balanceText(_ asset: WalletAsset) -> String {
    var parts: [String] = []
    if let atomicAmount, !exceedsAvailable, let usd = model.state.usd(atomicAmount, asset: asset) {
      parts.append("≈ \(usd)")
    }
    if let limit {
      // Worked out by the core: exact, and already less the fees.
      let most = ExactAmount.short(limit.atomic, decimals: asset.decimals)
      parts.append(
        isNative ? "Up to \(most) \(asset.symbol) after fees" : "Up to \(most) \(asset.symbol)")
    } else if let available {
      let held = ExactAmount.short(available.atomic, decimals: asset.decimals)
      if exceedsAvailable {
        parts.append("Only \(held) \(asset.symbol) available")
      } else if !available.atomic.contains(where: { $0 != "0" }) {
        parts.append("No \(asset.symbol) on \(networkName) yet")
      } else if isNative {
        // The coin pays its own fees: say so before Review has to.
        parts.append("\(held) \(asset.symbol) held · fees come out of it")
      } else {
        parts.append("\(held) \(asset.symbol) available")
      }
    } else {
      parts.append("Balance not read yet: refresh to check")
    }
    return parts.joined(separator: " · ")
  }
  /// The whole balance of a token, as typed. Nil for the network's coin, for nothing
  /// held, or when it is already the amount.
  private func maxAmount(_ asset: WalletAsset) -> String? {
    guard !asset.isNative, let available,
      available.atomic.contains(where: { $0 != "0" }), atomicAmount != available.atomic
    else { return nil }
    return Self.typed(available.atomic, asset)
  }
  /// Max for a network's coin: only when it holds some and the network can be asked.
  private func canAskMaximum(_ asset: WalletAsset) -> Bool {
    asset.isNative && !endpoint.isEmpty && account != nil
      && (available?.atomic.contains(where: { $0 != "0" }) ?? true)
  }
  /// Asks the core for the most that can be sent, then fills it in.
  private func askMaximum() {
    guard let account, let asset else { return }
    let recipient = recipientValid ? draft.cleanRecipient : ""
    model.run(.sendMaximum(account.slot, asset.id, recipient, endpoint, prefer)) {
      if let limit = model.sendLimit, limit.asset == asset.id {
        amount = Self.typed(limit.atomic, asset)
      }
    }
  }
  /// An exact amount as the field shows it, in the user's decimal separator.
  private static func typed(_ atomic: String, _ asset: WalletAsset) -> String {
    let text = ExactAmount.display(atomic, decimals: asset.decimals)
    let separator = Locale.current.decimalSeparator ?? "."
    return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
  }
  /// The amount is more than can be sent: say how much can, and why, with that amount
  /// one tap away.
  private func limitNote(_ limit: SendLimit, _ asset: WalletAsset) -> some View {
    let most = ExactAmount.short(limit.atomic, decimals: asset.decimals)
    let text =
      asset.isNative
      ? "You can send up to \(most) \(asset.symbol). The network fee is paid from the same balance."
      : "You can send up to \(most) \(asset.symbol)."
    return WalletNote(
      text, tone: .accent, icon: "info.circle",
      action: WalletNote.Action(title: "Use \(most)", icon: "arrow.down.to.line") {
        WalletHaptics.tap()
        amount = Self.typed(limit.atomic, asset)
        model.feedback = nil
      })
  }
  /// Another screen asked to send from one address first: say so, and let it go.
  private func preferChip(_ path: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.up.forward.circle").accessibilityHidden(true)
      Text("From \(WalletText.addressName(path)) first")
      Button {
        prefer = nil
      } label: {
        Image(systemName: "xmark").font(.caption2.weight(.bold))
          .frame(width: 24, height: 24).contentShape(Rectangle())
      }
      .buttonStyle(.plain).accessibilityLabel("Send from any address")
    }
    .font(.footnote.weight(.medium)).foregroundStyle(WalletTheme.accent)
    .padding(.leading, 10).padding(.trailing, 2)
    .background(WalletTheme.accent.opacity(0.1), in: Capsule())
    .accessibilityElement(children: .contain)
  }
  private var caret: some View { AmountCaret(height: Self.amountSize * 0.78) }

  // MARK: Recipient

  private var recipientBlock: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Text("To").roofStencil(13, tracking: 1.6).foregroundStyle(WalletTheme.muted)
          .accessibilityHidden(true)
        TextField("Recipient address", text: $recipient, axis: .vertical)
          .textFieldStyle(.plain).lineLimit(1...2)
          .font(.system(.body, design: .monospaced))
          .autocorrectionDisabled()
          .accessibilityLabel("Recipient address")
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
        recipientAccessories
      }
      .padding(.horizontal, 16).padding(.vertical, 12)
      .frame(minHeight: WalletMetrics.field + 20)
      .background(
        WalletTheme.surface,
        in: WalletShape.field
      )
      .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
      .overlay(
        WalletShape.field.strokeBorder(
          draft.recipientError != nil ? WalletTheme.danger : WalletTheme.border,
          lineWidth: draft.recipientError != nil ? 1.5 : 1)
      )
      if let error = draft.recipientError {
        Label(error, systemImage: "exclamationmark.circle.fill").font(.footnote)
          .foregroundStyle(WalletTheme.danger).fixedSize(horizontal: false, vertical: true)
      } else if let warning = draft.recentWarning ?? draft.ownAddressWarning {
        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.footnote)
          .foregroundStyle(WalletTheme.warning).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder private var recipientAccessories: some View {
    if recipientValid {
      Image(systemName: "checkmark.circle.fill").foregroundStyle(WalletTheme.success)
        .accessibilityLabel("Valid address")
    }
    if draft.cleanRecipient.isEmpty {
      if !draft.recentRecipients.isEmpty {
        Menu {
          ForEach(draft.recentRecipients.prefix(8)) { item in
            Button(
              "\(WalletText.short(item.recipient)) · \(model.state.networkName(item.chain)), \(item.date.formatted(date: .abbreviated, time: .omitted))"
            ) {
              recentPick = item
              recipient = item.recipient
            }
          }
        } label: {
          Image(systemName: "clock.arrow.circlepath")
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(WalletTheme.accent)
        .accessibilityLabel("Recent recipients").help("Recent recipients")
      }
      PasteButton(payloadType: String.self) { values in
        if let value = values.first?.trimmingCharacters(in: .whitespacesAndNewlines) {
          recipient = value
        }
      }
      .labelStyle(.iconOnly).buttonBorderShape(.capsule).walletTint()
      .help("Paste address")
      #if os(iOS)
        Button {
          scanning = true
        } label: {
          Image(systemName: "qrcode.viewfinder").font(.title3)
        }.buttonStyle(.plain).foregroundStyle(WalletTheme.accent)
          .accessibilityLabel("Scan address QR code")
      #endif
    } else {
      Button {
        recipient = ""
      } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(WalletTheme.muted)
      }.buttonStyle(.plain).accessibilityLabel("Clear recipient").help("Clear")
    }
  }

  // MARK: Review

  /// The network can't be used: when it is only switched off, the notice turns it on
  /// right here. When it has no endpoint at all, it leads to Networks.
  private func networkOff(_ asset: WalletAsset) -> some View {
    let network = model.state.network(asset.chain)
    let name = model.state.networkName(asset.chain)
    let switchable = network.map { !$0.enabled && $0.endpoint != nil } ?? false
    return WalletNote(
      switchable
        ? "\(name) is turned off. Turn it on to send."
        : "\(name) has no endpoint to send through. Add one in Networks.",
      tone: .accent, icon: "antenna.radiowaves.left.and.right.slash",
      action: switchable
        ? WalletNote.Action(
          title: "Turn on", icon: "power", busy: model.isRunning(.network(asset.chain))
        ) { model.run(.setNetwork(asset.chain, true)) }
        : WalletNote.Action(title: "Networks", icon: "arrow.right", run: openNetworks))
  }

  private var reviewButton: some View {
    WalletAction(title: "Review", icon: "paperplane", busy: preparing) {
      preparing = true
      // A new transfer: the last one's status card makes way.
      model.submission = nil
      if let account {
        if let assetID {
          model.run(
            .plan(account.slot, assetID, draft.cleanRecipient, draft.cleanAmount, endpoint, prefer))
        }
      }
    }
    .disabled(!model.canRun(.send) || !draft.valid).keyboardShortcut(.defaultAction)
  }

  /// Starts on the asset (and preferred address) another screen asked for.
  private func takeIntent() {
    guard let intent = model.sendIntent,
      model.state.assets.contains(where: { $0.id == intent.asset })
    else { return }
    model.sendIntent = nil
    assetID = intent.asset
    prefer = intent.prefer.flatMap { account?.paths.contains($0) == true ? $0 : nil }
  }

  private func defaults() {
    if !model.state.assets.contains(where: { $0.id == assetID }) {
      let usable = model.state.usableAssets
      let held = WalletPortfolio.holdings(model.state, account: account).first { !$0.isZero }
      assetID = held?.asset.id ?? usable.first?.id ?? model.state.assets.first?.id
    }
  }
}
