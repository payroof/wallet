import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Fixed colors of the scenery: light sources and signage, the same by day and night.
enum ScenePalette {
  /// Warm incandescent light: lit windows, marquee bulbs.
  static let bulb = Color(red: 1, green: 0.8, blue: 0.45)
  /// A bulb's hot core.
  static let bulbCore = Color(red: 1, green: 0.93, blue: 0.75)
  /// String lights in the roof garden.
  static let fairyLight = Color(red: 1, green: 0.85, blue: 0.5)
  /// Hazard tape and its black stripes, a traffic cone, a load of bricks.
  static let hazard = Color(red: 0.98, green: 0.78, blue: 0.2)
  static let hazardStripe = Color(red: 0.12, green: 0.12, blue: 0.14)
  static let cone = Color(red: 1, green: 0.52, blue: 0.16)
  static let brick = Color(red: 0.66, green: 0.29, blue: 0.2)
}
