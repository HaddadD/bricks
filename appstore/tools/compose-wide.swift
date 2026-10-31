// Lays a real capture (appstore/raw/) into a landscape App Store screenshot in the same
// style as the iPhone and iPad set: a pastel sky, floating glossy bricks, the headline
// and subtitle across the top, and the capture below in a frame for its platform.
//
//   swiftc -O appstore/tools/compose-wide.swift -o /tmp/compose-wide
//   /tmp/compose-wide <raw.png> <mac|tv|vision|duo> <width> <height> <sky hex> <headline> <subtitle> <out.png>
//
// The art is drawn here rather than generated, so it needs nothing beyond Xcode.
import AppKit

let a = CommandLine.arguments
guard a.count == 9, let raw = NSImage(contentsOfFile: a[1]), let W = Int(a[3]), let H = Int(a[4]),
      let sky = UInt32(a[5], radix: 16) else {
    print("usage: compose-wide <raw.png> <mac|tv|vision|duo> <width> <height> <sky hex> <headline> <subtitle> <out.png>")
    exit(1)
}
let kind = a[2], headline = a[6], subtitle = a[7]
let w = CGFloat(W), h = CGFloat(H)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: font.fontDescriptor.withDesign(.rounded)!, size: size)!
}

func text(_ s: String, _ font: NSFont, _ c: NSColor, centerX: CGFloat, top: CGFloat) -> CGFloat {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .paragraphStyle: p])
    let size = str.boundingRect(with: NSSize(width: w * 0.9, height: h), options: [.usesLineFragmentOrigin]).size
    str.draw(in: NSRect(x: centerX - w * 0.45, y: top - size.height, width: w * 0.9, height: size.height))
    return size.height
}

/// A glossy brick like the iPad art's: face gradient, darker bevel, highlight, soft shadow.
func brick(center: NSPoint, side: CGFloat, angle: CGFloat, face: UInt32, shade: UInt32) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.rotate(byDegrees: angle)
    t.concat()
    let r = NSRect(x: -side / 2, y: -side / 2, width: side, height: side)
    let corner = side * 0.24
    let shadow = NSShadow()
    shadow.shadowColor = color(shade).blended(withFraction: 0.4, of: .black)!.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = side * 0.18
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.08)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(shade).setFill()
    NSBezierPath(roundedRect: r, xRadius: corner, yRadius: corner).fill()
    NSGraphicsContext.restoreGraphicsState()
    let faceRect = NSRect(x: r.minX, y: r.minY + side * 0.1, width: side, height: side * 0.9)
    NSGradient(starting: color(face).blended(withFraction: 0.25, of: .white)!, ending: color(face))!
        .draw(in: NSBezierPath(roundedRect: faceRect, xRadius: corner, yRadius: corner), angle: -90)
    let bar = NSRect(x: r.minX + side * 0.16, y: r.maxY - side * 0.22, width: side * 0.68, height: side * 0.08)
    color(0xFFFFFF, 0.55).setFill()
    NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
}

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// Sky: the shot's colour at the top fading to the near-white foot.
NSGradient(colors: [color(sky).blended(withFraction: 0.35, of: .white)!, color(0xFBF7FB), color(0xF6EEF8)],
           atLocations: [0, 0.62, 1], colorSpace: .sRGB)!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)

// Floating bricks around the edges, in Theme's palette.
let palette: [(UInt32, UInt32)] = [(0xFFA8C5, 0xE98BA9), (0x8FDDE7, 0x74C2CC), (0xC8AEF0, 0xAD93D5),
                                   (0xF3DE84, 0xDCC46A), (0xA8E6B8, 0x8DCB9D), (0xFFB59E, 0xE99A82)]
let spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [   // x, y (fractions), size (of h), angle
    (0.06, 0.80, 0.12, -14), (0.94, 0.82, 0.11, 12), (0.04, 0.36, 0.10, 10),
    (0.96, 0.40, 0.12, -10), (0.10, 0.08, 0.09, 18), (0.90, 0.07, 0.10, -16),
]
for (i, s) in spots.enumerated() {
    let p = palette[i % palette.count]
    brick(center: NSPoint(x: w * s.0, y: h * s.1), side: h * s.2, angle: s.3, face: p.0, shade: p.1)
}

// Headline and subtitle.
let ink = color(0x3B2A35), soft = color(0x7A6A88)
// Sized to the height on landscape shots; a portrait one (the Duo) scales them down to fit across.
let type = min(1, w / h / 1.1)
var top = h * 0.95
top -= text(headline, rounded(h * 0.085 * type, .black), ink, centerX: w / 2, top: top)
top -= h * 0.005
top -= text(subtitle, rounded(h * 0.04 * type, .semibold), soft, centerX: w / 2, top: top)

// The capture, below the words.
let bottomMargin = h * 0.05
let maxH = top - h * 0.04 - bottomMargin
var source = raw
if kind == "vision" {
    // Vision Pro captures show a whole room; keep the window and a little of the room.
    let full = raw.size
    let crop = NSRect(x: full.width * 0.19, y: full.height * 0.14, width: full.width * 0.62, height: full.height * 0.62)
    source = NSImage(size: crop.size, flipped: false) { r in
        raw.draw(in: r, from: crop, operation: .copy, fraction: 1)
        return true
    }
}
let aspect = source.size.width / source.size.height
var shotH = maxH, shotW = maxH * aspect
if shotW > w * 0.8 { shotW = w * 0.8; shotH = shotW / aspect }
// Apple TV and iPhone Duo sit in a dark bezel, like the hardware.
let bezel: CGFloat = kind == "tv" ? h * 0.014 : kind == "duo" ? h * 0.01 : 0
let frame = NSRect(x: (w - shotW) / 2, y: bottomMargin + (maxH - shotH) / 2, width: shotW, height: shotH)
let outer = frame.insetBy(dx: -bezel, dy: -bezel)
let radius: CGFloat = kind == "mac" ? h * 0.012 : kind == "duo" ? h * 0.03 : h * 0.02

let shadow = NSShadow()
shadow.shadowColor = color(0x3B2A35, 0.28)
shadow.shadowBlurRadius = h * 0.04
shadow.shadowOffset = NSSize(width: 0, height: -h * 0.012)
NSGraphicsContext.saveGraphicsState()
shadow.set()
(kind == "tv" || kind == "duo" ? color(0x1C1A20) : color(0xFFFFFF)).setFill()
NSBezierPath(roundedRect: outer, xRadius: radius + bezel, yRadius: radius + bezel).fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
source.draw(in: frame)
NSGraphicsContext.restoreGraphicsState()

let url = URL(fileURLWithPath: a[8])
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
