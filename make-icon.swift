import AppKit

// A four-segment GPU mark, drawn as vectors so every icon size stays crisp.
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 212, yRadius: 212)
NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.22, blue: 0.26, alpha: 1),
           ending: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1))!.draw(in: tile, angle: -90)
NSColor.white.withAlphaComponent(0.10).setStroke()
tile.lineWidth = 2
tile.stroke()
let center = NSPoint(x: 512, y: 512)
let colors = [NSColor(srgbRed: 0.40, green: 0.62, blue: 1, alpha: 1),
              NSColor(white: 0.96, alpha: 1), NSColor(white: 0.72, alpha: 1), NSColor(white: 0.86, alpha: 1)]
for index in 0..<4 {
    let start = 90 - Double(index) * 90
    let wedge = NSBezierPath()
    wedge.move(to: center)
    wedge.appendArc(withCenter: center, radius: 286, startAngle: start, endAngle: start - 90, clockwise: true)
    wedge.close()
    colors[index].setFill()
    wedge.fill()
}
// Match the menu bar's clockwise four-GPU map with clear separation.
NSColor(srgbRed: 0.15, green: 0.17, blue: 0.20, alpha: 1).setStroke()
for angle in [0.0, 90, 180, 270] {
    let line = NSBezierPath()
    line.move(to: center)
    line.line(to: NSPoint(x: center.x + 288 * cos(angle * .pi / 180), y: center.y + 288 * sin(angle * .pi / 180)))
    line.lineWidth = 22
    line.stroke()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
