// Renders every alarm sound to ios/Sounds/<name>.caf, for the system alarm
// (AlarmKit) and the notification fallback, which can only play files. Same
// synthesis as the in-app beeper, repeated the way the app repeats it.
//
//   swiftc -parse-as-library -o build/make-sounds ../swift/Sources/Beeper.swift make-sounds.swift
//   build/make-sounds
//
// Run from ios/. The output is committed; rerun it after changing a sound.

import AVFoundation

@main
struct MakeSounds {
    /// Notification sounds longer than 30 s fall back to the default beep.
    static let seconds = 29.0
    static let rate = 22_050.0

    static func main() throws {
        try FileManager.default.createDirectory(atPath: "Sounds", withIntermediateDirectories: true)
        for sound in AlarmSound.allCases {
            let take = Beeper.render(sound.notes, length: sound.length, rate: rate)
            let period = Int(rate * max(AlarmSound.repeatEvery, sound.length))

            // whole rounds only, so the file never ends mid-note
            let rounds = Int(seconds * rate) / period
            var samples = [Float](repeating: 0, count: rounds * period)
            for round in 0..<rounds {
                for (i, value) in take.enumerated() where round * period + i < samples.count {
                    samples[round * period + i] += value
                }
            }

            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer {
                buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
            }

            // IMA4: a quarter the size of 16-bit PCM, and a format iOS alarms accept
            let url = URL(fileURLWithPath: "Sounds/\(sound.rawValue).caf")
            try? FileManager.default.removeItem(at: url)
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatAppleIMA4,
                AVSampleRateKey: rate,
                AVNumberOfChannelsKey: 1,
            ])
            try file.write(from: buffer)
            print("wrote \(url.path) (\(rounds) rounds)")
        }
    }
}
