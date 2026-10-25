import SwiftUI

/// What became of the transfer just sent, on Send right after the paper plane leaves.
/// One card, three outcomes: sent and waiting for a block, confirmed (the recipient has
/// the funds) or failed on-chain (nothing was transferred, the fee was spent). It
/// follows the receipts the model polls, so it changes by itself. Details opens the
/// transfer in full, the explorer shows it on-chain and the cross puts the card away.
struct TransferStatusCard: View {
  @Environment(WalletModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.walletAccent) private var accent
  let submission: TransferSubmission
  @State private var details: ActivityItem?

  private var stage: TransferSubmission.Stage {
    submission.stage(in: model.state.settings.transfers)
  }
  private var networkName: String { model.state.networkName(submission.chain) }
  private var amount: String {
    model.state.assetAmount(submission.amount, asset: submission.asset)
  }
  private var recipient: String {
    model.ownName(of: submission.recipient) ?? WalletText.short(submission.recipient)
  }
  /// The recorded transfer that moved the funds, for its detail sheet.
  private var transfer: LocalTransfer? {
    submission.transfer.flatMap { hash in
      model.state.settings.transfers.first { $0.id == hash }
    }
  }

  var body: some View {
    WalletCard(padding: 14) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          badge
          VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
              .contentTransition(.opacity)
            Text(detail).font(.footnote).foregroundStyle(WalletTheme.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 4)
          Button {
            model.submission = nil
          } label: {
            Image(systemName: "xmark").font(.caption.weight(.bold))
              .foregroundStyle(WalletTheme.muted)
              .frame(width: 28, height: 28).contentShape(Rectangle())
          }
          .buttonStyle(.plain).help("Dismiss").accessibilityLabel("Dismiss transfer status")
        }
        summary
        HStack(spacing: 10) {
          if let transfer {
            WalletAction(title: "Details", icon: "doc.text.magnifyingglass", secondary: true) {
              details = .sent(transfer)
            }
          }
          if let hash = submission.transfer,
            let url = Explorer.transaction(hash, model.state.network(submission.chain))
          {
            Link(destination: url) {
              Label("Explorer", systemImage: "arrow.up.right.square")
                .font(.callout.weight(.medium)).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: WalletMetrics.control)
            }
            .foregroundStyle(WalletTheme.accent)
            .background(WalletTheme.accent.opacity(0.08), in: Capsule(style: .continuous))
            .help(url.absoluteString)
          }
        }
        .environment(\.walletButtonFill, true)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: WalletMetrics.radius, style: .continuous)
        .strokeBorder(tone.opacity(0.35), lineWidth: 1)
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: stage)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Transfer status: \(title)")
    .onChange(of: stage) { _, now in
      AccessibilityNotification.Announcement(title).post()
      if now != .pending { WalletHaptics.notify(success: now == .confirmed) }
    }
    .walletSheet(item: $details) { item in
      ActivityDetailView(item: item) { details = nil }
    }
    .walletDismissOnLock { details = nil }
  }

  /// Amount, recipient and network in one line that never wraps a hex address.
  private var summary: some View {
    HStack(spacing: 8) {
      WalletNetworkGlyph(model.state, chain: submission.chain, size: 20)
      Text(amount).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1)
      Image(systemName: "arrow.right").font(.caption.weight(.bold))
        .foregroundStyle(WalletTheme.muted).accessibilityHidden(true)
      Text(recipient).font(.system(.callout, design: .monospaced)).lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .background(WalletTheme.raised, in: WalletShape.tile)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(amount) to \(recipient) on \(networkName)")
  }

  @ViewBuilder private var badge: some View {
    ZStack {
      Circle().fill(tone.opacity(0.14))
      switch stage {
      case .pending:
        WalletSpinner(size: 18).foregroundStyle(tone)
      case .confirmed:
        Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(tone)
          .transition(.scale.combined(with: .opacity))
      case .failed:
        Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(tone)
          .transition(.scale.combined(with: .opacity))
      }
    }
    .frame(width: 40, height: 40)
    .accessibilityHidden(true)
  }

  private var tone: Color {
    switch stage {
    case .pending: accent.accent
    case .confirmed: WalletTheme.success
    case .failed: WalletTheme.danger
    }
  }
  private var title: String {
    switch stage {
    case .pending: "Sent, waiting for confirmation"
    case .confirmed: "Transfer confirmed"
    case .failed: "Transfer failed"
    }
  }
  private var detail: String {
    switch stage {
    case .pending:
      "Broadcast to \(networkName). It is final once a block includes it, usually within a minute."
    case .confirmed:
      "Included in a block on \(networkName). The recipient has the funds."
    case .failed:
      "Rejected on-chain. Nothing was transferred, though the network fee was spent."
    }
  }
}
