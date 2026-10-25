import Foundation
import Synchronization

/// A point in an SVG's own coordinate space.
struct SVGPoint: Equatable, Sendable {
  var x: Double
  var y: Double
}

/// One drawing step. Arcs, circles, ellipses and rounded rectangles are already
/// converted to curves, so a renderer needs only these.
enum SVGPathElement: Equatable, Sendable {
  case move(SVGPoint)
  case line(SVGPoint)
  case quad(control: SVGPoint, end: SVGPoint)
  case curve(control1: SVGPoint, control2: SVGPoint, end: SVGPoint)
  case close
}

/// A color with components from 0 to 1.
struct SVGColor: Equatable, Sendable {
  var red: Double
  var green: Double
  var blue: Double
}

/// One filled shape, in the image's own coordinate space with every transform applied.
struct SVGLayer: Equatable, Sendable {
  var elements: [SVGPathElement]
  var color: SVGColor
  var evenOdd: Bool
  var opacity: Double
}

/// A parsed logo: the view box and the filled shapes, back to front.
struct SVGImage: Equatable, Sendable {
  var width: Double
  var height: Double
  var originX: Double
  var originY: Double
  var layers: [SVGLayer]
}

/// Why a logo was refused. The text is written for the person who pasted it.
enum SVGLogoError: Error, Equatable, LocalizedError, Sendable {
  case empty
  case tooLarge
  case malformed
  case notSVG
  case unsupportedElement(String)
  case unsupportedAttribute(String)
  case invalid(String)
  case tooComplex
  case nothingToDraw

  var errorDescription: String? {
    switch self {
    case .empty: "Paste or import an SVG."
    case .tooLarge: "The logo is larger than \(SVGLogo.maxBytes / 1024) KB."
    case .malformed: "This isn't valid SVG."
    case .notSVG: "The file's root element must be svg."
    case .unsupportedElement(let name):
      "The element \(name) isn't supported. Use plain shapes: path, circle, ellipse, rect, polygon and g."
    case .unsupportedAttribute(let name):
      "The attribute \(name) isn't supported. Convert strokes, gradients and styles to plain filled shapes."
    case .invalid(let what): "Couldn't read \(what)."
    case .tooComplex: "The logo is too detailed. Simplify the artwork."
    case .nothingToDraw: "The logo has no visible filled shape."
    }
  }
}

/// A small, safe SVG subset for network and token logos. Only filled vector shapes
/// are read: path (all commands), circle, ellipse, rect, polygon and g, with
/// translate, scale and matrix transforms, fill, fill-rule and opacity. Everything else
/// is refused, so a logo can never run script, load a resource or hide text. Parsing is
/// bounded in size, depth and work and never traps.
enum SVGLogo {
  /// The largest accepted source, in UTF-8 bytes.
  static let maxBytes = 16 * 1024
  private static let maxElements = 400
  private static let maxDepth = 12
  private static let maxSteps = 6000
  private static let maxCoordinate = 1_000_000.0

