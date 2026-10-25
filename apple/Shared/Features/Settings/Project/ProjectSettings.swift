import SwiftUI

/// The Project page, for the current account. An account has one project: its addresses
/// are numbered from the same root on every server, so a second project would hand out
/// the same addresses again. The page shows the project and its actions in one header
/// row, its stores, every credential of the project (pairings, stores' keys and created
/// tokens) in one list, and the project's public details folded away below.
struct ProjectSettings: View {
  @Environment(WalletModel.self) private var model
  @State private var connecting = false
  @State private var pairing = false
  @State private var creatingToken = false
  @State private var creatingStore = false
  @State private var connectingStore = false
  @State private var detailsShown = false
  @State private var revoking: AccessGrant?
  @State private var disconnecting: PathConnection?
  /// Which icon started the command running on the connection, so only it spins.
  @State private var started: Started?
  private enum Started { case find, refresh }
  private var connection: PathConnection? { model.connection }
  /// The server no longer accepts this device's credential for the project.
  private var connectionRevoked: Bool {
    connection.map { model.state.revokedConnections.contains($0.id) } ?? false
  }
  private var grantsLoaded: Bool {
    connection.map { model.state.grantsConnection == $0.id } ?? false
  }
  /// Commands on one connection run one at a time. The rest of the wallet stays usable.
  private func canRun(_ connection: PathConnection) -> Bool {
    model.canRun(.connection(connection.id))
  }
  private func running(_ action: Started) -> Bool {
    started == action && connection.map { model.isRunning(.connection($0.id)) } == true
  }
  private func start(_ action: Started, _ command: WalletCommand) {
    started = action
    model.run(command)
  }

