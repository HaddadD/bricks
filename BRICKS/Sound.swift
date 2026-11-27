import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// The game's sound effects.
///
/// Four of them are recordings in `BRICKS/Sounds`, which the project carries as a folder
/// reference — the whole folder is copied into the bundle, so swapping a clip is a
/// matter of replacing the file, and the names below are the filenames.
///
/// The milestone is the one that is still synthesised, since no recording was supplied
/// for it. Its notes are rendered at playback time by the section further down.
enum Sound {
    /// Mirrors the Sounds setting; every call below is a no-op when it is off.
    static var enabled = true

    /// A recorded effect and the file it plays, minus the `.mp3`.
    enum Clip: String, CaseIterable {
        /// Any line clear, however many lines went at once.
        case lineClear = "Clear Line"
        /// A piece landing on the board.
        case place = "Pop Sound"
        /// Winning a power-up from a gift, and spending one.
        case powerUp = "Powerup Sound"
        /// Out of moves.
        case gameOver = "Losing Sound"
    }

    static func lineClear() { play(.lineClear) }
    static func place() { play(.place) }
    static func powerUp() { play(.powerUp) }
    static func gameOver() { play(.gameOver) }

    /// Every 1000 points. The only effect with no recording behind it.
    static func milestone() {
        guard enabled else { return }
        ToneEngine.shared.play(milestoneNotes())
    }

    private static func play(_ clip: Clip) {
        guard enabled else { return }
        ClipPlayer.shared.play(clip)
    }

    // MARK: - The synthesised milestone

    /// An arpeggio landing on a held chord.
    private static func milestoneNotes() -> [Note] {
        var notes = [523.25, 659.25, 783.99, 1046.50, 1318.51].enumerated().map { i, freq in
            Note(freq: freq, at: Double(i) * 0.07, length: 0.6, gain: 0.45)
        }
        for freq in [523.25, 659.25, 783.99] {
            notes.append(Note(freq: freq, at: 0.35, length: 1.2, gain: 0.3))
        }
        return notes
    }
}

#if DEBUG
/// Seams for the headless tests, which cannot listen to anything.
extension Sound {
    static func testMilestoneSamples() -> [Float] { renderTone(milestoneNotes()) }
    static var testSampleRate: Double { sampleRate }
}
#endif

// MARK: - Playing the clips

#if canImport(UIKit) && canImport(AVFoundation)

/// One player per clip, loaded the first time that clip is asked for and kept.
///
/// Playing a clip that is already playing restarts it rather than layering a second
/// copy on top, which is what you want for the pop: hurrying through a deal should
/// sound like a run of pops, not a pile-up. Different clips still overlap freely, so a
/// placement that clears a line plays both.
private final class ClipPlayer {
    static let shared = ClipPlayer()

    private var players: [Sound.Clip: AVAudioPlayer] = [:]
    private var sessionReady = false
    /// Decoding a file is slow enough to drop a frame if it happens mid-animation, so
    /// loading and starting both happen off the main thread. Serial, which is what keeps
    /// the dictionary safe.
    private let queue = DispatchQueue(label: "bricks.sound", qos: .userInitiated)

    func play(_ clip: Sound.Clip) {
        queue.async { [self] in
            guard let player = player(for: clip) else { return }
            startSession()
            player.currentTime = 0
            player.play()
        }
    }

    private func player(for clip: Sound.Clip) -> AVAudioPlayer? {
        if let existing = players[clip] { return existing }

        // The clips ship as a folder reference, so they sit in a Sounds/ directory
        // inside the bundle. The flat lookup is the fallback for a build that copied
        // them loose instead.
        let url = Bundle.main.url(forResource: clip.rawValue, withExtension: "mp3", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: clip.rawValue, withExtension: "mp3")

        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
            assertionFailure("missing sound file: \(clip.rawValue).mp3")
            return nil
        }
        player.prepareToPlay()
        players[clip] = player
        return player
    }

    private func startSession() {
        guard !sessionReady else { return }
        sessionReady = true

        // .ambient with .mixWithOthers: the game never interrupts whatever the player is
        // listening to, and the ring/silent switch mutes it the way it mutes any game.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

/// Plays rendered samples — the milestone only. Started lazily on the first one, so a
/// run that never reaches 1000 points never builds an engine.
private final class ToneEngine {
    static let shared = ToneEngine()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private let queue = DispatchQueue(label: "bricks.tone", qos: .userInitiated)

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ notes: [Note]) {
        queue.async { [self] in
            let samples = renderTone(notes)
            guard let buffer = buffer(from: samples), start() else { return }
            player.scheduleBuffer(buffer, completionHandler: nil)
            if !player.isPlaying { player.play() }
        }
    }

    private func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    private func start() -> Bool {
        if engine.isRunning { return true }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        do {
            try engine.start()
        } catch {
            return false
        }
        return true
    }
}

#else

/// The headless rule tests build for macOS, where there is no audio device to talk to.
private final class ClipPlayer {
    static let shared = ClipPlayer()
    func play(_ clip: Sound.Clip) { }
}

private final class ToneEngine {
    static let shared = ToneEngine()
    func play(_ notes: [Note]) { }
}

#endif

// MARK: - The synthesiser

/// One note of an effect: where it starts, how long it rings, and how loud.
/// `bendTo` glides the pitch over the note's life.
fileprivate struct Note {
    var freq: Double
    var at: Double
    var length: Double
    var gain: Double
    var bendTo: Double? = nil
}

fileprivate let sampleRate = 44100.0

/// Turns a list of notes into mono samples. Pure arithmetic — no audio framework — so
/// it renders the same on the phone and under the headless rule tests.
fileprivate func renderTone(_ notes: [Note]) -> [Float] {
    guard let span = notes.map({ $0.at + $0.length }).max(), span > 0 else { return [] }
    var out = [Float](repeating: 0, count: Int((span + 0.05) * sampleRate))

    for note in notes {
        let first = Int(note.at * sampleRate)
        let count = Int(note.length * sampleRate)
        let decay = note.length * 0.38
        let landing = note.bendTo ?? note.freq
        var phase = 0.0

        for i in 0..<count {
            let index = first + i
            guard index < out.count else { break }
            let t = Double(i) / sampleRate
            let freq = note.freq + (landing - note.freq) * (t / note.length)
            phase += 2 * .pi * freq / sampleRate
            // Fast attack, exponential tail: a struck bar rather than a beep.
            let envelope = min(1, t / 0.006) * exp(-t / decay)
            let wave = sin(phase) + 0.22 * sin(phase * 2) + 0.08 * sin(phase * 3)
            out[index] += Float(wave * envelope * note.gain * 0.3)
        }
    }
    return out
}
