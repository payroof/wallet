import SwiftUI
import UniformTypeIdentifiers

/// The recovery words as a plain-text file the user saves where they choose.
struct RecoveryWordsDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.plainText]
  var text: String
  init(words: [String]) {
    let lines = words.enumerated().map { String(format: "%02d  %@", $0.offset + 1, $0.element) }
    text =
      "Payroof Wallet recovery words\nKeep offline. Anyone with these words can take your funds.\n\n"
      + lines.joined(separator: "\n") + "\n"
  }
  init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(text.utf8))
  }
}

/// The recovery words as a brick wall, laid in running bond: each brick is one word with
/// its number, read left to right, course by course, as written down. Every other
/// course is offset by half a brick. Blank bricks close the ends of those courses and
/// finish the last one, so the wall stands square.
struct RecoveryWordsGrid: View {
  let words: [String]
  private static let spacing: CGFloat = 4
  var body: some View {
    BrickBond(spacing: Self.spacing) {
      ForEach(Array(words.enumerated()), id: \.offset) { index, word in
        VStack(alignment: .leading, spacing: 0) {
          Text(String(format: "%02d", index + 1))
            .font(RoofFont.stencil(9, relativeTo: .caption2)).tracking(0.8)
            .foregroundStyle(Color.white.opacity(0.7))
          Text(word).font(.system(.footnote, design: .monospaced).weight(.semibold))
            .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          LinearGradient(
            colors: [WalletTheme.brick, WalletTheme.brickDeep], startPoint: .top, endPoint: .bottom),
          in: RoundedRectangle(cornerRadius: 3, style: .continuous)
        )
        .accessibilityElement(children: .combine)
      }
    }
    .background {
      // The blank bricks, drawn where the layout leaves room for them.
      Canvas { context, size in
        for slot in BrickBond.blanks(
          width: size.width, height: size.height, count: words.count, spacing: Self.spacing)
        {
          context.fill(
            Path(roundedRect: slot, cornerRadius: 3, style: .continuous),
            with: .linearGradient(
              Gradient(colors: [WalletTheme.brick, WalletTheme.brickDeep]),
              startPoint: CGPoint(x: slot.midX, y: slot.minY),
              endPoint: CGPoint(x: slot.midX, y: slot.maxY)))
        }
      }
      .opacity(0.72)
      .accessibilityHidden(true)
    }
    .padding(Self.spacing)
    .background(WalletTheme.mortar, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .textSelection(.enabled)
  }
}

/// Running bond: as many bricks per course as fit at a readable width. Odd courses are
/// shifted half a brick and hold one brick fewer, leaving a half brick's room at each end.
struct BrickBond: Layout {
  var spacing: CGFloat = 4
  static let minimumBrick: CGFloat = 86

  static func columns(_ width: CGFloat, spacing: CGFloat) -> Int {
    max(2, Int((width + spacing) / (minimumBrick + spacing)))
  }
  static func rows(count: Int, columns: Int) -> [Range<Int>] {
    var rows: [Range<Int>] = []
    var start = 0
    var odd = false
    while start < count {
      let take = min(odd ? columns - 1 : columns, count - start)
      rows.append(start..<(start + take))
      start += take
      odd.toggle()
    }
    return rows
  }
  /// Where the blank bricks go in a wall of this size: the half bricks closing every
  /// offset course, and the rest of a last course that isn't full.
  static func blanks(width: CGFloat, height: CGFloat, count: Int, spacing: CGFloat) -> [CGRect] {
    let n = columns(width, spacing: spacing)
    let courses = rows(count: count, columns: n)
    guard !courses.isEmpty else { return [] }
    let brick = (width - CGFloat(n - 1) * spacing) / CGFloat(n)
    let half = (brick - spacing) / 2
    let course = (height - CGFloat(courses.count - 1) * spacing) / CGFloat(courses.count)
    var slots: [CGRect] = []
    for (row, range) in courses.enumerated() {
      let y = CGFloat(row) * (course + spacing)
      let odd = !row.isMultiple(of: 2)
      let full = odd ? n - 1 : n
      let start = odd ? half + spacing : 0
      for missing in range.count..<full {
        slots.append(
          CGRect(
            x: start + CGFloat(missing) * (brick + spacing), y: y, width: brick, height: course))
      }
      if odd {
        slots.append(CGRect(x: 0, y: y, width: half, height: course))
        slots.append(CGRect(x: width - half, y: y, width: half, height: course))
      }
    }
    return slots
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 360
    let n = Self.columns(width, spacing: spacing)
    let brick = (width - CGFloat(n - 1) * spacing) / CGFloat(n)
    let height =
      subviews.map { $0.sizeThatFits(ProposedViewSize(width: brick, height: nil)).height }
      .max() ?? 0
    let count = Self.rows(count: subviews.count, columns: n).count
    return CGSize(
      width: width, height: CGFloat(count) * height + CGFloat(max(0, count - 1)) * spacing)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let n = Self.columns(bounds.width, spacing: spacing)
    let brick = (bounds.width - CGFloat(n - 1) * spacing) / CGFloat(n)
    let height =
      subviews.map { $0.sizeThatFits(ProposedViewSize(width: brick, height: nil)).height }
      .max() ?? 0
    let half = (brick - spacing) / 2
    for (row, range) in Self.rows(count: subviews.count, columns: n).enumerated() {
      let odd = !row.isMultiple(of: 2)
      var x = bounds.minX + (odd ? half + spacing : 0)
      let y = bounds.minY + CGFloat(row) * (height + spacing)
      for index in range {
        subviews[index].place(
          at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: brick, height: height))
        x += brick + spacing
      }
    }
  }
}
