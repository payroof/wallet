import SwiftUI

/// The reviewed plan, before anything is signed, and then its steps as they go out.
/// A plain transfer stays compact. Several legs or a gas sponsor show the flow of funds.
/// Fees are one row per step with the formula behind each. Every value fits its line:
/// amounts are rounded (the exact ones under Technical details) and the recipient is
/// shown in full on one line, its first and last characters picked out for checking.
struct TransferConfirmationView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(WalletModel.self) private var model
  @State private var showFees = false
  @State private var showTechnical = false
  /// Steps whose fee formula is open.
  @State private var formulas: Set<Int> = []
  /// A step is being signed and sent (or the plan is being dropped).
  private var sending: Bool { model.isRunning(.send) }
  private var progress: [StepProgress]? { model.progress }
  private var failed: Bool { progress?.contains(.failed) == true }

  var body: some View {
    WalletSheet(
      "Review transfer", subtitle: "Transfers can't be reversed.",
      icon: "paperplane", closeTitle: failed ? "Close" : "Cancel transfer",
      closeDisabled: sending,
      status: model.feedback?.status ?? .idle, dismissStatus: { model.feedback = nil },
      close: { model.run(.confirmPlan(false)) }
    ) {
      if let plan = model.state.plan {
        if let banner = progressBanner(plan) { banner }
        summary(plan)
        if plan.needsFlow {
          WalletCard {
            VStack(alignment: .leading, spacing: 12) {
              Text(flowCaption(plan)).font(.footnote).foregroundStyle(WalletTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
              SendFlowView(plan: plan) { amountText($0, plan) }
            }
          }
        }
        fees(plan)
        WalletDisclosure("Technical details", expanded: $showTechnical) {
          VStack(alignment: .leading, spacing: 0) {
            if let asset = model.state.planAsset, asset.id == plan.asset {
              WalletDetailRow(
                label: "Exact amount",
                value: ExactAmount.display(plan.amount, decimals: asset.decimals) + " "
                  + asset.symbol, copyable: true)
            }
            PublicValue(label: "Recipient", value: plan.recipient)
            PublicValue(label: "Asset", value: plan.asset.rawValue)
            if let endpoint = model.state.planEndpoint {
              WalletDetailRow(
                label: "RPC",
                value: model.state.endpointName(endpoint, chain: plan.network) + " · "
                  + RPCText.redacted(endpoint))
            }
          }
        }
      }
    } footer: {
      WalletSheetActions(
        cancelTitle: failed ? "Close" : "Cancel", cancelDisabled: sending,
        cancel: { model.run(.confirmPlan(false)) }
      ) {
        // Deliberately no default (Return) shortcut: signing needs an explicit click.
        WalletAction(
          title: "Confirm & sign locally", icon: "lock.shield", busy: sending,
          busyTitle: "Signing securely…"
        ) { model.send() }
        .disabled(sending || progress != nil || model.state.plan == nil)
      }
    }
    .walletModal(width: 620, busy: sending)
  }

  // MARK: Summary

  /// What is sent and to whom: the amount large with its value, the recipient in full,
  /// then where it comes from and the network.
  private func summary(_ plan: SendPlan) -> some View {
    WalletCard {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            if let asset = model.state.planAsset { WalletAssetGlyph(asset: asset, size: 18) }
            WalletEyebrow("You send")
          }
          Text(amountText(plan.amount, plan))
            .font(RoofFont.sign(44, relativeTo: .title)).monospacedDigit()
            .offset(y: SignMetrics.centering(44))
            .lineLimit(1).minimumScaleFactor(0.45).textSelection(.enabled)
          if let asset = model.state.planAsset, let usd = model.state.usd(plan.amount, asset: asset)
          {
            Text("≈ \(usd)").font(.subheadline).monospacedDigit()
              .foregroundStyle(WalletTheme.muted).lineLimit(1)
          }
        }
        ReviewRecipient(address: plan.recipient, name: model.ownName(of: plan.recipient))
        VStack(alignment: .leading, spacing: 0) {
          if !plan.needsFlow, let source = plan.sources.first {
            WalletDetailRow(
              label: "From",
              value: "\(WalletText.addressName(source.path)) · \(WalletText.short(source.address))")
          }
          WalletNetworkRow(label: "Network", state: model.state, chain: plan.network)
        }
      }
    }
  }

  /// While the steps go out, which one is under way. After a failure, plainly that the
  /// transfer did not (fully) go out.
  private func progressBanner(_ plan: SendPlan) -> WalletNote? {
    guard let progress else { return nil }
    let total = progress.count
    if let index = progress.firstIndex(of: .failed) {
      let sentBefore = progress[..<index].contains { if case .sent = $0 { true } else { false } }
      return WalletNote(
        sentBefore
          ? "Step \(index + 1) of \(total) failed. Earlier steps went out, nothing further did. Check Activity before trying again."
          : "The transfer did not go through. Check Activity before trying again.",
        tone: .danger, icon: "xmark.octagon.fill")
    }
    if let index = progress.firstIndex(of: .working) {
      return WalletNote(
        total == 1
          ? "Signing on this device and sending to \(model.state.networkName(plan.network))…"
          : "Signing and sending step \(index + 1) of \(total)…",
        tone: .accent, icon: "paperplane")
    }
    return nil
  }

  private func amountText(_ atomic: String, _ plan: SendPlan) -> String {
    guard let asset = model.state.planAsset, asset.id == plan.asset else {
      return atomic + " atomic units"
    }
    return ExactAmount.rounded(atomic, decimals: asset.decimals) + " " + asset.symbol
  }

  // MARK: Fees

  private func fees(_ plan: SendPlan) -> some View {
    WalletCard {
      VStack(alignment: .leading, spacing: 0) {
        WalletDetailRow(
          label: "Network fee", value: "Up to " + feeText(plan.maximumFee, plan), emphasis: true)
        if let total = nativeTotal(plan) {
          WalletDetailRow(label: "Total", value: "Up to " + total)
        }
        Text(
          "The fee quote holds for 15 minutes, and the first step must go out within two. The chain is checked again before each signature."
        )
        .font(.caption).foregroundStyle(WalletTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        if progress == nil {
          WalletDisclosure(
            plan.steps.count == 1 ? "Fee details" : "Fee breakdown",
            detail: plan.steps.count == 1 ? "" : "\(plan.steps.count) steps", expanded: $showFees
          ) {
            stepRows(plan)
          }
        } else {
          stepRows(plan).padding(.top, 8)
        }
      }
    }
  }

  /// One row per step: what it does, who pays, and its maximum fee. A tap shows the
  /// formula. While sending, each row also shows where its step stands.
  private func stepRows(_ plan: SendPlan) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
        Button {
          if formulas.contains(index) { formulas.remove(index) } else { formulas.insert(index) }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
              Image(systemName: Self.icon(step.kind)).font(.callout)
                .foregroundStyle(WalletTheme.accent).frame(width: 22)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 1) {
                Text(Self.title(step.kind)).font(.callout.weight(.medium)).lineLimit(1)
                Text("Paid by \(WalletText.addressName(step.payerPath))")
                  .font(.caption).foregroundStyle(WalletTheme.muted).lineLimit(1)
              }
              Spacer(minLength: 8)
              Text(feeText(step.maximumFee, plan, usd: false)).font(.callout).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
              status(index)
            }
            if formulas.contains(index) {
              Text(plan.formula(step)).font(.caption).monospacedDigit()
                .foregroundStyle(WalletTheme.muted).padding(.leading, 32)
            }
          }
          .padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the fee formula")
      }
    }
  }

  @ViewBuilder private func status(_ index: Int) -> some View {
    if let progress, progress.indices.contains(index) {
      switch progress[index] {
      case .pending:
        Image(systemName: "clock").foregroundStyle(WalletTheme.muted)
          .accessibilityLabel("Waiting")
      case .working:
        WalletSpinner(size: 14).foregroundStyle(WalletTheme.accent)
          .accessibilityLabel("Sending")
      case .sent(let hash):
        let confirmed =
          model.state.settings.transfers.first { $0.id == hash }?.status == "confirmed"
        Image(systemName: confirmed ? "checkmark.circle.fill" : "paperplane.fill")
          .foregroundStyle(
            confirmed ? AnyShapeStyle(WalletTheme.success) : AnyShapeStyle(WalletTheme.accent)
          )
          // The plane turns into the check in place when the transfer confirms.
          .contentTransition(.symbolEffect(.replace.downUp))
          .animation(reduceMotion ? nil : .default, value: confirmed)
          .accessibilityLabel(confirmed ? "Confirmed" : "Sent")
      case .failed:
        Image(systemName: "xmark.circle.fill").foregroundStyle(WalletTheme.danger)
          .accessibilityLabel("Failed")
      }
    }
  }

  /// Why the plan has more than one step, in a sentence.
  private func flowCaption(_ plan: SendPlan) -> String {
    var parts: [String] = []
    if plan.sources.count > 1 {
      parts.append(
        "No single address holds enough: \(plan.sources.count) of yours send a part each.")
    }
    if let step = plan.steps.first(where: \.sponsored) {
      parts.append(
        "\(WalletText.addressName(step.payerPath)) pays the network fee for the others.")
    }
    if plan.steps.contains(where: { $0.kind == .topUp }) {
      parts.append("A little coin is moved first to cover fees.")
    }
    if plan.steps.contains(where: { $0.kind == .permit || $0.kind == .authorization }) {
      parts.append("An approval is signed so the transfer can be paid for by another address.")
    }
    return parts.isEmpty ? "How the funds move:" : parts.joined(separator: " ")
  }

  /// Amount plus the maximum fee, when both are in the network's coin.
  private func nativeTotal(_ plan: SendPlan) -> String? {
    guard let native = model.state.nativeAsset(plan.network), native.id == plan.asset,
      let sum = AtomicText.add(plan.amount, plan.maximumFee)
    else { return nil }
    let text =
      ExactAmount.rounded(sum, decimals: native.decimals, rounding: .up) + " " + native.symbol
    return model.state.usd(sum, asset: native).map { text + " · " + $0 } ?? text
  }

  /// A fee in the network's coin, with its USD value when a price is cached.
  private func feeText(_ wei: String, _ plan: SendPlan, usd: Bool = true) -> String {
    let fee = model.state.feeAmount(wei, chain: plan.network)
    guard usd, let native = model.state.nativeAsset(plan.network),
      let value = model.state.usd(wei, asset: native)
    else { return fee }
    return fee + " · " + value
  }

  nonisolated static func title(_ kind: PlanStepKind) -> String {
    switch kind {
    case .transfer, .transferFrom: "Transfer"
    case .topUp: "Gas top-up"
    case .authorization: "Signed transfer"
    case .permit: "Permit"
    }
  }
  nonisolated static func icon(_ kind: PlanStepKind) -> String {
    switch kind {
    case .transfer, .transferFrom: "arrow.up.right"
    case .topUp: "fuelpump"
    case .authorization: "signature"
    case .permit: "checkmark.seal"
    }
  }
}

