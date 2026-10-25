import Charts
import SwiftUI

/// The back of an account's sign: its USD total over time, drawn in steps like a
/// skyline, across every network, token
/// and address, from the totals recorded after each update (`ValueHistory`). The latest
/// total and the change since the first point above a quiet line that runs edge to edge
/// and fills to the card's bottom. Over the line, the account's three largest holdings
/// by USD value, each token on each network on its own. Nothing on it reacts to touch,
/// so a tap anywhere turns the card back.
struct AccountValueBack: View {
  @Environment(WalletModel.self) private var model
  let account: ProjectCard
  let accent: WalletAccent

  private struct Point: Identifiable {
    let date: Date
    let usd: Double
    var id: Date { date }
  }
  private var history: [(date: Date, usd: Decimal)] {
    (model.state.values[String(account.slot)] ?? []).compactMap { point in
      point.value.map { (point.date, $0) }
    }
  }

  var body: some View {
    let history = history
    SignBoard(accent: accent, radius: AccountCard.radius, bulbs: false) {
      content(history)
    }
    .foregroundStyle(WalletAccent.onCard)
    .privacySensitive()
  }

  private func content(_ history: [(date: Date, usd: Decimal)]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(account.label).font(RoofFont.poster(16, relativeTo: .headline)).lineLimit(1)
          Spacer(minLength: 8)
          if let first = history.first {
            Text(first.date, format: .dateTime.day().month(.abbreviated))
              .font(.caption).foregroundStyle(WalletAccent.onCardMuted)
          }
        }
        HStack(alignment: .firstTextBaseline) {
          Text(history.last.map { WalletPortfolio.currency($0.usd) } ?? "$--.--")
            .font(RoofFont.sign(34, relativeTo: .title)).monospacedDigit().lineLimit(1)
            .offset(y: SignMetrics.centering(34))
            .minimumScaleFactor(0.6)
          Spacer(minLength: 8)
          if let change = change(history) {
            Text(change).font(.callout.weight(.medium)).monospacedDigit()
              .foregroundStyle(WalletAccent.onCardMuted).lineLimit(1)
          }
        }
      }
      .padding([.horizontal, .top], 18)
      chart(history)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 10)
        .overlay(alignment: .topTrailing) {
          leaders.padding(.top, 8).padding(.trailing, Self.trailing)
        }
        // Inside the board's edge (its neon tube or hairline), clipped to the same curve.
        .clipShape(
          UnevenRoundedRectangle(
            bottomLeadingRadius: AccountCard.radius - Self.edge,
            bottomTrailingRadius: AccountCard.radius - Self.edge, style: .continuous)
        )
        .padding([.horizontal, .bottom], Self.edge)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// How far the chart stays inside the board's edge.
  private static let edge: CGFloat = 4

  #if os(macOS)
    /// Clear of the carousel's chevron at the card's right edge.
    private static let trailing: CGFloat = 46
  #else
    private static let trailing: CGFloat = 18
  #endif

  /// Up to three rows, `(E) 1,234 USDC 23 addr`: the network's initial in its color, the
  /// amount and symbol, and how many addresses hold it. Nothing when nothing is held.
  @ViewBuilder private var leaders: some View {
    let rows = WalletPortfolio.top(
      WalletPortfolio.holdings(model.state, account: account), prices: model.state.settings.prices,
      limit: 3)
    if !rows.isEmpty {
      Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
        ForEach(rows) { row in
          GridRow {
            WalletNetworkGlyph(model.state, chain: row.asset.chain, size: 16)
              .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
            Text(Self.amount(row.atomic, decimals: row.asset.decimals))
              .font(.callout.weight(.semibold)).monospacedDigit()
              .gridColumnAlignment(.trailing)
            Text(row.asset.symbol).font(.callout.weight(.medium))
            Text("\(row.addresses) addr").font(.caption2).monospacedDigit()
              .foregroundStyle(WalletAccent.onCardMuted)
              .gridColumnAlignment(.trailing)
          }
          .lineLimit(1)
        }
      }
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(
        Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }
  /// Two decimals from 1 up, four below: enough to rank at a glance.
  private static func amount(_ atomic: String, decimals: Int) -> String {
    let whole = ExactAmount.display(atomic, decimals: decimals).prefix { $0 != "." }
    return ExactAmount.short(atomic, decimals: decimals, fraction: whole == "0" ? 4 : 2)
  }

  /// "+$12.40" or "−$3.10" since the first point. Nil until there are two.
  private func change(_ history: [(date: Date, usd: Decimal)]) -> String? {
    guard history.count > 1, let first = history.first, let last = history.last else {
      return nil
    }
    let delta = last.usd - first.usd
    let sign = delta < 0 ? "−" : "+"
    return sign + WalletPortfolio.currency(delta < 0 ? -delta : delta)
  }

  /// The line over a soft fill down to the card's edge. A single total is a flat line,
  /// none a dashed one.
  private func points(_ history: [(date: Date, usd: Decimal)]) -> [Point] {
    var points = history.map {
      Point(date: $0.date, usd: NSDecimalNumber(decimal: $0.usd).doubleValue)
    }
    if points.count == 1, let only = points.first {
      points.insert(Point(date: only.date.addingTimeInterval(-86_400), usd: only.usd), at: 0)
    }
    return points
  }

  @ViewBuilder private func chart(_ history: [(date: Date, usd: Decimal)]) -> some View {
    let points = points(history)
    if points.isEmpty {
      GeometryReader { proxy in
        Path { line in
          line.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
          line.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
        }
        .stroke(
          WalletAccent.onCardMuted.opacity(0.6),
          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
      }
      .accessibilityHidden(true)
    } else {
      let values = points.map(\.usd)
      let low = values.min() ?? 0
      let high = values.max() ?? 0
      // Flat history sits in the middle. Otherwise the line uses the height, with room
      // for its stroke above and for the fill below.
      let range = high > low ? high - low : max(abs(high) * 0.1, 1)
      let floor = low - range * (high > low ? 0.3 : 1)
      let ceiling = high + range * (high > low ? 0.12 : 1)
      Chart(points) { point in
        AreaMark(
          x: .value("Date", point.date), yStart: .value("Floor", floor),
          yEnd: .value("USD", point.usd)
        )
        // Steps, not curves: the history stands like a row of buildings.
        .interpolationMethod(.stepEnd)
        .foregroundStyle(
          LinearGradient(
            colors: [Color.white.opacity(0.30), Color.white.opacity(0.04)], startPoint: .top,
            endPoint: .bottom))
        LineMark(x: .value("Date", point.date), y: .value("USD", point.usd))
          .interpolationMethod(.stepEnd)
          .foregroundStyle(Color.white)
          .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
      }
      .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
      // The first and last points touch the card's sides: no rounding of the dates.
      .chartXScale(domain: points[0].date...points[points.count - 1].date)
      .chartYScale(domain: floor...ceiling)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}
