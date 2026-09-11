import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the timer shouts with when the disk is empty. Every one of these is
/// synthesised from sine partials at runtime — the app ships no audio files and
/// borrows nobody's recording, so there is nothing to license.
enum AlarmSound: String, CaseIterable, Identifiable {
    case beeps, chime, cuckoo, marimba, bell, buzzer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .beeps: "Beeps"
        case .chime: "Chime"
        case .cuckoo: "Cuckoo"
        case .marimba: "Marimba"
        case .bell: "Bell"
        case .buzzer: "Buzzer"
        }
    }

    /// Seconds of sound in one round of this pattern.
    var length: Double {
        switch self {
        case .beeps: 0.95
        case .chime: 2.40
        case .cuckoo: 1.40
        case .marimba: 1.00
        case .bell: 2.80
        case .buzzer: 1.20
        }
    }

    var notes: [Beeper.Note] {
        switch self {
        case .beeps:
            [
                Beeper.Note(start: 0.00, length: 0.20, freq: 880),
                Beeper.Note(start: 0.28, length: 0.20, freq: 880),
                Beeper.Note(start: 0.56, length: 0.30, freq: 1174.7),
            ]
        case .chime:
            // a rising third, ringing on
            [
                Beeper.Note(start: 0.00, length: 1.6, freq: 1046.5, decay: 2.2,
                            partials: [(1, 1), (2, 0.32), (3, 0.12)]),
                Beeper.Note(start: 0.42, length: 1.8, freq: 1318.5, decay: 1.9,
                            partials: [(1, 1), (2, 0.28), (3, 0.10)]),
            ]
        case .cuckoo:
            // the falling minor third every cuckoo clock uses, twice
            [
                Beeper.Note(start: 0.00, length: 0.26, freq: 784, decay: 5,
                            partials: [(1, 1), (2, 0.22)]),
                Beeper.Note(start: 0.30, length: 0.34, freq: 622.25, decay: 5,
                            partials: [(1, 1), (2, 0.22)]),
                Beeper.Note(start: 0.72, length: 0.26, freq: 784, decay: 5,
                            partials: [(1, 1), (2, 0.22)]),
                Beeper.Note(start: 1.02, length: 0.34, freq: 622.25, decay: 5,
                            partials: [(1, 1), (2, 0.22)]),
            ]
        case .marimba:
            // wooden: a strong fourth partial and a fast decay
            [
                Beeper.Note(start: 0.00, length: 0.45, freq: 659.25, decay: 9,
                            partials: [(1, 1), (4, 0.30), (10, 0.08)]),
                Beeper.Note(start: 0.30, length: 0.55, freq: 987.77, decay: 8,
                            partials: [(1, 1), (4, 0.26), (10, 0.07)]),
            ]
        case .bell:
            // struck metal: inharmonic partials, long tail
            [
                Beeper.Note(start: 0.00, length: 2.6, freq: 440, decay: 1.4,
                            partials: [(1, 1), (2.76, 0.42), (5.40, 0.22), (8.93, 0.10)]),
            ]
        case .buzzer:
            // low and rude, odd harmonics only
            [
                Beeper.Note(start: 0.00, length: 0.34, freq: 220, decay: 1.6,
                            partials: [(1, 1), (3, 0.45), (5, 0.26), (7, 0.16)]),
                Beeper.Note(start: 0.46, length: 0.34, freq: 220, decay: 1.6,
                            partials: [(1, 1), (3, 0.45), (5, 0.26), (7, 0.16)]),
                Beeper.Note(start: 0.92, length: 0.28, freq: 185, decay: 1.6,
                            partials: [(1, 1), (3, 0.45), (5, 0.26), (7, 0.16)]),
            ]
        }
    }
}

/// Holds the audio device only while something is actually sounding: an engine
/// left running pins the output at one sample rate and makes everything else on
/// the machine crackle.
final class Beeper {
    struct Note {
        let start: Double
        let length: Double
        let freq: Double
        var decay: Double = 7.5
        /// Overtones as (frequency ratio, loudness).
        var partials: [(Double, Double)] = [(1, 1)]
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var idleTimer: Timer?
    private var connected = false

    private static let warning = [Note(start: 0, length: 0.26, freq: 659.3, decay: 6)]

    init() {
        #if os(iOS)
        // .playback keeps the alarm audible when the phone is locked; the audio
        // background mode in Info.plist is what lets it run at all.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
        engine.attach(player)
    }

    // MARK: - the device

    private func wake() -> AVAudioFormat? {
        if !connected {
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            connected = true
        }
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                NSLog("audio engine failed: \(error.localizedDescription)")
                return nil
            }
        }
        if !player.isPlaying { player.play() }
        return player.outputFormat(forBus: 0)
    }

    /// Lets go of the output device a moment after the last sound, so other apps
    /// get their own sample rate back.
    private func sleepSoon(after seconds: Double) {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: seconds + 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.player.stop()
            self.engine.pause()
        }
    }

    // MARK: - synthesis

    private func buffer(_ notes: [Note], length: Double, key: String, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let cacheKey = "\(key)@\(Int(rate))"
        if let ready = cache[cacheKey] { return ready }

        let frames = AVAudioFrameCount(rate * length)
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buf.floatChannelData else { return nil }
        buf.frameLength = frames

        for frame in 0..<Int(frames) {
            let t = Double(frame) / rate
            var sample = 0.0
            for note in notes where t >= note.start && t < note.start + note.length {
                let local = t - note.start
                let attack = min(1.0, local / 0.006)
                let envelope = attack * exp(-local * note.decay)
                var voice = 0.0
                for (ratio, amplitude) in note.partials {
                    voice += sin(2 * .pi * note.freq * ratio * local) * amplitude
                }
                sample += voice * envelope * 0.34
            }
            let value = Float(max(-1, min(1, sample)))
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = value
            }
        }
        cache[cacheKey] = buf
        return buf
    }

    private func play(_ notes: [Note], length: Double, key: String) {
        guard let format = wake(),
              let buf = buffer(notes, length: length, key: key, format: format) else { return }
        player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        sleepSoon(after: length)
    }

    // MARK: - what the rest of the app asks for

    /// One round of the chosen alarm sound.
    func alarm(_ sound: AlarmSound) {
        play(sound.notes, length: sound.length, key: sound.rawValue)
        #if os(macOS)
        NSApplication.shared.requestUserAttention(.criticalRequest)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// Same thing, without nagging the Dock: used when picking a sound.
    func preview(_ sound: AlarmSound) {
        play(sound.notes, length: sound.length, key: sound.rawValue)
    }

    /// Single soft tone for the one-minute warning.
    func warn() {
        play(Self.warning, length: 0.34, key: "warn")
    }
}