/// The recipient, what the user must check before signing: this wallet's name for it
/// (or "External address") and the full address on one line, monospaced, with the
/// first six and last four characters in the accent. Shrinks to fit rather than wrap.
private struct ReviewRecipient: View {
  let address: String
  let name: String?
  var body: some View {
    HStack(spacing: 12) {
      WalletIconTile(systemName: name == nil ? "person.crop.circle" : "house")
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          WalletEyebrow("To")
          Text(name.map { "Your \($0)" } ?? "External address")
            .font(.caption.weight(.semibold)).foregroundStyle(WalletTheme.muted).lineLimit(1)
        }
        highlighted
          .font(.system(.callout, design: .monospaced))
          .lineLimit(1).minimumScaleFactor(0.5)
          .textSelection(.enabled)
      }
      Spacer(minLength: 4)
      WalletCopyButton(label: "recipient address", value: address)
    }
    .padding(10)
    .background(WalletTheme.raised.opacity(0.6), in: WalletShape.field)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("To \(name ?? "external address"), \(address)")
  }
  /// The ends people compare stand out, the middle stays quieter.
  private var highlighted: Text {
    guard address.count > 12 else { return Text(address).fontWeight(.semibold) }
    let head = String(address.prefix(6))
    let tail = String(address.suffix(4))
    let middle = String(address.dropFirst(6).dropLast(4))
    return Text(
      "\(Text(head).fontWeight(.bold).foregroundStyle(WalletTheme.accent))\(Text(middle).foregroundStyle(WalletTheme.text))\(Text(tail).fontWeight(.bold).foregroundStyle(WalletTheme.accent))"
    )
  }
}
