import CoreGraphics
import Foundation
import SceneKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The two satisfying shows that can play beside the puzzle instead of the runner.
enum SatisfyingKind {
    /// Kinetic sand, soap, slime, pressure washing and a rusty gear restored.
    case oddly
    /// Glass fruit, jelly keyboards and a crystal bar eaten square by square.
    case impossible
}

/// A loop of short 3D clips, lit like a product studio: physically based materials,
/// reflections from a soft-box environment, soft shadows, depth of field, ambient
/// occlusion and a little bloom. Each frame is rendered off screen, so it can go into
/// the same video as the runner.
final class SatisfyingShow {

    let kind: SatisfyingKind
    private let stage: Stage
    private let renderer: SCNRenderer
    private var clips: [(Stage) -> Clip]
    private var clip: Clip
    private var index = 0
    private(set) var time = 0.0
    private var clipStart = 0.0

    init(kind: SatisfyingKind) {
        self.kind = kind
        stage = Stage()
        renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = stage.scene
        renderer.pointOfView = stage.camera
        switch kind {
        case .oddly:
            clips = [
                { SliceClip(stage: $0, soap: false) },
                { SlimeClip(stage: $0) },
                { WashClip(stage: $0) },
                { SliceClip(stage: $0, soap: true) },
                { RestoreClip(stage: $0) },
            ]
        case .impossible:
            clips = [
                { GlassFruitClip(stage: $0) },
                { KeyboardClip(stage: $0) },
                { CrystalBarClip(stage: $0) },
            ]
        }
        clip = clips[0](stage)
    }

    func step(_ dt: Double) {
        time += dt
        if time - clipStart >= clip.length {
            clip.tearDown()
            stage.reset()
            index = (index + 1) % clips.count
            clip = clips[index](stage)
            clipStart = time
        }
        clip.update(time - clipStart)
    }

    func draw(in ctx: CGContext, size: CGSize) {
        SCNTransaction.flush()
        #if canImport(UIKit)
        let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X).cgImage
        #else
        let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let image else { return }
        ctx.saveGState()
        // The context draws with y down; images want y up.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        ctx.restoreGState()

        // A quick dip between clips.
        let local = time - clipStart
        let fade = max(0, 1 - local / 0.35, 1 - (clip.length - local) / 0.35)
        if fade > 0 {
            ctx.setFillColor(Stage.backdrop.copy(alpha: min(1, fade))!)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Stage

/// The studio every clip plays in: a table, lights, a camera and the environment.
final class Stage {
    static let backdrop = CGColor(red: 0.95, green: 0.92, blue: 0.95, alpha: 1)

    let scene = SCNScene()
    let camera = SCNNode()
    let table: SCNNode
    /// Each clip builds under here, and it's emptied between clips.
    let content = SCNNode()
    let key = SCNNode()

    init() {
        scene.background.contents = Textures.backdrop
        scene.lightingEnvironment.contents = Textures.studio
        scene.lightingEnvironment.intensity = 1.3
        scene.fogStartDistance = 7
        scene.fogEndDistance = 16
        scene.fogColor = Stage.backdrop

        let plane = SCNPlane(width: 40, height: 40)
        let surface = Materials.pbr(CGColor(red: 0.8, green: 0.76, blue: 0.82, alpha: 1), roughness: 0.75)
        plane.firstMaterial = surface
        table = SCNNode(geometry: plane)
        table.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        scene.rootNode.addChildNode(table)
        scene.rootNode.addChildNode(content)

        let light = SCNLight()
        light.type = .spot
        light.intensity = 420
        light.temperature = 5600
        light.spotInnerAngle = 30
        light.spotOuterAngle = 75
        light.castsShadow = true
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.shadowRadius = 9
        light.shadowSampleCount = 16
        light.shadowColor = CGColor(gray: 0, alpha: 0.45)
        light.zNear = 1
        light.zFar = 30
        key.light = light
        key.simdPosition = SIMD3(-2.5, 6, 3.5)
        key.simdLook(at: .zero)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .omni
        fill.light!.intensity = 90
        fill.light!.temperature = 7000
        fill.simdPosition = SIMD3(4, 3, -2)
        scene.rootNode.addChildNode(fill)

        let lens = SCNCamera()
        lens.fieldOfView = 34
        lens.zNear = 0.05
        lens.zFar = 40
        lens.wantsHDR = true
        lens.wantsExposureAdaptation = false
        lens.exposureOffset = -0.7
        lens.bloomIntensity = 0.25
        lens.bloomThreshold = 4
        lens.bloomBlurRadius = 8
        lens.screenSpaceAmbientOcclusionIntensity = 0.9
        lens.screenSpaceAmbientOcclusionRadius = 0.12
        lens.vignettingIntensity = 0.25
        lens.vignettingPower = 0.8
        lens.contrast = 0.18
        lens.saturation = 1.15
        camera.camera = lens
        scene.rootNode.addChildNode(camera)
    }

    func look(from position: SIMD3<Float>, at target: SIMD3<Float>, fieldOfView: CGFloat = 34) {
        camera.simdPosition = position
        camera.simdLook(at: target)
        camera.camera?.fieldOfView = fieldOfView
    }

    func reset() {
        content.childNodes.forEach { $0.removeFromParentNode() }
        scene.removeAllParticleSystems()
        table.removeAllParticleSystems()
    }

    /// A one-off spray of bits at a point in the world.
    func burst(_ system: SCNParticleSystem, at point: SIMD3<Float>) {
        var place = matrix_identity_float4x4
        place.columns.3 = SIMD4(point, 1)
        scene.addParticleSystem(system, transform: SCNMatrix4(place))
    }
}

/// One clip in a show. `update` gets the seconds since the clip began.
class Clip {
    unowned let stage: Stage
    var length: Double { 10 }

    init(stage: Stage) { self.stage = stage }

    func update(_ t: Double) {}

    func tearDown() {}

    func add(_ node: SCNNode) { stage.content.addChildNode(node) }
}

// MARK: - Helpers

enum Ease {
    static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
    static func smooth(_ x: Double) -> Double { let t = clamp(x); return t * t * (3 - 2 * t) }
    static func inQuad(_ x: Double) -> Double { let t = clamp(x); return t * t }
    static func outCubic(_ x: Double) -> Double { let t = clamp(x); return 1 - pow(1 - t, 3) }
    /// A spring settling from 1 to 0, for squash and wobble.
    static func spring(_ x: Double, frequency: Double = 3, damping: Double = 5) -> Double {
        guard x >= 0 else { return 0 }
        return exp(-damping * x) * cos(2 * .pi * frequency * x)
    }
    static func phase(_ t: Double, _ start: Double, _ duration: Double) -> Double { clamp((t - start) / duration) }
}

func sceneColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

#if canImport(UIKit)
func platformColor(_ c: CGColor) -> UIColor { UIColor(cgColor: c) }
#else
func platformColor(_ c: CGColor) -> NSColor { NSColor(cgColor: c) ?? .white }
#endif

enum Materials {
    static func pbr(_ base: CGColor, roughness: Double, metalness: Double = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = base
        m.roughness.contents = NSNumber(value: roughness)
        m.metalness.contents = NSNumber(value: metalness)
        return m
    }

    static func steel() -> SCNMaterial {
        pbr(CGColor(gray: 0.9, alpha: 1), roughness: 0.12, metalness: 1)
    }

    /// Glass or a clear sweet: tinted, glossy and see-through, with a clear coat. A
    /// physically based material ignores `transparency`; the diffuse colour's alpha is
    /// what lets light through.
    static func glass(_ tint: CGColor, opacity: Double = 0.35) -> SCNMaterial {
        let m = pbr(tint.copy(alpha: CGFloat(opacity))!, roughness: 0.03)
        m.transparencyMode = .aOne
        m.clearCoat.contents = NSNumber(value: 1)
        m.clearCoatRoughness.contents = NSNumber(value: 0.02)
        return m
    }

    static func sand(_ base: CGColor) -> SCNMaterial {
        let m = pbr(base, roughness: 1)
        m.multiply.contents = Textures.speckle
        m.multiply.wrapS = .repeat
        m.multiply.wrapT = .repeat
        m.multiply.contentsTransform = SCNMatrix4MakeScale(2, 2, 1)
        m.normal.contents = Textures.sandNormal
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.contentsTransform = SCNMatrix4MakeScale(8, 8, 1)
        return m
    }

    static func soap(_ base: CGColor) -> SCNMaterial {
        let m = pbr(base, roughness: 0.32)
        m.clearCoat.contents = NSNumber(value: 0.7)
        m.clearCoatRoughness.contents = NSNumber(value: 0.12)
        m.emission.contents = base
        m.emission.intensity = 0.06
        return m
    }
}

enum Particles {
    static let dot: CGImage = {
        let size = 32
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.9), CGColor(gray: 1, alpha: 0)] as CFArray,
                                  locations: [0, 0.55, 1])!
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                               endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        return ctx.makeImage()!
    }()

    /// Grains or crumbs that fall and settle on the table.
    static func crumbs(_ tint: CGColor, count: CGFloat, size: CGFloat, shape: SCNGeometry? = nil, collider: SCNNode) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.loops = false
        p.emissionDuration = 0.12
        p.birthRate = count / 0.12
        p.particleLifeSpan = 9
        p.particleSize = size
        p.particleSizeVariation = size * 0.6
        p.particleColor = platformColor(tint)
        p.particleColorVariation = SCNVector4(0.02, 0.1, 0.12, 0)
        p.particleImage = dot
        p.isLightingEnabled = false
        p.isAffectedByGravity = true
        p.acceleration = SCNVector3(0, -2, 0)
        p.particleVelocity = 0.6
        p.particleVelocityVariation = 0.6
        p.spreadingAngle = 70
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.emitterShape = shape
        p.birthLocation = shape == nil ? .surface : .volume
        p.colliderNodes = [collider]
        p.particleBounce = 0.05
        p.particleFriction = 1
        p.dampingFactor = 0.4
        p.blendMode = .alpha
        p.sortingMode = .distance
        return p
    }

    /// Glints that sparkle and fade: glitter, glass dust, sparks.
    static func glints(_ tint: CGColor, count: CGFloat, speed: CGFloat, life: CGFloat = 0.9, gravity: Bool = true, stretch: CGFloat = 0) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.loops = false
        p.emissionDuration = 0.08
        p.birthRate = count / 0.08
        p.particleLifeSpan = life
        p.particleLifeSpanVariation = life * 0.5
        p.particleSize = 0.012
        p.particleSizeVariation = 0.008
        p.particleColor = platformColor(tint)
        p.particleImage = dot
        p.isAffectedByGravity = gravity
        p.particleVelocity = speed
        p.particleVelocityVariation = speed * 0.7
        p.spreadingAngle = 180
        p.blendMode = .additive
        p.stretchFactor = stretch
        let fade = CAKeyframeAnimation()
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.6, 1]
        p.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return p
    }
}

