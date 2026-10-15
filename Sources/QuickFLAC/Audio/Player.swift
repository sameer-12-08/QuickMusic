import AVFoundation
import Observation

// Player wraps AVAudioEngine so the rest of the app never touches audio details.
//
// Swift concept: `@Observable` makes SwiftUI re-draw any view that READ one of
// these properties when it changes. Think of it as a Python object where the UI
// automatically subscribes to the attributes it uses.
//
// Audio graph:   AVAudioPlayerNode  ->  mainMixerNode (volume)  ->  speakers
// The player node reads the file from disk in small chunks while playing,
// so a 500 MB WAV costs about the same RAM as a 3 MB one.
@Observable
final class Player {

    // MARK: - State the UI can read
    // `private(set)` = readable from anywhere, writable only inside this class
    // (like a Python @property with no setter).
    private(set) var title: String?          // nil means "no file loaded"
    private(set) var currentURL: URL?        // lets the library highlight the playing row
    private(set) var isPlaying = false
    private(set) var duration: Double = 0    // seconds
    private(set) var volume: Float = 1       // 0...1

    // MARK: - Internals (the UI does not need to watch these)
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
    @ObservationIgnored private var file: AVAudioFile?
    // Frame (= one audio sample per channel) where the current scheduling began.
    // The node's own clock restarts at 0 every time we stop/reschedule (e.g. on seek),
    // so: current position = startFrame + node's elapsed frames.
    @ObservationIgnored private var startFrame: AVAudioFramePosition = 0
    // Bumped on every reschedule so stale "finished" callbacks can be ignored.
    @ObservationIgnored private var generation = 0
    // Set by PlaybackController: called (on the main thread) when a song plays to its end.
    @ObservationIgnored var onFinished: (() -> Void)?
    // Last position (in frames) we knew for sure. When the audio device changes, the
    // engine stops and its clock is lost, so this is where we resume from.
    @ObservationIgnored private var lastFrames: AVAudioFramePosition = 0

    init() {
        engine.attach(node)

        // macOS tells us when the audio hardware changes (headphones unplugged,
        // Bluetooth connected, sample rate changed...). The engine stops itself then.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: engine,
                                               queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    /// Reconnect to the (new) output device and carry on from the last known position.
    private func handleConfigurationChange() {
        guard let file else { return }
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        do {
            try engine.start()
        } catch {
            isPlaying = false
            return
        }
        // seek() reschedules from this position and presses play again if we were playing.
        seek(to: Double(lastFrames) / file.processingFormat.sampleRate)
    }

    // MARK: - Loading

    /// Opens a FLAC/WAV file and starts playing it. Throws if the file can't be read
    /// (like a Python function raising an exception; the caller uses `try`).
    /// `title` is optional text to show in the UI; it defaults to the file name.
    func load(_ url: URL, title displayTitle: String? = nil) throws {
        // AVAudioFile only reads the header here; audio data is NOT loaded into memory.
        let newFile = try AVAudioFile(forReading: url)

        generation += 1
        node.stop()
        engine.stop()

        // Connect using the file's own format (sample rate, channels).
        // The mixer converts to whatever the output device needs.
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: newFile.processingFormat)
        engine.mainMixerNode.outputVolume = volume
        try engine.start()

        file = newFile
        duration = Double(newFile.length) / newFile.processingFormat.sampleRate
        title = displayTitle ?? url.deletingPathExtension().lastPathComponent
        currentURL = url
        startFrame = 0
        schedule(from: 0)
        node.play()
        isPlaying = true
    }

    // MARK: - Controls

    func togglePlayPause() {
        guard file != nil else { return }
        if isPlaying {
            node.pause()
            isPlaying = false
        } else {
            if !engine.isRunning { try? engine.start() }
            node.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        guard let file else { return }
        let sampleRate = file.processingFormat.sampleRate
        // Clamp so we always have at least 1 frame left to play.
        let frame = min(max(AVAudioFramePosition(seconds * sampleRate), 0), file.length - 1)
        startFrame = frame
        schedule(from: frame)
        if isPlaying { node.play() }
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        engine.mainMixerNode.outputVolume = newVolume
    }

    /// Current playback position in seconds. The seek bar calls this a few times
    /// per second; we compute it on demand instead of storing it, so playing
    /// audio does not trigger constant UI updates.
    func currentTime() -> Double {
        guard let file else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        var frames = startFrame
        if let nodeTime = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: nodeTime) {
            frames += playerTime.sampleTime
            lastFrames = frames        // remember it for handleConfigurationChange()
        }
        return min(max(Double(frames) / sampleRate, 0), duration)
    }

    // MARK: - Scheduling

    /// Tells the player node "play this file starting at `frame` until the end".
    private func schedule(from frame: AVAudioFramePosition) {
        guard let file else { return }
        generation += 1
        let myGeneration = generation
        lastFrames = frame   // after load / seek / rewind, this IS the position
        node.stop()          // clears anything previously scheduled

        let remaining = AVAudioFrameCount(file.length - frame)
        node.scheduleSegment(file,
                             startingFrame: frame,
                             frameCount: remaining,
                             at: nil,
                             completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // This closure runs on an audio thread, so hop to the main thread
            // before touching state the UI reads.
            DispatchQueue.main.async { self?.trackFinished(myGeneration) }
        }
    }

    private func trackFinished(_ gen: Int) {
        guard gen == generation else { return }   // stale callback (we seeked or loaded something else)
        isPlaying = false
        startFrame = 0
        schedule(from: 0)   // rewind so pressing play restarts the track
        onFinished?()       // let the queue start the next song (if there is one)
    }
}
