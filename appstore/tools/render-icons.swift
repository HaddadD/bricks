// Renders the per-platform app icons from the same bricks the game draws (Theme's
// palette and BrickView's bevel and highlight), into BRICKS/Assets.xcassets:
//
//   Mac          AppIcon.appiconset/mac-*.png      rounded-square icon, all sizes
//   Apple Watch  AppIcon.appiconset/watch.png       3x3 grid that survives the circle mask
//   Apple TV     App Icon & Top Shelf Image.brandassets   layered icon + top shelf
//   Vision Pro   AppIcon Vision.solidimagestack            layered round icon
//
//   swiftc -O appstore/tools/render-icons.swift -o /tmp/render-icons && /tmp/render-icons
//
// The iPhone/iPad icon (AppIcon.png) is hand-made and left alone.
import AppKit

let assets = URL(fileURLWithPath: "BRICKS/Assets.xcassets")
let cream = rgb(0xF6EDE6)

// Theme.blocks / Theme.blockShades, by name.
let palette: [String: (UInt32, UInt32)] = [
    "blush": (0xFFA8C5, 0xE98BA9), "coral": (0xFFB59E, 0xE99A82), "apricot": (0xFFCF9E, 0xE9B482),
    "butter": (0xF3DE84, 0xDCC46A), "mint": (0xA8E6B8, 0x8DCB9D), "aqua": (0x8FDDE7, 0x74C2CC),
    "cornflower": (0xA6BDF7, 0x8BA2DC), "lilac": (0xC8AEF0, 0xAD93D5),
]

/// The 4x4 arrangement of the iOS icon, row by row.
let iconGrid = [
    ["butter", "blush", "blush", "lilac"],
    ["butter", "apricot", "apricot", "lilac"],
    ["butter", "apricot", "apricot", "cornflower"],
    ["butter", "coral", "cornflower", "cornflower"],
]
/// The centre 3x3 of it, for round icons.
let roundGrid = [
    ["butter", "blush", "lilac"],
    ["butter", "apricot", "lilac"],
    ["butter", "coral", "cornflower"],
]

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws into a fresh bitmap with a top-left origin, like the game's views. Pass
/// `flipped: false` to draw existing images, which a flipped context turns upside down.
func render(_ w: Int, _ h: Int, opaque: Bool = true, flipped: Bool = true, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
    if flipped {
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
    }
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ path: String) {
    let url = assets.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// One brick: the shade as a bottom bevel, the face above it, a soft highlight bar.
func brick(_ ctx: CGContext, _ name: String, _ r: CGRect) {
    let (face, shade) = palette[name]!
    let corner = r.width * 0.22
    ctx.addPath(rounded(r, corner)); ctx.setFillColor(rgb(shade)); ctx.fillPath()
    let faceRect = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.91)
    ctx.addPath(rounded(faceRect, corner)); ctx.setFillColor(rgb(face)); ctx.fillPath()
    let bar = CGRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.13,
                     width: r.width * 0.68, height: r.height * 0.07)
    ctx.addPath(rounded(bar, bar.height / 2)); ctx.setFillColor(CGColor(gray: 1, alpha: 0.4)); ctx.fillPath()
}

/// A grid of bricks filling `area`, with the game's gap between them.
func bricks(_ ctx: CGContext, _ grid: [[String]], in area: CGRect) {
    let n = CGFloat(grid.count), m = CGFloat(grid[0].count)
    let pitch = min(area.width / m, area.height / n)
    let size = pitch * 0.86
    let x0 = area.midX - pitch * m / 2 + (pitch - size) / 2
    let y0 = area.midY - pitch * n / 2 + (pitch - size) / 2
    for (r, row) in grid.enumerated() {
        for (c, name) in row.enumerated() {
            brick(ctx, name, CGRect(x: x0 + CGFloat(c) * pitch, y: y0 + CGFloat(r) * pitch, width: size, height: size))
        }
    }
}

func fill(_ ctx: CGContext, _ w: Int, _ h: Int, _ color: CGColor) {
    ctx.setFillColor(color); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
}

// MARK: - Mac: rounded square on Apple's 1024 grid (824 body, 100 margin), with shadow.

let macMaster = render(1024, 1024, opaque: false) { ctx in
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(rounded(body, 185)); ctx.setFillColor(cream); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(rounded(body, 185)); ctx.clip()
    bricks(ctx, iconGrid, in: body.insetBy(dx: 120, dy: 120))
}
var macImages: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = points * scale
    let name = "mac-\(points)@\(scale)x.png"
    let small = render(px, px, opaque: false, flipped: false) { ctx in
        ctx.interpolationQuality = .high
        ctx.draw(macMaster, in: CGRect(x: 0, y: 0, width: px, height: px))
    }
    save(small, "AppIcon.appiconset/\(name)")
    macImages.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}

// MARK: - Apple Watch: circle-masked by the system, so a 3x3 grid well inside it.

save(render(1024, 1024) { ctx in
    fill(ctx, 1024, 1024, cream)
    bricks(ctx, roundGrid, in: CGRect(x: 262, y: 262, width: 500, height: 500))
}, "AppIcon.appiconset/watch.png")