/// Textures drawn in code, so the app ships no image files for these scenes.
enum Textures {

    /// A grey texture, stored as RGB: Metal on iOS won't take a one-channel image here.
    private static func gray(_ size: Int, _ fill: (Int, Int) -> UInt8) -> CGImage {
        rgb(size, size) { x, y in
            let v = Double(fill(x, y)) / 255
            return (v, v, v)
        }
    }

    private static func rgb(_ width: Int, _ height: Int, _ fill: (Int, Int) -> (Double, Double, Double)) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = fill(x, y)
                let i = (y * width + x) * 4
                bytes[i] = UInt8(max(0, min(255, r * 255)))
                bytes[i + 1] = UInt8(max(0, min(255, g * 255)))
                bytes[i + 2] = UInt8(max(0, min(255, b * 255)))
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Smooth value noise that tiles, in 0...1.
    static func noise(_ x: Double, _ y: Double, period: Int, seed: UInt64) -> Double {
        func hash(_ i: Int, _ j: Int) -> Double {
            var h = UInt64(bitPattern: Int64(((i % period) + period) % period &* 73_856_093 ^ ((j % period) + period) % period &* 19_349_663)) &+ seed &* 0x9E37_79B9
            h = (h ^ (h >> 33)) &* 0xFF51_AFD7_ED55_8CCD
            h = (h ^ (h >> 33)) &* 0xC4CE_B9FE_1A85_EC53
            return Double(h >> 11) / Double(1 << 53)
        }
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    static func fractal(_ x: Double, _ y: Double, period: Int, seed: UInt64, octaves: Int = 4) -> Double {
        var total = 0.0, amplitude = 0.5, frequency = 1.0
        for o in 0..<octaves {
            total += noise(x * frequency, y * frequency, period: period * Int(frequency), seed: seed &+ UInt64(o)) * amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return total / 0.9375
    }

    /// A tangent-space normal map from fractal noise, for grain, grit and texture.
    static func noiseNormal(seed: UInt64, scale: Int, strength: Double) -> CGImage {
        let size = 256
        let period = 8 * scale
        var height = [Double](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                height[y * size + x] = fractal(Double(x) / Double(size) * Double(period), Double(y) / Double(size) * Double(period),
                                               period: period, seed: seed)
            }
        }
        return rgb(size, size) { x, y in
            let l = height[y * size + (x + size - 1) % size], r = height[y * size + (x + 1) % size]
            let u = height[((y + size - 1) % size) * size + x], d = height[((y + 1) % size) * size + x]
            var n = SIMD3((l - r) * strength * 8, (u - d) * strength * 8, 1.0)
            n /= sqrt((n * n).sum())
            return (n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5)
        }
    }

    static let speckle: CGImage = gray(256) { x, y in
        var h = UInt64(x &* 31 &+ y &* 977 &+ 13) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 31
        let grain = Double(h % 1000) / 1000
        return UInt8(222 + grain * 33 - (grain > 0.96 ? 50 : 0))
    }

    /// Fine, random grain: a normal per texel, so it reads as sand rather than lumps.
    static let sandNormal: CGImage = rgb(256, 256) { x, y in
        var h = UInt64(x &* 7919 &+ y &* 104_729 &+ 5) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 31
        h = h &* 0x94D0_49BB_1331_11EB
        let a = Double(h & 0xFFFF) / 65535 * 2 * .pi
        let tilt = Double((h >> 16) & 0xFF) / 255 * 0.7
        return (0.5 + cos(a) * tilt * 0.5, 0.5 + sin(a) * tilt * 0.5, 1)
    }

    /// A dark studio with soft boxes, as an equirectangular map. Glossy things reflect
    /// mostly darkness and a few bright panels, which is what makes them read as glossy.
    static let studio: CGImage = {
        let width = 512, height = 256
        return rgb(width, height) { x, y in
            let v = Double(y) / Double(height), u = Double(x) / Double(width)
            var c = 0.07 + 0.05 * (1 - v)
            if v > 0.52 { c = 0.16 + 0.04 * v }
            func box(_ cu: Double, _ cv: Double, _ w: Double, _ h: Double) -> Double {
                let du = abs(u - cu) / w, dv = abs(v - cv) / h
                let edge = max(du, dv)
                return edge < 1 ? 1 - pow(edge, 10) : 0
            }
            c += box(0.3, 0.3, 0.06, 0.1) + box(0.72, 0.34, 0.035, 0.14) * 0.8 + box(0.5, 0.12, 0.08, 0.03) * 0.5
            return (min(1, c), min(1, c * 0.98), min(1, c * 1.03))
        }
    }()

    static let backdrop: CGImage = {
        let width = 64, height = 256
        return rgb(width, height) { _, y in
            let v = Double(y) / Double(height)
            let top = (0.86, 0.88, 0.97), bottom = (0.97, 0.91, 0.93)
            let t = Ease.smooth((v - 0.2) / 0.5)
            return (top.0 + (bottom.0 - top.0) * t, top.1 + (bottom.1 - top.1) * t, top.2 + (bottom.2 - top.2) * t)
        }
    }()

    static func rust(seed: UInt64) -> CGImage {
        rgb(256, 256) { x, y in
            let n = fractal(Double(x) / 32, Double(y) / 32, period: 8, seed: seed, octaves: 5)
            let pits = fractal(Double(x) / 8, Double(y) / 8, period: 32, seed: seed &+ 7, octaves: 2)
            let dark = (0.24, 0.13, 0.08), orange = (0.62, 0.31, 0.13), pale = (0.72, 0.5, 0.33)
            var c = n < 0.5 ? mixRGB(dark, orange, n * 2) : mixRGB(orange, pale, (n - 0.5) * 2)
            if pits > 0.7 { c = mixRGB(c, dark, 0.6) }
            return c
        }
    }

    static let grime: CGImage = rgb(256, 256) { x, y in
        let n = fractal(Double(x) / 32, Double(y) / 32, period: 8, seed: 77, octaves: 5)
        let streak = noise(Double(x) / 4, Double(y) / 64, period: 64, seed: 5)
        let c = mixRGB((0.23, 0.22, 0.16), (0.46, 0.43, 0.32), n)
        return mixRGB(c, (0.2, 0.27, 0.15), max(0, streak - 0.55) * 1.5)
    }

    static func mixRGB(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
        let t = max(0, min(1, t))
        return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    /// Draws a texture with Core Graphics, y down.
    static func drawn(_ width: Int, _ height: Int, _ paint: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        paint(ctx)
        return ctx.makeImage()!
    }
}

/// A chef's knife, its edge at the node's origin, blade along z.
func makeKnife() -> SCNNode {
    let knife = SCNNode()
    let blade = SCNNode(geometry: SCNBox(width: 0.012, height: 0.5, length: 1.25, chamferRadius: 0.004))
    blade.geometry!.firstMaterial = Materials.steel()
    blade.simdPosition = SIMD3(0, 0.25, 0)
    knife.addChildNode(blade)
    let handle = SCNNode(geometry: SCNBox(width: 0.07, height: 0.13, length: 0.5, chamferRadius: 0.03))
    let wood = Materials.pbr(sceneColor(0x3B2A26), roughness: 0.45)
    wood.clearCoat.contents = NSNumber(value: 0.4)
    handle.geometry!.firstMaterial = wood
    handle.simdPosition = SIMD3(0, 0.42, 0.85)
    knife.addChildNode(handle)
    return knife
}

private let pastels: [UInt32] = [0xF7A8C4, 0xC8AEF0, 0xA8E6B8, 0xA6BDF7, 0xFFC99E, 0xFFE58A]
/// The pastels, deepened, for things you see through, which pale whatever they tint.
private let vivid: [UInt32] = [0xFF6FA8, 0xA77BFF, 0x3FD38A, 0x5F8CFF, 0xFF9A4D, 0xFFCF3A]

// MARK: - Oddly satisfying

/// Kinetic sand or a bar of soap, sliced; each slice topples off the block. Sand crumbles
/// into a heap of grains; soap breaks into pieces.
final class SliceClip: Clip {
    private let soap: Bool
    private let count = 12
    private let thick: Float = 0.15
    private let height: Float = 0.75
    private let depth: Float = 0.8
    private var pivots: [SCNNode] = []
    private var slices: [SCNNode] = []
    private var landed = Set<Int>()
    private let knife = makeKnife()
    private let cutLength = 1.45
    private let cuts = 6
    /// Each layer's colour, bottom up, for the grains it crumbles into.
    private var layerColors: [CGColor] = []

    init(stage: Stage, soap: Bool) {
        self.soap = soap
        super.init(stage: stage)
        let left = -Float(count) * thick / 2
        let colors = soap ? [pastels.randomElement()!] : Array(pastels.shuffled().prefix(3))
        layerColors = (0..<3).map { sceneColor(colors[soap ? 0 : $0]) }
        for i in 0..<count {
            let pivot = SCNNode()
            pivot.simdPosition = SIMD3(left + thick * Float(i + 1), 0, 0)
            let slice = SCNNode()
            slice.simdPosition = SIMD3(-thick / 2, 0, 0)
            let layers = 3
            for l in 0..<layers {
                let h = height / Float(layers)
                let box = SCNBox(width: CGFloat(thick - 0.002), height: CGFloat(h - (soap ? 0.004 : 0)), length: CGFloat(depth),
                                 chamferRadius: soap ? 0.012 : 0.004)
                box.firstMaterial = soap ? Materials.soap(sceneColor(colors[0])) : Materials.sand(sceneColor(colors[l]))
                let layer = SCNNode(geometry: box)
                layer.simdPosition = SIMD3(0, h * (Float(l) + 0.5), 0)
                layer.name = "layer"
                slice.addChildNode(layer)
            }
            pivot.addChildNode(slice)
            add(pivot)
            pivots.append(pivot)
            slices.append(slice)
        }
        add(knife)
        stage.look(from: SIMD3(2.5, 1.5, 2.4), at: SIMD3(0.55, 0.3, 0.05), fieldOfView: 36)
    }

    override func update(_ t: Double) {
        let left = -Float(count) * thick / 2
        let local = t - 0.4
        let k = max(0, min(cuts - 1, Int(local / cutLength)))
        let u = local - Double(k) * cutLength
        let index = count - 1 - k
        let edge = left + thick * Float(index)

        // The knife drops through the block, then lifts and moves to the next cut.
        var y = 1.1
        if local < 0 {
            y = 1.1
        } else if u < 0.5 {
            y = 1.1 - 1.1 * Ease.smooth(u / 0.5)
        } else if u < 0.65 {
            y = 0
        } else {
            y = 1.1 * Ease.smooth((u - 0.65) / 0.55)
        }
        let nextEdge = left + thick * Float(max(0, index - 1))
        let slide = Float(Ease.smooth((u - 1.0) / 0.4))
        knife.simdPosition = SIMD3(edge + (k < cuts - 1 ? (nextEdge - edge) * slide : 0), Float(y), -0.15)

        for c in 0..<cuts {
            let i = count - 1 - c
            let start = 0.4 + Double(c) * cutLength + 0.6
            let fall = Ease.inQuad((t - start) / 0.42)
            var angle = Float(-Double.pi / 2 * fall)
            if fall >= 1 {
                angle += Float(0.05 * Ease.spring(t - start - 0.42, frequency: 3, damping: 8))
                if !landed.contains(i) { landed.insert(i); land(i) }
            }
            pivots[i].simdEulerAngles = SIMD3(0, 0, angle)

            // Landed slices settle: sand crumbles down, soap pieces part.
            let after = t - start - 0.42
            if after > 0 {
                if soap {
                    for (n, layer) in slices[i].childNodes.enumerated() {
                        let spread = Float(Ease.outCubic(after / 0.35)) * 0.05
                        layer.simdPosition.z = (Float(n) - 1) * spread * 3
                    }
                } else {
                    let crumble = Float(Ease.smooth(after / 0.9))
                    slices[i].simdScale = SIMD3(1 - crumble * 0.8, 1, 1 + crumble * 0.08)
                }
                // Clear the landing spot before the next slice comes down.
                let away = Float(Ease.smooth((after - 0.8) / 0.5))
                if soap { slices[i].simdPosition.y = 0; pivots[i].simdPosition.z = away * 1.6 ; pivots[i].opacity = CGFloat(1 - away) }
            }
        }
    }

    private func land(_ i: Int) {
        let slice = slices[i]
        let centre = slice.simdConvertPosition(SIMD3(0, height / 2, 0), to: nil)
        if soap {
            let shavings = Particles.glints(sceneColor(0xFFFFFF, alpha: 0.9), count: 90, speed: 0.6, life: 0.8)
            shavings.blendMode = .alpha
            shavings.particleSize = 0.01
            stage.burst(shavings, at: centre)
        } else {
            for (n, layer) in slice.childNodes.enumerated() {
                let tint = layerColors[n]
                let box = SCNBox(width: CGFloat(height / 3), height: CGFloat(thick), length: CGFloat(depth), chamferRadius: 0)
                let grains = Particles.crumbs(tint, count: 700, size: 0.011, shape: box, collider: stage.table)
                grains.particleVelocity = 0.25
                let p = layer.simdConvertPosition(.zero, to: nil)
                stage.burst(grains, at: p)
            }
        }
    }
}

/// A glossy, glittery slime, kneaded and poked, its colours folding into each other.
final class SlimeClip: Clip {
    private let blob: SCNNode
    private let material: SCNMaterial
    private let stick: SCNNode

    override init(stage: Stage) {
        let sphere = SCNSphere(radius: 0.75)
        sphere.segmentCount = 160
        material = Materials.pbr(sceneColor(0xF7A8C4), roughness: 0.16)
        material.clearCoat.contents = NSNumber(value: 0.55)
        material.clearCoatRoughness.contents = NSNumber(value: 0.03)
        material.emission.contents = CGColor(gray: 0, alpha: 1)
        let (a, b) = [(0xFF5FA2, 0x5F8CFF), (0x3FD38A, 0xA56BFF), (0xFF9A4D, 0xFF5FA2)].randomElement()!
        func vec(_ hex: Int) -> String {
            String(format: "float3(%.3f, %.3f, %.3f)", Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }
        material.shaderModifiers = [
            .geometry: """
            #pragma arguments
            float3 poke;
            float press;
            float squash;
            #pragma body
            float3 p = _geometry.position.xyz;
            float t = scn_frame.time;
            float wobble = sin(p.x * 5.0 + t * 1.7) * sin(p.y * 6.0 - t * 1.3) * sin(p.z * 5.5 + t * 1.1);
            float d = distance(p, poke);
            float dent = press * exp(-d * d * 14.0);
            float3 n = _geometry.normal;
            p += n * (wobble * 0.035 - dent);
            p.y *= 0.62 - squash * 0.12;
            p.xz *= 1.0 + squash * 0.1;
            _geometry.position.xyz = p;
            """,
            .surface: """
            #pragma body
            float2 uv = _surface.diffuseTexcoord;
            float t = scn_frame.time * 0.35;
            float s = sin(uv.x * 25.13 + sin(uv.y * 9.0 + t * 2.0) * 3.0 + t * 1.5 + uv.y * 6.0);
            float k = smoothstep(-0.35, 0.35, s);
            float3 col = mix(\(vec(a)), \(vec(b)), k);
            col = mix(col, float3(1.0, 0.98, 1.0), smoothstep(0.92, 1.0, abs(s)) * 0.3);
            _surface.diffuse = float4(col, 1.0);
            float2 cell = floor(uv * float2(420.0, 220.0));
            float g = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
            float twinkle = 0.5 + 0.5 * sin(scn_frame.time * 6.0 + g * 40.0);
            _surface.emission = float4(float3(step(0.982, g) * twinkle * 1.6), 1.0);
            """,
        ]
        sphere.firstMaterial = material
        blob = SCNNode(geometry: sphere)
        blob.simdPosition = SIMD3(0, 0.42, 0)

        stick = SCNNode(geometry: SCNCapsule(capRadius: 0.06, height: 1.3))
        stick.geometry!.firstMaterial = Materials.pbr(sceneColor(0xE8D3B8), roughness: 0.55)
        super.init(stage: stage)
        add(blob)
        add(stick)
        stage.look(from: SIMD3(0, 1.55, 2.6), at: SIMD3(0, 0.3, 0), fieldOfView: 36)
    }

    override func update(_ t: Double) {
        // Three presses, each sinking in, dragging, and lifting off.
        let beat = 3.2
        let k = Int(t / beat)
        let u = t - Double(k) * beat
        let spots: [SIMD3<Float>] = [SIMD3(-0.25, 0.75, 0.25), SIMD3(0.3, 0.7, 0.1), SIMD3(0, 0.75, 0.4), SIMD3(-0.1, 0.72, -0.05)]
        let from = spots[k % spots.count], to = spots[(k + 1) % spots.count]
        let press = Ease.smooth(u / 0.7) * (1 - Ease.smooth((u - 2.1) / 0.6))
        let drag = Float(Ease.smooth((u - 0.8) / 1.3))
        let poke = from + (to - from) * drag * 0.6
        material.setValue(NSValue(scnVector3: SCNVector3(poke)), forKey: "poke")
        material.setValue(NSNumber(value: press * 0.32), forKey: "press")
        material.setValue(NSNumber(value: 0.5 + 0.5 * sin(t * 1.4)), forKey: "squash")

        let tip = SIMD3<Float>(poke.x, 0.42 + poke.y * 0.62 - Float(press) * 0.2, poke.z)
        stick.simdPosition = tip + SIMD3(0.18, 0.62, 0.12)
        stick.simdEulerAngles = SIMD3(0.18, 0, -0.28)
    }
}

/// Grime blasted off a pastel patio, row by row.
final class WashClip: Clip {
    private let deck: SCNNode
    private let material: SCNMaterial
    private let wand = SCNNode()
    private let spray: SCNParticleSystem
    private let splash: SCNParticleSystem
    private let splashNode = SCNNode()
    private let mask: CGContext
    private let clean: CGImage
    private let maskSize = 192
    private let width: Float = 3.0
    private let depth: Float = 2.0
    private var last: CGPoint?

    override init(stage: Stage) {
        let tile = vivid.shuffled()
        clean = Textures.drawn(768, 512) { ctx in
            ctx.setFillColor(sceneColor(0xEDE6E3))
            ctx.fill(CGRect(x: 0, y: 0, width: 768, height: 512))
            let side: CGFloat = 128
            for row in 0..<4 {
                for col in 0..<6 {
                    let rect = CGRect(x: CGFloat(col) * side + 5, y: CGFloat(row) * side + 5, width: side - 10, height: side - 10)
                    ctx.setFillColor(sceneColor(tile[(row + col) % 3]))
                    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
                    ctx.fillPath()
                    ctx.setFillColor(CGColor(gray: 1, alpha: 0.25))
                    ctx.fill(CGRect(x: rect.minX + 12, y: rect.minY + 12, width: rect.width * 0.5, height: 6))
                }
            }
        }
        mask = CGContext(data: nil, width: maskSize, height: maskSize * 2 / 3, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        mask.setFillColor(CGColor(gray: 0, alpha: 1))
        mask.fill(CGRect(x: 0, y: 0, width: maskSize, height: maskSize * 2 / 3))

        let plane = SCNBox(width: CGFloat(width), height: 0.06, length: CGFloat(depth), chamferRadius: 0.01)
        material = Materials.pbr(sceneColor(0x777766), roughness: 0.9)
        material.normal.contents = Textures.noiseNormal(seed: 31, scale: 2, strength: 1.2)
        plane.firstMaterial = material
        deck = SCNNode(geometry: plane)
        deck.simdPosition = SIMD3(0, 0.03, 0)

        let pipe = SCNNode(geometry: SCNCylinder(radius: 0.022, height: 1.4))
        pipe.geometry!.firstMaterial = Materials.steel()
        pipe.simdPosition = SIMD3(0, 0.7, 0)
        let nozzle = SCNNode(geometry: SCNCone(topRadius: 0.035, bottomRadius: 0.015, height: 0.1))
        nozzle.geometry!.firstMaterial = Materials.pbr(sceneColor(0xFFC99E), roughness: 0.3)
        nozzle.simdPosition = SIMD3(0, 0.0, 0)
        wand.addChildNode(pipe)
        wand.addChildNode(nozzle)

        spray = SCNParticleSystem()
        spray.birthRate = 2600
        spray.particleLifeSpan = 0.09
        spray.particleVelocity = 6
        spray.spreadingAngle = 5
        spray.emittingDirection = SCNVector3(0, -1, 0)
        spray.particleSize = 0.006
        spray.particleColor = platformColor(CGColor(red: 0.92, green: 0.96, blue: 1, alpha: 0.55))
        spray.particleImage = Particles.dot
        spray.stretchFactor = 0.03
        spray.blendMode = .additive

        splash = SCNParticleSystem()
        splash.birthRate = 1600
        splash.particleLifeSpan = 0.35
        splash.particleLifeSpanVariation = 0.2
        splash.particleVelocity = 1.4
        splash.particleVelocityVariation = 1
        splash.spreadingAngle = 75
        splash.emittingDirection = SCNVector3(0, 1, 0)
        splash.particleSize = 0.008
        splash.particleColor = platformColor(CGColor(red: 0.9, green: 0.95, blue: 1, alpha: 0.6))
        splash.particleImage = Particles.dot
        splash.isAffectedByGravity = true
        splash.blendMode = .additive
        splash.stretchFactor = 0.015

        super.init(stage: stage)
        add(deck)
        add(wand)
        add(splashNode)
        nozzle.addParticleSystem(spray)
        splashNode.addParticleSystem(splash)
        stage.look(from: SIMD3(0, 2.6, 2.4), at: SIMD3(0, 0, 0.15), fieldOfView: 40)
        refresh()
    }

    override func update(_ t: Double) {
        // A serpentine sweep: four passes across, top to bottom.
        let passes = 4.0
        let sweep = Ease.clamp((t - 0.3) / 9.2) * passes
        let row = min(passes - 1, floor(sweep))
        var across = sweep - row
        if Int(row) % 2 == 1 { across = 1 - across }
        let x = (Float(across) - 0.5) * width * 0.98
        let z = (Float((row + 0.5) / passes) - 0.5) * depth
        wand.simdPosition = SIMD3(x, 0.22, z)
        wand.simdEulerAngles = SIMD3(0.12, 0, -0.08)
        splashNode.simdPosition = SIMD3(x, 0.07, z)

        // Clear grime along the path since the last frame.
        let px = CGFloat((x / width + 0.5)) * CGFloat(maskSize)
        let py = CGFloat(1 - (z / depth + 0.5)) * CGFloat(maskSize * 2 / 3)
        let point = CGPoint(x: px, y: py)
        mask.setStrokeColor(CGColor(gray: 1, alpha: 1))
        mask.setLineCap(.round)
        mask.setLineWidth(CGFloat(maskSize) / CGFloat(passes) / 3 * 1.25)
        mask.beginPath()
        mask.move(to: last ?? point)
        mask.addLine(to: point)
        mask.strokePath()
        last = point
        refresh()
    }

    private func refresh() {
        guard let cleaned = mask.makeImage() else { return }
        let image = Textures.drawn(384, 256) { ctx in
            let rect = CGRect(x: 0, y: 0, width: 384, height: 256)
            ctx.draw(Textures.grime, in: rect)
            ctx.saveGState()
            ctx.clip(to: rect, mask: cleaned)
            ctx.draw(clean, in: rect)
            ctx.restoreGState()
        }
        material.diffuse.contents = image
        // Wet where it's been washed.
        material.roughness.contents = Textures.drawn(96, 64) { ctx in
            let rect = CGRect(x: 0, y: 0, width: 96, height: 64)
            ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
            ctx.fill(rect)
            ctx.saveGState()
            ctx.clip(to: rect, mask: cleaned)
            ctx.setFillColor(CGColor(gray: 0.38, alpha: 1))
            ctx.fill(rect)
            ctx.restoreGState()
        }
    }
}

/// A rusty gear brought back to a mirror shine by a spinning wire wheel, then set turning.
final class RestoreClip: Clip {
    private let gear: SCNNode
    private let material: SCNMaterial
    private let brush = SCNNode()
    private let sparks: SCNParticleSystem
    private let tip = SCNNode()

    override init(stage: Stage) {
        material = Materials.pbr(CGColor(gray: 1, alpha: 1), roughness: 0.9, metalness: 0.25)
        material.diffuse.contents = Textures.rust(seed: UInt64.random(in: 0...99))
        material.normal.contents = Textures.noiseNormal(seed: 12, scale: 2, strength: 1.6)
        material.shaderModifiers = [.surface: """
            #pragma arguments
            float sweep;
            #pragma body
            float2 cell = floor(_surface.diffuseTexcoord * 60.0);
            float jitter = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
            float edge = sweep + jitter * 0.06;
            float k = smoothstep(edge + 0.03, edge - 0.03, _surface.position.x);
            _surface.diffuse = mix(_surface.diffuse, float4(0.96, 0.9, 0.93, 1.0), k);
            _surface.metalness = mix(_surface.metalness, 1.0, k);
            _surface.roughness = mix(_surface.roughness, 0.16, k);
            _surface.normal = normalize(mix(_surface.normal, _surface.geometryNormal, k));
            """]

        // A gear: a disc with teeth and a raised hub, merged into one mesh.
        let body = SCNNode()
        let disc = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.16))
        body.addChildNode(disc)
        let hub = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.26))
        body.addChildNode(hub)
        let teeth = 18
        for i in 0..<teeth {
            let tooth = SCNNode(geometry: SCNBox(width: 0.13, height: 0.16, length: 0.16, chamferRadius: 0.02))
            let a = Float(i) / Float(teeth) * 2 * .pi
            tooth.simdPosition = SIMD3(cos(a) * 0.68, 0, sin(a) * 0.68)
            tooth.simdEulerAngles = SIMD3(0, -a, 0)
            body.addChildNode(tooth)
        }
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi
            let hole = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.17))
            hole.name = "hole"
            hole.simdPosition = SIMD3(cos(a) * 0.4, 0.005, sin(a) * 0.4)
            hole.geometry!.firstMaterial = Materials.pbr(CGColor(gray: 0.05, alpha: 1), roughness: 0.8)
            body.addChildNode(hole)
        }
        for node in body.childNodes where node.name != "hole" {
            node.geometry?.firstMaterial = material
        }
        gear = body.flattenedClone()
        gear.simdPosition = SIMD3(0, 0.8, 0)
        gear.simdEulerAngles = SIMD3(1.25, 0, 0)

        let wheel = SCNNode(geometry: SCNCylinder(radius: 0.16, height: 0.05))
        let bristles = Materials.pbr(sceneColor(0xC9A86A), roughness: 0.35, metalness: 1)
        bristles.normal.contents = Textures.noiseNormal(seed: 40, scale: 8, strength: 3)
        wheel.geometry!.firstMaterial = bristles
        wheel.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        let arm = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.7))
        arm.geometry!.firstMaterial = Materials.pbr(sceneColor(0xA6BDF7), roughness: 0.4)
        arm.simdPosition = SIMD3(0, 0.38, 0)
        brush.addChildNode(wheel)
        brush.addChildNode(arm)
        tip.simdPosition = SIMD3(0, -0.15, 0)
        brush.addChildNode(tip)

        sparks = Particles.glints(sceneColor(0xFFB45A), count: 0, speed: 2.2, life: 0.35, stretch: 0.04)
        sparks.loops = true
        sparks.birthRate = 500
        sparks.emissionDuration = 1
        sparks.emittingDirection = SCNVector3(-0.3, 1, 0.6)
        sparks.spreadingAngle = 45

        super.init(stage: stage)
        add(gear)
        add(brush)
        tip.addParticleSystem(sparks)
        stage.look(from: SIMD3(0, 1.5, 2.6), at: SIMD3(0, 0.75, 0), fieldOfView: 38)
    }

    override func update(_ t: Double) {
        // The wheel works left to right in three passes, then the gear spins, polished.
        let work = Ease.clamp((t - 0.4) / 7.0)
        let x = -0.85 + Float(work) * 1.7
        let bob = Float(sin(t * 9) * 0.03)
        let pass = Float(sin(t * 2.4)) * 0.45
        brush.simdPosition = SIMD3(x, 1.0 + bob + pass * 0.4, 0.45 + pass * 0.2)
        brush.childNodes[0].simdEulerAngles = SIMD3(Float(t * 40), 0, .pi / 2)
        sparks.birthRate = work > 0 && work < 1 ? 520 : 0
        if work >= 1 { brush.simdPosition.y += Float(Ease.smooth((t - 7.4) / 0.6)) * 2 }

        // Where the wheel has been, in the camera's space, is clean.
        let edge = stage.camera.simdConvertPosition(SIMD3(x + 0.08, 0.8, 0), from: nil).x
        material.setValue(NSNumber(value: work >= 1 ? 50 : edge), forKey: "sweep")

        let spin = Ease.inQuad((t - 7.6) / 1.2) * (t - 7.6)
        gear.simdOrientation = simd_quatf(angle: 1.25, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: Float(max(0, spin)) * 1.4, axis: SIMD3(0, 1, 0))
    }
}

