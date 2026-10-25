import XCTest

@testable import PayroofWallet

final class SVGLogoTests: XCTestCase {
  private func svg(_ body: String, root: String = "viewBox=\"0 0 32 32\"") -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" \(root)>\(body)</svg>"
  }

  private struct Bounds {
    var minX = Double.infinity
    var minY = Double.infinity
    var maxX = -Double.infinity
    var maxY = -Double.infinity
  }

  /// The box around every point a layer's path visits, control points included.
  private func bounds(_ layer: SVGLayer) -> Bounds {
    var box = Bounds()
    func add(_ p: SVGPoint) {
      box.minX = min(box.minX, p.x)
      box.maxX = max(box.maxX, p.x)
      box.minY = min(box.minY, p.y)
      box.maxY = max(box.maxY, p.y)
    }
    for element in layer.elements {
      switch element {
      case .move(let p), .line(let p): add(p)
      case .quad(let c, let e):
        add(c)
        add(e)
      case .curve(let c1, let c2, let e):
        add(c1)
        add(c2)
        add(e)
      case .close: break
      }
    }
    return box
  }

  private func firstLayer(_ body: String) throws -> SVGLayer {
    try XCTUnwrap(try SVGLogo.parse(svg(body)).layers.first)
  }

  // MARK: Parsing

  func testViewBoxAndSimplePath() throws {
    let image = try SVGLogo.parse(svg(#"<path d="M4 4H28V28H4Z"/>"#))
    XCTAssertEqual(image.width, 32)
    XCTAssertEqual(image.height, 32)
    XCTAssertEqual(image.layers.count, 1)
    XCTAssertEqual(
      image.layers[0].elements,
      [
        .move(SVGPoint(x: 4, y: 4)), .line(SVGPoint(x: 28, y: 4)),
        .line(SVGPoint(x: 28, y: 28)), .line(SVGPoint(x: 4, y: 28)), .close,
      ])
  }

  func testRelativeAndAbsoluteCommandsAgree() throws {
    let absolute = try firstLayer(#"<path d="M2 3L10 3L10 9Q12 12 8 14C6 16 4 16 2 14Z"/>"#)
    let relative = try firstLayer(#"<path d="m2 3l8 0l0 6q2 3 -2 5c-2 2 -4 2 -6 0z"/>"#)
    XCTAssertEqual(absolute.elements, relative.elements)
  }

  func testHorizontalVerticalAndImplicitRepeats() throws {
    let layer = try firstLayer(#"<path d="M1 1h4v4H1zM10 10 12 10 12 12"/>"#)
    let box = bounds(layer)
    XCTAssertEqual(box.minX, 1)
    XCTAssertEqual(box.maxX, 12)
    XCTAssertEqual(box.maxY, 12)
    XCTAssertTrue(layer.elements.contains(.line(SVGPoint(x: 12, y: 12))))
  }

  func testNumbersWithoutSeparators() throws {
    let layer = try firstLayer(#"<path d="M.5.5L1.5-2.5-1e0 3"/>"#)
    XCTAssertEqual(layer.elements.first, .move(SVGPoint(x: 0.5, y: 0.5)))
    XCTAssertTrue(layer.elements.contains(.line(SVGPoint(x: 1.5, y: -2.5))))
    XCTAssertTrue(layer.elements.contains(.line(SVGPoint(x: -1, y: 3))))
  }

  func testSmoothCurvesReflectControlPoints() throws {
    let layer = try firstLayer(#"<path d="M0 0C0 4 4 4 4 0S8 -4 8 0T12 0"/>"#)
    XCTAssertTrue(
      layer.elements.contains(
        .curve(
          control1: SVGPoint(x: 4, y: -4), control2: SVGPoint(x: 8, y: -4),
          end: SVGPoint(x: 8, y: 0))))
  }

  func testArcBecomesCurvesWithinItsBounds() throws {
    // Half circle of radius 6 from (10,16) to (22,16), sweeping over the top.
    let layer = try firstLayer(#"<path d="M10 16A6 6 0 0 1 22 16Z"/>"#)
    XCTAssertFalse(layer.elements.isEmpty)
    for element in layer.elements {
      if case .curve = element { continue }
      if case .move = element { continue }
      if case .line = element { continue }
      if case .close = element { continue }
      XCTFail("Arcs must be converted to curves")
    }
    let box = bounds(layer)
    XCTAssertEqual(box.minX, 10, accuracy: 0.01)
    XCTAssertEqual(box.maxX, 22, accuracy: 0.01)
    XCTAssertLessThan(box.minY, 11)
    XCTAssertGreaterThan(box.minY, 9)
    XCTAssertEqual(box.maxY, 16, accuracy: 0.01)
  }

  func testArcSweepAndRelativeForm() throws {
    let over = bounds(try firstLayer(#"<path d="M10 16A6 6 0 0 1 22 16"/>"#))
    let under = bounds(try firstLayer(#"<path d="M10 16A6 6 0 0 0 22 16"/>"#))
    XCTAssertLessThan(over.minY, 12)
    XCTAssertGreaterThan(under.maxY, 20)
    let relative = bounds(try firstLayer(#"<path d="m10 16a6 6 0 0 1 12 0"/>"#))
    XCTAssertEqual(relative.minY, over.minY, accuracy: 0.001)
    XCTAssertEqual(relative.maxX, 22, accuracy: 0.001)
  }

  func testLargeArcFlagAndPackedFlags() throws {
    let small = bounds(try firstLayer(#"<path d="M20 16A6 6 0 0 1 16 22"/>"#))
    let large = bounds(try firstLayer(#"<path d="M20 16A6 6 0 1 1 16 22"/>"#))
    XCTAssertGreaterThan(large.maxX - large.minX, small.maxX - small.minX)
    // Flags written without separators: "0 1" as "01".
    let packed = bounds(try firstLayer(#"<path d="M10 16A6 6 0 0122 16"/>"#))
    XCTAssertEqual(packed.maxX, 22, accuracy: 0.01)
  }

  func testArcWithTooSmallRadiusIsScaledUp() throws {
    let box = bounds(try firstLayer(#"<path d="M0 0A1 1 0 0 1 20 0"/>"#))
    XCTAssertEqual(box.maxX, 20, accuracy: 0.01)
    XCTAssertTrue(box.minY.isFinite && box.maxY.isFinite)
  }

  func testRotatedEllipticalArc() throws {
    let layer = try firstLayer(#"<path d="M4 16A12 4 45 0 1 28 16"/>"#)
    XCTAssertEqual(layer.elements.first, .move(SVGPoint(x: 4, y: 16)))
    guard case .curve(_, _, let end)? = layer.elements.last else {
      return XCTFail("The arc should end in a curve")
    }
    XCTAssertEqual(end.x, 28, accuracy: 0.001)
    XCTAssertEqual(end.y, 16, accuracy: 0.001)
    let box = bounds(layer)
    XCTAssertTrue(box.minX.isFinite && box.maxX.isFinite && box.minY.isFinite)
  }

  func testShapes() throws {
    let circle = bounds(try firstLayer(#"<circle cx="16" cy="16" r="10"/>"#))
    XCTAssertEqual(circle.minX, 6, accuracy: 0.01)
    XCTAssertEqual(circle.maxX, 26, accuracy: 0.01)
    XCTAssertEqual(circle.minY, 6, accuracy: 0.01)
    XCTAssertEqual(circle.maxY, 26, accuracy: 0.01)
    let ellipse = bounds(try firstLayer(#"<ellipse cx="16" cy="16" rx="12" ry="6"/>"#))
    XCTAssertEqual(ellipse.minX, 4, accuracy: 0.01)
    XCTAssertEqual(ellipse.maxY, 22, accuracy: 0.01)
    let rect = bounds(try firstLayer(#"<rect x="2" y="3" width="10" height="20"/>"#))
    XCTAssertEqual(rect.minX, 2)
    XCTAssertEqual(rect.maxX, 12)
    XCTAssertEqual(rect.maxY, 23)
    let rounded = try firstLayer(#"<rect x="0" y="0" width="10" height="10" rx="2"/>"#)
    XCTAssertGreaterThan(rounded.elements.count, 5)
    let polygon = try firstLayer(#"<polygon points="0,0 10,0 5,8"/>"#)
    XCTAssertEqual(polygon.elements.last, .close)
    XCTAssertEqual(bounds(polygon).maxY, 8)
  }

  func testTransformsAreApplied() throws {
    let moved = bounds(
      try firstLayer(#"<g transform="translate(10 20)"><path d="M0 0H4V4Z"/></g>"#))
    XCTAssertEqual(moved.minX, 10)
    XCTAssertEqual(moved.maxX, 14)
    XCTAssertEqual(moved.maxY, 24)
    let scaled = bounds(try firstLayer(#"<path transform="scale(2)" d="M1 1H3V3Z"/>"#))
    XCTAssertEqual(scaled.minX, 2)
    XCTAssertEqual(scaled.maxX, 6)
    let matrix = bounds(
      try firstLayer(#"<path transform="matrix(1 0 0 1 5 6)" d="M0 0H2V2Z"/>"#))
    XCTAssertEqual(matrix.minX, 5)
    XCTAssertEqual(matrix.maxY, 8)
    // Nested groups compose.
    let nested = bounds(
      try firstLayer(
        #"<g transform="translate(1 1)"><g transform="scale(3)"><path d="M0 0H1V1Z"/></g></g>"#))
    XCTAssertEqual(nested.minX, 1)
    XCTAssertEqual(nested.maxX, 4)
  }

  func testFillColorsOpacityAndFillRule() throws {
    let image = try SVGLogo.parse(
      svg(
        ##"<g fill="#ff0000"><path d="M0 0H4V4Z"/><path fill="#00f" fill-rule="evenodd" opacity="0.5" d="M0 0H4V4Z"/></g>"##
      ))
    XCTAssertEqual(image.layers.count, 2)
    XCTAssertEqual(image.layers[0].color, SVGColor(red: 1, green: 0, blue: 0))
    XCTAssertFalse(image.layers[0].evenOdd)
    XCTAssertEqual(image.layers[1].color, SVGColor(red: 0, green: 0, blue: 1))
    XCTAssertTrue(image.layers[1].evenOdd)
    XCTAssertEqual(image.layers[1].opacity, 0.5, accuracy: 0.001)
  }

  func testDefaultFillIsBlackAndFillNoneDrawsNothing() throws {
    let plain = try firstLayer(#"<path d="M0 0H4V4Z"/>"#)
    XCTAssertEqual(plain.color, SVGColor(red: 0, green: 0, blue: 0))
    XCTAssertThrowsError(try SVGLogo.parse(svg(#"<path fill="none" d="M0 0H4V4Z"/>"#)))
  }

  func testWidthHeightWithoutViewBox() throws {
    let image = try SVGLogo.parse(
      svg(#"<path d="M0 0H4V4Z"/>"#, root: #"width="24" height="12""#))
    XCTAssertEqual(image.width, 24)
    XCTAssertEqual(image.height, 12)
  }

  // MARK: Validation

  func testRefusesUnsafeElementsAndAttributes() {
    let refused = [
      svg("<script>alert(1)</script><path d=\"M0 0H4V4Z\"/>"),
      svg(#"<image href="https://example.com/a.png" width="8" height="8"/>"#),
      svg(##"<path d="M0 0H4V4Z"/><use href="#a"/>"##),
      svg(#"<path d="M0 0H4V4Z"/><foreignObject><div/></foreignObject>"#),
      svg(#"<path d="M0 0H4V4Z"/><text x="1" y="1">Hi</text>"#),
      svg(#"<path d="M0 0H4V4Z"/><style>path{fill:red}</style>"#),
      svg(#"<path d="M0 0H4V4Z" onload="alert(1)"/>"#),
      svg(#"<path d="M0 0H4V4Z" style="fill:red"/>"#),
      svg(#"<path d="M0 0H4V4Z" xlink:href="http://example.com/x"/>"#),
      svg(#"<path d="M0 0H4V4Z" href="http://example.com/x"/>"#),
      svg(#"<path d="M0 0H4V4Z" fill="url(#g)"/>"#),
      svg(#"<a href="https://example.com"><path d="M0 0H4V4Z"/></a>"#),
      svg(#"<linearGradient id="g"/><path d="M0 0H4V4Z"/>"#),
    ]
    for source in refused {
      XCTAssertFalse(SVGLogo.isValid(source), source)
      XCTAssertNotNil(SVGLogo.problem(source), source)
    }
  }

  func testRefusesWrongRootAndDoctype() {
    XCTAssertEqual(
      SVGLogo.problem("<html><path d=\"M0 0H4V4Z\"/></html>"),
      SVGLogoError.notSVG.errorDescription)
    let entity = """
      <!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]>\
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><path d="M0 0H4V4Z"/></svg>
      """
    XCTAssertFalse(SVGLogo.isValid(entity))
  }

  func testRefusesOversizeInput() {
    let long = String(repeating: "M0 0H1V1Z", count: 4000)
    let source = svg("<path d=\"\(long)\"/>")
    XCTAssertGreaterThan(source.utf8.count, SVGLogo.maxBytes)
    XCTAssertThrowsError(try SVGLogo.parse(source)) {
      XCTAssertEqual($0 as? SVGLogoError, .tooLarge)
    }
  }

  func testRefusesExcessiveWork() {
    let many = String(repeating: #"<path d="M0 0H1V1Z"/>"#, count: 500)
    XCTAssertFalse(SVGLogo.isValid(svg(many)))
    var deep = svg("<path d=\"M0 0H4V4Z\"/>")
    for _ in 0..<40 { deep = deep.replacingOccurrences(of: "<path", with: "<g><path") }
    XCTAssertFalse(SVGLogo.isValid(deep))
  }

  func testMalformedInputNeverCrashes() {
    let inputs = [
      "", " ", "<", "<svg", "<svg>", "</svg>", "not xml", "<svg/>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M\"/></svg>",
      svg(#"<path d="M0 0L"/>"#), svg(#"<path d="L1 1"/>"#),
      svg(#"<path d="M0 0A6 6 0 2 1 4 4"/>"#),
      svg(#"<path d="M0 0H1e999V1Z"/>"#), svg(#"<path d="M0 0H nan V1Z"/>"#),
      svg(#"<path d="M0 0H99999999999999999999999V1Z"/>"#),
      svg(#"<path d="M0 0Z Z Z Q"/>"#),
      svg(#"<circle cx="1" cy="1" r="-5"/>"#), svg(#"<rect width="-1" height="4"/>"#),
      svg(#"<path transform="scale(" d="M0 0H4V4Z"/>"#),
      svg(#"<path transform="matrix(1 2 3)" d="M0 0H4V4Z"/>"#),
      svg(#"<path transform="rotate(1e400)" d="M0 0H4V4Z"/>"#),
      svg(#"<polygon points="1,2,3"/>"#),
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 0 0\"><path d=\"M0 0H4V4Z\"/></svg>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"a b c d\"><path d=\"M0 0H4V4Z\"/></svg>",
      String(repeating: "<", count: 5000), "\u{0}\u{1}\u{2}", "<svg>\u{FFFE}</svg>",
    ]
    for input in inputs {
      _ = SVGLogo.problem(input)
      _ = SVGLogo.image(input)
    }
  }
}
