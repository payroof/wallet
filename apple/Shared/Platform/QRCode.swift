import CoreImage.CIFilterBuiltins
import Foundation

/// QR codes drawn on the device. A public value (a receive address) is drawn once and
/// kept while it is the one on screen. A secret (the recovery words) is drawn with a
/// context of its own and never kept, because the image is as secret as the words.
@MainActor enum QRCode {
  /// One Core Image context for public codes (creating one is slow).
  private static let context = CIContext()
  private static var last: (value: String, image: CGImage)?

  static func image(_ value: String, secret: Bool = false) -> CGImage? {
    if !secret, let last, last.value == value { return last.image }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(value.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let image = (secret ? CIContext() : context).createCGImage(output, from: output.extent)
    if !secret, let image { last = (value, image) }
    return image
  }
}