// MARK: - Impossible satisfying

/// Fruit made of glass, sliced clean through; the halves fall open to show their insides.
final class GlassFruitClip: Clip {
    private struct Fruit { var tint: UInt32; var flesh: UInt32; var cap: CGImage; var squash: Float }
    private var halves: [SCNNode] = []
    private var whole = SCNNode()
    private let knife = makeKnife()
    private var fruits: [Fruit] = []
    private var current = -1
    private var burst = Set<Int>()
    private let radius: Float = 0.5
    private let each = 10.0 / 3

    override init(stage: Stage) {
        super.init(stage: stage)
        fruits = [
            Fruit(tint: 0xFF5E7E, flesh: 0xFFE3E6, cap: Self.appleCap(), squash: 0.92),
            Fruit(tint: 0xFFA23A, flesh: 0xFFC46B, cap: Self.orangeCap(), squash: 0.96),
            Fruit(tint: 0x8FD14F, flesh: 0xB5E86A, cap: Self.kiwiCap(), squash: 0.82),
        ]
        add(knife)
        stage.look(from: SIMD3(1.1, 1.3, 2.1), at: SIMD3(0, 0.38, 0), fieldOfView: 34)
    }

    override func update(_ t: Double) {
        let k = min(2, Int(t / each))
        let u = t - Double(k) * each
        if k != current { build(k) }

        // The fruit drops in, the knife comes down, the halves fall open.
        let drop = Ease.outCubic(u / 0.45)
        let bounce = Float(Ease.spring(u - 0.45, frequency: 2.5, damping: 6) * 0.05)
        let restY = radius * fruits[k].squash
        let y = restY + Float(1 - drop) * 1.4 + (u > 0.45 ? abs(bounce) : 0)
        let open = Ease.smooth((u - 1.35) / 0.55)
        for (n, half) in halves.enumerated() {
            let side: Float = n == 0 ? -1 : 1
            half.simdPosition = SIMD3(side * Float(open) * 0.55, y + Float(open) * (radius - restY), 0)
            half.simdEulerAngles = SIMD3(0, 0, -side * Float(open) * .pi / 2)
        }
        whole.simdPosition.y = y

        var knifeY: Float = 1.6
        if u > 0.6 && u < 1.6 {
            knifeY = 1.6 - Float(Ease.smooth((u - 0.6) / 0.6)) * 1.6
        } else if u >= 1.6 {
            knifeY = Float(Ease.smooth((u - 1.6) / 0.6)) * 1.6
        }
        knife.simdPosition = SIMD3(0, knifeY, -0.35)
        let cut = u > 1.2
        whole.isHidden = cut
        halves.forEach { $0.isHidden = !cut }
        if u > 1.35, !burst.contains(k) {
            burst.insert(k)
            stage.burst(Particles.glints(sceneColor(0xFFFFFF), count: 160, speed: 1.1, life: 1.2), at: SIMD3(0, radius, 0))
        }
        // Slide out at the end of each fruit's turn.
        let leave = Float(Ease.smooth((u - each + 0.5) / 0.5))
        stage.content.childNodes.filter { $0 !== knife }.forEach { $0.opacity = CGFloat(1 - leave) }
    }

