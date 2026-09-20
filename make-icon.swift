import AppKit

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.13, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 216, yRadius: 216).fill()
let teal = NSColor(calibratedRed: 0.30, green: 0.87, blue: 0.74, alpha: 1)
teal.withAlphaComponent(0.12).setFill()
NSBezierPath(roundedRect: NSRect(x: 246, y: 246, width: 532, height: 532), xRadius: 84, yRadius: 84).fill()
teal.setStroke()
let chip = NSBezierPath(roundedRect: NSRect(x: 266, y: 266, width: 492, height: 492), xRadius: 62, yRadius: 62)
chip.lineWidth = 30
chip.stroke()
for offset in stride(from: 354, through: 672, by: 106) {
    for pair in [(NSPoint(x: offset, y: 210), NSPoint(x: offset, y: 266)), (NSPoint(x: offset, y: 758), NSPoint(x: offset, y: 814)), (NSPoint(x: 210, y: offset), NSPoint(x: 266, y: offset)), (NSPoint(x: 758, y: offset), NSPoint(x: 814, y: offset))] {
        let pin = NSBezierPath(); pin.move(to: pair.0); pin.line(to: pair.1); pin.lineWidth = 26; pin.lineCapStyle = .round; pin.stroke()
    }
}
let trace = NSBezierPath()
trace.move(to: NSPoint(x: 352, y: 474))
for point in [NSPoint(x: 425, y: 474), NSPoint(x: 475, y: 615), NSPoint(x: 545, y: 399), NSPoint(x: 596, y: 535), NSPoint(x: 672, y: 535)] { trace.line(to: point) }
trace.lineWidth = 32; trace.lineCapStyle = .round; trace.lineJoinStyle = .round; trace.stroke()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
