import SwiftUI

/// Presentation of the store links kept in `LocalSettings.storeLinks`.
enum StoreLinks {
  /// Where a Google Sheet is made. Opened in the browser, never read by the app.
  static let newSheetURL = URL(string: "https://docs.google.com/spreadsheets/create")
  /// The link without its scheme.
  static func display(_ url: String) -> String {
    url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
  }
}

/// Creates a Stor store for the project from a Google Sheet: share the sheet with the
/// Stor server's address, pick the store's address, paste the sheet. Create does the rest
/// (the sheet gets its tabs, and its Payments tab this project's URL and a key that can
/// only create payment addresses). The Stor server is ours unless changed, so it is
/// folded away.
struct NewStoreSheet: View {
  @Environment(WalletModel.self) private var model
  let connection: PathConnection
  let close: () -> Void
  /// The Stor server stores are created on: ours by default, any other the user enters.
  @State private var server = ""
  /// What that server asks of a new store. Nil until it answered.
  @State private var info: Stor.Info?
  /// The server was asked and didn't answer.
  @State private var missing = false
  @State private var loading = false
  @State private var serverShown = false
  @State private var subdomain = ""
  @State private var sheet = ""
  private var running: Bool { model.isRunning(.connection(connection.id)) }
  private var cleanServer: String { server.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var cleanSheet: String { sheet.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var valid: Bool {
    info != nil && model.canRun(.connection(connection.id)) && Stor.validSubdomain(subdomain)
      && !cleanSheet.isEmpty
  }
  var body: some View {
    WalletSheet(
      "New store", subtitle: connection.project, icon: "storefront", closeDisabled: running,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: close
    ) {
      VStack(alignment: .leading, spacing: 14) {
        if let info {
          ShareSheetCard(email: info.shareWith)
          StoreStep(number: 2, title: "Choose the store's address")
          WalletField("Address") {
            HStack(spacing: 2) {
              TextField("my-store", text: $subdomain).autocorrectionDisabled()
                #if os(iOS)
                  .textInputAutocapitalization(.never)
                #endif
              Text(info.suffix).foregroundStyle(WalletTheme.muted).lineLimit(1).fixedSize()
            }
          }
          StoreStep(number: 3, title: "Paste the sheet's link")
          WalletField("Google Sheet") {
            TextField(
              "Google Sheet", text: $sheet,
              prompt: Text(verbatim: "https://docs.google.com/spreadsheets/d/…")
            )
            .autocorrectionDisabled()
            #if os(iOS)
              .textInputAutocapitalization(.never).keyboardType(.URL)
            #endif
          }
        } else if loading {
          WalletSpinner(size: 18).foregroundStyle(WalletTheme.accent)
            .frame(maxWidth: .infinity).accessibilityLabel("Contacting the Stor server")
        }
        WalletDisclosure(
          "Stor server", detail: URL(string: cleanServer)?.host() ?? cleanServer,
          expanded: $serverShown
        ) {
          WalletField(
            "Stor server", error: missing ? "No Stor server answers at this address." : nil
          ) {
            TextField("Stor server", text: $server, prompt: Text(verbatim: "https://…"))
              .autocorrectionDisabled()
              .onSubmit { Task { await load() } }
              #if os(iOS)
                .textInputAutocapitalization(.never).keyboardType(.URL)
              #endif
          } accessory: {
            if info == nil {
              WalletIconButton(
                title: "Connect to this server", icon: "arrow.right", busy: loading
              ) { Task { await load() } }
              .disabled(cleanServer.isEmpty)
            }
          }
          .padding(.top, 8)
        }
      }
    } footer: {
      WalletSheetActions(cancelDisabled: running, cancel: close) {
        WalletAction(
          title: "Create", icon: "storefront", busy: running, busyTitle: "Creating…",
          action: create
        )
        .disabled(!valid).keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 520, busy: running)
    // Another address is another server: what the last one said no longer applies.
    .onChange(of: server) { _, _ in
      info = nil
      missing = false
    }
    // A server that doesn't answer is shown, so it can be corrected.
    .onChange(of: missing) { _, value in if value { serverShown = true } }
    .onChange(of: model.lockEpoch) { _, _ in sheet = "" }
    .task {
      // The first store takes the project's name. Later ones need their own.
      if model.state.settings.storeLinks[connection.id, default: []].isEmpty
        && Stor.validSubdomain(connection.project)
      {
        subdomain = connection.project
      }
      if server.isEmpty { server = model.state.settings.storServer }
      if info == nil { await load() }
    }
  }
  private func create() {
    guard valid, let info else { return }
    let address = subdomain
    model.run(
      .createStore(
        connection.origin, connection.project, info.stor, address, cleanSheet,
        link: info.url(address))
    ) { close() }
  }
  /// Asks the server in the field what a new store needs.
  private func load() async {
    let value = cleanServer
    guard !value.isEmpty, !loading else { return }
    loading = true
    // A pasted address may carry a path or a trailing slash. The server is its origin.
    let origin = URL(string: value).flatMap { url -> String? in
      guard let scheme = url.scheme, let host = url.host() else { return nil }
      return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
    }
    var answer: Stor.Info?
    if let origin { answer = await model.stor(origin) }
    loading = false
    // The field may have changed while the server was asked.
    guard value == cleanServer else { return }
    info = answer
    missing = answer == nil
    if let origin, answer != nil { model.run(.storServer(origin)) }
  }
}

/// Connects a store that already exists (made on Stor's page, or from another device) to
/// this project. Stor reads payments from the sheet's Payments tab, so connecting is a
/// new key named after the store, shown once with the project's URL, for the merchant to
/// paste there. Nothing is sent to Stor. The store's link joins the list when given.
struct ConnectStoreSheet: View {
  @Environment(WalletModel.self) private var model
  let connection: PathConnection
  let close: () -> Void
  @State private var store = ""
  @State private var url = ""
  @State private var key = ""
  private var running: Bool { model.isRunning(.connection(connection.id)) }
  /// The store's link as pasted (`https://my-store.stor.top/…`) or just its name.
  private var parsed: (subdomain: String, link: String?) {
    let value = store.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard value.contains("://"), let link = URL(string: value), let host = link.host(),
      let scheme = link.scheme
    else { return (value, nil) }
    let origin = "\(scheme)://\(host)" + (link.port.map { ":\($0)" } ?? "")
    return (host.split(separator: ".").first.map(String.init) ?? "", origin)
  }
  private var valid: Bool {
    Stor.validSubdomain(parsed.subdomain) && model.canRun(.connection(connection.id))
  }
  var body: some View {
    WalletSheet(
      key.isEmpty ? "Connect store" : "Paste into the sheet", subtitle: connection.project,
      icon: "storefront", closeDisabled: running,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: finish
    ) {
      if key.isEmpty { form } else { reveal }
    } footer: {
      if key.isEmpty {
        WalletSheetActions(cancelDisabled: running, cancel: finish) {
          WalletAction(
            title: "Get URL and KEY", icon: "key", busy: running, busyTitle: "Creating…",
            action: connect
          )
          .disabled(!valid).keyboardShortcut(.defaultAction)
        }
      } else {
        WalletAction(title: "Done", icon: "checkmark", action: finish)
          .keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 520, busy: running)
    .onChange(of: model.lockEpoch) { _, _ in finish() }
    .onDisappear {
      key = ""
      model.issuedToken = ""
      model.issuedStoreURL = ""
    }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(
        "For a store made on Stor's page or another device. Its sheet's Payments tab needs a **URL** and a **KEY** from this project."
      )
      .font(.footnote).foregroundStyle(WalletTheme.muted)
      .fixedSize(horizontal: false, vertical: true)
      WalletField("Store") {
        TextField(
          "Store", text: $store, prompt: Text(verbatim: "https://my-store.stor.top")
        )
        .autocorrectionDisabled()
        .onSubmit(connect)
        #if os(iOS)
          .textInputAutocapitalization(.never).keyboardType(.URL)
        #endif
      }
      Text("Its link, or just its name (my-store).")
        .font(.footnote).foregroundStyle(WalletTheme.muted)
    }
  }

  /// URL and KEY as the Payments tab lists them, each with its Copy button, then what
  /// each one is.
  private var reveal: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("In the sheet's **Payments** tab, paste each into the **Value** column.")
        .font(.footnote).foregroundStyle(WalletTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      PaymentsValue(
        name: "URL", value: url,
        detail: "Your payment server and project: where the store's payments go."
      )
      PaymentsValue(
        name: "KEY", value: key,
        detail:
          "Lets Stor create a payment address for each order and hear when it is paid. It can't move funds. Revoke it under Access.",
        source: .secret
      ) {
        model.feedback = WalletFeedback(
          message: "Copied. The clipboard clears in a minute.", kind: .info)
      }
      Label("The KEY is shown only once", systemImage: "eye.slash").font(.footnote)
        .foregroundStyle(WalletTheme.muted)
    }
  }

  private func connect() {
    guard valid else { return }
    let (subdomain, link) = parsed
    model.run(.storeKey(connection.origin, connection.project, subdomain, link: link)) {
      url = model.issuedStoreURL
      key = model.issuedToken
      model.issuedToken = ""
      model.issuedStoreURL = ""
    }
  }
  private func finish() {
    key = ""
    url = ""
    model.issuedToken = ""
    model.issuedStoreURL = ""
    close()
  }
}

/// One row of the Payments tab to fill: its name, the value in one field with a Copy
/// button at the end, and what the value is.
private struct PaymentsValue: View {
  let name: String
  let value: String
  let detail: String
  var source = WalletCopySource.publicValue
  var onCopy: (() -> Void)? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(name).font(.subheadline.weight(.semibold))
      HStack(spacing: 6) {
        Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel(name)
        WalletCopyButton(label: name, value: value, style: .field, source: source, onCopy: onCopy)
      }
      .padding(.leading, 12).padding(.trailing, 2).padding(.vertical, 2)
      .frame(minHeight: WalletMetrics.field)
      .background(WalletTheme.surface, in: WalletShape.field)
      .overlay(WalletShape.field.strokeBorder(WalletTheme.border))
      Text(detail).font(.footnote).foregroundStyle(WalletTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// A numbered step of New store, set like a sign on a door.
private struct StoreStep: View {
  let number: Int
  let title: String
  var body: some View {
    HStack(spacing: 8) {
      Text("\(number)").font(RoofFont.sign(15, relativeTo: .footnote))
        .offset(y: SignMetrics.centering(15))
        .foregroundStyle(WalletTheme.onAccent)
        .frame(width: 22, height: 22)
        .background(WalletTheme.accent, in: Circle())
      Text(title).font(RoofFont.posterMedium(15, relativeTo: .subheadline))
    }
    .padding(.top, 4)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// Step one of New store: who to share the Google Sheet with. The address is the one
/// thing to carry over to Google, so it stands on its own card, large and whole (it
/// wraps rather than truncates), with the role it needs and a copy button that says
/// when it has copied.
struct ShareSheetCard: View {
  let email: String
  private var local: String {
    email.split(separator: "@", maxSplits: 1).first.map(String.init) ?? email
  }
  private var domain: String {
    email.firstIndex(of: "@").map { String(email[$0...]) } ?? ""
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StoreStep(number: 1, title: "Share your Google Sheet")
      Text("In the sheet: Share → add this address → set it to **Editor**.")
        .font(.footnote).foregroundStyle(WalletTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      if let create = StoreLinks.newSheetURL {
        Link(destination: create) {
          Label("No sheet yet? Create one", systemImage: "arrow.up.right.square")
            .font(.footnote.weight(.medium))
        }
        .foregroundStyle(WalletTheme.accent)
      }
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "envelope.fill").foregroundStyle(WalletTheme.accent)
            .accessibilityHidden(true)
          // Whole on one line when it fits. Otherwise broken only at the "@", never
          // hyphenated inside a name.
          ViewThatFits(in: .horizontal) {
            Text(email).lineLimit(1)
            VStack(alignment: .leading, spacing: 1) {
              Text(local).lineLimit(1).minimumScaleFactor(0.7)
              Text(domain).lineLimit(1).minimumScaleFactor(0.6)
            }
          }
          .font(.system(.callout, design: .monospaced).weight(.semibold))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(email)
          Text("Editor").roofStencil(10, tracking: 1)
            .foregroundStyle(WalletTheme.accent)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(WalletTheme.accent.opacity(0.12), in: Capsule())
        }
        WalletCopyAction(
          title: "Copy address", value: email, role: .secondary, announcement: "Address copied")
      }
      .padding(14)
      .background(
        WalletTheme.surface,
        in: RoundedRectangle(cornerRadius: WalletMetrics.radius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: WalletMetrics.radius, style: .continuous)
          .strokeBorder(WalletTheme.accent.opacity(0.45), lineWidth: 1.5)
      )
    }

  }
}
