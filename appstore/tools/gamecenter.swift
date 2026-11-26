// Game Center artwork and catalog, from the same list the app reports against
// (BRICKS/Achievements.swift):
//
//   swiftc -O BRICKS/Achievements.swift appstore/tools/gamecenter.swift -o /tmp/gamecenter
//   /tmp/gamecenter render appstore/gamecenter     # every badge and banner as PNG
//   /tmp/gamecenter catalog > catalog.json         # names, points, ids, image paths
//
// appstore/tools/gamecenter-setup.py turns the catalog into App Store Connect records.
// Badges are the game's brick (Theme's palette, BrickView's bevel and highlight) holding
// an SF Symbol, on the brick's own colour; Game Center crops them to a circle, so
// everything sits inside the middle.
import AppKit

let cream: UInt32 = 0xFFFBF7

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// `hex` darkened towards black, for symbols and labels that need contrast on cream.
func deep(_ hex: UInt32, _ amount: CGFloat = 0.35) -> NSColor {
    color(hex).blended(withFraction: amount, of: .black)!
}

/// Draws with AppKit into an opaque sRGB bitmap (App Store Connect rejects artwork with
/// transparency) and saves it as PNG.
func png(_ w: Int, _ h: Int, _ path: String, _ draw: () -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
}

func background(_ rect: NSRect, _ name: String) {
    let (face, shade) = Achievement.palette[name]!
    NSGradient(starting: color(face).blended(withFraction: 0.25, of: .white)!, ending: color(shade))!
        .draw(in: rect, angle: -90)
    // The board's grid, faintly.
    let cell = rect.height / 8
    for row in 0..<Int(rect.height / cell) + 1 {
        for col in 0..<Int(rect.width / cell) + 1 {
            let r = NSRect(x: rect.minX + CGFloat(col) * cell, y: rect.minY + CGFloat(row) * cell, width: cell, height: cell)
                .insetBy(dx: cell * 0.06, dy: cell * 0.06)
            color(0xFFFFFF, 0.09).setFill()
            NSBezierPath(roundedRect: r, xRadius: cell * 0.2, yRadius: cell * 0.2).fill()
        }
    }
}

/// BrickView's brick in cream: a shade bevel along the bottom, the face, a highlight bar.
func brick(_ r: NSRect, shade: UInt32) {
    let corner = r.width * 0.22
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = deep(shade, 0.5).withAlphaComponent(0.35)
    shadow.shadowBlurRadius = r.width * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -r.width * 0.03)
    shadow.set()
    color(0xEDE3DA).setFill()
    NSBezierPath(roundedRect: r, xRadius: corner, yRadius: corner).fill()
    NSGraphicsContext.restoreGraphicsState()
    let faceRect = NSRect(x: r.minX, y: r.minY + r.height * 0.09, width: r.width, height: r.height * 0.91)
    color(cream).setFill()
    NSBezierPath(roundedRect: faceRect, xRadius: corner, yRadius: corner).fill()
    let bar = NSRect(x: r.minX + r.width * 0.16, y: r.maxY - r.height * 0.20, width: r.width * 0.68, height: r.height * 0.07)
    color(0xFFFFFF, 0.9).setFill()
    NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
}

func symbol(_ name: String, in r: NSRect, tint: NSColor) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: r.height, weight: .heavy)) else {
        fatalError("no SF Symbol \(name)")
    }
    let tinted = NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        tint.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let scale = min(r.width / base.size.width, r.height / base.size.height)
    let size = NSSize(width: base.size.width * scale, height: base.size.height * scale)
    tinted.draw(in: NSRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height))
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: font.fontDescriptor.withDesign(.rounded)!, size: size)!
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .black, color: NSColor, center: NSPoint) {
    let attributed = NSAttributedString(string: string, attributes: [.font: rounded(size, weight), .foregroundColor: color])
    let s = attributed.size()
    attributed.draw(at: NSPoint(x: center.x - s.width / 2, y: center.y - s.height / 2))
}

/// A square badge: brick with symbol, and a label tab (a count, "×3") along its bottom.
func badge(_ path: String, symbolName: String, colorName: String, label: String?, size: Int = 1024) {
    let s = CGFloat(size)
    let shade = Achievement.palette[colorName]!.shade
    png(size, size, path) {
        background(NSRect(x: 0, y: 0, width: s, height: s), colorName)
        let side = s * 0.5
        let b = NSRect(x: (s - side) / 2, y: (s - side) / 2 + (label == nil ? 0 : s * 0.035), width: side, height: side)
        brick(b, shade: shade)
        symbol(symbolName, in: b.insetBy(dx: side * 0.22, dy: side * 0.24).offsetBy(dx: 0, dy: side * 0.03), tint: deep(shade))
        if let label {
            let font = rounded(s * 0.1, .black)
            let w = NSAttributedString(string: label, attributes: [.font: font]).size().width + s * 0.09
            let tab = NSRect(x: (s - w) / 2, y: b.minY - s * 0.07, width: w, height: s * 0.135)
            deep(shade, 0.15).setFill()
            NSBezierPath(roundedRect: tab, xRadius: tab.height / 2, yRadius: tab.height / 2).fill()
            text(label, size: s * 0.1, color: .white, center: NSPoint(x: tab.midX, y: tab.midY))
        }
    }
}