    private func build(_ k: Int) {
        current = k
        whole.removeFromParentNode()
        halves.forEach { $0.removeFromParentNode() }
        let fruit = fruits[k]
        whole = fruitNode(fruit, side: 0)
        halves = [fruitNode(fruit, side: -1), fruitNode(fruit, side: 1)]
        add(whole)
        halves.forEach(add)
    }

    /// A whole fruit, or one half (side -1 keeps x < 0, +1 keeps x > 0) with its cut face.
    private func fruitNode(_ fruit: Fruit, side: Float) -> SCNNode {
        let node = SCNNode()
        let clip = side == 0 ? nil : """
            #pragma body
            if (_geometry.position.x * \(side) < 0.0) {
                _geometry.position.x = 0.0;
                _geometry.normal = float3(\(-side), 0.0, 0.0);
            }
            """

        let skin = SCNSphere(radius: CGFloat(radius))
        skin.segmentCount = 96
        let glass = Materials.glass(sceneColor(fruit.tint), opacity: 0.6)
        glass.roughness.contents = NSNumber(value: 0.0)
        if let clip { glass.shaderModifiers = [.geometry: clip] }
        skin.firstMaterial = glass
        let outer = SCNNode(geometry: skin)
        outer.simdScale = SIMD3(1, fruit.squash, 1)
        node.addChildNode(outer)

        let core = SCNSphere(radius: CGFloat(radius * 0.86))
        core.segmentCount = 72
        let flesh = Materials.glass(sceneColor(fruit.flesh), opacity: 0.55)
        flesh.roughness.contents = NSNumber(value: 0.25)
        flesh.emission.contents = sceneColor(fruit.flesh)
        flesh.emission.intensity = 0.3
        if let clip { flesh.shaderModifiers = [.geometry: clip] }
        core.firstMaterial = flesh
        let inner = SCNNode(geometry: core)
        inner.simdScale = SIMD3(1, fruit.squash, 1)
        node.addChildNode(inner)

        if side != 0 {
            let face = SCNNode(geometry: SCNCylinder(radius: CGFloat(radius * 0.995), height: 0.004))
            let m = Materials.glass(CGColor(gray: 1, alpha: 1), opacity: 1)
            m.diffuse.contents = fruit.cap
            m.emission.contents = fruit.cap
            m.emission.intensity = 0.35
            m.roughness.contents = NSNumber(value: 0.06)
            face.geometry!.firstMaterial = m
            face.simdEulerAngles = SIMD3(0, 0, .pi / 2)
            face.simdScale = SIMD3(1, 1, 1)
            face.simdPosition = SIMD3(side * 0.002, 0, 0)
            let squashed = SCNNode()
            squashed.simdScale = SIMD3(1, fruit.squash, 1)
            squashed.addChildNode(face)
            node.addChildNode(squashed)
        }

        let stem = SCNNode(geometry: SCNCylinder(radius: 0.022, height: 0.16))
        stem.geometry!.firstMaterial = Materials.glass(sceneColor(0x7A4E3A), opacity: 0.85)
        stem.simdPosition = SIMD3(side == 0 ? 0 : side * 0.012, radius * fruit.squash + 0.05, 0)
        stem.simdEulerAngles = SIMD3(0, 0, 0.2)
        if fruit.squash < 0.9 { stem.isHidden = true }
        node.addChildNode(stem)
        return node
    }

