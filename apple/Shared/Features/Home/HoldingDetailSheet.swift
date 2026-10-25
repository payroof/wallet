import SwiftUI

/// Where a balance is held: each network's amount, then each address that holds it.
/// Rounded values (the exact one on hover and when selected), with the time each was
/// read.
struct HoldingDetailSheet: View {
  @Environment(WalletModel.self) private var model
  let group: HoldingGroup
  let account: ProjectCard?
  let send: (WalletAsset, String?) -> Void
  let done: () -> Void
  var body: some View {
    WalletSheet(
      group.symbol,
      subtitle:
        "\(ExactAmount.short(group.total, decimals: group.decimals)) \(group.symbol) in \(account?.label ?? "this account")",
      icon: "circle.hexagongrid", closeTitle: "Done", close: done
    ) {
      ForEach(group.holdings) { holding in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            WalletNetworkGlyph(model.state, chain: holding.asset.chain, size: 20)
            Text(model.state.networkName(holding.asset.chain)).font(RoofFont.heading)
            Spacer(minLength: 8)
            Text(value(holding.total, holding.asset)).font(.callout.weight(.semibold))
              .monospacedDigit().lineLimit(1).textSelection(.enabled)
              .help(exact(holding.total, holding.asset))
            WalletAction(title: "Send", icon: "arrow.up.right", role: .tertiary, expand: false) {
              send(holding.asset, nil)
            }
          }
          WalletCard(padding: 6) {
            VStack(spacing: 0) {
              let held = holding.addresses.filter { $0.balance.atomic.contains { $0 != "0" } }
              ForEach(held, id: \.path) { item in
                Button {
                  send(holding.asset, item.path)
                } label: {
                  HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                      Text(WalletText.addressName(item.path)).font(.callout.weight(.medium))
                      Text(item.path).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(WalletTheme.muted)
                    }
                    Spacer(minLength: 8)
                    Text(value(item.balance.atomic, holding.asset)).font(.callout)
                      .monospacedDigit().textSelection(.enabled).lineLimit(1)
                      .minimumScaleFactor(0.6)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                      .foregroundStyle(WalletTheme.accent).accessibilityHidden(true)
                  }
                  .padding(.horizontal, 10).padding(.vertical, 8)
                  .contentShape(Rectangle())
                }
                .buttonStyle(WalletRowButtonStyle())
                .accessibilityLabel(
                  "Send \(holding.asset.symbol) from \(WalletText.addressName(item.path))"
                )
                .help("Send from \(WalletText.addressName(item.path))")
              }
            }
          }
          HStack {
            if let checked = holding.checked {
              Text("Checked \(WalletFreshness.relative(checked))")
            }
            Spacer()
            let empty =
              holding.addresses.count
              - holding.addresses.filter { $0.balance.atomic.contains { $0 != "0" } }.count
            if empty > 0 {
              Text("\(empty) more \(empty == 1 ? "address holds" : "addresses hold") none")
            }
          }
          .font(.caption).foregroundStyle(WalletTheme.muted)
        }
      }
      if group.holdings.count > 1 {
        WalletNote(
          "Grouped by symbol. Each network's \(group.symbol) is a separate token contract.")
      }
    }
    .walletModal(width: 480)
    .privacySensitive()
  }
  private func value(_ atomic: String, _ asset: WalletAsset) -> String {
    ExactAmount.short(atomic, decimals: asset.decimals) + " " + asset.symbol
  }
  private func exact(_ atomic: String, _ asset: WalletAsset) -> String {
    ExactAmount.display(atomic, decimals: asset.decimals) + " " + asset.symbol
  }
}
