import CoreGraphics
import CoreText
import Foundation

/// The two worlds of the runner that plays itself beside the puzzle.
enum RunnerStyle: String, CaseIterable, Identifiable {
    /// A winding brick causeway above the clouds: corners, gaps, hurdles and arches.
    case trail
    /// A straight three-lane toy-town street: barriers, parked carts and oncoming ones.
    case street

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trail: return "Trail"
        case .street: return "Street"
        }
    }

    var blurb: String {
        switch self {
        case .trail: return "Above the clouds"
        case .street: return "Toy-town traffic"
        }
    }
}

/// An endless runner that plays itself. It's a real game: obstacles are generated ahead,
/// an autopilot reads the track and jumps, slides and changes lanes, and collisions are
/// checked. A miss only makes the runner stumble, so a run never ends.
///
/// The track is a centre line made of straight segments with square corners. Positions on
/// it are `s`, the distance along the line, and `u`, the offset to the right of it.
final class RunnerGame {

    enum Kind { case hurdle, bar, block, gap, cart }

    struct Obstacle {
        var kind: Kind
        var s: Double
        var length: Double
        var lanes: [Int]
        /// Carts that roll toward the runner, in units a second.
        var speed: Double = 0
        var color: Int
        var hit = false

        var end: Double { s + length }

        func coversLane(_ lane: Int) -> Bool { lanes.contains(lane) }

        /// Whether a body centred `u` across the track would touch this.
        func covers(_ u: Double) -> Bool {
            kind == .gap || lanes.contains { abs(u - RunnerGame.laneU($0)) < 0.75 }
        }
    }

    struct Coin {
        var s: Double
        var lane: Int
        var height: Double
    }

    /// A straight piece of track. `heading` counts quarter turns clockwise from north and
    /// isn't wrapped, so the camera can ease between headings without spinning the long way.
    struct Segment {
        var start: Double
        var origin: SIMD2<Double>
        var heading: Int
    }

    static let laneWidth = 1.2
    static let halfWidth = 1.8
    static let gravity = 24.0
    static let jumpVelocity = 7.5
    /// Seconds from take-off to the top of a jump.
    static let apex = jumpVelocity / gravity
    static let startSpeed = 7.0
    static let maxSpeed = 13.0
    static let lateralSpeed = 9.0

    static func laneU(_ lane: Int) -> Double { Double(lane - 1) * laneWidth }

    let style: RunnerStyle

    private(set) var time = 0.0
    private(set) var s = 0.0
    private(set) var u = 0.0
    private(set) var y = 0.0
    private(set) var lane = 1
    private(set) var speed = RunnerGame.startSpeed
    private(set) var stars = 0
    /// Obstacles the autopilot failed to clear. It shouldn't, so this stays at zero.
    private(set) var hits = 0
    private(set) var obstacles: [Obstacle] = []
    private(set) var coins: [Coin] = []
    private(set) var segments: [Segment]
    /// The camera's heading in radians, easing round corners behind the runner.
    private(set) var cameraYaw = 0.0
    private(set) var sliding = 0.0
    private(set) var stumbling = 0.0

    private var vy = 0.0
    private var frontier = 22.0
    private var lastTurn = 0
    private var cartLaneBusy: [Double] = [-.infinity, -.infinity, -.infinity]
    private var rng: SplitMix

    init(style: RunnerStyle, seed: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        self.style = style
        rng = SplitMix(seed: seed)
        segments = [Segment(start: -40, origin: SIMD2(0, -40), heading: 0)]
        extend()
    }

    var isAirborne: Bool { y > 0 || vy > 0 }

    // MARK: - Track

    static func direction(_ heading: Int) -> SIMD2<Double> {
        switch ((heading % 4) + 4) % 4 {
        case 0: return SIMD2(0, 1)
        case 1: return SIMD2(1, 0)
        case 2: return SIMD2(0, -1)
        default: return SIMD2(-1, 0)
        }
    }

    static func right(of d: SIMD2<Double>) -> SIMD2<Double> { SIMD2(d.y, -d.x) }

    func segmentIndex(at s: Double) -> Int {
        var i = segments.count - 1
        while i > 0 && segments[i].start > s { i -= 1 }
        return i
    }

    func end(ofSegment i: Int) -> Double {
        i + 1 < segments.count ? segments[i + 1].start : .infinity
    }

    /// Ground position of a track point, in the plane: x east, y north.
    func ground(_ s: Double, _ u: Double, segment i: Int? = nil) -> SIMD2<Double> {
        let seg = segments[i ?? segmentIndex(at: s)]
        let d = Self.direction(seg.heading)
        return seg.origin + d * (s - seg.start) + Self.right(of: d) * u
    }