/// A 16:9 banner for challenges and the activity, at the 3840x2160 App Store Connect
/// requires: the badge's brick beside a title.
func banner(_ path: String, symbolName: String, colorName: String, title: String) {
    let (w, h): (CGFloat, CGFloat) = (3840, 2160)
    let shade = Achievement.palette[colorName]!.shade
    png(Int(w), Int(h), path) {
        background(NSRect(x: 0, y: 0, width: w, height: h), colorName)
        let side = h * 0.42
        let b = NSRect(x: w * 0.5 - side / 2, y: h * 0.42, width: side, height: side)
        brick(b, shade: shade)
        symbol(symbolName, in: b.insetBy(dx: side * 0.22, dy: side * 0.24).offsetBy(dx: 0, dy: side * 0.03), tint: deep(shade))
        text(title, size: h * 0.12, color: deep(shade, 0.45), center: NSPoint(x: w / 2, y: h * 0.26))
        text("BRICKS!", size: h * 0.055, weight: .heavy, color: deep(shade, 0.3).withAlphaComponent(0.7), center: NSPoint(x: w / 2, y: h * 0.14))
    }
}

func challengeArt(_ c: Challenge) -> (symbol: String, color: String) {
    c == .beatMyScore ? ("trophy.fill", "butter") : ("line.3.horizontal", "mint")
}

@main
enum Tool {
    static func main() {
        let args = CommandLine.arguments
        switch args.dropFirst().first {
        case "render":
            let dir = args.count > 2 ? args[2] : "appstore/gamecenter"
            for a in Achievement.allCases {
                badge("\(dir)/achievements/\(a.rawValue).png", symbolName: a.info.symbol, colorName: a.info.color, label: a.info.label)
            }
            for l in Leaderboard.allCases {
                badge("\(dir)/leaderboards/\(l.rawValue).png", symbolName: l.info.symbol, colorName: l.info.color, label: nil)
            }
            for c in Challenge.allCases {
                let art = challengeArt(c)
                banner("\(dir)/challenges/\(c.rawValue).png", symbolName: art.symbol, colorName: art.color, title: c.name)
            }
            banner("\(dir)/activity.png", symbolName: "square.grid.3x3.fill", colorName: "blush", title: GameActivity.name)
            print("rendered \(Achievement.allCases.count) badges, \(Leaderboard.allCases.count) leaderboards, \(Challenge.allCases.count) challenges and the activity into \(dir)")

        case "catalog":
            let dir = args.count > 2 ? args[2] : "appstore/gamecenter"
            let catalog: [String: Any] = [
                "achievements": Achievement.allCases.map { a -> [String: Any] in
                    let i = a.info
                    return ["vendorId": a.id, "name": i.name, "goal": i.goal, "earned": i.earned, "points": i.points,
                            "hidden": i.hidden, "image": "\(dir)/achievements/\(a.rawValue).png"]
                },
                "leaderboards": Leaderboard.allCases.map { l -> [String: Any] in
                    let i = l.info
                    var out: [String: Any] = ["vendorId": l.id, "name": i.name, "description": i.description,
                                              "one": i.unit.one, "many": i.unit.many, "keepsBest": i.keepsBest,
                                              "image": "\(dir)/leaderboards/\(l.rawValue).png"]
                    if let r = i.recurrence { out["recurrence"] = ["duration": r.duration, "rule": r.rule] }
                    return out
                },
                "challenges": Challenge.allCases.map { c -> [String: Any] in
                    ["vendorId": c.id, "name": c.name, "description": c.description, "leaderboard": c.leaderboard.id,
                     "image": "\(dir)/challenges/\(c.rawValue).png"]
                },
                "activity": ["vendorId": GameActivity.id, "name": GameActivity.name, "description": GameActivity.description,
                             "leaderboards": [Leaderboard.highScore.id, Leaderboard.daily.id, Leaderboard.weekly.id],
                             "image": "\(dir)/activity.png"],
            ]
            let data = try! JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)

        default:
            print("usage: gamecenter render [dir] | catalog [dir]")
        }
    }
}