    private static func capBase(_ ctx: CGContext, _ inner: CGColor, _ outer: CGColor) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [inner, outer] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                               endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [.drawsAfterEndLocation])
    }

    private static func appleCap() -> CGImage {
        Textures.drawn(512, 512) { ctx in
            capBase(ctx, sceneColor(0xFFF4F0), sceneColor(0xFF8FA6))
            ctx.setStrokeColor(sceneColor(0xF2C9A8))
            ctx.setLineWidth(6)
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi
                ctx.move(to: CGPoint(x: 256, y: 256))
                ctx.addLine(to: CGPoint(x: 256 + cos(a) * 110, y: 256 + sin(a) * 110))
                ctx.strokePath()
                ctx.setFillColor(sceneColor(0x5B3426))
                ctx.fillEllipse(in: CGRect(x: 256 + cos(a) * 70 - 12, y: 256 + sin(a) * 70 - 20, width: 24, height: 40))
            }
        }
    }

    private static func orangeCap() -> CGImage {
        Textures.drawn(512, 512) { ctx in
            capBase(ctx, sceneColor(0xFFE0A8), sceneColor(0xFF9A3A))
            ctx.setStrokeColor(sceneColor(0xFFF6E6))
            ctx.setLineWidth(7)
            for i in 0..<10 {
                let a = Double(i) / 10 * 2 * .pi
                ctx.move(to: CGPoint(x: 256 + cos(a) * 22, y: 256 + sin(a) * 22))
                ctx.addLine(to: CGPoint(x: 256 + cos(a) * 225, y: 256 + sin(a) * 225))
                ctx.strokePath()
            }
            ctx.setLineWidth(18)
            ctx.strokeEllipse(in: CGRect(x: 22, y: 22, width: 468, height: 468))
        }
    }

    private static func kiwiCap() -> CGImage {
        Textures.drawn(512, 512) { ctx in
            capBase(ctx, sceneColor(0xFFFBE6), sceneColor(0x7CC23F))
            ctx.setFillColor(sceneColor(0x1E1A12))
            for i in 0..<34 {
                let a = Double(i) / 34 * 2 * .pi
                let r = 95.0 + Double(i % 3) * 10
                ctx.fillEllipse(in: CGRect(x: 256 + cos(a) * r - 6, y: 256 + sin(a) * r - 10, width: 12, height: 20))
            }
            ctx.setFillColor(sceneColor(0xFFFDF0))
            ctx.fillEllipse(in: CGRect(x: 206, y: 206, width: 100, height: 100))
        }
    }
}