    /// The next corner ahead, if the trail has one.
    var nextTurn: Double? {
        segments.first { $0.start > s }?.start
    }

    // MARK: - Simulation

    func step(_ dt: Double) {
        time += dt
        let cruise = min(Self.maxSpeed, Self.startSpeed + time * 0.025)
        speed += (cruise - speed) * min(1, dt * 1.2)
        if stumbling > 0 { stumbling -= dt }

        think()

        let goal = Self.laneU(lane)
        let reach = Self.lateralSpeed * dt
        u += max(-reach, min(reach, goal - u))

        if isAirborne {
            vy -= Self.gravity * dt
            y += vy * dt
            if y <= 0 { y = 0; vy = 0 }
        }
        if sliding > 0 { sliding = max(0, sliding - dt) }

        s += speed * dt
        for i in obstacles.indices where obstacles[i].speed > 0 {
            obstacles[i].s -= obstacles[i].speed * dt
        }

        collide()
        collect()
        extend()

        let heading = Double(segments[segmentIndex(at: s)].heading) * .pi / 2
        cameraYaw += (heading - cameraYaw) * min(1, dt * 5)
    }

    /// The autopilot: pick a lane, then jump or slide for whatever is in it.
    private func think() {
        let ahead = obstacles.filter { !$0.hit && $0.end > s - 0.3 }

        func arrival(_ o: Obstacle) -> Double { max(0, o.s - s) / (speed + o.speed) }
        func walls(within seconds: Double) -> [Obstacle] {
            ahead.filter { ($0.kind == .block || $0.kind == .cart) && arrival($0) < seconds }
        }

        /// A lane can be taken if nothing walls it off soon, and nothing close by is in the
        /// lanes on the way: a wall alongside, or a hurdle too near to time a jump for.
        func open(_ l: Int, within seconds: Double) -> Bool {
            guard !walls(within: seconds).contains(where: { $0.coversLane(l) }) else { return false }
            let alongside = ahead.filter { $0.kind != .gap && arrival($0) < 0.5 }
            let crossed = l < lane ? Array(l..<lane) : Array((lane + 1)...max(lane + 1, l))
            return !alongside.contains { o in crossed.contains { o.coversLane($0) } }
        }

        var want = lane
        let threats = walls(within: 1.2)
        if let turn = nextTurn, turn - s < 9 {
            // Corners are kept clear of obstacles, so line up in the middle for them.
            want = 1
        } else if threats.contains(where: { $0.coversLane(want) }) {
            want = [lane - 1, lane + 1, lane - 2, lane + 2]
                .filter { (0...2).contains($0) }
                .first { open($0, within: 1.2) } ?? lane
        } else if threats.isEmpty {
            // Nothing to dodge: go after the next stars, if their lane is clear.
            if let coin = coins.filter({ $0.s > s + 2 && $0.s < s + speed * 1.4 }).min(by: { $0.s < $1.s }),
               coin.lane != lane, open(coin.lane, within: 2.2) {
                want = coin.lane
            }
        }
        lane = want

        for o in ahead where o.covers(u) || o.coversLane(want) {
            let centre = o.s + o.length / 2
            switch o.kind {
            case .hurdle, .gap:
                if !isAirborne, centre - s <= speed * Self.apex + 0.05, centre - s > -0.3 {
                    sliding = 0
                    vy = Self.jumpVelocity
                    y = 0.001
                }
            case .bar:
                if o.s - s <= speed * 0.12 + 0.4, !isAirborne {
                    sliding = max(sliding, (o.end + 0.5 - s) / speed)
                }
            case .block, .cart:
                break
            }
        }
    }

    private func collide() {
        for i in obstacles.indices where !obstacles[i].hit {
            let o = obstacles[i]
            guard s + 0.25 > o.s, s - 0.25 < o.end, o.covers(u) else { continue }
            let hit: Bool
            switch o.kind {
            case .hurdle: hit = y < 0.55
            case .bar: hit = sliding <= 0
            case .block, .cart: hit = true
            case .gap: hit = s > o.s + 0.15 && s < o.end - 0.15 && !isAirborne
            }
            guard hit else { continue }
            obstacles[i].hit = true
            hits += 1
            stumbling = 0.6
            speed *= 0.6
            // Over a gap, a stumble is a scramble up the far side.
            if o.kind == .gap { vy = Self.jumpVelocity; y = 0.001 }
        }
    }

    private func collect() {
        let before = coins.count
        coins.removeAll { c in
            abs(c.s - s) < 0.5 && abs(Self.laneU(c.lane) - u) < 0.6 && abs(y + 0.7 - c.height) < 1.0
        }
        stars += before - coins.count
    }

    // MARK: - Generation

