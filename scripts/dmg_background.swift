import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let W: CGFloat = 660
let H: CGFloat = 400

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha)
}

func render(scale: CGFloat, path: String) {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

  NSGraphicsContext.saveGraphicsState()
  let ctx = NSGraphicsContext(bitmapImageRep: rep)!
  NSGraphicsContext.current = ctx
  ctx.cgContext.scaleBy(x: scale, y: scale)

  // Finder draws icon labels black in light mode and white in dark mode,
  // ignoring the background image — only a mid-gray stays readable in both.
  rgb(0x74757A).setFill()
  NSRect(x: 0, y: 0, width: W, height: H).fill()

  let accent = rgb(0x2D7AD4)
  accent.setStroke()
  let shaft = NSBezierPath()
  shaft.lineWidth = 5
  shaft.lineCapStyle = .round
  shaft.move(to: NSPoint(x: 255, y: 215))
  shaft.line(to: NSPoint(x: 385, y: 215))
  shaft.stroke()

  accent.setFill()
  let head = NSBezierPath()
  head.move(to: NSPoint(x: 408, y: 215))
  head.line(to: NSPoint(x: 383, y: 228))
  head.line(to: NSPoint(x: 383, y: 202))
  head.close()
  head.fill()

  let label = "DRAG TO INSTALL" as NSString
  let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
    .foregroundColor: rgb(0xF2F2F3),
    .kern: 2.5,
  ]
  let size = label.size(withAttributes: attrs)
  label.draw(at: NSPoint(x: (W - size.width) / 2, y: 136), withAttributes: attrs)

  NSGraphicsContext.restoreGraphicsState()

  rep.size = NSSize(width: W, height: H)
  try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: path))
}

render(scale: 1, path: outDir + "/bg1x.png")
render(scale: 2, path: outDir + "/bg2x.png")
