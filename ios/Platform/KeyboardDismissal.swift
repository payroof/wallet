import SwiftUI
import UIKit

/// Hides the keyboard when the user taps anywhere outside a text field, on a screen or
/// in a sheet. Sheets can be presented in a window of their own, so whenever the
/// keyboard appears every window of the scene gets the recognizer. The tap still
/// reaches whatever was tapped. It is only observed.
struct KeyboardDismissal: UIViewRepresentable {
  func makeUIView(context: Context) -> HostView {
    let view = HostView()
    view.isUserInteractionEnabled = false
    return view
  }
  func updateUIView(_ view: HostView, context: Context) {}

  final class HostView: UIView, UIGestureRecognizerDelegate {
    private var observer: NSObjectProtocol?
    private var recognizers: [ObjectIdentifier: UITapGestureRecognizer] = [:]
    override func didMoveToWindow() {
      super.didMoveToWindow()
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
      guard window != nil else { return }
      observer = NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.watchWindows() } }
    }
    private func watchWindows() {
      // Forget the recognizers of windows that have gone (closed sheets).
      recognizers = recognizers.filter { $0.value.view != nil }
      for window in window?.windowScene?.windows ?? []
      where recognizers[ObjectIdentifier(window)]?.view !== window {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        recognizers[ObjectIdentifier(window)] = recognizer
      }
    }
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
      for window in window?.windowScene?.windows ?? [] { window.endEditing(true) }
    }
    /// A tap in a text field moves the focus there instead.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
    {
      var view = touch.view
      while let current = view {
        if current is UITextField || current is UITextView { return false }
        view = current.superview
      }
      return true
    }
    func gestureRecognizer(
      _ recognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
  }
}