    private func extend() {
        if style == .trail {
            while let last = segments.last, last.start < s + 160 {
                let length = Double(rng.int(in: 30...52))
                // Don't turn the same way three times running; it looks like a spiral.
                var turn = rng.bool() ? 1 : -1
                if turn == lastTurn, rng.chance(0.6) { turn = -turn }
                lastTurn = turn
                segments.append(Segment(
                    start: last.start + length,
                    origin: last.origin + Self.direction(last.heading) * length,
                    heading: last.heading + turn
                ))
            }
        }

        while frontier < s + 90 {
            if style == .trail, let turn = segments.first(where: { $0.start > frontier - 7 && $0.start < frontier + 10 }) {
                frontier = turn.start + 7
                continue
            }
            let v = min(Self.maxSpeed, speed + 2)
            place(at: frontier, speed: v)
            let gap = max(11, v * 1.15) + Double(rng.int(in: 0...8))
            if rng.chance(0.7) { lay(coinsFrom: frontier + 3, to: frontier + gap - 3) }
            frontier += gap
        }

        obstacles.removeAll { $0.end < s - 8 }
        coins.removeAll { $0.s < s - 4 }
        if segments.count > 3, segments[1].start < s - 60 { segments.removeFirst() }
    }

    private func place(at slot: Double, speed v: Double) {
        let color = rng.int(in: 0...5)
        if style == .trail {
            let all = [0, 1, 2]
            switch rng.int(in: 0...19) {
            case 0...4:
                obstacles.append(Obstacle(kind: .hurdle, s: slot, length: 0.3, lanes: all, color: color))
            case 5...8:
                obstacles.append(Obstacle(kind: .bar, s: slot, length: 0.4, lanes: all, color: color))
            case 9...12:
                obstacles.append(Obstacle(kind: .gap, s: slot.rounded(), length: Double(rng.int(in: 2...3)), lanes: all, color: color))
            default:
                let count = rng.chance(0.55) ? 1 : 2
                obstacles.append(Obstacle(kind: .block, s: slot, length: 1, lanes: Array(all.shuffled(using: &rng).prefix(count)), color: color))
            }
            return
        }

        // Lanes an oncoming cart will pass through here are off limits, and anything that
        // walls lanes off must leave one of the free ones open.
        let free = [0, 1, 2].filter { cartLaneBusy[$0] < slot - 2 }
        guard !free.isEmpty else { return }
        let roll = rng.int(in: 0...19)
        switch roll {
        case 0...3:
            let lanes = Array(free.shuffled(using: &rng).prefix(rng.int(in: 1...free.count)))
            obstacles.append(Obstacle(kind: .hurdle, s: slot, length: 0.3, lanes: lanes, color: color))
        case 4...6:
            let lanes = Array(free.shuffled(using: &rng).prefix(rng.int(in: 1...free.count)))
            obstacles.append(Obstacle(kind: .bar, s: slot, length: 0.4, lanes: lanes, color: color))
        case 7...11 where free.count >= 2:
            let count = free.count == 3 && rng.chance(0.4) ? 2 : 1
            obstacles.append(Obstacle(kind: .block, s: slot, length: 1, lanes: Array(free.shuffled(using: &rng).prefix(count)), color: color))
        case 12...15 where free.count >= 2:
            let count = free.count == 3 && rng.chance(0.35) ? 2 : 1
            obstacles.append(Obstacle(kind: .cart, s: slot, length: 6, lanes: Array(free.shuffled(using: &rng).prefix(count)), color: color))
        case 16...19 where free.count >= 2:
            // Rolls toward the runner so the two meet at this slot.
            // Plan with the speed the runner will really have, not the cautious estimate
            // the spacing uses, or the two meet early, maybe beside something else.
            let lane = free.randomElement(using: &rng)!
            let cartSpeed = 4.5
            let start = slot + cartSpeed * (slot - s) / min(Self.maxSpeed, speed + 0.3)
            obstacles.append(Obstacle(kind: .cart, s: start, length: 5, lanes: [lane], speed: cartSpeed, color: color))
            cartLaneBusy[lane] = start + 5
        default:
            obstacles.append(Obstacle(kind: .hurdle, s: slot, length: 0.3, lanes: [free[0]], color: color))
        }
    }

    private func lay(coinsFrom a: Double, to b: Double) {
        guard b - a > 3 else { return }
        let lanes = style == .street ? [0, 1, 2].filter { cartLaneBusy[$0] < a - 2 } : [0, 1, 2]
        guard let lane = lanes.randomElement(using: &rng) else { return }
        let turns = segments.dropFirst().map(\.start)
        var c = a
        while c < min(b, a + 10) {
            if !turns.contains(where: { abs($0 - c) < 9 }) {
                coins.append(Coin(s: c, lane: lane, height: 0.7))
            }
            c += 1.6
        }
    }
}

