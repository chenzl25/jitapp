import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Assets/AppIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)

let image = NSImage(size: size)
image.lockFocus()

let bg = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.22, alpha: 1.0).setFill()
bg.fill()

let inner = NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 844, height: 844), xRadius: 180, yRadius: 180)
NSColor(calibratedRed: 0.09, green: 0.20, blue: 0.37, alpha: 1.0).setFill()
inner.fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 380),
    .foregroundColor: NSColor(calibratedRed: 0.92, green: 0.98, blue: 1.0, alpha: 1.0),
    .paragraphStyle: paragraph
]

let text = "J" as NSString
text.draw(in: NSRect(x: 0, y: 245, width: 1024, height: 520), withAttributes: attrs)

let dot = NSBezierPath(ovalIn: NSRect(x: 670, y: 315, width: 84, height: 84))
NSColor(calibratedRed: 0.38, green: 0.82, blue: 1.0, alpha: 1.0).setFill()
dot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try png.write(to: url)
print("icon written to \(outputPath)")