/// A keyboard whose keys are made of jelly, glass and liquid chrome, typed on in a
/// fast, even rhythm; every key squashes and springs back.
final class KeyboardClip: Clip {
    private var keys: [SCNNode] = []
    private var presses: [(key: Int, at: Double)] = []
    private var materials: [SCNMaterial] = []
    private var style = -1

    override init(stage: Stage) {
        super.init(stage: stage)
        let base = SCNNode(geometry: SCNBox(width: 2.3, height: 0.12, length: 0.95, chamferRadius: 0.06))
        base.geometry!.firstMaterial = Materials.pbr(sceneColor(0xD9D2E6), roughness: 0.28, metalness: 1)
        base.simdPosition = SIMD3(0, 0.06, 0)
        add(base)

        let rows: [(count: Int, offset: Float)] = [(10, 0), (10, 0.05), (9, 0.1), (7, 0.15)]
        let pitch: Float = 0.205
        for (r, row) in rows.enumerated() {
            for c in 0..<row.count {
                let key = SCNNode(geometry: SCNBox(width: 0.17, height: 0.09, length: 0.17, chamferRadius: 0.035))
                key.simdPosition = SIMD3(-Float(9) * pitch / 2 + row.offset + Float(c) * pitch, 0.165, -0.3 + Float(r) * pitch)
                keys.append(key)
                add(key)
            }
        }
        let space = SCNNode(geometry: SCNBox(width: 0.95, height: 0.09, length: 0.17, chamferRadius: 0.035))
        space.simdPosition = SIMD3(0.05, 0.165, -0.3 + 4 * pitch)
        keys.append(space)
        add(space)

        // A steady, quick rhythm across the keys.
        var at = 0.3
        while at < length {
            presses.append((key: Int.random(in: 0..<keys.count), at: at))
            at += Double.random(in: 0.07...0.16)
        }
        stage.look(from: SIMD3(0.6, 1.2, 1.55), at: SIMD3(0, 0.12, 0.05), fieldOfView: 34)
    }