let appIconContents: [String: Any] = [
    "images": [
        ["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["filename": "watch.png", "idiom": "universal", "platform": "watchos", "size": "1024x1024"],
    ] + macImages,
    "info": ["author": "xcode", "version": 1],
]

// MARK: - Apple TV: a two-layer parallax icon, plus top shelf banners.

func tvBack(_ w: Int, _ h: Int) -> CGImage {
    render(w, h) { ctx in
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xFDF7F2), rgb(0xF0E8F4)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    }
}
func tvFront(_ w: Int, _ h: Int) -> CGImage {
    render(w, h, opaque: false) { ctx in
        let H = CGFloat(h)
        bricks(ctx, roundGrid, in: CGRect(x: 0, y: H * 0.14, width: CGFloat(w), height: H * 0.72))
    }
}
func shelf(_ w: Int, _ h: Int) -> CGImage {
    render(w, h) { ctx in
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xFDF7F2), rgb(0xF0E8F4)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        let W = CGFloat(w), H = CGFloat(h)
        // A run of bricks across the banner, like a cleared row in mid-air.
        let row = ["butter", "blush", "apricot", "lilac", "cornflower", "coral", "mint", "aqua", "butter", "blush"]
        let pitch = H * 0.2
        let y = H * 0.4
        let startX = (W - pitch * CGFloat(row.count)) / 2
        for (i, name) in row.enumerated() {
            brick(ctx, name, CGRect(x: startX + CGFloat(i) * pitch, y: y, width: pitch * 0.86, height: pitch * 0.86))
        }
    }
}

let brand = "App Icon & Top Shelf Image.brandassets"
func json(_ object: Any, _ path: String) {
    let url = assets.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
let info = ["author": "xcode", "version": 1] as [String: Any]

func imageStack(_ name: String, sizes: [(Int, Int, String)]) {
    let stack = "\(brand)/\(name).imagestack"
    json(["info": info, "layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]]],
         "\(stack)/Contents.json")
    for (layer, make) in [("Front", tvFront), ("Back", tvBack)] {
        json(["info": info], "\(stack)/\(layer).imagestacklayer/Contents.json")
        var images: [[String: String]] = []
        for (w, h, scale) in sizes {
            let file = "\(layer.lowercased())-\(w)x\(h).png"
            save(make(w, h), "\(stack)/\(layer).imagestacklayer/Content.imageset/\(file)")
            images.append(["filename": file, "idiom": "tv", "scale": scale])
        }
        json(["images": images, "info": info], "\(stack)/\(layer).imagestacklayer/Content.imageset/Contents.json")
    }
}
imageStack("App Icon", sizes: [(400, 240, "1x"), (800, 480, "2x")])
imageStack("App Icon - App Store", sizes: [(1280, 768, "1x")])

func shelfSet(_ name: String, _ w: Int, _ h: Int) {
    let dir = "\(brand)/\(name).imageset"
    save(shelf(w, h), "\(dir)/shelf-\(w)x\(h).png")
    save(shelf(w * 2, h * 2), "\(dir)/shelf-\(w * 2)x\(h * 2).png")
    json(["images": [["filename": "shelf-\(w)x\(h).png", "idiom": "tv", "scale": "1x"],
                     ["filename": "shelf-\(w * 2)x\(h * 2).png", "idiom": "tv", "scale": "2x"]],
          "info": info], "\(dir)/Contents.json")
}
shelfSet("Top Shelf Image", 1920, 720)
shelfSet("Top Shelf Image Wide", 2320, 720)

json(["assets": [
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
], "info": info], "\(brand)/Contents.json")

// MARK: - Vision Pro: three layers, masked to a circle by the system.

let vision = "AppIcon Vision.solidimagestack"
json(["info": info, "layers": [["filename": "Front.solidimagestacklayer"],
                               ["filename": "Middle.solidimagestacklayer"],
                               ["filename": "Back.solidimagestacklayer"]]], "\(vision)/Contents.json")
let visionLayers: [(String, CGImage)] = [
    ("Back", render(1024, 1024) { ctx in fill(ctx, 1024, 1024, cream) }),
    // The bricks split across two layers so they separate in depth.
    ("Middle", render(1024, 1024, opaque: false) { ctx in
        bricks(ctx, [["butter", "blush", "lilac"]], in: CGRect(x: 287, y: 262, width: 450, height: 150))
        bricks(ctx, [["butter", "coral", "cornflower"]], in: CGRect(x: 287, y: 612, width: 450, height: 150))
    }),
    ("Front", render(1024, 1024, opaque: false) { ctx in
        bricks(ctx, [["butter", "apricot", "lilac"]], in: CGRect(x: 287, y: 437, width: 450, height: 150))
    }),
]
for (layer, image) in visionLayers {
    let dir = "\(vision)/\(layer).solidimagestacklayer"
    json(["info": info], "\(dir)/Contents.json")
    save(image, "\(dir)/Content.imageset/\(layer.lowercased()).png")
    json(["images": [["filename": "\(layer.lowercased()).png", "idiom": "vision", "scale": "2x"]], "info": info],
         "\(dir)/Content.imageset/Contents.json")
}

json(appIconContents, "AppIcon.appiconset/Contents.json")
print("Icons written to \(assets.path)")
