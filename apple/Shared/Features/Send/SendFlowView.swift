import SwiftUI

/// The flow of funds of a plan: the addresses that fund it converge on the recipient.
/// When another address pays the gas it sits above as the sponsor, with dashed lines to
/// the legs it pays for.
struct SendFlowView: View {
  let plan: SendPlan
  /// An amount of the asset being sent, as shown.
  let amount: (String) -> String
  @State private var frames: [String: CGRect] = [:]

  private nonisolated static let space = "send-flow"
  private static let sponsorID = "sponsor"
  private static let recipientID = "recipient"

  /// The sponsor, when it pays gas for someone else's funds.
  private var sponsor: PlanParty? {
    guard let step = plan.steps.first(where: \.sponsored) else { return nil }
    return plan.sponsor ?? PlanParty(path: step.payerPath, address: step.payer)
  }
  /// Sources whose legs the sponsor pays for.
  private var sponsored: Set<String> {
    Set(plan.steps.filter(\.sponsored).map(\.ownerPath))
  }
  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 8), count: min(max(plan.sources.count, 1), 3))
  }

  var body: some View {
    VStack(spacing: 34) {
      if let sponsor {
        node(
          id: Self.sponsorID, icon: "fuelpump.fill", title: "Pays the fee",
          detail: WalletText.addressName(sponsor.path), tone: .accent
        )
        .frame(maxWidth: 200)
      }
      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(plan.sources, id: \.path) { source in
          node(
            id: source.path, icon: "wallet.pass", title: amount(source.amount),
            detail: WalletText.addressName(source.path), tone: .neutral
          )
        }
      }
      node(
        id: Self.recipientID, icon: "arrow.down.circle.fill", title: amount(plan.amount),
        detail: WalletText.short(plan.recipient), tone: .success
      )
      .frame(maxWidth: 220)
    }
    .frame(maxWidth: .infinity)
    .coordinateSpace(name: Self.space)
    .background { connectors }
    .padding(.vertical, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(summary)
  }

  private var summary: String {
    let from = plan.sources.map { "\(amount($0.amount)) from \(WalletText.addressName($0.path))" }
      .joined(separator: ", ")
    let paid = sponsor.map { ". \(WalletText.addressName($0.path)) pays the fee" } ?? ""
    return "\(from), to \(WalletText.short(plan.recipient))\(paid)"
  }

  private func node(id: String, icon: String, title: String, detail: String, tone: WalletTone)
    -> some View
  {
    VStack(spacing: 2) {
      HStack(spacing: 5) {
        Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(tone.color)
        Text(title).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      Text(detail).font(.system(.caption, design: .monospaced)).foregroundStyle(WalletTheme.muted)
        .lineLimit(1)
    }
    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity)
    .background(
      WalletTheme.surface,
      in: WalletShape.tile
    )
    .overlay(
      WalletShape.tile
        .strokeBorder(
          id == Self.sponsorID
            ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.border),
          style: StrokeStyle(lineWidth: 1, dash: id == Self.sponsorID ? [4, 3] : []))
    )
    .onGeometryChange(for: CGRect.self) {
      $0.frame(in: .named(Self.space))
    } action: {
      frames[id] = $0
    }
  }

  /// Solid arrows from every source into the recipient. Dashed gas lines from the
  /// sponsor to the sources it pays for.
  private var connectors: some View {
    ZStack {
      ForEach(plan.sources, id: \.path) { source in
        if let from = frames[source.path], let to = frames[Self.recipientID] {
          let start = CGPoint(x: from.midX, y: from.maxY)
          let end = CGPoint(x: to.midX + endOffset(source.path, in: to), y: to.minY)
          curve(start, end).stroke(WalletTheme.muted.opacity(0.7), lineWidth: 1.5)
          arrow(at: end).stroke(
            WalletTheme.muted.opacity(0.9),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        if sponsored.contains(source.path), let from = frames[Self.sponsorID],
          let to = frames[source.path]
        {
          let start = CGPoint(x: from.midX, y: from.maxY)
          let end = CGPoint(x: to.midX, y: to.minY)
          curve(start, end).stroke(
            WalletTheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
          Text("Gas").font(.caption2.weight(.medium)).foregroundStyle(WalletTheme.accent)
            .padding(.horizontal, 4).background(WalletTheme.canvas.opacity(0.9), in: Capsule())
            .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        }
      }
    }
    .allowsHitTesting(false)
  }

  /// Arrow tips are spread across the recipient's top edge, one per source.
  private func endOffset(_ path: String, in frame: CGRect) -> CGFloat {
    guard plan.sources.count > 1, let index = plan.sources.firstIndex(where: { $0.path == path })
    else { return 0 }
    let step = min(frame.width / CGFloat(plan.sources.count + 1), 24)
    return (CGFloat(index) - CGFloat(plan.sources.count - 1) / 2) * step
  }

  private func curve(_ from: CGPoint, _ to: CGPoint) -> Path {
    Path { path in
      let lift = max(abs(to.y - from.y) / 2, 8)
      path.move(to: from)
      path.addCurve(
        to: to, control1: CGPoint(x: from.x, y: from.y + lift),
        control2: CGPoint(x: to.x, y: to.y - lift))
    }
  }

  private func arrow(at tip: CGPoint) -> Path {
    Path { path in
      path.move(to: CGPoint(x: tip.x - 4, y: tip.y - 5))
      path.addLine(to: tip)
      path.addLine(to: CGPoint(x: tip.x + 4, y: tip.y - 5))
    }
  }
}
