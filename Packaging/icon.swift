// Builds the app icon master PNG (1024×1024) from the user-supplied artwork
// `Packaging/IMG_0530.png` (a "BMC CTRL" photo). The source is neither square
// nor 1024px, so we:
//   • mask to the standard macOS rounded-icon squircle (transparent margin),
//   • aspect-FILL a background copy to cover the squircle with matching tones,
//   • aspect-FIT the full image on top so no lettering is cropped.
// Run: `swift Packaging/icon.swift` → writes Packaging/icon_1024.png
import AppKit
import CoreImage

let SRC = "Packaging/IMG_0530.png"
let size: CGFloat = 1024

guard let srcImage = NSImage(contentsOfFile: SRC),
      let rawCG = srcImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("error: could not load \(SRC)\n", stderr); exit(1)
}

// Sharpen contrast: the artwork is dark-on-dark, so pivot around mid-gray to
// lift the background and deepen the ink, then add a touch of unsharp mask.
let ciCtx = CIContext()
var ci = CIImage(cgImage: rawCG)
ci = ci.applyingFilter("CIColorControls", parameters: [
    kCIInputContrastKey: 1.18,     // gentle lift, keeps midtones intact
    kCIInputBrightnessKey: 0.05,
    kCIInputSaturationKey: 0.35     // pull most of the red out toward neutral grey
])
ci = ci.applyingFilter("CIUnsharpMask", parameters: [
    kCIInputRadiusKey: 2.0,
    kCIInputIntensityKey: 0.45
])
guard let cg = ciCtx.createCGImage(ci, from: ci.extent) else {
    fputs("error: contrast pass failed\n", stderr); exit(1)
}
let iw = CGFloat(cg.width), ih = CGFloat(cg.height)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Standard macOS icon proportions: art within an inset squircle, transparent margin.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset*2, height: size - inset*2)
let corner: CGFloat = 185
let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.addPath(squircle); ctx.clip()

// Helper: draw the source scaled by `mode` ("fill" = cover, "fit" = contain), centered in `rect`.
func draw(_ mode: String) {
    let scale = mode == "fill" ? max(rect.width/iw, rect.height/ih)
                               : min(rect.width/iw, rect.height/ih)
    let w = iw*scale, h = ih*scale
    let x = rect.midX - w/2, y = rect.midY - h/2
    ctx.draw(cg, in: CGRect(x: x, y: y, width: w, height: h))
}
draw("fill")   // background fills the squircle (edges cropped)
draw("fit")    // full artwork on top (nothing cropped)

// Hairline border to seat it on light backgrounds.
ctx.addPath(squircle)
ctx.setStrokeColor(CGColor(red: 0.24, green: 0.24, blue: 0.25, alpha: 0.6)); ctx.setLineWidth(4)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()

let out = URL(fileURLWithPath: "Packaging/icon_1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path) from \(SRC)")
