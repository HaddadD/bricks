// Draws the App Store's creative assets for iPhone and iPad (iOS 27): the product page
// header (21:9, 3840x1646) and the search results card (3:2, 3840x2560). Both use the
// same pastel sky and glossy bricks as the screenshots, with the game itself taken from
// the 4K Apple TV capture (appstore/raw/tv-1.png), which is the wide layout at its
// crispest. The text and the game stay in the middle, where every crop keeps them.
//
//   swiftc -O appstore/tools/compose-creative.swift -o /tmp/compose-creative
//   /tmp/compose-creative <tv-1.png> <header|search> <out.png>
import AppKit

let a = CommandLine.arguments
guard a.count == 4, let raw = NSImage(contentsOfFile: a[1]), ["header", "search"].contains(a[2]) else {
    print("usage: compose-creative <tv-1.png> <header|search> <out.png>")
    exit(1)
}
let header = a[2] == "header"
let W = 3840, H = header ? 1646 : 2560
let w = CGFloat(W), h = CGFloat(H)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: font.fontDescriptor.withDesign(.rounded)!, size: size)!
}

/// Draws `s` in a box of `width` with its top at `top`; returns the height used.
@discardableResult
func text(_ s: String, _ font: NSFont, _ c: NSColor, x: CGFloat, top: CGFloat, width: CGFloat,
          align: NSTextAlignment) -> CGFloat {
    let p = NSMutableParagraphStyle()
    p.alignment = align
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .paragraphStyle: p])
    let size = str.boundingRect(with: NSSize(width: width, height: h), options: [.usesLineFragmentOrigin]).size
    str.draw(in: NSRect(x: x, y: top - size.height, width: width, height: size.height))
    return size.height
}

/// The game's wordmark: BRICKS! in the app's pink-to-periwinkle gradient.
func wordmark(_ size: CGFloat, x: CGFloat, top: CGFloat) -> CGFloat {
    let font = rounded(size, .black)
    let str = NSAttributedString(string: "BRICKS!", attributes: [.font: font])
    let bounds = str.boundingRect(with: NSSize(width: w, height: h), options: [.usesLineFragmentOrigin])
    let rect = NSRect(x: x, y: top - bounds.height, width: bounds.width, height: bounds.height)
    let mask = NSImage(size: rect.size, flipped: false) { r in
        str.draw(in: r)
        return true
    }
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.clip(to: rect, mask: mask.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    NSGradient(starting: color(0xF08FB4), ending: color(0xA6BDF7))!.draw(in: rect, angle: 0)
    NSGraphicsContext.restoreGraphicsState()
    return bounds.height
}

/// A glossy brick like the screenshots': face gradient, darker bevel, highlight, soft shadow.
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

// Sky: blush at the top fading to the near-white foot, as in the first screenshot.
NSGradient(colors: [color(0xFFA3C6).blended(withFraction: 0.45, of: .white)!, color(0xFBF7FB), color(0xEFE6F8)],
           atLocations: [0, 0.6, 1], colorSpace: .sRGB)!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)

// Floating bricks out by the edges, in Theme's palette.
let palette: [(UInt32, UInt32)] = [(0xFFA8C5, 0xE98BA9), (0x8FDDE7, 0x74C2CC), (0xC8AEF0, 0xAD93D5),
                                   (0xF3DE84, 0xDCC46A), (0xA8E6B8, 0x8DCB9D), (0xFFB59E, 0xE99A82)]
let spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = header
    ? [(0.05, 0.78, 0.16, -14), (0.955, 0.80, 0.14, 12), (0.10, 0.22, 0.13, 10),
       (0.955, 0.24, 0.14, -10), (0.30, 0.10, 0.09, 18), (0.36, 0.90, 0.08, -16)]
    : [(0.07, 0.86, 0.10, -14), (0.93, 0.88, 0.09, 12), (0.05, 0.42, 0.08, 10),
       (0.95, 0.46, 0.10, -10), (0.11, 0.09, 0.07, 18), (0.89, 0.08, 0.08, -16)]
for (i, s) in spots.enumerated() {
    let p = palette[i % palette.count]
    brick(center: NSPoint(x: w * s.0, y: h * s.1), side: h * s.2, angle: s.3, face: p.0, shade: p.1)
}

// The game: board, tray and power-ups from the Apple TV capture, without the header row
// or the version stamp.
let full = raw.size
let crop = NSRect(x: full.width * 0.205, y: full.height * (1 - 0.896), width: full.width * 0.59, height: full.height * 0.715)
let game = NSImage(size: crop.size, flipped: false) { r in
    raw.draw(in: r, from: crop, operation: .copy, fraction: 1)
    return true
}

func place(_ image: NSImage, in frame: NSRect) {
    let radius = frame.height * 0.04
    let shadow = NSShadow()
    shadow.shadowColor = color(0x3B2A35, 0.22)
    shadow.shadowBlurRadius = frame.height * 0.05
    shadow.shadowOffset = NSSize(width: 0, height: -frame.height * 0.015)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0xFBF7F4).setFill()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
}

let ink = color(0x3B2A35), soft = color(0x7A6A88)
let aspect = game.size.width / game.size.height

if header {
    // Words on the left, the game on the right, both inside the middle 70%.
    let gameH = h * 0.74
    let gameW = gameH * aspect
    let gap = w * 0.04
    let words = w * 0.27
    let left = (w - words - gap - gameW) / 2
    place(game, in: NSRect(x: left + words + gap, y: (h - gameH) / 2, width: gameW, height: gameH))

    var top = h * 0.70
    top -= wordmark(h * 0.115, x: left, top: top)
    top -= h * 0.02
    top -= text("Drop. Fill. Clear.", rounded(h * 0.075, .black), ink, x: left, top: top, width: words, align: .left)
    top -= h * 0.015
    text("A calm pastel block puzzle on every Apple device", rounded(h * 0.038, .semibold), soft,
         x: left, top: top, width: words, align: .left)
} else {
    // Headline across the top, the game underneath.
    var top = h * 0.93
    top -= text("Drop. Fill. Clear.", rounded(h * 0.085, .black), ink, x: w * 0.05, top: top, width: w * 0.9, align: .center)
    top -= h * 0.005
    top -= text("A calm pastel block puzzle", rounded(h * 0.042, .semibold), soft, x: w * 0.05, top: top, width: w * 0.9, align: .center)
    let gameH = top - h * 0.05 - h * 0.07
    let gameW = gameH * aspect
    place(game, in: NSRect(x: (w - gameW) / 2, y: h * 0.07, width: gameW, height: gameH))
}

let url = URL(fileURLWithPath: a[3])
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
