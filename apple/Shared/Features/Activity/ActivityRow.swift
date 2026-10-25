import SwiftUI

/// One Activity line, the same on Home and in Activity. Left: what happened and with
/// whom ("Received" · "From Address 3 · Base"). Right: the signed amount, and under it
/// when it happened, or its status while that is the news (pending, failed). Fee steps
/// (a gas top-up, a permit) are a small line of their own.
struct ActivityRow: View {
  @Environment(WalletModel.self) private var model
  let item: ActivityItem
  /// Says the day as well as the time, for lists that are not grouped by day.
  var showsDay = false
  var body: some View {
    let look = ActivityLook(item, state: model.state)
    if look.direction == .fee { feeLine(look) } else { line(look) }
  }

  private func line(_ look: ActivityLook) -> some View {
    let other = model.activityName(of: look.counterpart.address)
    let when = look.date.map { Self.when($0, withDay: showsDay) }
    return HStack(spacing: 12) {
      ActivityStep(icon: look.icon, tone: look.tone)
        .overlay(alignment: .bottomTrailing) {
          // The network's mark, small, so the line says where without a longer caption.
          WalletNetworkGlyph(model.state, chain: look.chain, size: 14)
            .overlay(Circle().strokeBorder(WalletTheme.surface, lineWidth: 1.5))
            .offset(x: 3, y: 3)
        }
      VStack(alignment: .leading, spacing: 2) {
        Text(look.title).font(.callout.weight(.medium)).lineLimit(1)
        Text("\(look.counterpart.role) \(other) · \(look.network)")
          .font(.caption).foregroundStyle(WalletTheme.muted).lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 3) {
        Text(look.signedAmount).font(.callout.weight(.semibold)).monospacedDigit()
          .foregroundStyle(Self.amountStyle(look))
          .strikethrough(look.failed)
          .lineLimit(1).minimumScaleFactor(0.7)
        if look.pending || look.failed {
          WalletBadge(title: look.status.title, tone: look.status.tone, icon: look.status.icon)
        } else if let when {
          Text(when).font(.caption).foregroundStyle(WalletTheme.muted).monospacedDigit()
            .lineLimit(1)
        }
      }
      .layoutPriority(1)
    }
    .padding(.vertical, 8).contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [
        "\(look.title) \(look.amount)", "\(look.counterpart.role.lowercased()) \(other)",
        "on \(look.network)", when, look.status.title,
      ].compactMap { $0 }.joined(separator: ", "))
  }

  /// A top-up or permit that made a send possible: small, with no amount.
  private func feeLine(_ look: ActivityLook) -> some View {
    HStack(spacing: 12) {
      Image(systemName: look.icon).font(.caption2)
        .foregroundStyle(WalletTheme.muted).frame(width: 22, height: 22)
        .background(WalletTheme.surface, in: Circle())
        .overlay(Circle().strokeBorder(WalletTheme.border))
        .frame(width: 34).accessibilityHidden(true)
      Text(look.title).font(.caption).foregroundStyle(WalletTheme.muted)
      Text(
        ([look.network] + [look.date.map { Self.when($0, withDay: showsDay) }].compactMap { $0 })
          .joined(separator: " · ")
      )
      .font(.caption2).foregroundStyle(WalletTheme.muted).lineLimit(1)
      Spacer(minLength: 8)
      Image(systemName: look.status.icon).font(.caption2).foregroundStyle(look.status.tone.color)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 2).contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(look.title) on \(look.network), \(look.status.title)")
  }

  /// Received money is green, a failed transfer moved nothing and is muted.
  static func amountStyle(_ look: ActivityLook) -> AnyShapeStyle {
    if look.failed { return AnyShapeStyle(WalletTheme.muted) }
    if look.direction == .received { return AnyShapeStyle(WalletTheme.success) }
    return AnyShapeStyle(WalletTheme.text)
  }

  /// "14:05", with the day, "Yesterday" or "3 Oct" for earlier days.
  static func when(_ date: Date, withDay: Bool) -> String {
    let time = date.formatted(date: .omitted, time: .shortened)
    guard withDay, !Calendar.current.isDateInToday(date) else { return time }
    if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.day().month(.abbreviated))
  }
}

/// An activity line's mark: its arrow on a landing of the fire stairs. Opaque, so the
/// stairs behind the list pass under it.
struct ActivityStep: View {
  let icon: String
  let tone: WalletTone
  var body: some View {
    Image(systemName: icon).font(.callout.weight(.semibold))
      .foregroundStyle(tone.color)
      .frame(width: 34, height: 34)
      .background(
        tone.color.opacity(0.14), in: WalletShape.tile
      )
      .background(WalletTheme.surface, in: WalletShape.tile)
      .overlay(
        WalletShape.tile.strokeBorder(
          tone.color.opacity(0.3), lineWidth: 1)
      )
      .accessibilityHidden(true)
  }
}

/// The fire escape behind an activity list: two rails and their rungs, running down the
/// column of marks so one transfer leads to the next.
struct FireStairs: View {
  var width: CGFloat = 34
  var body: some View {
    Canvas { context, size in
      let center = width / 2
      var path = Path()
      path.move(to: CGPoint(x: center - 6, y: 12))
      path.addLine(to: CGPoint(x: center - 6, y: size.height - 12))
      path.move(to: CGPoint(x: center + 6, y: 12))
      path.addLine(to: CGPoint(x: center + 6, y: size.height - 12))
      var y: CGFloat = 16
      while y < size.height - 12 {
        path.move(to: CGPoint(x: center - 6, y: y))
        path.addLine(to: CGPoint(x: center + 6, y: y))
        y += 7
      }
      context.stroke(path, with: .color(WalletTheme.border), lineWidth: 1.2)
    }
    .frame(width: width)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
