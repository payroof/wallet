import Foundation

/// One account's USD total at one moment, as an exact decimal string.
struct ValuePoint: Codable, Equatable, Sendable {
  var date: Date
  var usd: String
  var value: Decimal? { Decimal(string: usd, locale: nil) }
}

/// An account's USD total over time: one point per refresh that read it, at most one
/// per clock hour (a later read in the same hour replaces the earlier one), the newest
/// kept.
enum ValueHistory {
  static let limit = 1000

  /// `points` with `usd` recorded at `date`.
  static func record(_ usd: Decimal, at date: Date, in points: [ValuePoint]) -> [ValuePoint] {
    var points = points.filter { $0.date <= date }
    if let last = points.last, hour(last.date) == hour(date) { points.removeLast() }
    points.append(ValuePoint(date: date, usd: "\(usd)"))
    return Array(points.suffix(limit))
  }

  private static func hour(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSinceReferenceDate / 3600).rounded(.down))
  }
}