    override func update(_ t: Double) {
        let s = min(2, Int(t / (length / 3)))
        if s != style { restyle(s) }

        var squash = [Double](repeating: 0, count: keys.count)
        for press in presses where press.at <= t && t - press.at < 0.6 {
            let age = t - press.at
            let amount = age < 0.06 ? age / 0.06 : Ease.spring(age - 0.06, frequency: style == 0 ? 4 : 6, damping: style == 0 ? 6 : 11)
            squash[press.key] = max(squash[press.key], amount)
            if age < 1.0 / 30 {
                let p = keys[press.key].simdWorldPosition
                let tint = style == 2 ? sceneColor(0xFFFFFF) : sceneColor(pastels[press.key % pastels.count])
                stage.burst(Particles.glints(tint, count: 26, speed: 0.6, life: 0.5), at: p + SIMD3(0, 0.05, 0))
            }
        }
        for (i, key) in keys.enumerated() {
            let a = Float(squash[i])
            key.simdScale = SIMD3(1 + a * 0.16, 1 - a * 0.45, 1 + a * 0.16)
            key.simdPosition.y = 0.165 - a * 0.025
        }
    }

    private func restyle(_ s: Int) {
        style = s
        for (i, key) in keys.enumerated() {
            let tint = sceneColor(vivid[(i + i / 10) % vivid.count])
            let m: SCNMaterial
            switch s {
            case 0:
                m = Materials.glass(tint, opacity: 0.6)
            case 1:
                m = Materials.glass(CGColor(gray: 1, alpha: 1), opacity: 0.25)
                m.diffuse.contents = tint.copy(alpha: 0.35)
            default:
                m = Materials.pbr(tint, roughness: 0.04, metalness: 1)
                m.clearCoat.contents = NSNumber(value: 1)
            }
            key.geometry!.firstMaterial = m
        }
    }
}

