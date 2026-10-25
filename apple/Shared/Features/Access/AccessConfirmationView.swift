import SwiftUI

struct AccessConfirmationView: View {
  @Environment(WalletModel.self) private var model
  @State private var approving = false
  /// The project access is granted to. Preset to the one the request was reviewed for.
  @State private var project = ""
  /// The request is being reviewed, approved or declined.
  private var deciding: Bool { model.isRunning(.access) }
  private var origin: String { LocalDevelopment.origin(model.state.accessLink) ?? "Invalid origin" }
  private var candidates: [PathConnection] {
    model.state.settings.connections.filter { $0.origin == origin }
  }
  private var connection: PathConnection? {
    candidates.first { $0.project == project }
  }
  var body: some View {
    WalletSheet(
      "Approve access?",
      subtitle: subtitle,
      icon: "person.badge.key", closeTitle: "Decline", closeDisabled: deciding,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: { model.run(.dismissAccess) }
    ) {
      if let access = model.state.access {
        // One card answers who is asking, for which project, until when.
        WalletCard(padding: 0) {
          VStack(alignment: .leading, spacing: 0) {
            PublicValue(label: "Server", value: origin)
              .padding(.horizontal, 14).padding(.vertical, 4)
            projectRow.padding(.horizontal, 14).padding(.vertical, 10)
            WalletDetailRow(label: "Request expires", value: expiry(access.expiresAt))
              .padding(.horizontal, 14).padding(.vertical, 4)
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          WalletSectionHeader("Allows", detail: "\(access.permissions.count)")
          WalletCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(access.permissions, id: \.self) { permission in
                let sensitive = permission == "access"
                HStack(alignment: .top, spacing: 10) {
                  WalletLineIcon(systemName: permissionIcon(permission))
                    .font(.callout)
                    .foregroundStyle(
                      sensitive
                        ? AnyShapeStyle(WalletTheme.warning) : AnyShapeStyle(WalletTheme.accent)
                    )
                    .frame(width: 20)
                  let title = Text(permissionTitle(permission)).fontWeight(.semibold)
                  let detail = Text(permissionDetail(permission))
                    .foregroundStyle(WalletTheme.muted)
                  Text("\(title)  \(detail)").font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
              }
            }
          }
        }
      }
    } footer: {
      WalletSheetActions(
        cancelTitle: "Decline", cancelIcon: "hand.raised", cancelDisabled: deciding,
        cancel: { model.run(.dismissAccess) }
      ) {
        // No default shortcut: approval needs an explicit click.
        WalletAction(
          title: "Allow access", icon: "checkmark.shield", busy: deciding && approving,
          busyTitle: "Approving…"
        ) {
          approving = true
          model.run(.pairing(model.state.accessLink, project, true))
        }.disabled(deciding || connection == nil)
      }
    }
    .walletModal(width: 560, busy: deciding)
    .onChange(of: deciding) { _, deciding in if !deciding { approving = false } }
    .onAppear {
      project = model.state.accessProject
      // A single connected project needs no choice.
      if connection == nil, candidates.count == 1, let only = candidates.first {
        project = only.project
      }
    }
  }
  /// Who is asking, named by the host it came from. The host is what identifies it.
  private var subtitle: String {
    guard let access = model.state.access else { return "" }
    let host = URL(string: origin)?.host ?? origin
    return "\(access.name) on \(host) wants to use one of your projects."
  }
  /// One connected project: shown, nothing to choose. Several: a compact selector.
  /// A request only opens with a connected project. Wallet checks that first.
  @ViewBuilder private var projectRow: some View {
    if candidates.count == 1, let only = candidates.first {
      WalletDetailRow(label: "Project", value: "\(only.project) · \(projectDetail(only))")
    } else {
      WalletSelector(
        label: "Project",
        options: candidates.map {
          WalletOption(value: $0.project, title: $0.project, subtitle: projectDetail($0))
        },
        selection: $project,
        placeholder: "Choose a project"
      )
      .disabled(deciding)
    }
  }
  private func projectDetail(_ item: PathConnection) -> String {
    let label = model.state.projects.first { $0.slot == item.slot }?.label ?? "Slot \(item.slot)"
    return "Account: \(label)"
  }
  private func expiry(_ raw: String) -> String {
    guard let date = WalletDate.parse(raw) else { return raw }
    return date.formatted(date: .abbreviated, time: .shortened)
  }
  private func permissionTitle(_ permission: String) -> String {
    switch permission {
    case "references": "Payment references"
    case "webhooks": "Webhooks"
    case "paths": "Address discovery"
    case "access": "Access"
    default: permission.capitalized
    }
  }
  private func permissionIcon(_ permission: String) -> String {
    switch permission {
    case "references": "number"
    case "webhooks": "bell"
    case "paths": "magnifyingglass"
    case "access": "key"
    default: "questionmark.diamond"
    }
  }
  private func permissionDetail(_ permission: String) -> String {
    switch permission {
    case "references": "Allocate receive addresses for payment references."
    case "webhooks": "Configure signed payment notifications."
    case "paths": "Discover public receive addresses."
    case "access": "List, grant and revoke other integrations' access. Allow only if you trust it."
    default: "Unknown permission. Do not approve."
    }
  }
}
