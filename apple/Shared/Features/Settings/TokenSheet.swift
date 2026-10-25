import SwiftUI

/// Adds or edits any token, including a network's native coin (symbol, name and
/// decimals. A native coin has no contract). Every entry can be removed. A complete
/// contract address is read from the network itself to prefill the other fields.
struct TokenSheet: View {
  @Environment(WalletModel.self) private var model
  let id: AssetID?
  /// The network a new token starts on.
  var network: ChainID? = nil
  let done: () -> Void
  @State private var chain: ChainID?
  @State private var contract = ""
  @State private var symbol = ""
  @State private var name = ""
  @State private var decimals = "18"
  @State private var priceURL = ""
  @State private var priceField = ""
  @State private var color = ""
  @State private var logo: String?
  @State private var priceCheck = PriceCheck.idle
  @State private var confirmRemove = false
  /// This sheet's own save or removal is running. Other work never shows here.
  @State private var saving = false
  @State private var lookup = Lookup.idle
  /// The values last filled in from the contract. A field still showing them (or its
  /// initial value) is refilled by the next lookup, and a field the user typed in is kept.
  @State private var filled = Filled(symbol: "", name: "", decimals: "18")
  private enum Lookup: Equatable {
    case idle, reading
    case found(String)
    case failed(String)
  }
  private enum PriceCheck: Equatable {
    case idle, checking
    case price(String)
    case failed(String)
  }
  private struct Filled { var symbol, name, decimals: String }
  private var existing: WalletAsset? {
    id.flatMap { id in model.state.assets.first { $0.id == id } }
  }
  private var native: Bool { existing?.isNative == true }
  private var cleanContract: String { contract.trimmingCharacters(in: .whitespacesAndNewlines) }
  /// The contract as typed, once it is a full address.
  private var address: EVMAddress? { EVMAddress(cleanContract) }
  /// The asset the form describes, once it has a network and a full contract.
  private var candidate: AssetID? {
    guard let chain, let address else { return nil }
    return .token(address.normalized, on: chain)
  }
  private var contractError: String? {
    guard !native, !cleanContract.isEmpty else { return nil }
    guard address != nil else {
      return "Enter the full contract address: 0x followed by 40 hexadecimal characters."
    }
    if let candidate, candidate != id,
      let other = model.state.assets.first(where: { $0.id == candidate })
    {
      return
        "Already in your list as \(other.symbol) on \(model.state.networkName(candidate.chain))."
    }
    return nil
  }
  private var decimalsError: String? {
    guard !decimals.isEmpty else { return nil }
    return Int(decimals).map { (0...36).contains($0) } == true
      ? nil : "Use a whole number from 0 to 36."
  }
  private var cleanURL: String { priceURL.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var cleanField: String { priceField.trimmingCharacters(in: .whitespacesAndNewlines) }
  /// Both parts or neither: an oracle needs a document and a path into it.
  private var priceSource: PriceSource? {
    cleanURL.isEmpty || cleanField.isEmpty ? nil : PriceSource(url: cleanURL, field: cleanField)
  }
  private var priceValid: Bool {
    (cleanURL.isEmpty && cleanField.isEmpty)
      || (priceSource != nil && RPCText.validURL(cleanURL))
  }
  private var priceURLError: String? {
    cleanURL.isEmpty || RPCText.validURL(cleanURL) ? nil : "Use an HTTPS URL."
  }
  private var draft: WalletAsset? {
    guard let places = Int(decimals), (0...36).contains(places), priceValid,
      !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    if native, let existing {
      return WalletAsset(
        id: existing.id, symbol: symbol, decimals: places, name: name, price: priceSource,
        color: color, logo: logo)
    }
    guard contractError == nil, let candidate else { return nil }
    return WalletAsset(
      id: candidate, symbol: symbol, decimals: places, name: name, price: priceSource,
      color: color, logo: logo)
  }
  var body: some View {
    WalletSheet(
      existing == nil ? "Add token" : (existing?.symbol ?? "Token"),
      subtitle: existing.map { "On \(model.state.networkName($0.chain))" } ?? "",
      icon: "circle.hexagongrid", closeDisabled: saving,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: done
    ) {
      if !native {
        WalletLabeled("Network") {
          WalletNetworkChooser(networks: model.state.networks, selection: $chain)
        }
        WalletField(
          "Contract address", hint: contractHint, error: contractError, warning: lookupWarning
        ) {
          TextField("0x…", text: $contract).autocorrectionDisabled()
            .font(.system(.body, design: .monospaced))
            #if os(iOS)
              .textInputAutocapitalization(.never)
            #endif
        }
      }
      WalletFormRow {
        WalletField("Symbol") {
          TextField("e.g. USDC", text: $symbol).autocorrectionDisabled()
        }
        WalletField("Decimals", error: decimalsError) { TextField("18", text: $decimals) }
          .frame(maxWidth: 120)
      }
      WalletField("Name") { TextField("Optional", text: $name) }
      WalletLookEditor(color: $color, logo: $logo) { art, size in
        WalletAssetGlyph(symbol: symbol.isEmpty ? "TKN" : symbol, art: art, size: size)
      }
      WalletFormRow {
        WalletField("Price URL", error: priceURLError) {
          TextField("Price URL", text: $priceURL, prompt: Text(verbatim: "https://…"))
            .autocorrectionDisabled()
            #if os(iOS)
              .textInputAutocapitalization(.never)
            #endif
        }
        // The check and its result sit inside the field they verify, on its own
        // line: the form keeps its height and nothing is added below it.
        WalletField("Price field") {
          HStack(spacing: 4) {
            TextField("Price field", text: $priceField, prompt: Text(verbatim: "ethereum.usd"))
              .autocorrectionDisabled()
              #if os(iOS)
                .textInputAutocapitalization(.never)
              #endif
            checkPriceButton
          }
        }
        .frame(maxWidth: 230)
      }
    } footer: {
      if existing != nil {
        WalletSheetActions(cancelDisabled: saving, cancel: done) {
          WalletAction(title: "Remove", icon: "trash", role: .destructive, expand: false) {
            confirmRemove = true
          }.disabled(!model.canRun(.asset))
        } primary: {
          saveAction
        }
      } else {
        WalletSheetActions(cancelDisabled: saving, cancel: done) { saveAction }
      }
    }
    .walletModal(width: 520, busy: saving)
    .onChange(of: model.isRunning(.asset)) { _, running in if !running { saving = false } }
    .onAppear {
      if let existing {
        chain = existing.chain
        contract = existing.contract?.text ?? ""
        symbol = existing.symbol
        name = existing.name ?? ""
        decimals = String(existing.decimals)
        priceURL = existing.price?.url ?? ""
        priceField = existing.price?.field ?? ""
        color = existing.color
        logo = existing.logo
      } else if chain == nil {
        chain = network ?? model.state.networks.first?.id
        color = WalletAccent.random(avoiding: model.state.assets.map(\.color)).rawValue
      }
    }
    .task(id: candidate) { await readContract() }
    .onChange(of: cleanURL + " " + cleanField) { _, _ in priceCheck = .idle }
    .onChange(of: model.lockEpoch) { _, _ in done() }
    .walletDismissOnLock { confirmRemove = false }
    .alert("Remove \(existing?.symbol ?? "token")?", isPresented: $confirmRemove) {
      Button("Cancel", role: .cancel) {}
      Button("Remove", role: .destructive) {
        if let id, model.canRun(.asset) {
          saving = true
          model.run(.removeAsset(id)) { done() }
        }
      }
    } message: {
      Text(
        "It's removed from this wallet. Funds on-chain are unaffected, and you can add it again.")
    }
  }
  private var contractHint: String {
    switch lookup {
    case .reading: "Reading the token from \(chain.map(model.state.networkName) ?? "the network")…"
    case .found(let summary): summary
    default: "Copy it from the token issuer's official site."
    }
  }
  private var lookupWarning: String? {
    if case .failed(let message) = lookup { message } else { nil }
  }
  /// Reads symbol, name and decimals from the contract once a full address is entered.
  private func readContract() async {
    lookup = .idle
    guard !native, let chain, let address, contractError == nil,
      address.lowercased != existing?.contract?.lowercased
    else { return }
    let network = model.state.networkName(chain)
    guard model.state.endpoint(for: chain) != nil else {
      lookup = .failed("Turn on \(network) to fill in the details automatically.")
      return
    }
    // Let typing or pasting settle before calling the network.
    try? await Task.sleep(for: .milliseconds(350))
    guard !Task.isCancelled else { return }
    lookup = .reading
    let details = await model.readToken(chain: chain, contract: address)
    guard !Task.isCancelled else { return }
    guard let details else {
      lookup = .failed("Couldn't read this contract on \(network). Enter its details below.")
      return
    }
    let places = String(details.decimals)
    if symbol == filled.symbol { symbol = details.symbol }
    if name == filled.name { name = details.name }
    if decimals == filled.decimals { decimals = places }
    filled = Filled(symbol: details.symbol, name: details.name, decimals: places)
    let title = details.name.isEmpty ? details.symbol : "\(details.name) (\(details.symbol))"
    lookup = .found("Found \(title) · \(details.decimals) decimals")
  }
  /// Checks the price, then shows it, or why it failed, in the button's place.
  /// Tapping again re-checks. Sized to the field's text line so the field never grows.
  private var checkPriceButton: some View {
    let source = priceValid ? priceSource : nil
    return Button {
      if let source { checkPrice(source) }
    } label: {
      Group {
        switch priceCheck {
        case .checking: WalletSpinner(size: 13).foregroundStyle(WalletTheme.muted)
        case .price(let value):
          Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            .foregroundStyle(WalletTheme.success).lineLimit(1).fixedSize()
        case .failed:
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(WalletTheme.warning)
        case .idle:
          Image(systemName: "arrow.clockwise").fontWeight(.semibold)
            .foregroundStyle(WalletTheme.accent)
        }
      }
      .font(.callout).frame(minWidth: 18, maxHeight: 18).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(source == nil || priceCheck == .checking).opacity(source == nil ? 0.35 : 1)
    .accessibilityLabel(priceLabel).help(priceLabel)
  }
  private var priceLabel: String {
    switch priceCheck {
    case .idle: "Check price"
    case .checking: "Checking price"
    case .price(let value): "Price \(value). Check again"
    case .failed(let reason): "\(reason). Check again"
    }
  }
  private func checkPrice(_ source: PriceSource) {
    priceCheck = .checking
    Task {
      // A thrown error means the request failed, nil means the field wasn't a price.
      let result = await Task.detached {
        Result { try prices(url: source.url, fields: [source.field]).first ?? nil }
      }.value
      guard source == priceSource else { return }
      switch result {
      case .failure: priceCheck = .failed("Request failed")
      case .success(let value):
        priceCheck =
          value.flatMap { Decimal(string: $0, locale: nil) }
          .map { .price(WalletPortfolio.currency($0)) } ?? .failed("Field not found")
      }
    }
  }
  private var saveAction: some View {
    WalletAction(
      title: existing == nil ? "Add token" : "Save", icon: "checkmark", busy: saving,
      busyTitle: "Saving…"
    ) { save() }
    .disabled(!model.canRun(.asset) || draft == nil || !changed).keyboardShortcut(.defaultAction)
  }
  private var changed: Bool {
    guard let existing, let draft else { return true }
    return draft.id != existing.id || draft.symbol != existing.symbol
      || draft.decimals != existing.decimals || draft.price != existing.price
      || (draft.name ?? "") != (existing.name ?? "") || color != existing.color
      || logo != existing.logo
  }
  private func save() {
    guard let draft, model.canRun(.asset) else { return }
    saving = true
    model.run(.saveAsset(draft, replacing: id)) { done() }
  }
}
