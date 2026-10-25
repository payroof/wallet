import SwiftUI

/// Who lives on an account's roof, chosen from its slot: a cat, a pair of pigeons, or
/// nobody. Drawn centred on the sign's top edge, which is the ledge they sit on.
struct RoofResident: View {
  let slot: UInt32
  var body: some View {
    switch (slot / 2 + slot) % 3 {
    case 0: RoofCat().frame(width: 26, height: 44)
    case 1: Pigeons().frame(width: 30, height: 24)
    default: EmptyView()
    }
  }
}

/// A cat sitting on the ledge, seen from the front, its tail hanging down over the sign
/// and flicking now and then. Its eyes shine at night and it blinks. A faint rim of
/// moonlight keeps its outline against the dark. The ledge runs through the frame's
/// middle.
private struct RoofCat: View {
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let night = scheme == .dark
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
      let time = reduceMotion ? 1 : context.date.timeIntervalSinceReferenceDate
      Canvas { g, size in
        let w = size.width
        let ledge = size.height / 2
        let ink =
          night
          ? Color(red: 0.05, green: 0.06, blue: 0.1) : Color(red: 0.16, green: 0.18, blue: 0.26)
        // Tail: hangs from the right of the body over the sign, swinging slowly.
        let swing = sin(time * 1.7) * 3 + (sin(time * 0.37) > 0.92 ? sin(time * 14) * 2 : 0)
        var tail = Path()
        tail.move(to: CGPoint(x: w * 0.66, y: ledge - 2))
        tail.addCurve(
          to: CGPoint(x: w * 0.78 + swing, y: ledge + 18),
          control1: CGPoint(x: w * 0.92, y: ledge + 2),
          control2: CGPoint(x: w * 0.6 + swing, y: ledge + 10))
        var cat = Path()
        cat.addEllipse(in: CGRect(x: w * 0.2, y: ledge - 15, width: w * 0.56, height: 17))
        cat.addEllipse(in: CGRect(x: w * 0.27, y: ledge - 22, width: w * 0.42, height: 11))
        cat.addLines([
          CGPoint(x: w * 0.29, y: ledge - 17), CGPoint(x: w * 0.3, y: ledge - 26),
          CGPoint(x: w * 0.42, y: ledge - 20),
        ])
        cat.addLines([
          CGPoint(x: w * 0.54, y: ledge - 20), CGPoint(x: w * 0.66, y: ledge - 26),
          CGPoint(x: w * 0.67, y: ledge - 17),
        ])
        let rim = Color(red: 0.95, green: 0.9, blue: 0.75).opacity(night ? 0.35 : 0.0)
        g.stroke(cat, with: .color(rim), lineWidth: 1.6)
        g.stroke(tail, with: .color(rim), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
        g.fill(cat, with: .color(ink))
        g.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        // Eyes: green lamps at night, blinking every few seconds.
        let blink = time.truncatingRemainder(dividingBy: 4.7) < 0.16
        if night {
          for x in [w * 0.41, w * 0.56] {
            let eye = CGRect(x: x - 1.5, y: ledge - 18.5, width: 3, height: blink ? 0.6 : 3)
            // A soft glint rather than a beam: dim enough to be found, not to stare.
            g.fill(
              Path(ellipseIn: eye.insetBy(dx: -2, dy: -2)),
              with: .color(Color(red: 0.6, green: 0.85, blue: 0.35).opacity(blink ? 0 : 0.14)))
            g.fill(
              Path(ellipseIn: eye),
              with: .color(Color(red: 0.62, green: 0.8, blue: 0.38).opacity(0.85)))
          }
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// Two pigeons on the ledge. One bobs its head now and then.
private struct Pigeons: View {
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
      let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
      Canvas { g, size in
        let ledge = size.height / 2
        let ink =
          scheme == .dark
          ? Color(red: 0.42, green: 0.45, blue: 0.56) : Color(red: 0.3, green: 0.33, blue: 0.42)
        for (index, (x, scale)) in [(CGFloat(1), CGFloat(1)), (size.width * 0.55, 0.85)]
          .enumerated()
        {
          let w = size.width * 0.42 * scale
          let h: CGFloat = 10 * scale
          let bob = index == 0 && time.truncatingRemainder(dividingBy: 3.1) < 0.25 ? 1.5 : 0
          let y = ledge - h
          var bird = Path()
          bird.addEllipse(in: CGRect(x: x, y: y + h * 0.35, width: w * 0.8, height: h * 0.65))
          bird.addEllipse(in: CGRect(x: x + w * 0.55, y: y + bob, width: w * 0.42, height: h * 0.5))
          bird.move(to: CGPoint(x: x + w * 0.95, y: y + h * 0.22 + bob))
          bird.addLine(to: CGPoint(x: x + w * 1.1, y: y + h * 0.3 + bob))
          bird.addLine(to: CGPoint(x: x + w * 0.93, y: y + h * 0.36 + bob))
          bird.move(to: CGPoint(x: x + w * 0.05, y: y + h * 0.6))
          bird.addLine(to: CGPoint(x: x - w * 0.18, y: y + h * 0.5))
          bird.addLine(to: CGPoint(x: x, y: y + h * 0.85))
          g.fill(bird, with: .color(ink))
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
