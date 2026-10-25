import SwiftUI

/// Adds a network, or edits one: on/off, its endpoints (every one selectable,
/// editable and removable, each chain-verified before saving), and its details.
struct NetworkSheet: View {
  @Environment(WalletModel.self) private var model
  let done: () -> Void
  /// The network being edited. Nil while adding one.
  @State private var chain: ChainID?
  @State private var chainNumber = ""
  @State private var name = ""
  @State private var mode = TransactionMode.eip1559
  @State private var currency = ""
  @State private var explorer = ""
  @State private var url = ""
  /// The look being edited: a preset name or `#RRGGBB`, and the logo (nil is none).
  @State private var color = ""
  @State private var logo: String?
  @State private var editing: String?
  @State private var showDetails = false
  @State private var confirmRemove: RPCEndpoint?
  @State private var confirmRemoveNetwork = false
  /// An endpoint add/save is running. Its button shows the progress.
  @State private var submitting = false
  init(chain: ChainID?, done: @escaping () -> Void) {
    self._chain = State(initialValue: chain)
    self.done = done
  }
  private var network: WalletNetwork? { chain.flatMap { model.state.network($0) } }
  private var list: [RPCEndpoint] { chain.map { model.state.endpoints(for: $0) } ?? [] }
  private var active: String? { chain.flatMap { model.state.endpoint(for: $0) } }
  /// The network shown is being changed (an endpoint, a toggle, its details).
  private var saving: Bool { chain.map { model.isRunning(.network($0)) } ?? false }
  /// Its endpoints are being checked. That never holds back other changes.
  private var probing: Bool { chain.map { model.isRunning(.probe($0)) } ?? false }
  /// Whether the network shown can be changed now.
  private var editable: Bool { chain.map { model.canRun(.network($0)) } ?? false }
  /// The network being added. Nil until the chain ID is a number.
  private var newChain: ChainID? { ChainID(number: chainNumber) }
  private var adding: Bool { newChain.map { model.isRunning(.network($0)) } ?? false }
  private var chainError: String? {
    guard !chainNumber.isEmpty else { return nil }
    guard let newChain else { return "Use the network's decimal chain ID, for example 10." }
    if model.state.network(newChain) != nil {
      return "This network is already in your list."
    }
    return nil
  }
  private var urlError: String? {
    let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    guard RPCText.validURL(value) else {
      return "Use a full HTTPS URL without a username or password."
    }
    if list.contains(where: { $0.url == value && $0.url != editing }) {
      return "This endpoint is already in the list."
    }
    return nil
  }
  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var cleanExplorer: String { explorer.trimmingCharacters(in: .whitespacesAndNewlines) }
  /// The color, logo and preview of the network being added or edited.
  private var lookEditor: some View {
    WalletLookEditor(color: $color, logo: $logo) { art, size in
      WalletNetworkGlyph(
        name: trimmedName.isEmpty ? (network?.name ?? "") : trimmedName, art: art, size: size)
    }
  }
  private var explorerError: String? {
    cleanExplorer.isEmpty || RPCText.validURL(cleanExplorer) ? nil : "Use an HTTPS URL."
  }
  /// For transaction links: `<URL>/tx/<hash>`.
  private var explorerField: some View {
    WalletField("Block explorer", error: explorerError) {
      TextField(
        "Block explorer", text: $explorer, prompt: Text(verbatim: "https://etherscan.io (optional)")
      ).autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never).keyboardType(.URL)
        #endif
    }
  }
  var body: some View {
    Group {
      if let network { editor(network) } else { creator }
    }
    .onChange(of: model.lockEpoch) { _, _ in done() }
  }

  // MARK: Add

  private var canAdd: Bool {
    newChain.map { model.canRun(.network($0)) } == true && chainError == nil
      && !trimmedName.isEmpty
      && explorerError == nil
  }
  private var creator: some View {
    WalletSheet(
      "Add network", icon: "network", closeDisabled: adding,
      status: model.feedback?.status ?? .idle,
      dismissStatus: { model.feedback = nil }, close: done
    ) {
      WalletFormRow {
        WalletField("Name") { TextField("e.g. Optimism", text: $name) }
        WalletField("Chain ID", error: chainError) { TextField("e.g. 10", text: $chainNumber) }
          .frame(maxWidth: 150)
      }
      WalletFormRow {
        WalletField("Native coin") {
          TextField("ETH (optional)", text: $currency).autocorrectionDisabled()
        }
        feeMode.frame(maxWidth: 220)
      }
      explorerField
      lookEditor
    } footer: {
      WalletSheetActions(cancelDisabled: adding, cancel: done) {
        WalletAction(title: "Add network", icon: "plus", busy: adding, busyTitle: "Adding…") {
          add()
        }
        .disabled(!canAdd).keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 520, busy: adding)
    .onAppear {
      if color.isEmpty {
        color = WalletAccent.random(avoiding: model.state.networks.map(\.color)).rawValue
      }
    }
  }
  /// Labelled like a field and exactly as tall as one, so it pairs with a field.
  private var feeMode: some View {
    WalletLabeled("Fees") {
      Picker("Fee mode", selection: $mode) {
        Text("EIP-1559").tag(TransactionMode.eip1559)
        Text("Legacy").tag(TransactionMode.legacy)
      }
      .pickerStyle(.segmented).labelsHidden()
    }
  }
  private func add() {
    guard canAdd, let id = newChain else { return }
    let symbol = currency.trimmingCharacters(in: .whitespacesAndNewlines)
    model.run(
      .saveNetwork(
        chain: id, name: trimmedName, mode: mode, explorer: cleanExplorer, currency: symbol,
        look: WalletLook(color: color, logo: logo))
    ) {
      chain = id
    }
  }

  // MARK: Edit

  private func editor(_ network: WalletNetwork) -> some View {
    WalletSheet(
      network.name,
      subtitle: "Chain ID \(network.id.number)\(network.enabled ? "" : " · Off")",
      icon: "network",
      closeTitle: "Done", status: editorStatus, dismissStatus: { model.feedback = nil },
      close: done
    ) {
      VStack(alignment: .leading, spacing: 8) {
        WalletSectionHeader("Endpoints", detail: list.isEmpty ? "" : "\(list.count)") {
          if !list.isEmpty {
            WalletAction(
              title: "Check all", icon: "antenna.radiowaves.left.and.right", role: .tertiary,
              expand: false, busy: probing, busyTitle: "Checking…"
            ) { model.run(.probeEndpoints(network.id)) }
            .disabled(!model.canRun(.probe(network.id)))
          }
        }
        if list.isEmpty {
          WalletEmptyState(
            icon: "server.rack", title: "No endpoints",
            detail: "Add one below to turn this network on.")
        } else {
          WalletCard(padding: 6) {
            VStack(spacing: 0) {
              ForEach(list) { item in endpointRow(item, network: network) }
            }
          }
        }
        WalletField(
          editing == nil ? "Add endpoint" : "Edit endpoint",
          error: urlError
        ) {
          TextField("RPC URL", text: $url, prompt: Text(verbatim: "https://…"))
            .autocorrectionDisabled()
            .font(.system(.body, design: .monospaced)).onSubmit { submit(network) }
            #if os(iOS)
              .textInputAutocapitalization(.never).keyboardType(.URL)
            #endif
        } accessory: {
          // Icons, so the input keeps the row on a phone too.
          if editing != nil {
            WalletIconButton(
              title: "Cancel editing", icon: "xmark", quiet: true,
              tint: AnyShapeStyle(WalletTheme.muted)
            ) {
              editing = nil
              url = ""
            }
          }
          WalletIconButton(
            title: editing == nil ? "Add endpoint" : "Save endpoint",
            icon: editing == nil ? "plus" : "checkmark", busy: saving && submitting
          ) { submit(network) }
          .disabled(
            !editable || url.trimmingCharacters(in: .whitespaces).isEmpty || urlError != nil)
        }
      }
      WalletDisclosure(
        "Network details", detail: "Name, fees, explorer, look", expanded: $showDetails
      ) {
        VStack(alignment: .leading, spacing: 14) {
          WalletFormRow {
            WalletField("Name") { TextField("Name", text: $name) }
            feeMode.frame(maxWidth: 220)
          }
          explorerField
          lookEditor
          HStack(spacing: 10) {
            WalletAction(
              title: "Remove \(network.name)", icon: "trash", role: .destructive, expand: false
            ) { confirmRemoveNetwork = true }.disabled(!editable)
            Spacer(minLength: 0)
            WalletAction(title: "Save details", icon: "checkmark", expand: false) {
              model.run(
                .saveNetwork(
                  chain: network.id, name: trimmedName, mode: mode, explorer: cleanExplorer,
                  currency: nil, look: WalletLook(color: color, logo: logo)))
            }
            .disabled(
              !editable || trimmedName.isEmpty || explorerError != nil
                || (trimmedName == network.name && mode == network.transactionMode
                  && cleanExplorer == (network.explorer ?? "") && color == network.color
                  && logo == network.logo)
            )
          }
        }
      }
    }
    .walletModal(width: 580, busy: saving)
    .onChange(of: saving) { _, saving in if !saving { submitting = false } }
    .onAppear {
      name = network.name
      mode = network.transactionMode
      explorer = network.explorer ?? ""
      color = network.color
      logo = network.logo
    }
    .walletDismissOnLock {
      confirmRemove = nil
      confirmRemoveNetwork = false
    }
    .alert(
      "Remove endpoint?",
      isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })
    ) {
      Button("Cancel", role: .cancel) { confirmRemove = nil }
      Button("Remove", role: .destructive) {
        if let item = confirmRemove { model.run(.deleteEndpoint(network.id, item.url)) }
        confirmRemove = nil
      }
    } message: {
      Text(
        confirmRemove?.url == active
          ? "It's the selected endpoint. \(network.name) switches to the next one, or stops working if none is left."
          : "You can add it again later.")
    }
    .alert("Remove \(network.name)?", isPresented: $confirmRemoveNetwork) {
      Button("Cancel", role: .cancel) {}
      Button("Remove", role: .destructive) {
        model.run(.removeNetwork(network.id)) { done() }
      }
    } message: {
      Text(
        "Its endpoints and tokens are removed. Funds on-chain aren't affected, and you can add it again."
      )
    }
  }

  /// Checking and adding endpoints report progress in their own buttons. Other
  /// changes (toggles, selection, details) report it here, as do all results.
  private var editorStatus: WalletStatus {
    if saving && !submitting { return .progress("Saving…") }
    return model.feedback?.status ?? .idle
  }

  private func endpointRow(_ item: RPCEndpoint, network: WalletNetwork) -> some View {
    let selected = item.url == active
    let health = model.state.health(item.url, chain: network.id)
    return HStack(spacing: 6) {
      Button {
        if !selected { model.run(.selectEndpoint(network.id, item.url)) }
      } label: {
        HStack(spacing: 12) {
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3).foregroundStyle(
              selected ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.border)
            )
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text(item.name).font(.callout.weight(selected ? .semibold : .medium))
              .lineLimit(1)
            Text(keySource(item) ?? RPCText.redacted(item.url))
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(WalletTheme.muted).lineLimit(1).truncationMode(.middle)
          }
          Spacer(minLength: 8)
          // Trailing, so a check never moves the name or the URL.
          healthLabel(health)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(minHeight: WalletMetrics.control + 10)
      }
      .buttonStyle(WalletRowButtonStyle())
      .disabled(!editable || !network.enabled)
      .accessibilityLabel("\(item.name), \(RPCText.redacted(item.url)), \(healthText(health))")
      .accessibilityAddTraits(selected ? .isSelected : [])
      .accessibilityHint(selected ? "" : "Selects this endpoint for \(network.name)")
      // One menu instead of two buttons keeps the name and URL readable on phones.
      // Provider endpoints come from their key: nothing to edit or remove here.
      if !item.isProvider {
        Menu {
          Button("Edit", systemImage: "pencil") {
            editing = item.url
            url = item.url
          }
          Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = item }
        } label: {
          Image(systemName: "ellipsis.circle").font(.body.weight(.medium))
            .frame(width: WalletMetrics.control, height: WalletMetrics.control)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(WalletTheme.muted)
        .disabled(!editable)
        .accessibilityLabel("More for \(item.name)").help("Edit or remove")
      }
    }
  }

  /// Where a provider endpoint's key comes from. Nil for a plain URL.
  private func keySource(_ item: RPCEndpoint) -> String? {
    guard let provider = KeyProvider(reference: item.url) else { return nil }
    return model.state.providers.contains(provider.id) ? "Your key" : "Built-in key"
  }
  @ViewBuilder private func healthLabel(_ health: EndpointHealth?) -> some View {
    if probing {
      WalletSpinner(size: 12).foregroundStyle(WalletTheme.muted)
    } else if let health {
      Label(
        health.verified ? "Verified" : "Unavailable",
        systemImage: health.verified ? "checkmark.circle.fill" : "xmark.circle.fill"
      )
      .labelStyle(.titleAndIcon).font(.caption.weight(.medium)).lineLimit(1)
      .foregroundStyle(health.verified ? WalletTone.success.color : WalletTone.danger.color)
      .fixedSize().help(healthText(health))
    }
  }
  private func healthText(_ health: EndpointHealth?) -> String {
    guard let health else { return probing ? "Checking" : "Not checked" }
    let time = health.date.formatted(date: .omitted, time: .shortened)
    return health.verified
      ? "Reachable and serving this network, checked \(time)"
      : "Unreachable or not serving this network, checked \(time)"
  }
  private func submit(_ network: WalletNetwork) {
    let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard editable, !value.isEmpty, urlError == nil else { return }
    submitting = true
    model.run(.addEndpoint(chain: network.id, url: value, replacing: editing)) {
      url = ""
      editing = nil
    }
  }
}
