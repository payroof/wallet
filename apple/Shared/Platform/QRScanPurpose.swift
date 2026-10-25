import Foundation

/// What a QR scan is for, and the prefilter its payload must pass. The scanners
/// (iOS: ios/Platform, macOS: macos/Platform) share it.
enum QRScanPurpose {
  case address, pairing, recoveryWords

  /// The scanner's heading.
  var title: String {
    switch self {
    case .address: "Scan an address"
    case .pairing: "Scan a pairing link"
    case .recoveryWords: "Scan recovery words"
    }
  }
  /// Shown when the camera sees some other QR code.
  var invalidMessage: String {
    switch self {
    case .address: "Not an EVM address"
    case .pairing: "Not a Payroof pairing link"
    case .recoveryWords: "Not a recovery phrase"
    }
  }
  /// Recovery phrases have 12, 15, 18, 21 or 24 words.
  static let phraseLengths = [12, 15, 18, 21, 24]
  func accepts(_ payload: String) -> Bool {
    switch self {
    case .address:
      return EVMAddress(payload) != nil
    case .pairing:
      // This is only a transport prefilter. Rust parses and verifies the
      // pairing request, and the user must still explicitly approve it.
      guard let url = URL(string: payload) else { return false }
      return WalletIncomingLink.resolve(url) != nil
    case .recoveryWords:
      // Words of letters only, separated by whitespace. The core checks the phrase
      // itself (word list and checksum) when the wallet is opened.
      let words = payload.split(whereSeparator: \.isWhitespace)
      return Self.phraseLengths.contains(words.count)
        && words.allSatisfy { $0.allSatisfy { $0.isLetter } }
    }
  }
}
