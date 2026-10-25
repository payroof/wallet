import SwiftUI

/// What a credential may do on a project, with its short label and icon.
enum APIPermission: String, CaseIterable {
  case references, paths, webhooks, access
  var title: String { rawValue.capitalized }
  var icon: String {
    switch self {
    case .references: "doc.text"
    case .paths: "point.3.connected.trianglepath.dotted"
    case .webhooks: "bolt"
    case .access: "key"
    }
  }
  /// Access lets a credential manage other credentials.
  var tone: WalletTone { self == .access ? .warning : .neutral }
}

/// Creates a token with a subset of this device's permissions. The token is shown once,
/// in this sheet only, and is dropped when the sheet closes or the wallet locks.
struct NewTokenSheet: View {
  @Environment(WalletModel.self) private var model
  let connection: PathConnection
  let close: () -> Void
  @State private var name = ""
  @State private var permissions: Set<APIPermission> = [.references, .paths]
  @State private var token = ""
  private var running: Bool { model.isRunning(.connection(connection.id)) }
  private var valid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !permissions.isEmpty
      && model.canRun(.connection(connection.id))
  }
  var body: some View {
    WalletSheet(
      token.isEmpty ? "New token" : "Token created", subtitle: connection.project,
      icon: "key", closeDisabled: running,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: finish
    ) {
      if token.isEmpty { form } else { reveal }
    } footer: {
      if token.isEmpty {
        WalletSheetActions(cancelDisabled: running, cancel: finish) {
          WalletAction(
            title: "Create", icon: "plus", busy: running, busyTitle: "Creating…", action: create
          )
          .disabled(!valid).keyboardShortcut(.defaultAction)
        }
      } else {
        WalletAction(title: "Done", icon: "checkmark", action: finish)
          .keyboardShortcut(.defaultAction)
      }
    }
    .walletModal(width: 480, busy: running)
    .onChange(of: model.lockEpoch) { _, _ in token = "" }
    .onDisappear {
      token = ""
      model.issuedToken = ""
    }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 14) {
      WalletField("Name") {
        TextField("my-integration", text: $name).autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Permissions").font(.subheadline.weight(.medium))
          .foregroundStyle(WalletTheme.muted)
        WalletFlowLayout(spacing: 8) {
          ForEach(APIPermission.allCases, id: \.self) { permission in
            WalletChip(
              option: WalletOption(
                value: permission, title: permission.title, icon: permission.icon,
                badge: permission == .access ? "Powerful" : nil, badgeTone: .warning),
              selected: permissions.contains(permission)
            ) {
              if permissions.contains(permission) {
                permissions.remove(permission)
              } else {
                permissions.insert(permission)
              }
            }
          }
        }
      }
    }
  }

  /// The token in one field with its Copy button at the end, and the one thing to know
  /// about it below.
  private var reveal: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text(token).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel("Token")
        WalletCopyButton(label: "token", value: token, style: .field, source: .secret) {
          model.feedback = WalletFeedback(
            message: "Copied. The clipboard clears in a minute.", kind: .info)
        }
      }
      .padding(.leading, 12).padding(.trailing, 2).padding(.vertical, 2)
      .frame(minHeight: WalletMetrics.field)
      .background(
        WalletTheme.surface, in: WalletShape.field
      )
      .overlay(
        WalletShape.field.strokeBorder(WalletTheme.border)
      )
      Label("Shown only once", systemImage: "eye.slash").font(.footnote)
        .foregroundStyle(WalletTheme.muted)
    }
  }

  private func create() {
    guard valid else { return }
    let chosen = APIPermission.allCases.filter(permissions.contains).map(\.rawValue)
    model.run(.createGrant(connection.origin, connection.project, name, chosen)) {
      token = model.issuedToken
      model.issuedToken = ""
    }
  }
  private func finish() {
    token = ""
    model.issuedToken = ""
    close()
  }
}
