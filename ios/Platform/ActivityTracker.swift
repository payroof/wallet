import SwiftUI
import UIKit

/// Reports any touch in the app's window, and typing in any text field, as activity,
/// so the inactivity lock only counts time the user really left the wallet alone.
/// It observes touches without recognizing or cancelling them.
struct ActivityTracker: UIViewRepresentable {
  let onActivity: @MainActor () -> Void
  func makeUIView(context: Context) -> TrackerView {
    let view = TrackerView()
    view.onActivity = onActivity
    view.isUserInteractionEnabled = false
    return view
  }
  func updateUIView(_ view: TrackerView, context: Context) { view.onActivity = onActivity }

  final class TrackerView: UIView {
    var onActivity: (@MainActor () -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var recognizer: Recognizer?
    override func didMoveToWindow() {
      super.didMoveToWindow()
      // Off-window (or moving to another), stop observing. On a window, observe it.
      if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
      recognizer = nil
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers = []
      guard let window else { return }
      let recognizer = Recognizer { [weak self] in self?.onActivity?() }
      window.addGestureRecognizer(recognizer)
      self.recognizer = recognizer
      for name in [UITextField.textDidChangeNotification, UITextView.textDidChangeNotification] {
        observers.append(
          NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.onActivity?() }
          })
      }
    }
  }

  /// Sees every touch begin, then fails so it never takes part in gestures.
  final class Recognizer: UIGestureRecognizer {
    private let touched: @MainActor () -> Void
    init(touched: @escaping @MainActor () -> Void) {
      self.touched = touched
      super.init(target: nil, action: nil)
      cancelsTouchesInView = false
      delaysTouchesBegan = false
      delaysTouchesEnded = false
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      touched()
      state = .failed
    }
  }
}
