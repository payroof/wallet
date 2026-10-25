import SwiftUI

/// One activity item, opened as a receipt. Read top to bottom: how much and whether it
/// went through (the rounded amount, its value today, the status in a sentence), then who
/// it was between (this wallet's own addresses by name), then where, with the transaction
/// one tap from the explorer. Raw values (the exact amount, full addresses, contract,
/// block, RPC) wait under Technical details. Long hex is always one shortened line, never
/// broken across lines. A transfer signed here and one found on-chain open the same way.
struct ActivityDetailView: View {
  @Environment(WalletModel.self) private var model
  let item: ActivityItem
  let done: () -> Void
  @Environment(\.openURL) private var openURL
  @State private var technical = false

  var body: some View {
    let look = ActivityLook(item, state: model.state)
    WalletSheet(
      look.title,
      subtitle: look.date?.formatted(date: .long, time: .shortened) ?? look.network,
      icon: look.icon, closeTitle: "Done", close: done
    ) {
      summary(look)
      if look.direction != .fee { route(look) }
      WalletCard(padding: 12) {
        VStack(alignment: .leading, spacing: 0) {
          WalletNetworkRow(label: "Network", state: model.state, chain: look.chain)
          if let slot = look.slot {
            WalletDetailRow(
              label: "Account",
              value: model.state.projects.first { $0.slot == slot }?.label ?? "Slot \(slot)")
          }
          ActivityCopyRow(
            label: "Transaction", text: WalletText.short(look.transaction), value: look.transaction)
        }
      }
      if let url = Explorer.transaction(look.transaction, model.state.network(look.chain)) {
        WalletAction(title: "View on explorer", icon: "arrow.up.right.square", secondary: true) {
          openURL(url)
        }
        .help(url.absoluteString)
      }
      WalletDisclosure("Technical details", expanded: $technical) {
        VStack(alignment: .leading, spacing: 0) {
          WalletDetailRow(
            label: "Exact amount", value: look.amount, monospaced: true, copyable: true)
          ActivityHexRow(label: "From", value: look.from)
          ActivityHexRow(label: "To", value: look.to)
          ActivityHexRow(label: "Transaction", value: look.transaction)
          ActivityHexRow(
            label: look.contract == nil ? "Asset" : "Token contract",
            value: look.contract?.text ?? look.asset.rawValue)
          if let block = look.block { WalletDetailRow(label: "Block", value: String(block)) }
          if let endpoint = look.endpoint {
            WalletDetailRow(label: "Sent through", value: RPCText.redacted(endpoint))
          }
        }
      }
    }
    .walletModal(width: 560)
    // Names this wallet's own addresses on either side.
    .task { await model.deriveAddresses(model.currentAccount?.orderedPaths ?? []) }
  }

  /// The rounded amount, large and signed, its value at today's price, and the status
  /// with a sentence on what it means. The exact amount is under Technical details.
  private func summary(_ look: ActivityLook) -> some View {
    WalletCard {
      VStack(spacing: 6) {
        if let token = model.state.assets.first(where: { $0.id == look.asset }) {
          WalletAssetGlyph(asset: token, size: 32).padding(.bottom, 2)
        }
        Text(look.signedShortAmount)
          .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
          .foregroundStyle(ActivityRow.amountStyle(look))
          .strikethrough(look.failed)
          .lineLimit(1).minimumScaleFactor(0.4)
          .textSelection(.enabled)
        if let usd = look.usd {
          Text("≈ \(usd) at today's price").font(.subheadline).foregroundStyle(WalletTheme.muted)
        }
        WalletBadge(title: look.status.title, tone: look.status.tone, icon: look.status.icon)
          .padding(.top, 4)
        Text(Self.statusLine(look)).font(.footnote).foregroundStyle(WalletTheme.muted)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(look.title) \(look.amount), \(look.status.title). \(Self.statusLine(look))")
  }

  /// What the status means, in a sentence.
  private static func statusLine(_ look: ActivityLook) -> String {
    if look.pending { return "Sent to the network, waiting to be included in a block." }
    if look.failed {
      return "Failed on-chain: nothing was transferred, though the network fee was spent."
    }
    switch look.direction {
    case .received: return "Arrived on \(look.network)."
    case .moved: return "Moved between your own addresses on \(look.network)."
    case .sent, .fee: return "Confirmed on \(look.network)."
    }
  }

  /// From, then To, joined by an arrow, the account's own addresses go by their names.
  private func route(_ look: ActivityLook) -> some View {
    WalletCard(padding: 12) {
      VStack(alignment: .leading, spacing: 0) {
        ActivityParty(role: "From", address: look.from, name: model.ownName(of: look.from))
        Image(systemName: "arrow.down").font(.caption.weight(.bold))
          .foregroundStyle(WalletTheme.muted)
          .frame(width: WalletMetrics.tile).padding(.vertical, 2)
          .accessibilityHidden(true)
        ActivityParty(role: "To", address: look.to, name: model.ownName(of: look.to))
      }
    }
  }
}

/// One side of a transfer: its role, this wallet's name for it (or "Elsewhere"), and
/// the shortened address, copied in full with one tap.
private struct ActivityParty: View {
  let role: String
  let address: String
  let name: String?
  var body: some View {
    HStack(spacing: 12) {
      WalletIconTile(
        systemName: name == nil ? "globe" : "house", style: .raised,
        tint: name == nil ? AnyShapeStyle(WalletTheme.muted) : AnyShapeStyle(WalletTheme.accent))
      VStack(alignment: .leading, spacing: 1) {
        Text(role.uppercased()).font(RoofFont.eyebrow).tracking(1.2)
          .foregroundStyle(WalletTheme.muted)
        Text(name ?? "External address").font(.callout.weight(.semibold)).lineLimit(1)
        Text(WalletText.short(address)).font(.system(.caption, design: .monospaced))
          .foregroundStyle(WalletTheme.muted).lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: 8)
      WalletCopyButton(label: "\(role) address", value: address, size: 36)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(role): \(name ?? "external address"), \(address)")
  }
}

/// A label and a shortened value whose full form is copied.
private struct ActivityCopyRow: View {
  let label: String
  let text: String
  let value: String
  var body: some View {
    HStack(spacing: 12) {
      Text(label).font(.subheadline).foregroundStyle(WalletTheme.muted)
      Spacer(minLength: 8)
      Text(text).font(.system(.callout, design: .monospaced))
        .lineLimit(1).truncationMode(.middle)
      WalletCopyButton(label: label, value: value, size: 28)
    }
    .padding(.vertical, 6)
  }
}

/// A long hex value (address, transaction, contract) on one line, shortened in the
/// middle with its full form selectable and copied with one tap.
private struct ActivityHexRow: View {
  let label: String
  let value: String
  var body: some View {
    HStack(spacing: 12) {
      Text(label).font(.subheadline).foregroundStyle(WalletTheme.muted)
      Spacer(minLength: 8)
      Text(WalletText.short(value)).font(.system(.callout, design: .monospaced))
        .lineLimit(1).truncationMode(.middle)
      WalletCopyButton(label: label, value: value, size: 28)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label): \(value)")
  }
}
