import SwiftUI
import UniformTypeIdentifiers

/// The "Look" section of the network and token editors: the app's color picker and an
/// optional SVG logo that is imported, pasted or removed. The preview is the real glyph
/// at three sizes and follows every change. Nothing is stored here: the owner saves
/// `color` and `logo`.
struct WalletLookEditor<Preview: View>: View {
  /// A preset name or `#RRGGBB`.
  @Binding var color: String
  /// The SVG text. Nil means no logo.
  @Binding var logo: String?
  /// The glyph for a look at a size.
  @ViewBuilder let preview: (WalletArt, CGFloat) -> Preview
  @State private var pasted = ""
  @State private var problem: String?
  @State private var importing = false
  @State private var showPaste = false

  /// What the sheet draws now.
  private var art: WalletArt { WalletArt(color: color, logo: logo) }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      WalletEyebrow("Look")
      HStack(alignment: .center, spacing: 14) {
        preview(art, 44)
        preview(art, 26)
        preview(art, 18)
        Spacer(minLength: 0)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Preview")
      VStack(alignment: .leading, spacing: 8) {
        Text("Color").font(.callout.weight(.medium))
        WalletColorPicker(selection: $color)
      }
      WalletLabeled("Logo") { logoControls }
      if showPaste {
        WalletField("SVG text", hint: "Filled shapes only. At most 16 KB.", error: problem) {
          TextField("<svg viewBox=\"0 0 32 32\">…</svg>", text: $pasted, axis: .vertical)
            .lineLimit(3...6).autocorrectionDisabled()
            .font(.system(.footnote, design: .monospaced))
            #if os(iOS)
              .textInputAutocapitalization(.never)
            #endif
        }
        .onChange(of: pasted) { _, text in apply(text) }
      } else if let problem {
        Label(problem, systemImage: "exclamationmark.triangle.fill")
          .font(.footnote).foregroundStyle(WalletTheme.danger)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.svg]) { result in
      load(result)
    }
  }

  // MARK: Logo

  private var logoControls: some View {
    WalletFlowLayout(spacing: 8) {
      WalletAction(
        title: "Import SVG", icon: "square.and.arrow.down", role: .secondary, expand: false
      ) { importing = true }
      WalletAction(
        title: showPaste ? "Hide text" : "Paste SVG", icon: "doc.on.clipboard",
        role: .secondary, expand: false
      ) { showPaste.toggle() }
      if logo != nil {
        WalletAction(title: "Remove logo", icon: "trash", role: .tertiary, expand: false) {
          logo = nil
          pasted = ""
          problem = nil
        }
      }
    }
  }

  /// Takes pasted or imported text as the logo when it is a valid one.
  private func apply(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      problem = nil
      return
    }
    if let reason = SVGLogo.problem(trimmed) {
      problem = reason
    } else {
      problem = nil
      logo = trimmed
    }
  }

  private func load(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else {
      problem = "Couldn't open this file."
      return
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size <= SVGLogo.maxBytes else {
      problem = SVGLogoError.tooLarge.errorDescription
      return
    }
    guard let data = try? Data(contentsOf: url), data.count <= SVGLogo.maxBytes,
      let text = String(data: data, encoding: .utf8)
    else {
      problem = "Couldn't read this file as text."
      return
    }
    showPaste = true
    pasted = text
    apply(text)
  }
}
