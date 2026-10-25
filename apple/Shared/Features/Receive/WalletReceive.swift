import SwiftUI

/// The address and its QR code are the screen, centred. Which address (from the list, an
/// exact index or path) is the header's title. A new one is its action, opposite.
struct WalletReceive: View {
  @Environment(WalletModel.self) private var model
  @State private var path = ""
  @State private var choosing = false
  /// The address was asked for while another command ran. It is derived right after.
  @State private var waiting = false
  @Environment(\.walletAccent) private var accent
  private var account: ProjectCard? { model.currentAccount }
  private var shown: ReceiveAddress? {
    guard let address = model.state.address, address.path == path else { return nil }
    return address
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        addressBody
      }
      .padding(.horizontal, WalletMetrics.page).padding(.vertical, 28)
      // Wide enough for a full address on one line, and QR and actions stay centered.
      .frame(maxWidth: 640).frame(maxWidth: .infinity)
    }
    // While the address is shorter than the screen, it sits in the middle.
    .defaultScrollAnchor(.center, for: .alignment)
    .walletPageBackground()
    .toolbar {
      WalletHeaderTitle {
        Button {
          choosing = true
        } label: {
          WalletChoiceLabel(title: path.isEmpty ? "Address" : WalletText.addressName(path))
        }
        .buttonStyle(.plain)
        .help("Choose an address")
        .accessibilityLabel(
          "Receiving to \(path.isEmpty ? "no address" : WalletText.addressName(path))"
        )
        .accessibilityHint("Change")
      }
      WalletHeaderAction {
        Button {
          model.run(.address(model.account, nil)) { path = model.state.address?.path ?? path }
        } label: {
          // The progress indicator takes the icon's place. The button keeps its size.
          Image(systemName: "plus")
            .opacity(model.isRunning(.address) ? 0 : 1)
            .overlay {
              if model.isRunning(.address) { ProgressView().controlSize(.small) }
            }
        }
        .disabled(!model.canRun(.address))
        .help("New address").accessibilityLabel("New address")
      }
    }
    .onAppear { selectDefaults() }
    .onChange(of: model.account) { _, _ in
      path = ""
      selectDefaults()
    }
    .onChange(of: path) { _, _ in derive() }
    .onChange(of: model.canRun(.address)) { _, free in
      if free && waiting { derive() }
    }

    .walletSheet(isPresented: $choosing) {
      AddressPickerSheet(slot: model.account, path: $path) { choosing = false }
    }
    .walletDismissOnLock { choosing = false }
  }

  @ViewBuilder private var addressBody: some View {
    if let address = shown {
      if let image = QRCode.image(address.address) {
        // The code on a rooftop billboard, its bulbs round the edge, on lattice legs.
        VStack(spacing: 0) {
          SignBoard(accent: accent, radius: 26) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
              .frame(width: 200, height: 200).padding(14)
              .background(.white, in: WalletShape.tile)
              .padding(24)
              .accessibilityLabel("QR code for the public receive address")
          }
          SignLegs(count: 2, color: WalletTheme.roofEdge).frame(width: 150, height: 30)
          Capsule().fill(WalletTheme.roofEdge).frame(width: 220, height: 4)
        }
        .transition(.scale(scale: 0.92).combined(with: .opacity))
      }
      addressText(address.address)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background {
          // A brass plaque, screwed to the wall.
          WalletShape.field.fill(WalletTheme.surface)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .overlay {
          WalletShape.field
            .strokeBorder(WalletTheme.border, lineWidth: 1)
        }
        .overlay(alignment: .leading) { screw.padding(.leading, 6) }
        .overlay(alignment: .trailing) { screw.padding(.trailing, 6) }
      HStack(spacing: 10) {
        WalletCopyAction(title: "Copy", value: address.address, announcement: "Address copied")
          // A new address starts with a fresh Copy.
          .id(address.address)

        ShareLink(item: address.address) {
          Label("Share", systemImage: "square.and.arrow.up")
        }.buttonStyle(WalletButtonStyle(role: .secondary))
      }.frame(maxWidth: 360)
    } else if path.isEmpty {
      WalletEmptyState(
        icon: "qrcode", title: "No address yet",
        detail: "Create an address for this account to receive funds."
      ) {
        WalletAction(title: "Create address", icon: "plus", expand: false) {
          model.run(.address(model.account, nil)) { path = model.state.address?.path ?? "" }
        }.disabled(!model.canRun(.address))
      }
    } else if model.isRunning(.address) || waiting {
      VStack(spacing: 12) {
        WalletSpinner(size: 22).foregroundStyle(WalletTheme.accent)
        Text("Deriving address…").font(.callout).foregroundStyle(WalletTheme.muted)
      }
      .frame(height: 240).accessibilityElement(children: .combine)
    } else {
      WalletEmptyState(
        icon: "qrcode", title: WalletText.addressName(path),
        detail: "Derive this address on device to show its QR code."
      ) {
        WalletAction(title: "Show address", icon: "qrcode", expand: false) {
          model.run(.exact(path))
        }
      }
    }
  }

  private var screw: some View {
    Circle().fill(WalletTheme.border).frame(width: 5, height: 5)
      .overlay(Rectangle().fill(WalletTheme.muted.opacity(0.6)).frame(width: 4, height: 0.8))
      .accessibilityHidden(true)
  }

  /// The full address on one line whenever it fits. Where it can't (narrow phones,
  /// large text), it breaks into two balanced lines at a fixed point: every
  /// character stays visible and selectable, and no hyphen is ever inserted.
  private func addressText(_ value: String) -> some View {
    ViewThatFits(in: .horizontal) {
      emphasized(value, split: false).lineLimit(1).fixedSize()
      emphasized(value, split: true).fixedSize(horizontal: false, vertical: true)
    }
    .font(.system(.body, design: .monospaced)).multilineTextAlignment(.center)
    .textSelection(.enabled)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Address \(value)")
    .accessibilityAddTraits(.isStaticText)
  }

  /// Bold first and last characters: the parts people compare when verifying.
  private func emphasized(_ value: String, split: Bool) -> Text {
    guard value.count > 12 else { return Text(value) }
    let head = String(value.prefix(6))
    let tail = String(value.suffix(4))
    var middle = String(value.dropFirst(6).dropLast(4))
    let half = value.count / 2 - head.count
    if split && half > 0 && half < middle.count {
      middle.insert("\n", at: middle.index(middle.startIndex, offsetBy: half))
    }
    return Text(
      "\(Text(head).fontWeight(.bold))\(Text(middle).foregroundStyle(WalletTheme.muted))\(Text(tail).fontWeight(.bold))"
    )
  }
  private func selectDefaults() {
    if path.isEmpty {
      if let address = model.state.address, account?.paths.contains(address.path) == true {
        path = address.path
      } else {
        path = account?.latestPath ?? ""
      }
    }
    derive()
  }
  /// Derives the chosen address on device. One command runs at a time, so a request
  /// made while another runs waits for it instead of being lost.
  private func derive() {
    guard !path.isEmpty, model.state.address?.path != path else {
      waiting = false
      return
    }
    waiting = !model.canRun(.address)
    if !waiting { model.run(.exact(path)) }
  }

}
