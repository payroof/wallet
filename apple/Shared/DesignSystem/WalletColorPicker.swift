import SwiftUI

/// The app's one color picker, for accounts, networks and tokens alike: the preset
/// swatches (`WalletAccent.presets`) and a last, rainbow one for any color. The custom swatch opens a
/// compact inline picker (hue strip and saturation/brightness field) drawn with plain
/// gradients, so it appears at once. Dragging edits a local draft and the swatch previews
/// it. The owner commits `selection` only when the user saves. The selected swatch
/// carries a check, not just a ring.
struct WalletColorPicker: View {
  @Binding var selection: String
  @State private var open = false
  @State private var hue = 0.07
  @State private var saturation = 0.83
  @State private var brightness = 0.64
  private var current: WalletAccent { WalletAccent(rawValue: selection) ?? .copper }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        ForEach(WalletAccent.presets) { option in
          let selected = current == option
          Button {
            selection = option.rawValue
            open = false
          } label: {
            swatch(Circle().fill(option.accent), option, selected)
          }
          .buttonStyle(.plain)
          .help(option.title)
          .accessibilityLabel(option.title)
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
        customSwatch
      }
      if open { field }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Color")
    .onAppear {
      if current.isCustom, let (r, g, b) = AccountAccent.rgb(hex: selection) {
        (hue, saturation, brightness) = Self.hsb(r, g, b)
      }
    }
  }

  private var customSwatch: some View {
    let selected = current.isCustom
    let ring = AngularGradient(
      colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center)
    return Button {
      open.toggle()
      if open && !selected { commit() }
    } label: {
      swatch(
        ZStack {
          if selected { Circle().fill(current.accent) } else { Circle().fill(ring) }
        }, current, selected)
    }
    .buttonStyle(.plain)
    .help("Custom color")
    .accessibilityLabel("Custom color")
    .accessibilityValue(selected ? selection : "")
    .accessibilityHint(open ? "Hides the color controls" : "Shows the color controls")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var field: some View {
    VStack(spacing: 10) {
      GeometryReader { box in
        let hueColor = Color(hue: hue, saturation: 1, brightness: 1)
        ZStack {
          LinearGradient(colors: [.white, hueColor], startPoint: .leading, endPoint: .trailing)
          LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(WalletShape.tile)
        .overlay(alignment: .topLeading) {
          knob(Color(hue: hue, saturation: saturation, brightness: brightness))
            .offset(
              x: saturation * box.size.width - 10, y: (1 - brightness) * box.size.height - 10)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0).onChanged {
            saturation = Self.clamp($0.location.x / box.size.width)
            brightness = 1 - Self.clamp($0.location.y / box.size.height)
            commit()
          })
      }
      .frame(height: 120)
      .accessibilityElement()
      .accessibilityLabel("Saturation and brightness")
      .accessibilityValue(
        "Saturation \(Int(saturation * 100)) percent, brightness \(Int(brightness * 100)) percent"
      )
      .accessibilityAdjustableAction { direction in
        let step = direction == .increment ? 0.05 : -0.05
        brightness = Self.clamp(brightness + step)
        commit()
      }
      GeometryReader { box in
        LinearGradient(
          colors: stride(from: 0.0, through: 1.0, by: 1 / 6).map {
            Color(hue: $0, saturation: 1, brightness: 1)
          }, startPoint: .leading, endPoint: .trailing
        )
        .clipShape(Capsule())
        .overlay(alignment: .leading) {
          knob(Color(hue: hue, saturation: 1, brightness: 1))
            .offset(x: hue * box.size.width - 10)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0).onChanged {
            hue = Self.clamp($0.location.x / box.size.width)
            commit()
          })
      }
      .frame(height: 20)
      .accessibilityElement()
      .accessibilityLabel("Hue")
      .accessibilityValue("\(Int(hue * 360)) degrees")
      .accessibilityAdjustableAction { direction in
        hue = Self.clamp(hue + (direction == .increment ? 1 : -1) / 36)
        commit()
      }
    }
  }

  private func knob(_ color: Color) -> some View {
    Circle().fill(color).frame(width: 20, height: 20)
      .overlay(Circle().strokeBorder(.white, lineWidth: 2))
      .shadow(radius: 1)
      .allowsHitTesting(false)
  }

  private func swatch(_ fill: some View, _ option: WalletAccent, _ selected: Bool) -> some View {
    ZStack {
      fill
      if selected {
        Image(systemName: "checkmark").font(.caption.weight(.bold))
          .foregroundStyle(option.onAccent)
      }
    }
    .frame(width: 24, height: 24)
    .padding(3)
    .overlay(Circle().strokeBorder(selected ? option.accent : .clear, lineWidth: 2))
    .contentShape(Circle())
  }

  /// Writes the draft as `#RRGGBB`, only when it is a valid accent.
  private func commit() {
    let (r, g, b) = Self.rgb(hue, saturation, brightness)
    let hex = String(format: "#%02X%02X%02X", Self.byte(r), Self.byte(g), Self.byte(b))
    if AccountAccent.isValid(hex) { selection = hex }
  }

  private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
  private static func byte(_ v: Double) -> Int { Int((clamp(v) * 255).rounded()) }

  static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
    let sector = min(h, 0.999999) * 6
    let i = floor(sector)
    let f = sector - i
    let p = v * (1 - s)
    let q = v * (1 - s * f)
    let t = v * (1 - s * (1 - f))
    switch Int(i) {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
  }

  static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let high = max(r, g, b)
    let delta = high - min(r, g, b)
    var h = 0.0
    if delta > 0 {
      if high == r {
        h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
      } else if high == g {
        h = (b - r) / delta + 2
      } else {
        h = (r - g) / delta + 4
      }
      h /= 6
      if h < 0 { h += 1 }
    }
    return (h, high == 0 ? 0 : delta / high, high)
  }
}
