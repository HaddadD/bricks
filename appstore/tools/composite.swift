// composite <art.png> <screenshot.png> <width> <height> <out.png>
// Scales the GPT art to exactly width x height (aspect-fill), finds the chroma-key
// green screen, and replaces it with the real screenshot (aspect-fit, edges extended
// so no UI is cropped), with soft edges and green-spill removal.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot load \(path)") }
    return img
}

func render(_ img: CGImage, into rect: CGRect, width: Int, height: Int,
            extendingTo box: CGRect? = nil) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: width * height * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    buf.withUnsafeMutableBytes { p in
        let ctx = CGContext(data: p.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Fill the rest of `box` by stretching the image's outermost rows/columns, so an
        // aspect-fit screenshot reaches the screen edges without cropping any UI.
        if let box = box {
            let (iw, ih) = (img.width, img.height)
            if rect.minY > box.minY, let row = img.cropping(to: CGRect(x: 0, y: ih - 1, width: iw, height: 1)) {
                ctx.draw(row, in: CGRect(x: rect.minX, y: box.minY, width: rect.width, height: rect.minY - box.minY + 1))
            }
            if rect.maxY < box.maxY, let row = img.cropping(to: CGRect(x: 0, y: 0, width: iw, height: 1)) {
                ctx.draw(row, in: CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: box.maxY - rect.maxY + 1))
            }
            if rect.minX > box.minX, let col = img.cropping(to: CGRect(x: 0, y: 0, width: 1, height: ih)) {
                ctx.draw(col, in: CGRect(x: box.minX, y: rect.minY, width: rect.minX - box.minX + 1, height: rect.height))
            }
            if rect.maxX < box.maxX, let col = img.cropping(to: CGRect(x: iw - 1, y: 0, width: 1, height: ih)) {
                ctx.draw(col, in: CGRect(x: rect.maxX - 1, y: rect.minY, width: box.maxX - rect.maxX + 1, height: rect.height))
            }
        }
        ctx.draw(img, in: rect)
    }
    return buf
}

func aspectFit(_ img: CGImage, _ box: CGRect) -> CGRect {
    let s = min(box.width / CGFloat(img.width), box.height / CGFloat(img.height))
    let w = CGFloat(img.width) * s, h = CGFloat(img.height) * s
    return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
}

func aspectFill(_ img: CGImage, _ box: CGRect) -> CGRect {
    let s = max(box.width / CGFloat(img.width), box.height / CGFloat(img.height))
    let w = CGFloat(img.width) * s, h = CGFloat(img.height) * s
    return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
}

let a = CommandLine.arguments
guard a.count == 6, let W = Int(a[3]), let H = Int(a[4]) else {
    print("usage: composite art.png shot.png width height out.png"); exit(2)
}
let art = load(a[1]), shot = load(a[2])
let artAspect = Double(art.width) / Double(art.height), outAspect = Double(W) / Double(H)
if abs(artAspect - outAspect) > 0.03 {
    // Aspect-fill will crop the art; usually means the model ignored the canvas shape.
    FileHandle.standardError.write("WARNING: \(a[1]) is \(art.width)x\(art.height), far from \(W)x\(H); regenerate it\n".data(using: .utf8)!)
}
var px = render(art, into: aspectFill(art, CGRect(x: 0, y: 0, width: W, height: H)), width: W, height: H)

// Greenness: how far green exceeds the larger of red/blue. Buffer rows run top-down.
func greenness(_ i: Int) -> Int { Int(px[i + 1]) - max(Int(px[i]), Int(px[i + 2])) }
var minX = W, minY = H, maxX = -1, maxY = -1, count = 0
for y in 0..<H { for x in 0..<W {
    if greenness((y * W + x) * 4) > 120 {
        count += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}}
guard count > W * H / 20 else { print("ERROR: no green screen found (\(count) px)"); exit(3) }

let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
// CoreGraphics draws bottom-up, so flip the box's y when placing the screenshot.
let cgBox = CGRect(x: box.minX, y: CGFloat(H) - box.maxY, width: box.width, height: box.height)
// Fit (never crop) the screenshot, then extend its edges to fill the screen shape.
let sp = render(shot, into: aspectFit(shot, cgBox), width: W, height: H, extendingTo: cgBox)

let pad = 6
for y in max(0, minY - pad)...min(H - 1, maxY + pad) { for x in max(0, minX - pad)...min(W - 1, maxX + pad) {
    let i = (y * W + x) * 4
    let g = greenness(i)
    if g <= 20 { continue }
    let inside = x >= minX && x <= maxX && y >= minY && y <= maxY
    let alpha = inside ? min(1.0, Double(g - 20) / 90.0) : 0
    // Remove green spill from whatever art remains on the edge.
    let r = Double(px[i]), b = Double(px[i + 2])
    let gClamped = min(Double(px[i + 1]), max(r, b))
    px[i]     = UInt8(r * (1 - alpha) + Double(sp[i]) * alpha)
    px[i + 1] = UInt8(gClamped * (1 - alpha) + Double(sp[i + 1]) * alpha)
    px[i + 2] = UInt8(b * (1 - alpha) + Double(sp[i + 2]) * alpha)
    px[i + 3] = 255
}}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let out: CGImage = px.withUnsafeMutableBytes { p in
    CGContext(data: p.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
              space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
}
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[5]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { print("ERROR: write failed"); exit(4) }
print("ok \(a[5]) screen=\(Int(box.width))x\(Int(box.height))@\(minX),\(minY) aspect=\(String(format: "%.3f", box.width / box.height))")
