#if os(iOS)
import AVKit
import SwiftUI

/// What Sensory enhancement plays under the board.
enum SensoryMode: String, CaseIterable, Identifiable {
    /// An endless runner that plays itself, on the trail or the street.
    case runner
    /// Kinetic sand, soap, slime, pressure washing, a rusty gear restored.
    case oddlySatisfying
    /// Glass fruit, jelly and chrome keyboards, a crystal bar eaten square by square.
    case impossibleSatisfying

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runner: return "Runner"
        case .oddlySatisfying: return "Oddly Satisfying"
        case .impossibleSatisfying: return "Impossible Satisfying"
        }
    }

    var blurb: String {
        switch self {
        case .runner: return "An endless run that plays itself"
        case .oddlySatisfying: return "Sand, soap, slime, washing, restoring"
        case .impossibleSatisfying: return "Glass fruit, jelly keys, crystal snacks"
        }
    }

    var symbol: String {
        switch self {
        case .runner: return "figure.run"
        case .oddlySatisfying: return "hands.and.sparkles.fill"
        case .impossibleSatisfying: return "sparkles"
        }
    }
}

/// One thing that can play: it moves on by a time step and draws a frame.
private protocol SensoryVisual: AnyObject {
    /// Whether drawing a frame takes the GPU, which an app in the background may not use.
    var needsGPU: Bool { get }
    func step(_ dt: Double)
    func draw(in ctx: CGContext, size: CGSize)
}

private final class RunnerVisual: SensoryVisual {
    let needsGPU = false
    let game: RunnerGame
    init(_ style: RunnerStyle) { game = RunnerGame(style: style) }
    func step(_ dt: Double) { game.step(dt) }
    func draw(in ctx: CGContext, size: CGSize) { RunnerRenderer.draw(game, in: ctx, size: size) }
}

extension SatisfyingShow: SensoryVisual {
    var needsGPU: Bool { true }
}

/// Plays Sensory enhancement as live video, so it can sit under the board and float in a
/// Picture in Picture window. Frames are drawn on a background queue and handed to a
/// sample-buffer layer, which is all Picture in Picture needs; the video is live, so the
/// window offers nothing to scrub, skip or pause, only to move, resize or tuck away.
final class SensoryPlayer: NSObject, ObservableObject {

    /// What's playing: the mode, and the runner's world (ignored by the shows).
    struct Content: Equatable {
        var mode: SensoryMode
        var style: RunnerStyle
    }

    static let shared = SensoryPlayer()

    /// Whether it's in the floating window right now.
    @Published private(set) var isFloating = false
    /// Whether the system will float it: false with Picture in Picture switched off in
    /// Settings, or until the first frames are in.
    @Published private(set) var canFloat = false

    let layer = AVSampleBufferDisplayLayer()

    static let pixelSize = CGSize(width: 768, height: 432)
    private static let framesPerSecond = 30.0

    private let queue = DispatchQueue(label: "ca.wilsonlam.bricks.sensory", qos: .userInitiated)
    // Touched only on `queue`.
    private var visual: SensoryVisual?
    private var playing: Content?
    private var lastFrame: CFTimeInterval = 0
    private var pool: CVPixelBufferPool?
    private var inForeground = true

    private var clock: DispatchSourceTimer?
    private var pip: AVPictureInPictureController?
    private var possible: NSKeyValueObservation?
    private var isOn = false
    private var wantsToFloat = false
    private var isActive = true

    private override init() {
        super.init()
        layer.videoGravity = .resizeAspect
        #if DEBUG
        // `-floating` lays the screen out as if the video were in Picture in Picture, which
        // the Simulator doesn't offer.
        isFloating = ProcessInfo.processInfo.arguments.contains("-floating")
        #endif
    }

    // MARK: - Control

    /// Starts `content`, or carries on if it's already playing. With `float`, it goes into
    /// the floating window as soon as the system allows.
    func play(_ content: Content, float: Bool) {
        queue.async {
            guard self.playing != content else { return }
            // Switching the runner's world doesn't matter to a show that's playing.
            if content.mode != .runner, self.playing?.mode == content.mode { self.playing = content; return }
            self.playing = content
            switch content.mode {
            case .runner: self.visual = RunnerVisual(content.style)
            case .oddlySatisfying: self.visual = SatisfyingShow(kind: .oddly)
            case .impossibleSatisfying: self.visual = SatisfyingShow(kind: .impossible)
            }
        }
        isOn = true
        setUpPictureInPicture()
        if float { self.float() }
        updateClock()
    }

    func stop() {
        isOn = false
        wantsToFloat = false
        pip?.stopPictureInPicture()
        updateClock()
        queue.async {
            self.visual = nil
            self.playing = nil
        }
        layer.flush()
    }

