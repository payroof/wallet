import Foundation

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor enum PublicClipboard {
  static func copy(_ value: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
    #else
      UIPasteboard.general.string = value
    #endif
  }
}

/// Secret text (recovery words) on the clipboard, for one paste only: kept on this
/// device, hidden from clipboard managers, and cleared after a minute.
@MainActor enum SecretClipboard {
  static let lifetime: TimeInterval = 60
  static func copy(_ value: String) {
    #if os(macOS)
      let board = NSPasteboard.general
      board.clearContents()
      board.setString(value, forType: .string)
      // Clipboard managers skip concealed and transient items.
      board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
      board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
      let change = board.changeCount
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(lifetime))
        if board.changeCount == change { board.clearContents() }
      }
    #else
      UIPasteboard.general.setItems(
        [["public.utf8-plain-text": value]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(lifetime)])
    #endif
  }
}