/// A small, fast, seedable random number generator, so a test can replay a run.
struct SplitMix: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func bool() -> Bool { Bool.random(using: &self) }
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
}

// MARK: - Drawing

/// Draws a `RunnerGame` frame with Core Graphics, into whatever context it's given: a
/// video frame for Picture in Picture, or a bitmap in the tests.
enum RunnerRenderer {

    private struct RGB {
        var r, g, b: Double

        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }

        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        func mix(_ o: RGB, _ t: Double) -> RGB {
            let t = max(0, min(1, t))
            return RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
        }

        func scaled(_ k: Double) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }

        func cg(_ alpha: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: alpha) }
    }

    /// The puzzle's pastels.
    private static let palette: [RGB] = [0xF7A8C4, 0xFFC99E, 0xA8E6B8, 0xA6BDF7, 0xC8AEF0, 0xFFE58A].map(RGB.init)
    private static let ink = RGB(0x4A4458)

    private struct Camera {
        var position: SIMD3<Double>
        var yaw: Double
        var pitch = 0.28
        var focal: Double
        var centre: CGPoint

        func project(_ p: SIMD3<Double>) -> (point: CGPoint, depth: Double)? {
            let f = SIMD2(sin(yaw), cos(yaw))
            let dx = p.x - position.x, dy = p.y - position.y, dz = p.z - position.z
            let across = dx * f.y - dz * f.x
            let along = dx * f.x + dz * f.y
            let depth = along * cos(pitch) - dy * sin(pitch)
            let up = dy * cos(pitch) + along * sin(pitch)
            guard depth > 0.3 else { return nil }
            return (CGPoint(x: centre.x + focal * across / depth, y: centre.y - focal * up / depth), depth)
        }

        var horizon: Double { centre.y - focal * tan(pitch) }
    }

    /// Something to paint, and how far away it is, for painting far to near.
    private struct Item {
        var depth: Double
        var paint: (CGContext) -> Void
    }

    static let drawDistance = 62.0

    static func draw(_ game: RunnerGame, in ctx: CGContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        let trackPoint = game.ground(game.s, game.u * 0.45)
        let look = SIMD2(sin(game.cameraYaw), cos(game.cameraYaw))
        let eye = trackPoint - look * 4.0
        let camera = Camera(
            position: SIMD3(eye.x, 2.6, eye.y),
            yaw: game.cameraYaw,
            focal: h * 1.05,
            centre: CGPoint(x: w / 2, y: h / 2)
        )
        let trail = game.style == .trail
        let fog = trail ? RGB(0xF6E7F2) : RGB(0xF4E6F0)

        drawSky(game, ctx: ctx, camera: camera, w: w, h: h, fog: fog)

        var ground: [Item] = []
        var things: [Item] = []

        func shade(_ c: RGB, _ depth: Double) -> RGB { c.mix(fog, (depth - 24) / (drawDistance - 24)) }

        /// `under` paints it before anything else at the same distance: mortar beneath
        /// bricks, road beneath its markings.
        func quad(_ pts: [SIMD3<Double>], _ color: RGB, into list: inout [Item], under: Bool = false) {
            var screen: [CGPoint] = []
            var depth = 0.0
            for p in pts {
                guard let q = camera.project(p) else { return }
                screen.append(q.point)
                depth += q.depth
            }
            depth /= Double(pts.count)
            guard depth < drawDistance else { return }
            let fill = shade(color, depth).cg()
            list.append(Item(depth: depth + (under ? 0.05 : 0)) { ctx in
                ctx.beginPath()
                ctx.addLines(between: screen)
                ctx.closePath()
                ctx.setFillColor(fill)
                ctx.fillPath()
            })
        }

        func point(_ s: Double, _ u: Double, _ y: Double, _ seg: Int) -> SIMD3<Double> {
            let g = game.ground(s, u, segment: seg)
            return SIMD3(g.x, y, g.y)
        }

        /// A box on the track, painted face by face; only faces turned toward the camera.
        func box(s0: Double, s1: Double, u0: Double, u1: Double, y0: Double, y1: Double, color: RGB, depthBias: Double = 0) {
            let seg = game.segmentIndex(at: s0)
            func p(_ s: Double, _ u: Double, _ y: Double) -> SIMD3<Double> { point(s, u, y, seg) }
            let centre = p((s0 + s1) / 2, (u0 + u1) / 2, (y0 + y1) / 2)
            let faces: [([SIMD3<Double>], Double)] = [
                ([p(s0, u0, y1), p(s0, u1, y1), p(s1, u1, y1), p(s1, u0, y1)], 1.08),
                ([p(s0, u0, y0), p(s0, u1, y0), p(s0, u1, y1), p(s0, u0, y1)], 0.92),
                ([p(s1, u0, y0), p(s1, u1, y0), p(s1, u1, y1), p(s1, u0, y1)], 0.9),
                ([p(s0, u0, y0), p(s1, u0, y0), p(s1, u0, y1), p(s0, u0, y1)], 0.8),
                ([p(s0, u1, y0), p(s1, u1, y0), p(s1, u1, y1), p(s0, u1, y1)], 0.8),
            ]
            var painted: [([CGPoint], CGColor)] = []
            var nearest = Double.infinity
            for (pts, light) in faces {
                let mid = pts.reduce(SIMD3<Double>.zero, +) / 4
                let out = mid - centre
                let toEye = camera.position - mid
                guard (out * toEye).sum() > 0 else { continue }
                var screen: [CGPoint] = []
                for q in pts {
                    guard let pr = camera.project(q) else { return }
                    screen.append(pr.point)
                    nearest = min(nearest, pr.depth)
                }
                painted.append((screen, shade(color.scaled(light), nearest).cg()))
            }
            guard nearest < drawDistance else { return }
            things.append(Item(depth: nearest + depthBias) { ctx in
                for (screen, fill) in painted {
                    ctx.beginPath()
                    ctx.addLines(between: screen)
                    ctx.closePath()
                    ctx.setFillColor(fill)
                    ctx.fillPath()
                }
            })
        }

        // Ground.
        let from = floor(game.s - 4), to = game.s + drawDistance
        let gaps = game.obstacles.filter { $0.kind == .gap }
        func inGap(_ a: Double, _ b: Double) -> Bool { gaps.contains { a < $0.end - 0.01 && b > $0.s + 0.01 } }

        for seg in game.segments.indices {
            let start = max(game.segments[seg].start, from)
            // Run the segment on past its corner by half the path's width, to square it off.
            let stop = min(game.end(ofSegment: seg) + RunnerGame.halfWidth, to)
            guard start < stop else { continue }
            var a = start
            while a < stop {
                let b = min(floor(a) + 1, stop)
                let row = Int(floor(a))
                if trail {
                    if !inGap(a, b) {
                        let hw = RunnerGame.halfWidth
                        quad([point(a, -hw, 0, seg), point(a, hw, 0, seg), point(b, hw, 0, seg), point(b, -hw, 0, seg)], RGB(0xD9C9E6), into: &ground, under: true)
                        for lane in 0..<3 {
                            let c = palette[abs(row * 7 + lane * 3 + (row & 1) * 2) % palette.count].mix(RGB(0xFFFFFF), 0.25)
                            let u0 = RunnerGame.laneU(lane) - 0.56, u1 = RunnerGame.laneU(lane) + 0.56
                            quad([point(a + 0.06, u0, 0, seg), point(a + 0.06, u1, 0, seg), point(b - 0.06, u1, 0, seg), point(b - 0.06, u0, 0, seg)], c, into: &ground)
                        }
                        // The causeway's sides, and its face where it starts again after a gap.
                        quad([point(a, -hw, 0, seg), point(b, -hw, 0, seg), point(b, -hw, -0.7, seg), point(a, -hw, -0.7, seg)], RGB(0xB7A3CC), into: &ground, under: true)
                        quad([point(a, hw, 0, seg), point(b, hw, 0, seg), point(b, hw, -0.7, seg), point(a, hw, -0.7, seg)], RGB(0xB7A3CC), into: &ground, under: true)
                        if inGap(a - 1, a) {
                            quad([point(a, -hw, 0, seg), point(a, hw, 0, seg), point(a, hw, -0.7, seg), point(a, -hw, -0.7, seg)], RGB(0xA892BF), into: &ground, under: true)
                        }
                    }
                } else {
                    let tone = row & 1 == 0 ? RGB(0xE9E1F0) : RGB(0xE2D9EB)
                    quad([point(a, -1.8, 0, seg), point(a, 1.8, 0, seg), point(b, 1.8, 0, seg), point(b, -1.8, 0, seg)], tone, into: &ground, under: true)
                    if row % 3 != 0 {
                        for edge in [-0.6, 0.6] {
                            quad([point(a, edge - 0.04, 0, seg), point(a, edge + 0.04, 0, seg), point(b, edge + 0.04, 0, seg), point(b, edge - 0.04, 0, seg)], RGB(0xFFFFFF), into: &ground)
                        }
                    }
                    for side in [-1.0, 1.0] {
                        quad([point(a, side * 1.8, 0, seg), point(a, side * 3.2, 0, seg), point(b, side * 3.2, 0, seg), point(b, side * 1.8, 0, seg)], RGB(0xFCE3D2), into: &ground, under: true)
                        quad([point(a, side * 1.8, 0.12, seg), point(a, side * 1.95, 0.12, seg), point(b, side * 1.95, 0.12, seg), point(b, side * 1.8, 0.12, seg)], RGB(0xF7C9B0), into: &ground)
                    }
                }
                a = b
            }
        }

        // Toy-town houses along the street.
        if !trail {
            let first = Int(floor(from / 6)), last = Int(ceil(to / 6))
            for k in first...last {
                for side in [-1.0, 1.0] {
                    var hash = SplitMix(seed: UInt64(bitPattern: Int64(k * 2 + (side > 0 ? 1 : 0))) &+ 99)
                    let height = 2.0 + Double(hash.int(in: 0...8)) * 0.5
                    let depth = 3.0 + Double(hash.int(in: 0...4)) * 0.5
                    let color = palette[hash.int(in: 0...5)]
                    let near = 4.0, far = near + depth
                    box(s0: Double(k) * 6, s1: Double(k) * 6 + 4.8,
                        u0: side > 0 ? near : -far, u1: side > 0 ? far : -near,
                        y0: 0, y1: height, color: color.mix(RGB(0xFFFFFF), 0.15))
                    // A roof in a deeper shade.
                    box(s0: Double(k) * 6 + 0.2, s1: Double(k) * 6 + 4.6,
                        u0: side > 0 ? near + 0.2 : -far + 0.2, u1: side > 0 ? far - 0.2 : -near - 0.2,
                        y0: height, y1: height + 0.35, color: color.scaled(0.85), depthBias: -0.01)
                }
            }
        }

        // Obstacles.
        for o in game.obstacles where o.s < to && o.end > from {
            let color = palette[o.color]
            switch o.kind {
            case .gap:
                break
            case .hurdle:
                for lane in o.lanes {
                    let c = RunnerGame.laneU(lane)
                    box(s0: o.s, s1: o.end, u0: c - 0.55, u1: c + 0.55, y0: 0, y1: 0.5, color: color)
                    box(s0: o.s - 0.01, s1: o.end + 0.01, u0: c - 0.2, u1: c + 0.2, y0: 0.18, y1: 0.32, color: RGB(0xFFFFFF), depthBias: -0.02)
                }
            case .bar:
                let lo = RunnerGame.laneU(o.lanes.min()!) - 0.6, hi = RunnerGame.laneU(o.lanes.max()!) + 0.6
                box(s0: o.s, s1: o.end, u0: lo, u1: lo + 0.14, y0: 0, y1: 1.3, color: color.scaled(0.9))
                box(s0: o.s, s1: o.end, u0: hi - 0.14, u1: hi, y0: 0, y1: 1.3, color: color.scaled(0.9))
                box(s0: o.s, s1: o.end, u0: lo, u1: hi, y0: 1.0, y1: 1.3, color: color, depthBias: -0.01)
            case .block:
                for lane in o.lanes {
                    let c = RunnerGame.laneU(lane)
                    box(s0: o.s, s1: o.end, u0: c - 0.52, u1: c + 0.52, y0: 0, y1: 1.6, color: color)
                }
            case .cart:
                for lane in o.lanes {
                    let c = RunnerGame.laneU(lane)
                    box(s0: o.s, s1: o.end, u0: c - 0.55, u1: c + 0.55, y0: 0.25, y1: 1.6, color: color)
                    box(s0: o.s - 0.02, s1: o.s + 0.3, u0: c - 0.4, u1: c + 0.4, y0: 0.95, y1: 1.4, color: RGB(0xFFFFFF), depthBias: -0.05)
                    for (ws, wu) in [(o.s + 0.6, c - 0.5), (o.s + 0.6, c + 0.3), (o.end - 0.9, c - 0.5), (o.end - 0.9, c + 0.3)] {
                        box(s0: ws, s1: ws + 0.5, u0: wu, u1: wu + 0.2, y0: 0, y1: 0.35, color: ink.mix(RGB(0xFFFFFF), 0.2), depthBias: 0.01)
                    }
                }
            }
        }

        // Stars.
        for coin in game.coins where coin.s < to && coin.s > from {
            let g = game.ground(coin.s, RunnerGame.laneU(coin.lane))
            guard let q = camera.project(SIMD3(g.x, coin.height, g.y)) else { continue }
            let radius = camera.focal * 0.24 / q.depth
            let turn = cos(game.time * 4 + coin.s)
            let fill = shade(RGB(0xFFD24D), q.depth).cg()
            let edge = shade(RGB(0xE8A93A), q.depth).cg()
            things.append(Item(depth: q.depth) { ctx in
                star(ctx, at: q.point, radius: radius, squash: max(0.25, abs(turn)), fill: fill, edge: edge)
            })
        }

        // The runner.
        let foot = game.ground(game.s, game.u)
        if let q = camera.project(SIMD3(foot.x, game.y, foot.y)),
           let shadow = camera.project(SIMD3(foot.x, 0, foot.y)) {
            let k = camera.focal / q.depth
            let overGap = gaps.contains { game.s > $0.s && game.s < $0.end }
            things.append(Item(depth: q.depth - 0.5) { ctx in
                if !overGap {
                    ctx.setFillColor(ink.cg(0.18 * max(0.3, 1 - game.y)))
                    ctx.fillEllipse(in: CGRect(x: shadow.point.x - 0.34 * k, y: shadow.point.y - 0.09 * k, width: 0.68 * k, height: 0.18 * k))
                }
                runner(ctx, game: game, foot: q.point, k: k)
            })
        }

        for item in ground.sorted(by: { $0.depth > $1.depth }) { item.paint(ctx) }
        for item in things.sorted(by: { $0.depth > $1.depth }) { item.paint(ctx) }

        hud(game, ctx: ctx, w: w, h: h)
    }

    // MARK: Pieces

    private static func drawSky(_ game: RunnerGame, ctx: CGContext, camera: Camera, w: Double, h: Double, fog: RGB) {
        let horizon = camera.horizon
        let space = CGColorSpaceCreateDeviceRGB()
        let trail = game.style == .trail

        let sky = CGGradient(colorsSpace: space, colors: [RGB(trail ? 0x9EC5F8 : 0xA9CDF6).cg(), fog.cg()] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: horizon), options: [.drawsAfterEndLocation])

        // The sun and far clouds sit at fixed bearings, so they swing past on a corner.
        func screenX(bearing: Double) -> Double? {
            var d = bearing - game.cameraYaw
            d = atan2(sin(d), cos(d))
            guard abs(d) < 1.1 else { return nil }
            return w / 2 + camera.focal * tan(d)
        }
        if let x = screenX(bearing: 0.5) {
            ctx.setFillColor(RGB(0xFFF3C4).cg(0.55))
            ctx.fillEllipse(in: CGRect(x: x - h * 0.16, y: horizon - h * 0.42, width: h * 0.32, height: h * 0.32))
            ctx.setFillColor(RGB(0xFFF7DC).cg())
            ctx.fillEllipse(in: CGRect(x: x - h * 0.1, y: horizon - h * 0.36, width: h * 0.2, height: h * 0.2))
        }

        let below = CGGradient(colorsSpace: space,
                               colors: (trail ? [fog.cg(), RGB(0xE4D9F3).cg()] : [RGB(0xD8F0CF).cg(), RGB(0xB9E3AE).cg()]) as CFArray,
                               locations: [0, 1])!
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: horizon, width: w, height: h - horizon))
        ctx.drawLinearGradient(below, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: h), options: [])
        ctx.restoreGState()

        for i in 0..<14 {
            let bearing = Double(i) * 0.45 + (trail ? 0 : 0.2)
            guard let x = screenX(bearing: bearing) else { continue }
            let tall = h * (0.05 + Double(i % 3) * 0.02)
            if trail {
                // Puffs on the sea of cloud below the path.
                let y = horizon + h * (0.03 + Double(i % 4) * 0.06)
                ctx.setFillColor(RGB(0xFFFFFF).cg(0.7))
                ctx.fillEllipse(in: CGRect(x: x - tall * 2, y: y - tall * 0.4, width: tall * 4, height: tall * 0.9))
            }
            ctx.setFillColor(RGB(0xFFFFFF).cg(0.65))
            ctx.fillEllipse(in: CGRect(x: x - tall * 1.6, y: horizon - h * (0.18 + Double(i % 5) * 0.035), width: tall * 3.2, height: tall))
        }
    }

    /// A little pastel brick in a headband, seen from behind.
    private static func runner(_ ctx: CGContext, game: RunnerGame, foot: CGPoint, k: Double) {
        if game.stumbling > 0, Int(game.stumbling * 20) % 2 == 0 { return }
        let body = RGB(0xF08FB4)
        let phase = game.s * 2.4
        let sliding = game.sliding > 0
        let air = game.isAirborne

        let bw = (sliding ? 0.8 : 0.62) * k
        let bh = (sliding ? 0.5 : 0.82) * k
        let legs = sliding ? 0.0 : (air ? 0.22 : 0.4) * k
        let top = foot.y - legs - bh

        if !sliding {
            for side in [-1.0, 1.0] {
                let swing = air ? 0 : sin(phase + (side > 0 ? .pi : 0)) * 0.12 * k
                let rect = CGRect(x: foot.x + side * 0.15 * k - 0.08 * k, y: foot.y - legs + max(0, swing) - 0.02 * k,
                                  width: 0.16 * k, height: legs - max(0, swing) + 0.02 * k)
                ctx.setFillColor(ink.mix(body, 0.3).cg())
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 0.07 * k, cornerHeight: 0.07 * k, transform: nil))
                ctx.fillPath()
            }
            for side in [-1.0, 1.0] {
                let swing = air ? -0.18 * k : sin(phase + (side > 0 ? 0 : .pi)) * 0.1 * k
                let rect = CGRect(x: foot.x + side * (bw / 2 + 0.03 * k) - 0.07 * k, y: top + bh * 0.35 + swing,
                                  width: 0.14 * k, height: bh * 0.42)
                ctx.setFillColor(body.scaled(0.85).cg())
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 0.07 * k, cornerHeight: 0.07 * k, transform: nil))
                ctx.fillPath()
            }
        }

        let bob = air || sliding ? 0 : abs(sin(phase)) * 0.04 * k
        let shell = CGRect(x: foot.x - bw / 2, y: top - bob, width: bw, height: bh)
        ctx.setFillColor(body.cg())
        ctx.addPath(CGPath(roundedRect: shell, cornerWidth: 0.16 * k, cornerHeight: 0.16 * k, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(RGB(0xFFFFFF).cg(0.35))
        ctx.addPath(CGPath(roundedRect: shell.insetBy(dx: bw * 0.12, dy: 0).divided(atDistance: bh * 0.22, from: .minYEdge).slice.offsetBy(dx: 0, dy: bh * 0.06),
                           cornerWidth: 0.06 * k, cornerHeight: 0.06 * k, transform: nil))
        ctx.fillPath()

        // Headband, its tails streaming behind in the wind.
        let band = CGRect(x: shell.minX, y: shell.minY + bh * 0.3, width: bw, height: bh * 0.14)
        ctx.setFillColor(RGB(0xA6BDF7).cg())
        ctx.fill(band)
        let flutter = sin(game.time * 14) * 0.05 * k
        ctx.beginPath()
        ctx.move(to: CGPoint(x: band.maxX - 0.08 * k, y: band.midY))
        ctx.addLine(to: CGPoint(x: band.maxX + 0.24 * k, y: band.midY + 0.12 * k + flutter))
        ctx.addLine(to: CGPoint(x: band.maxX + 0.18 * k, y: band.midY + 0.2 * k + flutter))
        ctx.closePath()
        ctx.fillPath()
    }

    private static func star(_ ctx: CGContext, at c: CGPoint, radius r: Double, squash: Double, fill: CGColor, edge: CGColor) {
        ctx.beginPath()
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let len = i % 2 == 0 ? r : r * 0.48
            let p = CGPoint(x: c.x + cos(a) * len * squash, y: c.y + sin(a) * len)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.closePath()
        ctx.setFillColor(fill)
        ctx.setStrokeColor(edge)
        ctx.setLineWidth(max(1, r * 0.14))
        ctx.drawPath(using: .fillStroke)
    }

    private static func hud(_ game: RunnerGame, ctx: CGContext, w: Double, h: Double) {
        let size = h * 0.07
        let pad = h * 0.04
        let distance = "\(Int(game.s).formatted()) m"
        let stars = game.stars.formatted()

        func pill(_ text: String, x: Double, alignRight: Bool, icon: Bool) {
            let line = textLine(text, size: size)
            let width = Double(CTLineGetTypographicBounds(line, nil, nil, nil))
            let iconWidth = icon ? size * 1.15 : 0
            let pillWidth = width + iconWidth + size * 0.9
            let left = alignRight ? x - pillWidth : x
            let rect = CGRect(x: left, y: pad, width: pillWidth, height: size * 1.55)
            ctx.setFillColor(RGB(0xFFFFFF).cg(0.78))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
            ctx.fillPath()
            if icon {
                star(ctx, at: CGPoint(x: left + size * 0.45 + size * 0.45, y: rect.midY), radius: size * 0.5, squash: 1,
                     fill: RGB(0xFFD24D).cg(), edge: RGB(0xE8A93A).cg())
            }
            ctx.textPosition = CGPoint(x: left + size * 0.45 + iconWidth, y: rect.midY + size * 0.35)
            CTLineDraw(line, ctx)
        }

        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        pill(distance, x: pad, alignRight: false, icon: false)
        pill(stars, x: w - pad, alignRight: true, icon: true)
        ctx.restoreGState()
    }

    private static func textLine(_ text: String, size: Double) -> CTLine {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let font = CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink.cg(),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