/// A bar of crystal, chrome or opal, eaten square by square: each one snaps off with
/// a glittering crunch and is lifted away.
final class CrystalBarClip: Clip {
    private var squares: [SCNNode] = []
    private var bites: [Double] = []
    private var crunched = Set<Int>()
    private var style = -1
    private let cols = 4, rows = 2
    private let side: Float = 0.34

    override init(stage: Stage) {
        super.init(stage: stage)
        for r in 0..<rows {
            for c in 0..<cols {
                let node = SCNNode(geometry: SCNBox(width: CGFloat(side - 0.02), height: 0.16, length: CGFloat(side - 0.02), chamferRadius: 0.035))
                node.simdPosition = SIMD3((Float(c) - Float(cols - 1) / 2) * side, 0.08, (Float(r) - 0.5) * side)
                squares.append(node)
                add(node)
            }
        }
        let order = (0..<squares.count).sorted { a, b in (a % cols, a / cols) > (b % cols, b / cols) }
        squares = order.map { squares[$0] }
        bites = (0..<squares.count).map { 0.6 + Double($0) * 1.05 }
        stage.look(from: SIMD3(0.4, 1.25, 1.75), at: SIMD3(0, 0.1, 0), fieldOfView: 34)
    }

    override func update(_ t: Double) {
        let s = min(2, Int(t / (length / 3)))
        if s != style { restyle(s) }
        for (i, square) in squares.enumerated() {
            let u = t - bites[i]
            guard u > 0 else { continue }
            // Snap: a tilt on its hinge, a crunch, then up and away.
            let tilt = Float(Ease.smooth(u / 0.18)) * 0.5
            let lift = Float(Ease.inQuad((u - 0.2) / 0.55))
            square.simdEulerAngles = SIMD3(-tilt - lift * 0.8, lift * 0.6, tilt * 0.3)
            square.simdPosition.y = 0.08 + lift * 1.6
            square.simdPosition.z = (square.simdPosition.z) + lift * 0.02
            square.opacity = CGFloat(1 - Ease.smooth((u - 0.55) / 0.2))
            if u > 0.18, !crunched.contains(i) {
                crunched.insert(i)
                let p = square.simdPosition
                let tint = style == 1 ? sceneColor(0xFFFFFF) : sceneColor(pastels[i % pastels.count])
                let shards = Particles.glints(tint, count: 140, speed: 1.0, life: 1.4)
                shards.particleSize = 0.016
                shards.isLightingEnabled = false
                stage.burst(shards, at: p)
                let crumbs = Particles.crumbs(tint, count: 60, size: 0.012, collider: stage.table)
                stage.burst(crumbs, at: p)
            }
        }
    }

    private func restyle(_ s: Int) {
        style = s
        for (i, square) in squares.enumerated() where square.opacity > 0 {
            let tint = sceneColor(vivid[i % vivid.count])
            let m: SCNMaterial
            switch s {
            case 0:
                m = Materials.glass(tint, opacity: 0.5)
                m.emission.contents = tint
                m.emission.intensity = 0.08
            case 1:
                m = Materials.pbr(sceneColor(0xF6D2CF), roughness: 0.05, metalness: 1)
            default:
                m = Materials.pbr(CGColor(gray: 0.95, alpha: 1), roughness: 0.12)
                m.clearCoat.contents = NSNumber(value: 1)
                m.shaderModifiers = [.surface: """
                    #pragma body
                    float f = 1.0 - abs(dot(_surface.normal, _surface.view));
                    float h = f * 2.2 + scn_frame.time * 0.15 + _surface.diffuseTexcoord.x * 0.6;
                    float3 c = 0.62 + 0.3 * cos(6.2831 * (h + float3(0.0, 0.33, 0.67)));
                    _surface.diffuse = float4(c, 1.0);
                    _surface.emission = float4(c * f * 0.35, 1.0);
                    """]
                m.emission.contents = CGColor(gray: 0, alpha: 1)
            }
            square.geometry!.firstMaterial = m
        }
    }
}