  /// Parses and validates `text`.
  static func parse(_ text: String) throws -> SVGImage {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw SVGLogoError.empty }
    guard trimmed.utf8.count <= maxBytes else { throw SVGLogoError.tooLarge }
    let lower = trimmed.lowercased()
    guard !lower.contains("<!doctype"), !lower.contains("<!entity") else {
      throw SVGLogoError.malformed
    }
    let builder = Builder()
    let parser = XMLParser(data: Data(trimmed.utf8))
    parser.shouldResolveExternalEntities = false
    parser.delegate = builder
    let finished = parser.parse()
    if let failure = builder.failure { throw failure }
    guard finished, builder.closedRoot else { throw SVGLogoError.malformed }
    guard let image = builder.image, !image.layers.isEmpty else {
      throw SVGLogoError.nothingToDraw
    }
    return image
  }

  /// The user-facing reason `text` is refused, or nil when it is a valid logo.
  static func problem(_ text: String) -> String? {
    do {
      _ = try parse(text)
      return nil
    } catch {
      return (error as? SVGLogoError)?.errorDescription ?? "This isn't valid SVG."
    }
  }

  /// Whether `text` is a valid logo.
  static func isValid(_ text: String) -> Bool { problem(text) == nil }

  // MARK: Cache

  private static let cache = Mutex<[String: SVGImage?]>([:])

  /// The parsed image, or nil when `text` is not a valid logo. Results are cached.
  static func image(_ text: String) -> SVGImage? {
    if let hit = cache.withLock({ $0[text] }) { return hit }
    let parsed = try? parse(text)
    cache.withLock {
      if $0.count >= 256 { $0.removeAll() }
      $0[text] = .some(parsed)
    }
    return parsed
  }

  // MARK: Parsing

  private struct Affine {
    var a = 1.0
    var b = 0.0
    var c = 0.0
    var d = 1.0
    var e = 0.0
    var f = 0.0
    /// `self` applied after `other`, as nested transforms compose.
    func concatenating(_ other: Affine) -> Affine {
      Affine(
        a: a * other.a + c * other.b, b: b * other.a + d * other.b,
        c: a * other.c + c * other.d, d: b * other.c + d * other.d,
        e: a * other.e + c * other.f + e, f: b * other.e + d * other.f + f)
    }
    func apply(_ p: SVGPoint) -> SVGPoint {
      SVGPoint(x: a * p.x + c * p.y + e, y: b * p.x + d * p.y + f)
    }
  }

  private struct Style {
    var fill: SVGColor? = SVGColor(red: 0, green: 0, blue: 0)
    var evenOdd = false
    var fillOpacity = 1.0
    var opacity = 1.0
    var transform = Affine()
  }

  /// Attributes that carry no drawing meaning and are safe to ignore.
  private static let ignored: Set<String> = [
    "id", "class", "version", "xmlns", "preserveaspectratio", "clip-rule", "shape-rendering",
    "role", "focusable",
  ]

  private final class Builder: NSObject, XMLParserDelegate {
    var failure: SVGLogoError?
    var image: SVGImage?
    var closedRoot = false
    private var stack: [Style] = []
    private var layers: [SVGLayer] = []
    private var count = 0
    private var steps = 0
    private var rootSeen = false
    private var box = (x: 0.0, y: 0.0, w: 0.0, h: 0.0)

    private func fail(_ error: SVGLogoError, _ parser: XMLParser) {
      if failure == nil { failure = error }
      parser.abortParsing()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
      if failure == nil { failure = .malformed }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if !string.allSatisfy(\.isWhitespace) { fail(.unsupportedElement("text"), parser) }
    }
    func parser(_ parser: XMLParser, foundCDATA block: Data) {
      fail(.unsupportedElement("CDATA"), parser)
    }

    func parser(
      _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes: [String: String]
    ) {
      count += 1
      guard count <= SVGLogo.maxElements, stack.count < SVGLogo.maxDepth else {
        return fail(.tooComplex, parser)
      }
      do {
        if !rootSeen {
          guard name == "svg" else { throw SVGLogoError.notSVG }
          rootSeen = true
          try root(attributes)
          var style = Style()
          try SVGLogo.read(attributes, into: &style, element: "svg")
          stack.append(style)
          return
        }
        guard !closedRoot, let parent = stack.last else { throw SVGLogoError.malformed }
        var style = parent
        try SVGLogo.read(attributes, into: &style, element: name)
        stack.append(style)
        if name != "g" { try shape(name, attributes, style) }
      } catch let error as SVGLogoError {
        fail(error, parser)
      } catch {
        fail(.malformed, parser)
      }
    }

    func parser(
      _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      guard !stack.isEmpty else { return }
      stack.removeLast()
      if stack.isEmpty {
        closedRoot = true
        image = SVGImage(
          width: box.w, height: box.h, originX: box.x, originY: box.y, layers: layers)
      }
    }

    private func root(_ attributes: [String: String]) throws {
      if let raw = attributes["viewBox"] {
        let numbers = try SVGLogo.numbers(raw, what: "the viewBox")
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else {
          throw SVGLogoError.invalid("the viewBox")
        }
        box = (numbers[0], numbers[1], numbers[2], numbers[3])
      } else if let width = attributes["width"], let height = attributes["height"] {
        let w = try SVGLogo.length(width, what: "the width")
        let h = try SVGLogo.length(height, what: "the height")
        guard w > 0, h > 0 else { throw SVGLogoError.invalid("the size") }
        box = (0, 0, w, h)
      } else {
        throw SVGLogoError.invalid("the viewBox")
      }
      guard box.w <= SVGLogo.maxCoordinate, box.h <= SVGLogo.maxCoordinate,
        abs(box.x) <= SVGLogo.maxCoordinate, abs(box.y) <= SVGLogo.maxCoordinate
      else { throw SVGLogoError.invalid("the viewBox") }
    }

    private func shape(_ name: String, _ a: [String: String], _ style: Style) throws {
      var elements: [SVGPathElement] = []
      let number = { (key: String) throws -> Double in
        try a[key].map { try SVGLogo.length($0, what: key) } ?? 0
      }
      switch name {
      case "path":
        guard let d = a["d"] else { throw SVGLogoError.invalid("the path data") }
        elements = try SVGLogo.pathData(d, budget: SVGLogo.maxSteps - steps)
      case "circle":
        let r = try number("r")
        guard r > 0 else { throw SVGLogoError.invalid("the circle") }
        elements = SVGLogo.ellipse(cx: try number("cx"), cy: try number("cy"), rx: r, ry: r)
      case "ellipse":
        let rx = try number("rx")
        let ry = try number("ry")
        guard rx > 0, ry > 0 else { throw SVGLogoError.invalid("the ellipse") }
        elements = SVGLogo.ellipse(cx: try number("cx"), cy: try number("cy"), rx: rx, ry: ry)
      case "rect":
        let w = try number("width")
        let h = try number("height")
        guard w > 0, h > 0 else { throw SVGLogoError.invalid("the rectangle") }
        var rx = try a["rx"].map { try SVGLogo.length($0, what: "rx") }
        var ry = try a["ry"].map { try SVGLogo.length($0, what: "ry") }
        if rx == nil { rx = ry }
        if ry == nil { ry = rx }
        elements = SVGLogo.rectangle(
          x: try number("x"), y: try number("y"), width: w, height: h,
          rx: min(max(rx ?? 0, 0), w / 2), ry: min(max(ry ?? 0, 0), h / 2))
      case "polygon":
        let values = try SVGLogo.numbers(a["points"] ?? "", what: "the points")
        guard values.count >= 6, values.count % 2 == 0 else {
          throw SVGLogoError.invalid("the points")
        }
        for index in stride(from: 0, to: values.count, by: 2) {
          let point = SVGPoint(x: values[index], y: values[index + 1])
          elements.append(index == 0 ? .move(point) : .line(point))
        }
        elements.append(.close)
      default:
        throw SVGLogoError.unsupportedElement(name)
      }
      steps += elements.count
      guard steps <= SVGLogo.maxSteps else { throw SVGLogoError.tooComplex }
      guard let color = style.fill else { return }
      let mapped = try elements.map { try SVGLogo.map($0, style.transform) }
      layers.append(
        SVGLayer(
          elements: mapped, color: color, evenOdd: style.evenOdd,
          opacity: min(max(style.opacity * style.fillOpacity, 0), 1)))
    }
  }

  /// Applies one element's presentation attributes on top of its parent's style.
  private static func read(
    _ attributes: [String: String], into style: inout Style, element: String
  ) throws {
    let allowed: Set<String> =
      switch element {
      case "svg": ["viewBox", "width", "height", "x", "y"]
      case "g": []
      case "path": ["d"]
      case "circle": ["cx", "cy", "r"]
      case "ellipse": ["cx", "cy", "rx", "ry"]
      case "rect": ["x", "y", "width", "height", "rx", "ry"]
      case "polygon": ["points"]
      default: throw SVGLogoError.unsupportedElement(element)
      }
    for key in attributes.keys {
      let lower = key.lowercased()
      let known = ["fill", "fill-rule", "fill-opacity", "opacity", "transform", "stroke"]
      if allowed.contains(key) || known.contains(lower) { continue }
      if lower.hasPrefix("data-") || lower.hasPrefix("aria-") || lower.hasPrefix("xmlns:") {
        continue
      }
      if ignored.contains(lower) { continue }
      throw SVGLogoError.unsupportedAttribute(key)
    }
    if let stroke = attributes["stroke"], stroke != "none" {
      throw SVGLogoError.unsupportedAttribute("stroke")
    }
    if let value = attributes["fill"] { style.fill = try color(value) }
    if let value = attributes["fill-rule"] {
      switch value {
      case "evenodd": style.evenOdd = true
      case "nonzero": style.evenOdd = false
      default: throw SVGLogoError.invalid("fill-rule")
      }
    }
    if let value = attributes["fill-opacity"] {
      style.fillOpacity = try unit(value, what: "fill-opacity")
    }
    if let value = attributes["opacity"] {
      style.opacity *= try unit(value, what: "opacity")
    }
    if let value = attributes["transform"] {
      style.transform = style.transform.concatenating(try transform(value))
    }
  }

  private static func unit(_ text: String, what: String) throws -> Double {
    let value = try number(text.trimmingCharacters(in: .whitespaces), what: what)
    guard (0...1).contains(value) else { throw SVGLogoError.invalid(what) }
    return value
  }

  private static func number(_ text: String, what: String) throws -> Double {
    guard !text.isEmpty, text.utf8.count <= 40, let value = Double(text), value.isFinite,
      abs(value) <= maxCoordinate
    else { throw SVGLogoError.invalid(what) }
    return value
  }

  /// A plain number, optionally in px. Other units and percentages are refused.
  private static func length(_ text: String, what: String) throws -> Double {
    var value = text.trimmingCharacters(in: .whitespaces)
    if value.hasSuffix("px") { value.removeLast(2) }
    return try number(value, what: what)
  }

  /// Numbers separated by whitespace and commas.
  private static func numbers(_ text: String, what: String) throws -> [Double] {
    let parts = text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
    guard parts.count <= 2 * maxSteps else { throw SVGLogoError.tooComplex }
    return try parts.map { try number(String($0), what: what) }
  }

  // MARK: Colors

  private static let names: [String: SVGColor] = [
    "black": SVGColor(red: 0, green: 0, blue: 0),
    "white": SVGColor(red: 1, green: 1, blue: 1),
    "red": SVGColor(red: 1, green: 0, blue: 0),
    "green": SVGColor(red: 0, green: 128 / 255, blue: 0),
    "blue": SVGColor(red: 0, green: 0, blue: 1),
    "yellow": SVGColor(red: 1, green: 1, blue: 0),
    "orange": SVGColor(red: 1, green: 165 / 255, blue: 0),
    "purple": SVGColor(red: 128 / 255, green: 0, blue: 128 / 255),
    "gray": SVGColor(red: 128 / 255, green: 128 / 255, blue: 128 / 255),
    "grey": SVGColor(red: 128 / 255, green: 128 / 255, blue: 128 / 255),
    "cyan": SVGColor(red: 0, green: 1, blue: 1),
    "magenta": SVGColor(red: 1, green: 0, blue: 1),
  ]

  /// A fill: nil means none. Hex, rgb() and a few basic names are understood.
  private static func color(_ text: String) throws -> SVGColor? {
    let value = text.trimmingCharacters(in: .whitespaces).lowercased()
    if value == "none" || value == "transparent" { return nil }
    if let named = names[value] { return named }
    if value.hasPrefix("#") {
      let digits = Array(value.dropFirst())
      guard digits.allSatisfy(\.isHexDigit), [3, 6].contains(digits.count) else {
        throw SVGLogoError.invalid("the fill color")
      }
      let full = digits.count == 3 ? digits.flatMap { [$0, $0] } : digits
      let bytes = stride(from: 0, to: 6, by: 2).map {
        Double(Int(String(full[$0...$0 + 1]), radix: 16) ?? 0) / 255
      }
      return SVGColor(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
    if value.hasPrefix("rgb("), value.hasSuffix(")") {
      let parts = value.dropFirst(4).dropLast().split(whereSeparator: {
        $0 == "," || $0.isWhitespace
      })
      guard parts.count == 3 else { throw SVGLogoError.invalid("the fill color") }
      let channels = try parts.map { part -> Double in
        if part.hasSuffix("%") {
          let percent = try number(String(part.dropLast()), what: "the fill color")
          return min(max(percent, 0), 100) / 100
        }
        return min(max(try number(String(part), what: "the fill color"), 0), 255) / 255
      }
      return SVGColor(red: channels[0], green: channels[1], blue: channels[2])
    }
    throw SVGLogoError.invalid("the fill color")
  }

  // MARK: Transforms

  private static func transform(_ text: String) throws -> Affine {
    var result = Affine()
    var rest = Substring(text)
    var seen = 0
    while true {
      rest = rest.drop(while: { $0.isWhitespace || $0 == "," })
      if rest.isEmpty { return result }
      seen += 1
      guard seen <= 8, let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")"),
        open < close
      else { throw SVGLogoError.invalid("the transform") }
      let name = rest[..<open].trimmingCharacters(in: .whitespaces)
      let args = try numbers(String(rest[rest.index(after: open)..<close]), what: "the transform")
      var next = Affine()
      switch (name, args.count) {
      case ("translate", 1): next.e = args[0]
      case ("translate", 2):
        next.e = args[0]
        next.f = args[1]
      case ("scale", 1):
        next.a = args[0]
        next.d = args[0]
      case ("scale", 2):
        next.a = args[0]
        next.d = args[1]
      case ("matrix", 6):
        next = Affine(a: args[0], b: args[1], c: args[2], d: args[3], e: args[4], f: args[5])
      default: throw SVGLogoError.invalid("the transform")
      }
      result = result.concatenating(next)
      rest = rest[rest.index(after: close)...]
    }
  }

  private static func map(_ element: SVGPathElement, _ t: Affine) throws -> SVGPathElement {
    func p(_ point: SVGPoint) throws -> SVGPoint {
      let mapped = t.apply(point)
      guard mapped.x.isFinite, mapped.y.isFinite, abs(mapped.x) <= maxCoordinate * 100,
        abs(mapped.y) <= maxCoordinate * 100
      else { throw SVGLogoError.invalid("the shape") }
      return mapped
    }
    switch element {
    case .move(let a): return .move(try p(a))
    case .line(let a): return .line(try p(a))
    case .quad(let c, let e): return .quad(control: try p(c), end: try p(e))
    case .curve(let c1, let c2, let e):
      return .curve(control1: try p(c1), control2: try p(c2), end: try p(e))
    case .close: return .close
    }
  }

  // MARK: Shapes

  private static let kappa = 0.5522847498307936

  private static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> [SVGPathElement] {
    let kx = rx * kappa
    let ky = ry * kappa
    return [
      .move(SVGPoint(x: cx + rx, y: cy)),
      .curve(
        control1: SVGPoint(x: cx + rx, y: cy + ky), control2: SVGPoint(x: cx + kx, y: cy + ry),
        end: SVGPoint(x: cx, y: cy + ry)),
      .curve(
        control1: SVGPoint(x: cx - kx, y: cy + ry), control2: SVGPoint(x: cx - rx, y: cy + ky),
        end: SVGPoint(x: cx - rx, y: cy)),
      .curve(
        control1: SVGPoint(x: cx - rx, y: cy - ky), control2: SVGPoint(x: cx - kx, y: cy - ry),
        end: SVGPoint(x: cx, y: cy - ry)),
      .curve(
        control1: SVGPoint(x: cx + kx, y: cy - ry), control2: SVGPoint(x: cx + rx, y: cy - ky),
        end: SVGPoint(x: cx + rx, y: cy)),
      .close,
    ]
  }

  private static func rectangle(
    x: Double, y: Double, width: Double, height: Double, rx: Double, ry: Double
  ) -> [SVGPathElement] {
    guard rx > 0, ry > 0 else {
      return [
        .move(SVGPoint(x: x, y: y)), .line(SVGPoint(x: x + width, y: y)),
        .line(SVGPoint(x: x + width, y: y + height)), .line(SVGPoint(x: x, y: y + height)),
        .close,
      ]
    }
    let kx = rx * kappa
    let ky = ry * kappa
    let r = x + width
    let b = y + height
    return [
      .move(SVGPoint(x: x + rx, y: y)),
      .line(SVGPoint(x: r - rx, y: y)),
      .curve(
        control1: SVGPoint(x: r - rx + kx, y: y), control2: SVGPoint(x: r, y: y + ry - ky),
        end: SVGPoint(x: r, y: y + ry)),
      .line(SVGPoint(x: r, y: b - ry)),
      .curve(
        control1: SVGPoint(x: r, y: b - ry + ky), control2: SVGPoint(x: r - rx + kx, y: b),
        end: SVGPoint(x: r - rx, y: b)),
      .line(SVGPoint(x: x + rx, y: b)),
      .curve(
        control1: SVGPoint(x: x + rx - kx, y: b), control2: SVGPoint(x: x, y: b - ry + ky),
        end: SVGPoint(x: x, y: b - ry)),
      .line(SVGPoint(x: x, y: y + ry)),
      .curve(
        control1: SVGPoint(x: x, y: y + ry - ky), control2: SVGPoint(x: x + rx - kx, y: y),
        end: SVGPoint(x: x + rx, y: y)),
      .close,
    ]
  }

  // MARK: Path data

  /// Reads path data into absolute drawing steps. At most `budget` steps are produced.
  static func pathData(_ text: String, budget: Int) throws -> [SVGPathElement] {
    var reader = PathReader(Array(text.utf8))
    var out: [SVGPathElement] = []
    var current = SVGPoint(x: 0, y: 0)
    var start = current
    var lastCubic: SVGPoint?
    var lastQuad: SVGPoint?
    var command: UInt8 = 0
    var first = true
    let bad = SVGLogoError.invalid("the path data")
    func push(_ element: SVGPathElement) throws {
      out.append(element)
      if out.count > budget { throw SVGLogoError.tooComplex }
    }
    reader.skipSeparators()
    while !reader.atEnd {
      if let letter = reader.command() {
        command = letter
        reader.skipSeparators()
      } else if command == 0 || command == UInt8(ascii: "Z") || command == UInt8(ascii: "z") {
        throw bad
      }
      if first {
        guard command == UInt8(ascii: "M") || command == UInt8(ascii: "m") else { throw bad }
        first = false
      }
      let relative = command >= 97
      let base = relative ? current : SVGPoint(x: 0, y: 0)
      var nextCubic: SVGPoint?
      var nextQuad: SVGPoint?
      switch command | 0x20 {
      case UInt8(ascii: "m"):
        let point = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        try push(.move(point))
        current = point
        start = point
        command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
      case UInt8(ascii: "l"):
        current = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        try push(.line(current))
      case UInt8(ascii: "h"):
        current = SVGPoint(x: (relative ? current.x : 0) + (try reader.number()), y: current.y)
        try push(.line(current))
      case UInt8(ascii: "v"):
        current = SVGPoint(x: current.x, y: (relative ? current.y : 0) + (try reader.number()))
        try push(.line(current))
      case UInt8(ascii: "c"):
        let c1 = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        let c2 = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        let end = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        try push(.curve(control1: c1, control2: c2, end: end))
        nextCubic = c2
        current = end
      case UInt8(ascii: "s"):
        let c1 =
          lastCubic.map { SVGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
        let c2 = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        let end = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        try push(.curve(control1: c1, control2: c2, end: end))
        nextCubic = c2
        current = end
      case UInt8(ascii: "q"):
        let c = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        let end = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        try push(.quad(control: c, end: end))
        nextQuad = c
        current = end
      case UInt8(ascii: "t"):
        let c =
          lastQuad.map { SVGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
        let end = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        try push(.quad(control: c, end: end))
        nextQuad = c
        current = end
      case UInt8(ascii: "a"):
        let rx = try reader.number()
        let ry = try reader.number()
        let rotation = try reader.number()
        let large = try reader.flag()
        let sweep = try reader.flag()
        let end = SVGPoint(x: base.x + (try reader.number()), y: base.y + (try reader.number()))
        for element in arc(
          from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
        {
          try push(element)
        }
        current = end
      case UInt8(ascii: "z"):
        try push(.close)
        current = start
      default:
        throw bad
      }
      lastCubic = nextCubic
      lastQuad = nextQuad
      reader.skipSeparators()
    }
    guard !out.isEmpty else { throw bad }
    return out
  }

  private struct PathReader {
    let bytes: [UInt8]
    var index = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }
    var atEnd: Bool { index >= bytes.count }

    mutating func skipSeparators() {
      while index < bytes.count, [32, 9, 10, 13, 44].contains(bytes[index]) { index += 1 }
    }
    mutating func command() -> UInt8? {
      guard index < bytes.count else { return nil }
      let byte = bytes[index]
      guard "MmLlHhVvCcSsQqTtAaZz".utf8.contains(byte) else { return nil }
      index += 1
      return byte
    }
    mutating func flag() throws -> Bool {
      skipSeparators()
      guard index < bytes.count, bytes[index] == 48 || bytes[index] == 49 else {
        throw SVGLogoError.invalid("the path data")
      }
      defer { index += 1 }
      return bytes[index] == 49
    }
    mutating func number() throws -> Double {
      skipSeparators()
      let begin = index
      if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
      var digits = 0
      while index < bytes.count, (48...57).contains(bytes[index]) {
        index += 1
        digits += 1
      }
      if index < bytes.count, bytes[index] == 46 {
        index += 1
        while index < bytes.count, (48...57).contains(bytes[index]) {
          index += 1
          digits += 1
        }
      }
      guard digits > 0 else { throw SVGLogoError.invalid("the path data") }
      if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
        var probe = index + 1
        if probe < bytes.count, bytes[probe] == 43 || bytes[probe] == 45 { probe += 1 }
        if probe < bytes.count, (48...57).contains(bytes[probe]) {
          while probe < bytes.count, (48...57).contains(bytes[probe]) { probe += 1 }
          index = probe
        }
      }
      guard index - begin <= 40,
        let value = Double(String(decoding: bytes[begin..<index], as: UTF8.self)),
        value.isFinite, abs(value) <= SVGLogo.maxCoordinate
      else { throw SVGLogoError.invalid("the path data") }
      return value
    }
  }

  /// An elliptical arc as up to four cubic curves per quarter turn (SVG 1.1 F.6.5).
  private static func arc(
    from p0: SVGPoint, to p1: SVGPoint, rx rawRx: Double, ry rawRy: Double, rotation: Double,
    large: Bool, sweep: Bool
  ) -> [SVGPathElement] {
    var rx = abs(rawRx)
    var ry = abs(rawRy)
    if p0 == p1 { return [] }
    guard rx > 0, ry > 0 else { return [.line(p1)] }
    let phi = rotation * .pi / 180
    let cosPhi = cos(phi)
    let sinPhi = sin(phi)
    let dx = (p0.x - p1.x) / 2
    let dy = (p0.y - p1.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy
    let y1 = -sinPhi * dx + cosPhi * dy
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
      rx *= lambda.squareRoot()
      ry *= lambda.squareRoot()
    }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    guard denominator > 0 else { return [.line(p1)] }
    var factor = (max(numerator, 0) / denominator).squareRoot()
    if large == sweep { factor = -factor }
    let cxp = factor * rx * y1 / ry
    let cyp = -factor * ry * x1 / rx
    let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
    let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2
    func angle(_ ux: Double, _ uy: Double) -> Double { atan2(uy, ux) }
    let theta1 = angle((x1 - cxp) / rx, (y1 - cyp) / ry)
    var delta = angle((-x1 - cxp) / rx, (-y1 - cyp) / ry) - theta1
    if sweep, delta < 0 { delta += 2 * .pi }
    if !sweep, delta > 0 { delta -= 2 * .pi }
    let pieces = max(1, Int((abs(delta) / (.pi / 2) - 1e-9).rounded(.up)))
    let step = delta / Double(pieces)
    let t = 4 / 3 * tan(step / 4)
    var out: [SVGPathElement] = []
    var a = theta1
    for index in 0..<pieces {
      let b = a + step
      func point(_ theta: Double, _ ox: Double, _ oy: Double) -> SVGPoint {
        let x = cos(theta) + ox
        let y = sin(theta) + oy
        return SVGPoint(
          x: cx + rx * x * cosPhi - ry * y * sinPhi, y: cy + rx * x * sinPhi + ry * y * cosPhi)
      }
      let c1 = point(a, -t * sin(a), t * cos(a))
      let c2 = point(b, t * sin(b), -t * cos(b))
      let end = index == pieces - 1 ? p1 : point(b, 0, 0)
      out.append(.curve(control1: c1, control2: c2, end: end))
      a = b
    }
    return out
  }
}
