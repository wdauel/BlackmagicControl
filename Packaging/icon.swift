// Renders the app icon master PNG (1024×1024) in the TechCam aesthetic:
// a dark squircle with a green "aperture" ring, a green center, and an amber
// accent tick. Run: `swift Packaging/icon.swift` → writes Packaging/icon_1024.png
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF)/255, green: CGFloat((hex >> 8) & 0xFF)/255,
            blue: CGFloat(hex & 0xFF)/255, alpha: 1)
}

// Squircle background with a subtle vertical gradient.
let inset = 100.0
let rect = CGRect(x: inset, y: inset, width: size - inset*2, height: size - inset*2)
let corner = 185.0
let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.saveGState()
ctx.addPath(path); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [color(0x303034), color(0x141416)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Hairline border.
ctx.addPath(path)
ctx.setStrokeColor(color(0x3C3C40)); ctx.setLineWidth(4)
ctx.strokePath()

let center = CGPoint(x: size/2, y: size/2)

// Outer thin ring (stroke grey).
ctx.setStrokeColor(color(0x3C3C40)); ctx.setLineWidth(10)
ctx.addArc(center: center, radius: 300, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.strokePath()

// Bold green aperture ring.
ctx.setStrokeColor(color(0x2FB84F)); ctx.setLineWidth(46)
ctx.addArc(center: center, radius: 236, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.strokePath()

// Green center dot.
ctx.setFillColor(color(0x2FB84F))
ctx.addArc(center: center, radius: 72, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.fillPath()

// Amber accent tick at 12 o'clock, sitting on the ring.
ctx.setFillColor(color(0xFFB020))
ctx.addArc(center: CGPoint(x: center.x, y: center.y + 236), radius: 30,
           startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()

let out = URL(fileURLWithPath: "Packaging/icon_1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