    func float() {
        wantsToFloat = true
        startFloatingIfPossible()
    }

    /// Keeps running in the background only while floating; there's nothing to see
    /// otherwise. Out there the shows hold their last frame, since rendering them takes the
    /// GPU; the runner, drawn on the CPU, keeps going.
    func setActive(_ active: Bool) {
        isActive = active
        queue.async { self.inForeground = active }
        updateClock()
    }

    private func updateClock() {
        let needed = isOn && (isActive || isFloating)
        if needed, clock == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1 / Self.framesPerSecond, leeway: .milliseconds(4))
            timer.setEventHandler { [weak self] in self?.tick() }
            queue.async { self.lastFrame = CACurrentMediaTime() }
            timer.resume()
            clock = timer
        } else if !needed, let timer = clock {
            timer.cancel()
            clock = nil
        }
    }

    // MARK: - Frames

    private func tick() {
        let now = CACurrentMediaTime()
        guard let visual, inForeground || !visual.needsGPU else {
            lastFrame = now
            return
        }
        // A long pause (the app was away) resumes where it left off rather than leaping.
        let dt = min(0.1, now - lastFrame)
        lastFrame = now
        visual.step(dt)
        guard let buffer = render(visual) else { return }

        if #available(iOS 17.0, *) {
            let renderer = layer.sampleBufferRenderer
            if renderer.status == .failed { renderer.flush() }
            renderer.enqueue(buffer)
        } else {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(buffer)
        }
    }

    private func render(_ visual: SensoryVisual) -> CMSampleBuffer? {
        let width = Int(Self.pixelSize.width), height = Int(Self.pixelSize.height)
        if pool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var pixels: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixels)
        guard let pixels else { return nil }

        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixels),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // The renderer draws with y pointing down, like the screen.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        visual.draw(in: ctx, size: Self.pixelSize)

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(Self.framesPerSecond)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    // MARK: - Picture in Picture

    private func setUpPictureInPicture() {
        // Without a floating window on this device, the runner still plays under the board.
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        // Picture in Picture belongs to video, so the app needs a playback audio session,
        // even though nothing here makes a sound. Mixing leaves the player's music playing.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])

        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        possible = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            DispatchQueue.main.async {
                self?.canFloat = controller.isPictureInPicturePossible
                self?.startFloatingIfPossible()
            }
        }
        pip = controller
    }

    private func startFloatingIfPossible() {
        guard wantsToFloat, isActive, let pip, pip.isPictureInPicturePossible, !pip.isPictureInPictureActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        pip.startPictureInPicture()
    }
}

extension SensoryPlayer: AVPictureInPictureControllerDelegate {

    // The board takes its usual size while the video floats, and makes room again as it
    // comes back. The space goes once the window is up, so the window grows out of it, and
    // returns before the window flies home, so it has somewhere to land.

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        withAnimation(.easeInOut(duration: 0.3)) { isFloating = true }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        withAnimation(.easeInOut(duration: 0.3)) { isFloating = false }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isFloating = false
        wantsToFloat = false
        updateClock()
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        isFloating = false
        wantsToFloat = false
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // Make room under the board, then let the window fly into it.
        withAnimation(.easeInOut(duration: 0.3)) { isFloating = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { completionHandler(true) }
    }
}

extension SensoryPlayer: AVPictureInPictureSampleBufferPlaybackDelegate {

    // Live and always playing: no pause, no scrubbing, no skipping.

    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { false }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// Sensory enhancement under the board, shown only while it isn't floating. A button
/// sends it back out after it's been brought home.
struct SensoryStage: View {
    @ObservedObject private var player = SensoryPlayer.shared

    var body: some View {
        VideoLayerView(layer: player.layer)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if player.canFloat {
                    Button {
                        Haptics.tap()
                        player.float()
                    } label: {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.card.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel("Float it in a window")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sensory")
    }
}

/// Hosts the video layer.
private struct VideoLayerView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.isUserInteractionEnabled = false
        view.video = layer
        return view
    }

    func updateUIView(_ view: Host, context: Context) {}

    /// The layer lives on while the video floats; it's just out of the window until the
    /// stage comes back.
    static func dismantleUIView(_ view: Host, coordinator: ()) {
        view.video = nil
    }

    final class Host: UIView {
        var video: CALayer? {
            didSet {
                // A newer stage may already have taken the layer; leave it there.
                if oldValue?.superlayer === layer { oldValue?.removeFromSuperlayer() }
                if let video { layer.addSublayer(video) }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            video?.frame = bounds
            CATransaction.commit()
        }
    }
}
#endif
