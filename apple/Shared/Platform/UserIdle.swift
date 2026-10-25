import Foundation

#if os(macOS)
  import CoreGraphics
#endif

/// Seconds since the last keyboard, mouse or trackpad input anywhere on this Mac.
/// `nil` where the system doesn't report it (iOS). The app's own input is used there.
enum UserIdle {
  static var seconds: TimeInterval? {
    #if os(macOS)
      [
        CGEventType.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown,
        .otherMouseDown, .leftMouseDragged, .scrollWheel,
      ]
      .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
      .min()
    #else
      nil
    #endif
  }
}
