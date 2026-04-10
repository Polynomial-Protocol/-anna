import AVFoundation
import Foundation

/// Generates gentle ambient music with a slow arpeggio and soft pad.
/// Used during onboarding for a pleasant, non-intrusive background texture.
final class AmbientPadPlayer: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isPlaying = false
    private let lock = NSLock()

    func play() {
        lock.lock()
        guard !isPlaying else { lock.unlock(); return }
        isPlaying = true
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.startEngine()
        }
    }

    private func startEngine() {
        let sampleRate: Double = 44100
        let duration: Double = 16.0  // 16-second loop for variety
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            lock.lock(); isPlaying = false; lock.unlock()
            return
        }
        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else {
            lock.lock(); isPlaying = false; lock.unlock()
            return
        }

        let sr = Float(sampleRate)

        // ─── Layer 1: Slow chord progression pad ───
        // Cmaj7 (0-4s) → Am7 (4-8s) → Fmaj7 (8-12s) → Gmaj (12-16s)
        let chords: [[(Float, Float)]] = [
            // (frequency, pan) — pan: -1 left, 0 center, +1 right
            [(130.81, -0.3), (164.81, 0.2), (196.00, -0.1), (246.94, 0.3)],   // Cmaj7
            [(110.00, 0.2), (130.81, -0.2), (164.81, 0.1), (196.00, -0.3)],   // Am7
            [(87.31, -0.1), (110.00, 0.3), (130.81, -0.2), (164.81, 0.1)],    // Fmaj7
            [(98.00, 0.1), (123.47, -0.3), (146.83, 0.2), (196.00, -0.1)],    // G
        ]
        let padAmp: Float = 0.02
        let chordDuration = Float(duration) / Float(chords.count)

        // ─── Layer 2: Gentle arpeggio ───
        // Notes that float over the pad, one at a time
        let arpeggioNotes: [Float] = [
            261.63, 329.63, 392.00, 493.88,  // C4, E4, G4, B4 (up)
            392.00, 329.63, 261.63, 246.94,   // G4, E4, C4, B3 (down)
            220.00, 261.63, 329.63, 392.00,   // A3, C4, E4, G4
            349.23, 329.63, 293.66, 261.63,   // F4, E4, D4, C4
        ]
        let noteDuration: Float = 1.0  // 1 second per arpeggio note
        let arpAmp: Float = 0.035

        // ─── Layer 3: Subtle high shimmer ───
        let shimmerFreqs: [Float] = [1046.50, 1318.51]  // C5, E5 — very quiet sparkle
        let shimmerAmp: Float = 0.004

        // ─── Render ───
        for frame in 0..<Int(frameCount) {
            let t = Float(frame) / sr
            var sampleL: Float = 0
            var sampleR: Float = 0

            // Pad: determine which chord is active, crossfade between them
            let chordIndex = Int(t / chordDuration) % chords.count
            let chordProgress = (t - Float(chordIndex) * chordDuration) / chordDuration
            let nextChordIndex = (chordIndex + 1) % chords.count

            // Crossfade envelope (last 15% of each chord fades to next)
            let crossfadeStart: Float = 0.85
            let currentWeight: Float
            let nextWeight: Float
            if chordProgress > crossfadeStart {
                let fade = (chordProgress - crossfadeStart) / (1.0 - crossfadeStart)
                currentWeight = 1.0 - fade
                nextWeight = fade
            } else {
                currentWeight = 1.0
                nextWeight = 0.0
            }

            for (freq, pan) in chords[chordIndex] {
                // Warm tone: sine + soft triangle harmonic
                let sine = sin(t * freq * 2.0 * .pi)
                let harmonic = sin(t * freq * 4.0 * .pi) * 0.15  // subtle overtone
                let tone = (sine + harmonic) * padAmp * currentWeight
                sampleL += tone * (1.0 - max(0, pan) * 0.5)
                sampleR += tone * (1.0 + min(0, pan) * 0.5)
            }
            if nextWeight > 0 {
                for (freq, pan) in chords[nextChordIndex] {
                    let sine = sin(t * freq * 2.0 * .pi)
                    let harmonic = sin(t * freq * 4.0 * .pi) * 0.15
                    let tone = (sine + harmonic) * padAmp * nextWeight
                    sampleL += tone * (1.0 - max(0, pan) * 0.5)
                    sampleR += tone * (1.0 + min(0, pan) * 0.5)
                }
            }

            // Arpeggio: one note at a time with attack/decay envelope
            let noteIndex = Int(t / noteDuration) % arpeggioNotes.count
            let noteProgress = (t - Float(noteIndex) * noteDuration) / noteDuration
            let noteFreq = arpeggioNotes[noteIndex]

            // Envelope: quick attack (5%), sustain (60%), long decay (35%)
            let noteEnv: Float
            if noteProgress < 0.05 {
                noteEnv = noteProgress / 0.05
            } else if noteProgress < 0.65 {
                noteEnv = 1.0
            } else {
                noteEnv = (1.0 - noteProgress) / 0.35
            }

            // Soft bell-like tone: sine + detuned sine for warmth
            let arpTone = sin(t * noteFreq * 2.0 * .pi)
            let arpDetune = sin(t * noteFreq * 1.002 * 2.0 * .pi)  // slight detune for richness
            let arpSample = (arpTone + arpDetune * 0.5) * arpAmp * noteEnv

            // Alternate arpeggio slightly left/right for movement
            let arpPan = sin(t * 0.3) * 0.4  // slow pan oscillation
            sampleL += arpSample * (1.0 - max(0, arpPan))
            sampleR += arpSample * (1.0 + min(0, arpPan))

            // Shimmer: very quiet high notes for sparkle
            for shimFreq in shimmerFreqs {
                let shimmer = sin(t * shimFreq * 2.0 * .pi) * shimmerAmp
                let shimPan = sin(t * 0.7 + shimFreq) * 0.6
                sampleL += shimmer * (1.0 - max(0, shimPan))
                sampleR += shimmer * (1.0 + min(0, shimPan))
            }

            // Loop fade: smooth crossfade at boundaries
            let fadeFrames = Int(sampleRate * 0.3)
            var envelope: Float = 1.0
            if frame < fadeFrames {
                envelope = Float(frame) / Float(fadeFrames)
            } else if frame > Int(frameCount) - fadeFrames {
                envelope = Float(Int(frameCount) - frame) / Float(fadeFrames)
            }

            leftChannel[frame] = sampleL * envelope
            rightChannel[frame] = sampleR * envelope
        }

        // ─── Engine setup ───
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let reverb = AVAudioUnitReverb()

        engine.attach(player)
        engine.attach(reverb)

        reverb.loadFactoryPreset(.cathedral)
        reverb.wetDryMix = 70

        engine.connect(player, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        let targetVolume: Float = 0.4
        engine.mainMixerNode.outputVolume = 0  // start silent for fade-in

        do {
            try engine.start()
            player.play()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
        } catch {
            lock.lock(); isPlaying = false; lock.unlock()
            return
        }

        // Fade in over 2 seconds
        DispatchQueue.global(qos: .userInitiated).async {
            let steps = 40
            for i in 1...steps {
                engine.mainMixerNode.outputVolume = targetVolume * (Float(i) / Float(steps))
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        lock.lock()
        self.audioEngine = engine
        self.playerNode = player
        lock.unlock()
    }

    func stop() {
        lock.lock()
        guard isPlaying, let engine = audioEngine else { lock.unlock(); return }
        isPlaying = false
        let mainMixer = engine.mainMixerNode
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let startVolume = mainMixer.outputVolume
            let steps = 30
            for i in 1...steps {
                mainMixer.outputVolume = startVolume * (1.0 - Float(i) / Float(steps))
                Thread.sleep(forTimeInterval: 0.05)
            }
            self?.playerNode?.stop()
            engine.stop()
            self?.lock.lock()
            self?.audioEngine = nil
            self?.playerNode = nil
            self?.lock.unlock()
        }
    }
}