  var body: some View {
    Group {
      if let connection {
        VStack(alignment: .leading, spacing: 20) {
          header(connection)
          if !connectionRevoked {
            stores(connection)
            access(connection)
          }
          details(connection)
        }
      } else {
        // Nothing to manage yet: one centred invitation to connect.
        WalletEmptyState(
          icon: "link", title: "No project", detail: "Accept payments to this account."
        ) {
          WalletAction(title: "Connect", icon: "link", expand: false) {
            model.feedback = nil
            connecting = true
          }
          .disabled(model.busy)
        }
        .frame(maxHeight: .infinity)
      }
    }
    // The project's credentials are listed as soon as the page opens.
    .task(id: connection?.id) { await loadGrants() }
    .walletSheet(isPresented: $connecting) {
      ConnectProjectSheet { connecting = false }
    }
    .walletSheet(isPresented: $pairing) {
      PairSheet(project: connection?.project ?? "") { pairing = false }
    }
    .walletSheet(isPresented: $creatingToken) {
      if let connection {
        NewTokenSheet(connection: connection) { creatingToken = false }
      }
    }
    .walletSheet(isPresented: $creatingStore) {
      if let connection {
        NewStoreSheet(connection: connection) { creatingStore = false }
      }
    }
    .walletSheet(isPresented: $connectingStore) {
      if let connection {
        ConnectStoreSheet(connection: connection) { connectingStore = false }
      }
    }
    .walletDismissOnLock {
      revoking = nil
      disconnecting = nil
      connecting = false
      pairing = false
      creatingToken = false
      creatingStore = false
      connectingStore = false
    }
    .alert(
      "Disconnect \(disconnecting?.project ?? "project")?",
      isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } })
    ) {
      Button("Cancel", role: .cancel) { disconnecting = nil }
      Button("Disconnect", role: .destructive) {
        if let item = disconnecting { model.run(.disconnect(item.origin, item.project)) }
        disconnecting = nil
      }
    } message: {
      Text(
        "This device forgets its access. The project and your addresses stay. Connect again anytime."
      )
    }
    .alert(
      "Revoke access?",
      isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } })
    ) {
      Button("Cancel", role: .cancel) { revoking = nil }
      Button("Revoke", role: .destructive) {
        if let grant = revoking, let connection {
          model.run(.revokeGrant(connection.origin, connection.project, grant.id))
        }
        revoking = nil
      }
    } message: {
      Text(
        "\(revoking?.name ?? "This credential") loses access to the project. If it's this device's access, connect again afterwards."
      )
    }
  }

  // MARK: Header

  private func header(_ connection: PathConnection) -> some View {
    WalletCard(padding: 12) {
      HStack(spacing: 10) {
        projectLabel(connection)
        Spacer(minLength: 8)
        if connectionRevoked {
          WalletAction(
            title: "Reconnect", icon: "arrow.clockwise", expand: false,
            busy: model.isRunning(.connection(connection.id)), busyTitle: "Reconnecting…"
          ) {
            model.run(.connect(connection.origin, connection.project, connection.slot))
          }
          .fixedSize()
          .disabled(!canRun(connection))
        } else {
          WalletIconButton(
            title: "Find new addresses", icon: "arrow.down.circle",
            busy: running(.find), quiet: true
          ) {
            start(.find, .sync(connection.origin, connection.project, connection.slot))
          }
          .help(Self.discovery)
          .disabled(!canRun(connection))
        }
        WalletIconButton(
          title: "Disconnect", icon: "minus.circle", quiet: true,
          tint: AnyShapeStyle(WalletTheme.danger)
        ) { disconnecting = connection }
        .disabled(!canRun(connection))
      }
    }
  }

  private func projectLabel(_ item: PathConnection) -> some View {
    let lost = connectionRevoked
    return HStack(spacing: 8) {
      Circle().fill(lost ? WalletTheme.warning : WalletTheme.success).frame(width: 8, height: 8)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        Text(item.project).font(.callout.weight(.semibold)).lineLimit(1)
        Text(lost ? "Access revoked" : Self.host(item))
          .font(.caption).foregroundStyle(lost ? WalletTheme.warning : WalletTheme.muted)
          .lineLimit(1).truncationMode(.middle)
      }
    }
    .accessibilityElement(children: .combine)
  }

  static func host(_ item: PathConnection) -> String {
    URL(string: item.origin)?.host ?? item.origin
  }

  // MARK: Access

  private func access(_ connection: PathConnection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      WalletSectionHeader("Access") {
        HStack(spacing: 2) {
          WalletIconButton(title: "New token", icon: "key", quiet: true) {
            creatingToken = true
          }
          WalletIconButton(title: "Pair", icon: "qrcode", quiet: true) { pairing = true }
            .disabled(!model.canRun(.access))
          WalletIconButton(
            title: "Refresh access", icon: "arrow.clockwise",
            busy: running(.refresh), quiet: true
          ) {
            start(.refresh, .grants(connection.origin, connection.project))
          }
          .disabled(!canRun(connection))
        }
      }
      WalletCard(padding: 12) {
        VStack(alignment: .leading, spacing: 12) {
          if !grantsLoaded {
            Text("…").font(.callout).foregroundStyle(WalletTheme.muted)
          } else if model.state.grants.isEmpty {
            Text("No credentials").font(.callout).foregroundStyle(WalletTheme.muted)
          } else {
            ForEach(model.state.grants) { grant in
              grantRow(grant, connection)
              if grant.id != model.state.grants.last?.id { Divider() }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func grantRow(_ grant: AccessGrant, _ connection: PathConnection) -> some View {
    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text(grant.name).font(.callout.weight(.medium)).lineLimit(1)
          if let created = WalletDate.parse(grant.createdAt) {
            Text(WalletFreshness.relative(created)).font(.caption)
              .foregroundStyle(WalletTheme.muted).lineLimit(1)
          }
        }
        WalletFlowLayout(spacing: 6) {
          ForEach(grant.permissions, id: \.self) { raw in
            let permission = APIPermission(rawValue: raw)
            WalletBadge(
              title: permission?.title ?? raw.capitalized, tone: permission?.tone ?? .neutral,
              icon: permission?.icon)
          }
        }
      }
      Spacer(minLength: 8)
      WalletIconButton(
        title: "Revoke \(grant.name)", icon: "xmark.circle", quiet: true,
        tint: AnyShapeStyle(WalletTheme.danger)
      ) { revoking = grant }
      .disabled(!canRun(connection))
    }
  }

  // MARK: Details

  /// The project's public facts, folded away: the server, how many of the account's
  /// addresses it handed out, and the watch root it was given with its fingerprint.
  private func details(_ connection: PathConnection) -> some View {
    WalletDisclosure(
      "Details", detail: addressCount, expanded: $detailsShown
    ) {
      VStack(alignment: .leading, spacing: 8) {
        WalletCard(padding: 0) {
          VStack(alignment: .leading, spacing: 0) {
            PublicValue(label: "Server", value: connection.origin)
            Divider()
            WalletDetailRow(label: "Addresses", value: addressCount)
            Divider()
            PublicValue(label: "Fingerprint", value: connection.fingerprint)
            Divider()
            PublicValue(label: "Watch root", value: connection.root)
          }
          .padding(.horizontal, 14).padding(.vertical, 4)
        }
        Text(Self.discovery)
          .font(.caption).foregroundStyle(WalletTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 4)
      }
    }
  }
  /// When the project's new payment addresses are looked for. Nothing polls the server
  /// in the background: it only hears from this device when asked.
  static let discovery =
    "New addresses are found when you connect, with every refresh of this account, and with Find new addresses. Nothing checks in the background."
  private var addressCount: String {
    let count = model.currentAccount?.paths.count ?? 0
    return count == 1 ? "1 address" : "\(count) addresses"
  }

  // MARK: Stores

  /// The project's Stor stores, each a link to its storefront. New store opens the
  /// sheet that creates one, Connect store gives a store made elsewhere (on Stor's page,
  /// or from another device) its URL and KEY. A project can back several stores: each has
  /// its own key and webhook, and its own orders' payment addresses.
  private func stores(_ connection: PathConnection) -> some View {
    let urls = model.state.settings.storeLinks[connection.id, default: []]
    return VStack(alignment: .leading, spacing: 8) {
      WalletSectionHeader("Stores", detail: urls.isEmpty ? "" : "\(urls.count)") {
        HStack(spacing: 2) {
          WalletIconButton(title: "Connect store", icon: "link", quiet: true) {
            model.feedback = nil
            connectingStore = true
          }
          .disabled(!canRun(connection))
          WalletIconButton(title: "New store", icon: "plus", quiet: true) {
            model.feedback = nil
            creatingStore = true
          }
          .disabled(!canRun(connection))
        }
      }
      WalletCard(padding: urls.isEmpty ? 12 : 6) {
        if urls.isEmpty {
          Text("No stores").font(.callout).foregroundStyle(WalletTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          VStack(spacing: 0) {
            ForEach(urls, id: \.self) { url in storeRow(url) }
          }
        }
      }
    }
  }
  private func storeRow(_ url: String) -> some View {
    Link(destination: URL(string: url) ?? URL(fileURLWithPath: "/")) {
      HStack(spacing: 10) {
        Image(systemName: "storefront").foregroundStyle(WalletTheme.accent)
          .accessibilityHidden(true)
        Text(StoreLinks.display(url))
          .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 8)
        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
          .foregroundStyle(WalletTheme.muted).accessibilityHidden(true)
      }
      .padding(.horizontal, 10).frame(minHeight: WalletMetrics.control + 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(WalletRowButtonStyle())
    .help(url)
  }

  /// Lists the project's credentials. Waits briefly for a command running on the same
  /// connection.
  private func loadGrants() async {
    guard let connection, !connectionRevoked, !grantsLoaded else { return }
    for _ in 0..<40 where !canRun(connection) {
      try? await Task.sleep(for: .milliseconds(150))
      if Task.isCancelled { return }
    }
    guard canRun(connection) else { return }
    model.run(.grants(connection.origin, connection.project))
  }
}
