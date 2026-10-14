import Foundation
import AVFoundation

let sampleRate: Double = 44100.0
let dlsURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

struct NoteEvent {
    let track: Int
    let note: UInt8
    let velocity: UInt8
    let startSec: Double
    let durationSec: Double
}

struct TrackConfig {
    let program: UInt8
    let isPercussion: Bool
    let volume: Float
    let pan: Float
    let reverbWet: Float
}

/// Renders a multi-track MIDI sequence through Apple's CoreAudio Roland GS SoundBank (`gs_instruments.dls`)
/// with per-track stereo panning and `AVAudioUnitReverb` studio hall acoustics.
func renderSequenceOffline(
    tracks: [TrackConfig],
    notes: [NoteEvent],
    totalSeconds: Double,
    reverbPreset: AVAudioUnitReverbPreset = .mediumHall
) throws -> (left: [Float], right: [Float]) {
    let engine = AVAudioEngine()
    var samplers: [AVAudioUnitSampler] = []

    for cfg in tracks {
        let sampler = AVAudioUnitSampler()
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(reverbPreset)
        reverb.wetDryMix = cfg.reverbWet

        engine.attach(sampler)
        engine.attach(reverb)

        sampler.pan = cfg.pan
        sampler.overallGain = 20.0 * log10(max(0.001, cfg.volume))

        engine.connect(sampler, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        let bankMSB = cfg.isPercussion
            ? UInt8(kAUSampler_DefaultPercussionBankMSB)
            : UInt8(kAUSampler_DefaultMelodicBankMSB)
        try sampler.loadSoundBankInstrument(
            at: dlsURL,
            program: cfg.program,
            bankMSB: bankMSB,
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
        samplers.append(sampler)
    }

    let maxFrames: AVAudioFrameCount = 512
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
    try engine.start()

    // Warm up audio units for 2048 frames before t=0
    let warmBuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames)!
    for _ in 0..<4 {
        _ = try engine.renderOffline(maxFrames, to: warmBuf)
    }

    struct RawAction {
        let frame: Int
        let isOn: Bool
        let track: Int
        let note: UInt8
        let velocity: UInt8
    }

    var actions: [RawAction] = []
    actions.reserveCapacity(notes.count * 2)
    for n in notes {
        let onFrame = max(0, Int((n.startSec * sampleRate).rounded()))
        let offFrame = max(onFrame + 64, Int(((n.startSec + n.durationSec) * sampleRate).rounded()))
        actions.append(RawAction(frame: onFrame, isOn: true, track: n.track, note: n.note, velocity: n.velocity))
        actions.append(RawAction(frame: offFrame, isOn: false, track: n.track, note: n.note, velocity: 0))
    }
    // Sort by frame; note-offs before note-ons at the exact same frame so repeated notes retrigger cleanly
    actions.sort { a, b in
        if a.frame != b.frame { return a.frame < b.frame }
        return !a.isOn && b.isOn
    }

    let totalFrames = Int((totalSeconds * sampleRate).rounded())
    var outL = [Float](repeating: 0, count: totalFrames)
    var outR = [Float](repeating: 0, count: totalFrames)

    let renderBuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames)!
    var actionIdx = 0
    var currentFrame = 0

    while currentFrame < totalFrames {
        // Trigger all MIDI events up to currentFrame
        while actionIdx < actions.count && actions[actionIdx].frame <= currentFrame {
            let act = actions[actionIdx]
            let ch: UInt8 = tracks[act.track].isPercussion ? 9 : 0
            if act.isOn {
                samplers[act.track].startNote(act.note, withVelocity: act.velocity, onChannel: ch)
            } else {
                samplers[act.track].stopNote(act.note, onChannel: ch)
            }
            actionIdx += 1
        }

        var nextEventFrame = totalFrames
        if actionIdx < actions.count {
            nextEventFrame = min(totalFrames, actions[actionIdx].frame)
        }
        let framesToRender = min(Int(maxFrames), max(1, nextEventFrame - currentFrame))
        let status = try engine.renderOffline(AVAudioFrameCount(framesToRender), to: renderBuf)
        if status == .success,
           let chL = renderBuf.floatChannelData?[0],
           let chR = renderBuf.floatChannelData?[1] {
            for i in 0..<framesToRender {
                outL[currentFrame + i] = chL[i]
                outR[currentFrame + i] = chR[i]
            }
        }
        currentFrame += framesToRender
    }

    engine.stop()
    return (outL, outR)
}

/// Soft-knee studio mastering limiter & stereo WAV encoder.
/// For seamless loop tracks, blends the reverb tail of the second half into the loop boundary.
func writeStereoWav(
    path: String,
    left: [Float],
    right: [Float],
    targetPeak: Float = 0.90,
    repeats: Int = 1
) throws {
    let frames = left.count
    var peak: Float = 0.001
    for i in 0..<frames {
        peak = max(peak, max(abs(left[i]), abs(right[i])))
    }
    let gain = targetPeak / peak

    let singleBlockBytes = frames * 4
    let totalDataBytes = singleBlockBytes * repeats
    var data = Data(count: 44 + totalDataBytes)

    data.withUnsafeMutableBytes { rawPtr in
        let ptr = rawPtr.baseAddress!
        // RIFF header
        ptr.storeBytes(of: UInt32(0x46464952).littleEndian, toByteOffset: 0, as: UInt32.self) // "RIFF"
        ptr.storeBytes(of: UInt32(36 + totalDataBytes).littleEndian, toByteOffset: 4, as: UInt32.self)
        ptr.storeBytes(of: UInt32(0x45564157).littleEndian, toByteOffset: 8, as: UInt32.self) // "WAVE"
        // fmt chunk
        ptr.storeBytes(of: UInt32(0x20746d66).littleEndian, toByteOffset: 12, as: UInt32.self) // "fmt "
        ptr.storeBytes(of: UInt32(16).littleEndian, toByteOffset: 16, as: UInt32.self)
        ptr.storeBytes(of: UInt16(1).littleEndian, toByteOffset: 20, as: UInt16.self) // PCM
        ptr.storeBytes(of: UInt16(2).littleEndian, toByteOffset: 22, as: UInt16.self) // Stereo
        ptr.storeBytes(of: UInt32(sampleRate).littleEndian, toByteOffset: 24, as: UInt32.self)
        ptr.storeBytes(of: UInt32(sampleRate * 4).littleEndian, toByteOffset: 28, as: UInt32.self)
        ptr.storeBytes(of: UInt16(4).littleEndian, toByteOffset: 32, as: UInt16.self)
        ptr.storeBytes(of: UInt16(16).littleEndian, toByteOffset: 34, as: UInt16.self)
        // data chunk
        ptr.storeBytes(of: UInt32(0x61746164).littleEndian, toByteOffset: 36, as: UInt32.self) // "data"
        ptr.storeBytes(of: UInt32(totalDataBytes).littleEndian, toByteOffset: 40, as: UInt32.self)

        for i in 0..<frames {
            let l = Float(tanh(Double(left[i] * gain * 1.15)) / tanh(1.15))
            let r = Float(tanh(Double(right[i] * gain * 1.15)) / tanh(1.15))
            let sL = Int16(clamping: Int((l * 32767.0).rounded()))
            let sR = Int16(clamping: Int((r * 32767.0).rounded()))
            let offset = 44 + i * 4
            ptr.storeBytes(of: sL.littleEndian, toByteOffset: offset, as: Int16.self)
            ptr.storeBytes(of: sR.littleEndian, toByteOffset: offset + 2, as: Int16.self)
        }

        if repeats > 1 {
            let src = ptr.advanced(by: 44)
            for rep in 1..<repeats {
                let dst = ptr.advanced(by: 44 + rep * singleBlockBytes)
                dst.copyMemory(from: src, byteCount: singleBlockBytes)
            }
            // Apply a tiny 256-sample (~5.8ms) micro-fade at the very first and very last
            // samples of the entire multi-repeat file so even an external player restart is click-free.
            let totalFrames = frames * repeats
            let edgeFade = min(256, totalFrames / 8)
            for f in 0..<edgeFade {
                let scale = Float(f) / Float(edgeFade)
                let startOff = 44 + f * 4
                let sL0 = Int16(littleEndian: ptr.load(fromByteOffset: startOff, as: Int16.self))
                let sR0 = Int16(littleEndian: ptr.load(fromByteOffset: startOff + 2, as: Int16.self))
                ptr.storeBytes(of: Int16(Float(sL0) * scale).littleEndian, toByteOffset: startOff, as: Int16.self)
                ptr.storeBytes(of: Int16(Float(sR0) * scale).littleEndian, toByteOffset: startOff + 2, as: Int16.self)

                let endOff = 44 + (totalFrames - 1 - f) * 4
                let sL1 = Int16(littleEndian: ptr.load(fromByteOffset: endOff, as: Int16.self))
                let sR1 = Int16(littleEndian: ptr.load(fromByteOffset: endOff + 2, as: Int16.self))
                ptr.storeBytes(of: Int16(Float(sL1) * scale).littleEndian, toByteOffset: endOff, as: Int16.self)
                ptr.storeBytes(of: Int16(Float(sR1) * scale).littleEndian, toByteOffset: endOff + 2, as: Int16.self)
            }
        }
    }

    try data.write(to: URL(fileURLWithPath: path))
}

func midiToFreq(_ midi: Int) -> Double {
    return 440.0 * pow(2.0, Double(midi - 69) / 12.0)
}

// ============================================================================
// 1. BGM TRACK 1: "CYBER OVERDRIVE" (132 BPM OutRun / Mario Kart Electro-Brass)
// ============================================================================
func buildCyberOverdriveBgm() throws -> (left: [Float], right: [Float]) {
    let bpm = 132.0
    let stepSec = 60.0 / bpm / 4.0 // 16th note = 0.113636s
    let loopSteps = 128 // 8 bars
    let loopSec = Double(loopSteps) * stepSec
    // Render 3 full cycles so cycle 1 has both a full pre-roll from cycle 0
    // and natural look-ahead into cycle 2 for a 100% seamless loop crossfade!
    let renderSec = loopSec * 3.0 + 0.2

    let tracks: [TrackConfig] = [
        // 0: Power Drum Kit (Percussion bank, Program 16 = Power Kit)
        TrackConfig(program: 16, isPercussion: true, volume: 0.95, pan: 0.0, reverbWet: 14),
        // 1: Synth Bass 1 (Program 38)
        TrackConfig(program: 38, isPercussion: false, volume: 0.88, pan: -0.08, reverbWet: 6),
        // 2: Slap Bass 1 (Program 36 - layered for attack punch)
        TrackConfig(program: 36, isPercussion: false, volume: 0.65, pan: 0.08, reverbWet: 8),
        // 3: DX7 Rhodes Electric Piano 2 (Program 5)
        TrackConfig(program: 5, isPercussion: false, volume: 0.68, pan: -0.35, reverbWet: 26),
        // 4: Brass Section (Program 61)
        TrackConfig(program: 61, isPercussion: false, volume: 0.78, pan: 0.25, reverbWet: 28),
        // 5: Sawtooth Lead (Program 81)
        TrackConfig(program: 81, isPercussion: false, volume: 0.76, pan: -0.12, reverbWet: 32),
        // 6: Vibraphone / Bell Arpeggio (Program 11)
        TrackConfig(program: 11, isPercussion: false, volume: 0.58, pan: 0.38, reverbWet: 30),
        // 7: Warm Strings Pad (Program 48)
        TrackConfig(program: 48, isPercussion: false, volume: 0.46, pan: 0.0, reverbWet: 38),
    ]

    // 8-bar progression: Am9 | Fmaj9 | Cmaj9 | G6 | Dm9 | Em7 | Fmaj7 | E7sus4 -> E7
    let bars: [[UInt8]] = [
        [33, 57, 60, 64, 67, 71], // Bar 0: Am9   (A1, A3, C4, E4, G4, B4)
        [29, 53, 57, 60, 64, 67], // Bar 1: Fmaj9 (F1, F3, A3, C4, E4, G4)
        [36, 60, 64, 67, 71, 74], // Bar 2: Cmaj9 (C2, C4, E4, G4, B4, D5)
        [31, 55, 59, 62, 64, 67], // Bar 3: G6    (G1, G3, B3, D4, E4, G4)
        [38, 57, 60, 64, 65, 69], // Bar 4: Dm9   (D2, A3, C4, E4, F4, A4)
        [28, 55, 59, 62, 64, 67], // Bar 5: Em7   (E1, G3, B3, D4, E4, G4)
        [29, 53, 57, 60, 64, 69], // Bar 6: Fmaj13(F1, F3, A3, C4, E4, A4)
        [28, 56, 59, 62, 64, 68], // Bar 7: E7    (E1, G#3, B3, D4, E4, G#4)
    ]

    // Melodic events: (stepIn128, midiNote, durationSteps, harmonyMidiOrZero)
    let melody: [(Int, UInt8, Double, UInt8)] = [
        // Bar 0 (Am9)
        (0, 69, 1.8, 0), (2, 72, 1.8, 0), (4, 76, 2.5, 72), (7, 79, 1.0, 76),
        (8, 76, 2.8, 72), (11, 74, 1.0, 0), (12, 72, 2.0, 69), (14, 71, 1.8, 0),
        // Bar 1 (Fmaj9)
        (16, 69, 1.8, 65), (18, 72, 1.8, 0), (20, 76, 2.5, 72), (23, 79, 1.0, 0),
        (24, 81, 3.5, 76), (28, 79, 2.0, 72), (30, 76, 1.8, 0),
        // Bar 2 (Cmaj9)
        (32, 79, 2.8, 76), (35, 81, 1.0, 0), (36, 84, 2.8, 79), (39, 83, 1.0, 0),
        (40, 79, 2.0, 76), (42, 76, 2.0, 72), (44, 74, 3.5, 71),
        // Bar 3 (G6)
        (48, 74, 1.8, 71), (50, 76, 1.8, 0), (52, 79, 2.8, 74), (55, 76, 1.0, 0),
        (56, 74, 2.0, 71), (58, 72, 1.8, 0), (60, 71, 3.5, 67),
        // Bar 4 (Dm9)
        (64, 69, 1.8, 65), (66, 74, 1.8, 0), (68, 77, 2.5, 74), (71, 81, 1.0, 77),
        (72, 79, 2.0, 76), (74, 77, 1.8, 0), (76, 76, 3.5, 72),
        // Bar 5 (Em7)
        (80, 71, 1.8, 67), (82, 76, 1.8, 0), (84, 79, 2.5, 76), (87, 83, 1.0, 79),
        (88, 81, 2.0, 76), (90, 79, 1.8, 0), (92, 76, 3.5, 71),
        // Bar 6 (Fmaj13 climb!)
        (96, 72, 1.8, 69), (98, 76, 1.8, 72), (100, 79, 1.8, 76), (102, 81, 1.8, 77),
        (104, 84, 2.8, 81), (107, 83, 1.0, 79), (108, 81, 3.5, 76),
        // Bar 7 (E7 Grand Prix Turnaround!)
        (112, 80, 2.8, 76), (115, 83, 1.0, 79), (116, 86, 2.8, 83), (119, 84, 1.0, 80),
        (120, 83, 3.5, 76), (124, 80, 3.5, 74),
    ]

    var notes: [NoteEvent] = []
    let arpOrder = [1, 2, 3, 4, 5, 4, 3, 2]

    for cycle in 0..<3 {
        let baseStep = cycle * loopSteps
        for bar in 0..<8 {
            let chord = bars[bar]
            let barStartStep = baseStep + bar * 16
            let barStartSec = Double(barStartStep) * stepSec

            // Sustained strings pad (Track 7)
            for c in 1...4 {
                notes.append(NoteEvent(track: 7, note: chord[c], velocity: 78, startSec: barStartSec, durationSec: stepSec * 15.5))
            }

            // Crash cymbal on Bar 0 and Bar 4
            if bar % 4 == 0 {
                notes.append(NoteEvent(track: 0, note: 49, velocity: 112, startSec: barStartSec, durationSec: 1.5))
            }

            // Syncopated Rhodes + Brass chord stabs on steps 0, 3, 6, 10, 12
            let stabSteps: [(Int, Double, UInt8)] = [
                (0, 2.4, 102), (3, 2.2, 94), (6, 3.2, 100), (10, 1.8, 92), (12, 3.4, 98)
            ]
            for (s, durSteps, vel) in stabSteps {
                let stSec = Double(barStartStep + s) * stepSec
                for c in 1...5 {
                    notes.append(NoteEvent(track: 3, note: chord[c], velocity: vel, startSec: stSec, durationSec: stepSec * durSteps))
                    if s == 0 || s == 6 || s == 12 {
                        notes.append(NoteEvent(track: 4, note: chord[c], velocity: vel - 8, startSec: stSec, durationSec: stepSec * (durSteps * 0.85)))
                    }
                }
            }

            for s in 0..<16 {
                let globalStep = barStartStep + s
                let tSec = Double(globalStep) * stepSec

                // 1. Drums (Track 0)
                if s % 4 == 0 || (bar % 2 == 1 && s == 14) {
                    notes.append(NoteEvent(track: 0, note: 36, velocity: 124, startSec: tSec, durationSec: 0.25))
                }
                if s == 4 || s == 12 {
                    notes.append(NoteEvent(track: 0, note: 38, velocity: 120, startSec: tSec, durationSec: 0.25))
                    notes.append(NoteEvent(track: 0, note: 39, velocity: 96, startSec: tSec, durationSec: 0.22))
                }
                if (bar == 3 || bar == 7) && s >= 12 {
                    let tomNotes: [UInt8] = [50, 48, 47, 45]
                    notes.append(NoteEvent(track: 0, note: tomNotes[s - 12], velocity: 116, startSec: tSec, durationSec: 0.20))
                }
                if s % 4 == 2 {
                    notes.append(NoteEvent(track: 0, note: 46, velocity: 98, startSec: tSec, durationSec: stepSec * 1.8))
                } else {
                    let hatVel: UInt8 = (s % 2 == 0) ? 92 : 72
                    notes.append(NoteEvent(track: 0, note: 42, velocity: hatVel, startSec: tSec, durationSec: stepSec * 0.7))
                }

                // 2. Octave-Pumping Bassline (Tracks 1 & 2)
                let bassNote = chord[0] + ((s % 2 == 1) ? 12 : 0)
                let bassVel: UInt8 = (s % 4 == 0) ? 118 : ((s % 2 == 1) ? 108 : 96)
                notes.append(NoteEvent(track: 1, note: bassNote, velocity: bassVel, startSec: tSec, durationSec: stepSec * 0.82))
                if s % 2 == 0 || s % 4 == 3 {
                    notes.append(NoteEvent(track: 2, note: bassNote + 12, velocity: bassVel - 12, startSec: tSec, durationSec: stepSec * 0.65))
                }

                // 3. 16th-Note Vibraphone Arpeggiator (Track 6)
                let arpIdx = arpOrder[s % arpOrder.count]
                let arpNote = chord[arpIdx] + 12
                notes.append(NoteEvent(track: 6, note: arpNote, velocity: (s % 2 == 0) ? 88 : 74, startSec: tSec, durationSec: stepSec * 0.85))
            }
        }

        // 4. Hero Lead Melody (Track 5 = Saw Lead, Track 4 = Brass Harmony)
        for (mStep, mNote, durSteps, harmNote) in melody {
            let stSec = Double(baseStep + mStep) * stepSec
            let durSec = durSteps * stepSec * 0.92
            notes.append(NoteEvent(track: 5, note: mNote, velocity: 114, startSec: stSec, durationSec: durSec))
            if harmNote > 0 {
                notes.append(NoteEvent(track: 4, note: harmNote, velocity: 96, startSec: stSec, durationSec: durSec))
            }
        }
    }

    var rendered = try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: renderSec, reverbPreset: .mediumHall)

    // Layer true phase-integrated 44.1kHz Analog Sub-Bass & Punchy Kick Sub-Thump across all 3 cycles
    // BEFORE slicing so the sub-bass phase is 100% continuous at the loop boundary!
    var subPhase = 0.0
    var kickPhase = 0.0
    for i in 0..<rendered.left.count {
        let t = Double(i) / sampleRate
        let stepFloat = t / stepSec
        let step = Int(floor(stepFloat)) % loopSteps
        let stepT = (stepFloat - floor(stepFloat)) * stepSec
        let bar = (step / 16) % 8
        let s = step % 16

        let subFreq = midiToFreq(Int(bars[bar][0]))
        subPhase += (2.0 * Double.pi * subFreq) / sampleRate
        let subEnv = (1.0 - exp(-stepT * 180.0)) * exp(-stepT * 8.0)
        let subSig = Float(sin(subPhase) * subEnv * 0.14)

        var kickSub: Float = 0.0
        if s % 4 == 0 {
            let kFreq = 115.0 * exp(-stepT * 42.0) + 46.0
            kickPhase += (2.0 * Double.pi * kFreq) / sampleRate
            kickSub = Float(sin(kickPhase) * exp(-stepT * 16.0) * 0.18)
        } else {
            kickPhase = 0.0
        }

        rendered.left[i] += subSig + kickSub
        rendered.right[i] += subSig + kickSub
    }

    let startFrame = Int((loopSec * sampleRate).rounded())
    let loopFrames = Int((loopSec * sampleRate).rounded())
    var loopL = Array(rendered.left[startFrame..<(startFrame + loopFrames)])
    var loopR = Array(rendered.right[startFrame..<(startFrame + loopFrames)])

    // Apply a 1024-sample (~23ms) cosine crossfade at the end of cycle 1 with the end of cycle 0
    // so loop[loopFrames-1] -> loop[0] is 100% click-free and phase-matched!
    let xfade = 1024
    for k in 0..<xfade {
        let alpha = Float(0.5 * (1.0 - cos(Double(k) / Double(xfade) * Double.pi))) // 0 -> 1
        let idx = loopFrames - xfade + k
        let preIdx = startFrame - xfade + k
        loopL[idx] = loopL[idx] * (1.0 - alpha) + rendered.left[preIdx] * alpha
        loopR[idx] = loopR[idx] * (1.0 - alpha) + rendered.right[preIdx] * alpha
    }

    return (loopL, loopR)
}

// ============================================================================
// 2. BGM TRACK 2: "TURBO FUNK GP" (126 BPM Mario Kart 8 Big-Band Jazz-Funk)
// ============================================================================
func buildFunkyCircuitBgm() throws -> (left: [Float], right: [Float]) {
    let bpm = 126.0
    let stepSec = 60.0 / bpm / 4.0
    let loopSteps = 128
    let loopSec = Double(loopSteps) * stepSec
    let renderSec = loopSec * 3.0 + 0.2

    let tracks: [TrackConfig] = [
        // 0: Standard Acoustic/Funk Drum Kit (Percussion bank, Program 0)
        TrackConfig(program: 0, isPercussion: true, volume: 0.96, pan: 0.0, reverbWet: 12),
        // 1: Slap Bass 1 (Program 36)
        TrackConfig(program: 36, isPercussion: false, volume: 0.92, pan: -0.05, reverbWet: 8),
        // 2: Rhodes Electric Piano 1 (Program 4)
        TrackConfig(program: 4, isPercussion: false, volume: 0.76, pan: -0.38, reverbWet: 22),
        // 3: Funk Clavinet (Program 7)
        TrackConfig(program: 7, isPercussion: false, volume: 0.62, pan: 0.42, reverbWet: 18),
        // 4: Big-Band Brass Section (Program 61)
        TrackConfig(program: 61, isPercussion: false, volume: 0.84, pan: 0.22, reverbWet: 26),
        // 5: Lead Alto Sax / Trumpet Fusion (Program 65 Alto Sax)
        TrackConfig(program: 65, isPercussion: false, volume: 0.80, pan: -0.15, reverbWet: 28),
        // 6: Lead Trumpet (Program 56)
        TrackConfig(program: 56, isPercussion: false, volume: 0.75, pan: 0.18, reverbWet: 28),
        // 7: Vibraphone (Program 11)
        TrackConfig(program: 11, isPercussion: false, volume: 0.64, pan: 0.30, reverbWet: 30),
    ]

    // 8-bar Jazz-Funk progression: Fmaj9 | Em7 - A7 | Dm9 | G13 | Em9 | Am9 | Abmaj9 | G13sus4
    let bars: [[UInt8]] = [
        [29, 57, 60, 64, 67, 72], // Bar 0: Fmaj9
        [28, 55, 59, 62, 67, 71], // Bar 1: Em7
        [38, 53, 57, 60, 64, 69], // Bar 2: Dm9
        [31, 55, 59, 64, 65, 71], // Bar 3: G13
        [28, 55, 59, 62, 66, 71], // Bar 4: Em9
        [33, 57, 60, 64, 67, 71], // Bar 5: Am9
        [32, 56, 60, 63, 67, 70], // Bar 6: Abmaj9
        [31, 55, 60, 62, 65, 69], // Bar 7: G13sus4
    ]

    // Big-Band Jazz-Kart Horn Melody: (stepIn128, leadMidi, durSteps, brassHarmonyMidi)
    let melody: [(Int, UInt8, Double, UInt8)] = [
        // Bar 0 (Fmaj9)
        (0, 72, 1.5, 69), (2, 76, 1.5, 72), (4, 79, 1.5, 76), (6, 81, 2.5, 77),
        (9, 79, 1.0, 76), (10, 76, 1.8, 72), (12, 74, 2.8, 69),
        // Bar 1 (Em7 -> A7)
        (16, 71, 1.5, 67), (18, 74, 1.5, 71), (20, 76, 1.5, 72), (22, 79, 2.5, 74),
        (25, 76, 1.0, 73), (26, 74, 1.8, 69), (28, 73, 2.8, 69),
        // Bar 2 (Dm9)
        (32, 69, 1.5, 65), (34, 72, 1.5, 69), (36, 74, 1.5, 71), (38, 77, 2.5, 72),
        (41, 81, 1.8, 76), (43, 79, 1.5, 74), (45, 76, 2.5, 72),
        // Bar 3 (G13)
        (48, 74, 1.0, 71), (49, 76, 1.0, 72), (50, 79, 2.0, 74), (52, 83, 2.5, 79),
        (55, 81, 1.5, 76), (57, 79, 1.5, 74), (59, 76, 1.5, 71), (61, 74, 2.5, 67),
        // Bar 4 (Em9)
        (64, 76, 1.5, 71), (66, 79, 1.5, 74), (68, 83, 1.5, 79), (70, 84, 2.5, 79),
        (73, 83, 1.5, 79), (75, 79, 1.5, 74), (77, 76, 2.5, 71),
        // Bar 5 (Am9)
        (80, 72, 1.5, 69), (82, 76, 1.5, 72), (84, 79, 1.5, 76), (86, 81, 2.5, 76),
        (89, 84, 1.8, 79), (91, 81, 1.5, 76), (93, 79, 2.5, 72),
        // Bar 6 (Abmaj9 Key-Modulation Lift!)
        (96, 75, 1.5, 72), (98, 79, 1.5, 75), (100, 82, 1.5, 79), (102, 84, 2.5, 79),
        (105, 82, 1.5, 79), (107, 79, 1.5, 75), (109, 75, 2.5, 72),
        // Bar 7 (G13sus4 Brass Turnaround!)
        (112, 74, 1.5, 69), (114, 77, 1.5, 72), (116, 79, 1.5, 74), (118, 81, 1.5, 77),
        (120, 83, 2.5, 79), (123, 84, 1.5, 79), (125, 86, 2.5, 81),
    ]

    var notes: [NoteEvent] = []
    let funkKickSteps: Set<Int> = [0, 3, 6, 8, 10, 14]
    let ghostSnareSteps: Set<Int> = [2, 7, 9, 15]
    let compSteps: [(Int, Double, UInt8)] = [
        (0, 2.0, 98), (3, 1.8, 92), (6, 2.5, 100), (10, 1.5, 90), (12, 2.8, 96)
    ]

    for cycle in 0..<3 {
        let baseStep = cycle * loopSteps
        for bar in 0..<8 {
            let chord = bars[bar]
            let barStartStep = baseStep + bar * 16
            let barStartSec = Double(barStartStep) * stepSec

            if bar % 4 == 0 {
                notes.append(NoteEvent(track: 0, note: 49, velocity: 108, startSec: barStartSec, durationSec: 1.4))
            }

            // Rhodes comping (Track 2)
            for (s, durSteps, vel) in compSteps {
                let stSec = Double(barStartStep + s) * stepSec
                for c in 1...5 {
                    notes.append(NoteEvent(track: 2, note: chord[c], velocity: vel, startSec: stSec, durationSec: stepSec * durSteps))
                }
            }

            for s in 0..<16 {
                let globalStep = barStartStep + s
                let tSec = Double(globalStep) * stepSec

                // 1. Funk Drums (Track 0)
                if funkKickSteps.contains(s) {
                    notes.append(NoteEvent(track: 0, note: 36, velocity: (s == 0 || s == 8) ? 122 : 108, startSec: tSec, durationSec: 0.22))
                }
                if s == 4 || s == 12 {
                    notes.append(NoteEvent(track: 0, note: 38, velocity: 120, startSec: tSec, durationSec: 0.24))
                } else if ghostSnareSteps.contains(s) {
                    notes.append(NoteEvent(track: 0, note: 38, velocity: 58, startSec: tSec, durationSec: 0.12))
                }
                if s % 4 == 2 {
                    notes.append(NoteEvent(track: 0, note: 46, velocity: 92, startSec: tSec, durationSec: stepSec * 1.5))
                } else {
                    notes.append(NoteEvent(track: 0, note: 42, velocity: (s % 2 == 0) ? 88 : 68, startSec: tSec, durationSec: stepSec * 0.65))
                }
                if s == 4 || s == 12 {
                    notes.append(NoteEvent(track: 0, note: 54, velocity: 78, startSec: tSec, durationSec: 0.18))
                }

                // 2. Syncopated Slap Bass (Track 1)
                let isPop = (s == 2 || s == 7 || s == 11 || s == 14)
                let isFifth = (s == 5 || s == 13)
                let bassMidi: UInt8 = chord[0] + (isPop ? 12 : (isFifth ? 7 : 0))
                let bassVel: UInt8 = isPop ? 122 : ((s % 4 == 0) ? 116 : 95)
                if s != 9 {
                    notes.append(NoteEvent(track: 1, note: bassMidi, velocity: bassVel, startSec: tSec, durationSec: stepSec * (isPop ? 0.55 : 0.78)))
                }

                // 3. Funk Clavinet 16th Skank on off-beats (Track 3)
                if s == 2 || s == 5 || s == 11 || s == 15 {
                    notes.append(NoteEvent(track: 3, note: chord[2], velocity: 86, startSec: tSec, durationSec: stepSec * 0.55))
                    notes.append(NoteEvent(track: 3, note: chord[4], velocity: 86, startSec: tSec, durationSec: stepSec * 0.55))
                }

                // 4. Sparkling Vibraphone counter-line (Track 7)
                if s % 2 == 0 {
                    let vNote = chord[1 + ((s / 2) % 5)] + 12
                    notes.append(NoteEvent(track: 7, note: vNote, velocity: 80, startSec: tSec, durationSec: stepSec * 1.4))
                }
            }
        }

        // 5. Big-Band Sax + Trumpet + Brass Section Lead (Tracks 4, 5, 6)
        for (mStep, mNote, durSteps, harmNote) in melody {
            let stSec = Double(baseStep + mStep) * stepSec
            let durSec = durSteps * stepSec * 0.90
            notes.append(NoteEvent(track: 5, note: mNote, velocity: 112, startSec: stSec, durationSec: durSec))
            notes.append(NoteEvent(track: 6, note: mNote, velocity: 106, startSec: stSec, durationSec: durSec))
            if harmNote > 0 {
                notes.append(NoteEvent(track: 4, note: harmNote, velocity: 100, startSec: stSec, durationSec: durSec))
            }
        }
    }

    var rendered = try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: renderSec, reverbPreset: .mediumHall)

    var subPhase = 0.0
    for i in 0..<rendered.left.count {
        let t = Double(i) / sampleRate
        let stepFloat = t / stepSec
        let step = Int(floor(stepFloat)) % loopSteps
        let stepT = (stepFloat - floor(stepFloat)) * stepSec
        let bar = (step / 16) % 8
        let subFreq = midiToFreq(Int(bars[bar][0]))
        subPhase += (2.0 * Double.pi * subFreq) / sampleRate
        let subEnv = (1.0 - exp(-stepT * 180.0)) * exp(-stepT * 9.0)
        let subSig = Float(sin(subPhase) * subEnv * 0.13)
        rendered.left[i] += subSig
        rendered.right[i] += subSig
    }

    let startFrame = Int((loopSec * sampleRate).rounded())
    let loopFrames = Int((loopSec * sampleRate).rounded())
    var loopL = Array(rendered.left[startFrame..<(startFrame + loopFrames)])
    var loopR = Array(rendered.right[startFrame..<(startFrame + loopFrames)])

    let xfade = 1024
    for k in 0..<xfade {
        let alpha = Float(0.5 * (1.0 - cos(Double(k) / Double(xfade) * Double.pi)))
        let idx = loopFrames - xfade + k
        let preIdx = startFrame - xfade + k
        loopL[idx] = loopL[idx] * (1.0 - alpha) + rendered.left[preIdx] * alpha
        loopR[idx] = loopR[idx] * (1.0 - alpha) + rendered.right[preIdx] * alpha
    }

    return (loopL, loopR)
}

// ============================================================================
// 3. STUDIO SOUND EFFECTS (SFX)
// ============================================================================

/// 1. Countdown Beep ("3... 2... 1..."): Sampled Vibraphone + Rhodes + Brass + Warm Sub Attack
func buildSfxCountdownBeep() throws -> (left: [Float], right: [Float]) {
    let tracks: [TrackConfig] = [
        TrackConfig(program: 11, isPercussion: false, volume: 0.95, pan: -0.15, reverbWet: 24), // Vibraphone
        TrackConfig(program: 5, isPercussion: false, volume: 0.85, pan: 0.15, reverbWet: 24),  // DX Rhodes
        TrackConfig(program: 61, isPercussion: false, volume: 0.65, pan: 0.0, reverbWet: 20),  // Brass Section
        TrackConfig(program: 0, isPercussion: true, volume: 0.70, pan: 0.0, reverbWet: 10),    // Drum transient
    ]
    let notes: [NoteEvent] = [
        NoteEvent(track: 0, note: 69, velocity: 118, startSec: 0.0, durationSec: 0.24), // A4
        NoteEvent(track: 0, note: 81, velocity: 112, startSec: 0.0, durationSec: 0.24), // A5
        NoteEvent(track: 1, note: 69, velocity: 115, startSec: 0.0, durationSec: 0.24),
        NoteEvent(track: 1, note: 76, velocity: 105, startSec: 0.0, durationSec: 0.24), // E5
        NoteEvent(track: 2, note: 69, velocity: 100, startSec: 0.0, durationSec: 0.20),
        NoteEvent(track: 3, note: 36, velocity: 95, startSec: 0.0, durationSec: 0.15),
    ]
    return try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: 0.36, reverbPreset: .mediumRoom)
}

/// 2. Countdown GO!!: Full Big-Band Brass Fanfare Chord + Orchestra Hit + Crash Cymbal!
func buildSfxCountdownGo() throws -> (left: [Float], right: [Float]) {
    let tracks: [TrackConfig] = [
        TrackConfig(program: 61, isPercussion: false, volume: 0.95, pan: -0.20, reverbWet: 30), // Brass Section
        TrackConfig(program: 56, isPercussion: false, volume: 0.88, pan: 0.25, reverbWet: 30),  // Trumpet
        TrackConfig(program: 55, isPercussion: false, volume: 0.78, pan: 0.0, reverbWet: 28),   // Orchestra Hit
        TrackConfig(program: 11, isPercussion: false, volume: 0.80, pan: -0.30, reverbWet: 30), // Vibraphone
        TrackConfig(program: 0, isPercussion: true, volume: 0.88, pan: 0.0, reverbWet: 22),     // Crash + Kick
    ]
    // Bright Cmaj9 chord (C4, G4, B4, D5, E5, G5, C6)
    let chord: [UInt8] = [60, 67, 71, 74, 76, 79, 84]
    var notes: [NoteEvent] = [
        NoteEvent(track: 2, note: 72, velocity: 120, startSec: 0.0, durationSec: 0.55),
        NoteEvent(track: 4, note: 36, velocity: 124, startSec: 0.0, durationSec: 0.40),
        NoteEvent(track: 4, note: 49, velocity: 118, startSec: 0.0, durationSec: 0.70),
    ]
    for n in chord {
        notes.append(NoteEvent(track: 0, note: n, velocity: 120, startSec: 0.0, durationSec: 0.62))
        notes.append(NoteEvent(track: 1, note: n, velocity: 116, startSec: 0.015, durationSec: 0.60))
        notes.append(NoteEvent(track: 3, note: n, velocity: 112, startSec: 0.0, durationSec: 0.65))
    }
    return try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: 0.88, reverbPreset: .mediumHall)
}

/// 3. Turbo Boost Whoosh: Smooth 4-Pole Filtered Jet Turbine Air Rush + Sub Ignition + Warm Chord Swell
func buildSfxBoost() throws -> (left: [Float], right: [Float]) {
    let duration = 0.74
    let tracks: [TrackConfig] = [
        TrackConfig(program: 62, isPercussion: false, volume: 0.65, pan: -0.25, reverbWet: 35), // Synth Brass 1
        TrackConfig(program: 89, isPercussion: false, volume: 0.75, pan: 0.25, reverbWet: 40),  // Warm Pad
        TrackConfig(program: 0, isPercussion: true, volume: 0.85, pan: 0.0, reverbWet: 18),     // Kick + Cymbal swell
    ]
    let notes: [NoteEvent] = [
        NoteEvent(track: 2, note: 36, velocity: 125, startSec: 0.0, durationSec: 0.35),
        NoteEvent(track: 0, note: 60, velocity: 105, startSec: 0.0, durationSec: 0.55),
        NoteEvent(track: 0, note: 67, velocity: 105, startSec: 0.02, durationSec: 0.55),
        NoteEvent(track: 0, note: 72, velocity: 110, startSec: 0.04, durationSec: 0.55),
        NoteEvent(track: 1, note: 60, velocity: 110, startSec: 0.0, durationSec: 0.60),
        NoteEvent(track: 1, note: 72, velocity: 110, startSec: 0.0, durationSec: 0.60),
        NoteEvent(track: 1, note: 79, velocity: 110, startSec: 0.04, durationSec: 0.60),
    ]
    var (left, right) = try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: duration, reverbPreset: .mediumHall)

    // Layer smooth aerodynamic jet turbine whoosh (4-pole lowpass + bandpass filtered noise + sub ignition)
    var subPhase = 0.0
    var turbinePhaseL = 0.0
    var turbinePhaseR = 0.0
    var lp1L = 0.0, lp2L = 0.0, bpL = 0.0
    var lp1R = 0.0, lp2R = 0.0, bpR = 0.0
    var rngState: UInt64 = 0xCAFEBABE

    func nextRand() -> Double {
        rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
        return Double(Int64(bitPattern: rngState)) / Double(Int64.max)
    }

    for i in 0..<left.count {
        let t = Double(i) / sampleRate
        let prog = t / duration
        let env = sin(pow(prog, 0.45) * Double.pi)

        // Sub-bass ignition thump (145 Hz -> 42 Hz, true phase integration!)
        let subFreq = 105.0 * exp(-t * 22.0) + 42.0
        subPhase += (2.0 * Double.pi * subFreq) / sampleRate
        let subSig = sin(subPhase) * exp(-t * 7.5) * 0.48

        // Smooth twin-turbine harmonic spool (180 Hz -> 520 Hz)
        let turbFreq = 180.0 + 340.0 * (1.0 - exp(-t * 5.5))
        turbinePhaseL += (2.0 * Double.pi * turbFreq) / sampleRate
        turbinePhaseR += (2.0 * Double.pi * (turbFreq * 1.006)) / sampleRate
        let turbL = (sin(turbinePhaseL) + 0.4 * sin(turbinePhaseL * 2.0)) * env * 0.16
        let turbR = (sin(turbinePhaseR) + 0.4 * sin(turbinePhaseR * 2.0)) * env * 0.16

        // Aerodynamic jet air rush (SVF bandpass + cascaded lowpass, zero harshness!)
        let nL = nextRand()
        let nR = nextRand()
        let cutoff = 320.0 + 1650.0 * sin(pow(prog, 0.6) * Double.pi)
        let f = min(0.45, 2.0 * sin(Double.pi * cutoff / sampleRate))
        let q = 0.42

        let hpL = nL - lp1L - q * bpL
        bpL += f * hpL
        lp1L += f * bpL
        lp2L += 0.35 * (bpL - lp2L)

        let hpR = nR - lp1R - q * bpR
        bpR += f * hpR
        lp1R += f * bpR
        lp2R += 0.35 * (bpR - lp2R)

        left[i] = left[i] * 0.65 + Float(subSig + turbL + lp2L * env * 0.45)
        right[i] = right[i] * 0.65 + Float(subSig + turbR + lp2R * env * 0.45)
    }
    return (left, right)
}

/// 4. Drift Spark Tier Charge: Sparkling Celesta + Glockenspiel + Orchestral Harp Triad!
func buildSfxDriftCharge() throws -> (left: [Float], right: [Float]) {
    let tracks: [TrackConfig] = [
        TrackConfig(program: 8, isPercussion: false, volume: 0.90, pan: -0.25, reverbWet: 28),  // Celesta
        TrackConfig(program: 9, isPercussion: false, volume: 0.85, pan: 0.25, reverbWet: 28),   // Glockenspiel
        TrackConfig(program: 46, isPercussion: false, volume: 0.88, pan: 0.0, reverbWet: 32),   // Orchestral Harp
    ]
    // D5 - F#5 - A5 - D6 rapid ascending sparkle
    let notesMidi: [UInt8] = [74, 78, 81, 86]
    var notes: [NoteEvent] = []
    for (idx, n) in notesMidi.enumerated() {
        let st = Double(idx) * 0.032
        notes.append(NoteEvent(track: 0, note: n, velocity: 112, startSec: st, durationSec: 0.22))
        notes.append(NoteEvent(track: 1, note: n, velocity: 106, startSec: st, durationSec: 0.22))
        notes.append(NoteEvent(track: 2, note: n, velocity: 114, startSec: st, durationSec: 0.24))
    }
    return try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: 0.38, reverbPreset: .mediumHall)
}

/// 5. Golden Coin Pickup: Crisp Glockenspiel + Vibraphone + DX Rhodes B5 -> E6 Bell
func buildSfxCoin() throws -> (left: [Float], right: [Float]) {
    let tracks: [TrackConfig] = [
        TrackConfig(program: 9, isPercussion: false, volume: 0.92, pan: -0.15, reverbWet: 24),  // Glockenspiel
        TrackConfig(program: 11, isPercussion: false, volume: 0.92, pan: 0.15, reverbWet: 26),  // Vibraphone
        TrackConfig(program: 5, isPercussion: false, volume: 0.80, pan: 0.0, reverbWet: 22),    // DX Rhodes
    ]
    let notes: [NoteEvent] = [
        // B5 (83) -> E6 (88)
        NoteEvent(track: 0, note: 83, velocity: 116, startSec: 0.0, durationSec: 0.09),
        NoteEvent(track: 1, note: 83, velocity: 116, startSec: 0.0, durationSec: 0.09),
        NoteEvent(track: 2, note: 71, velocity: 105, startSec: 0.0, durationSec: 0.09),

        NoteEvent(track: 0, note: 88, velocity: 124, startSec: 0.068, durationSec: 0.32),
        NoteEvent(track: 1, note: 88, velocity: 124, startSec: 0.068, durationSec: 0.32),
        NoteEvent(track: 2, note: 76, velocity: 112, startSec: 0.068, durationSec: 0.32),
    ]
    return try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: 0.44, reverbPreset: .mediumHall)
}

/// 6. Item Box Pickup & Roulette: Crystal Harp Chime + 8-Note Stereo Marimba/Vibraphone Roulette!
func buildSfxItemPickup() throws -> (left: [Float], right: [Float]) {
    let tracks: [TrackConfig] = [
        TrackConfig(program: 12, isPercussion: false, volume: 0.92, pan: -0.30, reverbWet: 24), // Marimba
        TrackConfig(program: 11, isPercussion: false, volume: 0.90, pan: 0.30, reverbWet: 26),  // Vibraphone
        TrackConfig(program: 8, isPercussion: false, volume: 0.84, pan: 0.0, reverbWet: 28),    // Celesta
        TrackConfig(program: 46, isPercussion: false, volume: 0.82, pan: 0.0, reverbWet: 32),   // Harp
    ]
    let arpNotes: [UInt8] = [72, 76, 79, 83, 84, 88, 91, 96]
    var notes: [NoteEvent] = [
        // Initial crystal box chime chord
        NoteEvent(track: 3, note: 72, velocity: 115, startSec: 0.0, durationSec: 0.25),
        NoteEvent(track: 3, note: 79, velocity: 115, startSec: 0.01, durationSec: 0.25),
        NoteEvent(track: 3, note: 84, velocity: 115, startSec: 0.02, durationSec: 0.25),
    ]
    for (idx, n) in arpNotes.enumerated() {
        let st = Double(idx) * 0.055
        let dur = (idx == arpNotes.count - 1) ? 0.26 : 0.11
        notes.append(NoteEvent(track: idx % 2, note: n, velocity: 118, startSec: st, durationSec: dur))
        notes.append(NoteEvent(track: 2, note: n, velocity: 108, startSec: st, durationSec: dur))
    }
    return try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: 0.68, reverbPreset: .mediumHall)
}

/// 7. Jump Ramp Trick: Orchestral Harp Glissando + Brass Section + Vibraphone Sparkle!
func buildSfxJumpTrick() throws -> (left: [Float], right: [Float]) {
    let tracks: [TrackConfig] = [
        TrackConfig(program: 46, isPercussion: false, volume: 0.92, pan: -0.25, reverbWet: 35), // Harp
        TrackConfig(program: 11, isPercussion: false, volume: 0.88, pan: 0.25, reverbWet: 32),  // Vibraphone
        TrackConfig(program: 61, isPercussion: false, volume: 0.82, pan: 0.0, reverbWet: 28),   // Brass Section
        TrackConfig(program: 9, isPercussion: false, volume: 0.78, pan: 0.30, reverbWet: 32),   // Glockenspiel
    ]
    // E major 9th sparkling glissando: E4, G#4, B4, D#5, E5, F#5, G#5, B5, E6
    let gliss: [UInt8] = [64, 68, 71, 75, 76, 78, 80, 83, 88]
    var notes: [NoteEvent] = []
    for (idx, n) in gliss.enumerated() {
        let st = Double(idx) * 0.024
        notes.append(NoteEvent(track: 0, note: n, velocity: 116, startSec: st, durationSec: 0.42))
        notes.append(NoteEvent(track: 1, note: n, velocity: 110, startSec: st, durationSec: 0.40))
        if idx >= 4 {
            notes.append(NoteEvent(track: 3, note: n, velocity: 104, startSec: st, durationSec: 0.38))
        }
    }
    // Warm brass chord swell underneath
    for n in [UInt8(64), 68, 71, 76] {
        notes.append(NoteEvent(track: 2, note: n, velocity: 106, startSec: 0.04, durationSec: 0.45))
    }
    return try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: 0.68, reverbPreset: .mediumHall)
}

/// 8. Shell Fire Cannon: Punchy Timpani/Kick Launch + Resonant Filtered Plasma Torpedo Whoosh!
func buildSfxShellFire() throws -> (left: [Float], right: [Float]) {
    let duration = 0.45
    let tracks: [TrackConfig] = [
        TrackConfig(program: 47, isPercussion: false, volume: 0.95, pan: 0.0, reverbWet: 22),   // Timpani
        TrackConfig(program: 55, isPercussion: false, volume: 0.78, pan: 0.0, reverbWet: 24),   // Orchestra Hit
        TrackConfig(program: 16, isPercussion: true, volume: 0.92, pan: 0.0, reverbWet: 18),    // Power Drums
    ]
    let notes: [NoteEvent] = [
        NoteEvent(track: 0, note: 48, velocity: 126, startSec: 0.0, durationSec: 0.32),
        NoteEvent(track: 1, note: 60, velocity: 110, startSec: 0.0, durationSec: 0.22),
        NoteEvent(track: 2, note: 36, velocity: 127, startSec: 0.0, durationSec: 0.30),
        NoteEvent(track: 2, note: 47, velocity: 118, startSec: 0.0, durationSec: 0.28),
    ]
    var (left, right) = try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: duration, reverbPreset: .mediumRoom)

    // Layer true phase-integrated plasma torpedo launch sweep
    var phaseL = 0.0
    var phaseR = 0.0
    for i in 0..<left.count {
        let t = Double(i) / sampleRate
        let freq = 920.0 * exp(-t * 11.0) + 95.0
        phaseL += (2.0 * Double.pi * freq) / sampleRate
        phaseR += (2.0 * Double.pi * (freq * 1.008)) / sampleRate
        let env = (1.0 - exp(-t * 250.0)) * exp(-t * 7.5)
        let sigL = Float((0.7 * sin(phaseL) + 0.3 * sin(phaseL * 2.0)) * env * 0.38)
        let sigR = Float((0.7 * sin(phaseR) + 0.3 * sin(phaseR * 2.0)) * env * 0.38)
        left[i] = left[i] * 0.75 + sigL
        right[i] = right[i] * 0.75 + sigR
    }
    return (left, right)
}

/// 9. Impact / Spin-Out Hit: Timpani + Crash + Low Brass Discord + Sub Thud + Tire Skid!
func buildSfxImpact() throws -> (left: [Float], right: [Float]) {
    let duration = 0.54
    let tracks: [TrackConfig] = [
        TrackConfig(program: 47, isPercussion: false, volume: 0.96, pan: 0.0, reverbWet: 22),   // Timpani
        TrackConfig(program: 61, isPercussion: false, volume: 0.82, pan: -0.2, reverbWet: 25),  // Brass Section
        TrackConfig(program: 16, isPercussion: true, volume: 0.96, pan: 0.15, reverbWet: 20),   // Power Drum Kit
    ]
    let notes: [NoteEvent] = [
        NoteEvent(track: 0, note: 41, velocity: 127, startSec: 0.0, durationSec: 0.42),
        NoteEvent(track: 0, note: 47, velocity: 124, startSec: 0.0, durationSec: 0.42),
        // Cartoon brass spin-out cluster (F3, B3, E4 -> E3, Bb3, Eb4)
        NoteEvent(track: 1, note: 53, velocity: 115, startSec: 0.0, durationSec: 0.18),
        NoteEvent(track: 1, note: 59, velocity: 115, startSec: 0.0, durationSec: 0.18),
        NoteEvent(track: 1, note: 52, velocity: 110, startSec: 0.16, durationSec: 0.26),
        NoteEvent(track: 1, note: 58, velocity: 110, startSec: 0.16, durationSec: 0.26),
        // Heavy Kick + Snare + China Crash
        NoteEvent(track: 2, note: 36, velocity: 127, startSec: 0.0, durationSec: 0.35),
        NoteEvent(track: 2, note: 38, velocity: 124, startSec: 0.0, durationSec: 0.35),
        NoteEvent(track: 2, note: 52, velocity: 112, startSec: 0.0, durationSec: 0.45),
    ]
    var (left, right) = try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: duration, reverbPreset: .mediumRoom)

    var subPhase = 0.0
    for i in 0..<left.count {
        let t = Double(i) / sampleRate
        let subFreq = 140.0 * exp(-t * 18.0) + 38.0
        subPhase += (2.0 * Double.pi * subFreq) / sampleRate
        let sub = Float(sin(subPhase) * exp(-t * 8.0) * 0.42)
        left[i] = left[i] * 0.78 + sub
        right[i] = right[i] * 0.78 + sub
    }
    return (left, right)
}

/// 10. Lap Complete Checkpoint Fanfare: Upbeat Big-Band Brass + Vibraphone + Drums!
func buildSfxLapComplete() throws -> (left: [Float], right: [Float]) {
    let tracks: [TrackConfig] = [
        TrackConfig(program: 61, isPercussion: false, volume: 0.92, pan: -0.20, reverbWet: 28), // Brass Section
        TrackConfig(program: 56, isPercussion: false, volume: 0.88, pan: 0.20, reverbWet: 28),  // Trumpet
        TrackConfig(program: 11, isPercussion: false, volume: 0.85, pan: 0.25, reverbWet: 30),  // Vibraphone
        TrackConfig(program: 0, isPercussion: true, volume: 0.85, pan: 0.0, reverbWet: 20),     // Drums
    ]
    // G4 - C5 - E5 - G5 - C6!
    let seq: [(UInt8, Double, Double, UInt8)] = [
        (67, 0.00, 0.09, 60),
        (72, 0.08, 0.09, 64),
        (76, 0.16, 0.09, 67),
        (79, 0.24, 0.11, 72),
        (84, 0.34, 0.42, 76),
    ]
    var notes: [NoteEvent] = [
        NoteEvent(track: 3, note: 36, velocity: 118, startSec: 0.0, durationSec: 0.25),
        NoteEvent(track: 3, note: 36, velocity: 124, startSec: 0.34, durationSec: 0.35),
        NoteEvent(track: 3, note: 49, velocity: 112, startSec: 0.34, durationSec: 0.50),
    ]
    for (lead, st, dur, harm) in seq {
        notes.append(NoteEvent(track: 0, note: lead, velocity: 118, startSec: st, durationSec: dur))
        notes.append(NoteEvent(track: 0, note: harm, velocity: 106, startSec: st, durationSec: dur))
        notes.append(NoteEvent(track: 1, note: lead, velocity: 115, startSec: st, durationSec: dur))
        notes.append(NoteEvent(track: 2, note: lead, velocity: 112, startSec: st, durationSec: dur + 0.06))
    }
    return try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: 0.90, reverbPreset: .mediumHall)
}

/// 11. Grand Prix Victory Fanfare: Full Symphonic Brass + Trumpets + Slap Bass + Drums + Bells!
func buildSfxVictoryFanfare() throws -> (left: [Float], right: [Float]) {
    let tracks: [TrackConfig] = [
        TrackConfig(program: 61, isPercussion: false, volume: 0.94, pan: -0.22, reverbWet: 32), // Brass Section
        TrackConfig(program: 56, isPercussion: false, volume: 0.90, pan: 0.22, reverbWet: 32),  // Trumpet
        TrackConfig(program: 11, isPercussion: false, volume: 0.82, pan: 0.30, reverbWet: 34),  // Vibraphone
        TrackConfig(program: 36, isPercussion: false, volume: 0.88, pan: -0.10, reverbWet: 12), // Slap Bass
        TrackConfig(program: 0, isPercussion: true, volume: 0.90, pan: 0.0, reverbWet: 22),     // Drum Kit
    ]
    // Classic podium fanfare: C5 - C5 - C5 - C5 - Ab4 - Bb4 - C5 - Bb4 - C5!!
    struct FanfareStep {
        let start: Double
        let dur: Double
        let melody: UInt8
        let mid: UInt8
        let low: UInt8
        let bass: UInt8
    }
    let steps: [FanfareStep] = [
        FanfareStep(start: 0.00, dur: 0.12, melody: 72, mid: 67, low: 64, bass: 48),
        FanfareStep(start: 0.13, dur: 0.12, melody: 72, mid: 67, low: 64, bass: 48),
        FanfareStep(start: 0.26, dur: 0.12, melody: 72, mid: 67, low: 64, bass: 48),
        FanfareStep(start: 0.39, dur: 0.28, melody: 72, mid: 67, low: 64, bass: 48),
        FanfareStep(start: 0.70, dur: 0.28, melody: 68, mid: 63, low: 60, bass: 44), // Ab major
        FanfareStep(start: 1.01, dur: 0.28, melody: 70, mid: 65, low: 62, bass: 46), // Bb major
        FanfareStep(start: 1.32, dur: 0.18, melody: 72, mid: 67, low: 64, bass: 48), // C5
        FanfareStep(start: 1.54, dur: 0.13, melody: 70, mid: 65, low: 62, bass: 46), // Bb4
        FanfareStep(start: 1.69, dur: 0.85, melody: 72, mid: 67, low: 64, bass: 48), // Cmaj9 Grand Finale!
    ]

    var notes: [NoteEvent] = []
    for (idx, s) in steps.enumerated() {
        notes.append(NoteEvent(track: 0, note: s.melody, velocity: 120, startSec: s.start, durationSec: s.dur))
        notes.append(NoteEvent(track: 0, note: s.mid, velocity: 112, startSec: s.start, durationSec: s.dur))
        notes.append(NoteEvent(track: 0, note: s.low, velocity: 108, startSec: s.start, durationSec: s.dur))
        notes.append(NoteEvent(track: 1, note: s.melody, velocity: 118, startSec: s.start, durationSec: s.dur))
        notes.append(NoteEvent(track: 2, note: s.melody + 12, velocity: 106, startSec: s.start, durationSec: s.dur + 0.08))
        notes.append(NoteEvent(track: 3, note: s.bass, velocity: 118, startSec: s.start, durationSec: s.dur))

        // Drums on every hit
        notes.append(NoteEvent(track: 4, note: 36, velocity: 122, startSec: s.start, durationSec: 0.20))
        notes.append(NoteEvent(track: 4, note: 38, velocity: 116, startSec: s.start, durationSec: 0.20))
        if idx == 3 || idx == 4 || idx == 5 || idx == 8 {
            notes.append(NoteEvent(track: 4, note: 49, velocity: 118, startSec: s.start, durationSec: 0.70))
        }
    }
    // Add high D6 & E6 on the final chord for a glorious Cmaj9 finish
    notes.append(NoteEvent(track: 0, note: 74, velocity: 112, startSec: 1.69, durationSec: 0.85))
    notes.append(NoteEvent(track: 1, note: 76, velocity: 116, startSec: 1.69, durationSec: 0.85))

    return try renderSequenceOffline(tracks: tracks, notes: notes, totalSeconds: 2.75, reverbPreset: .mediumHall)
}

// ============================================================================
// MAIN GENERATOR ENTRYPOINT
// ============================================================================
let outDirs = CommandLine.arguments.dropFirst()
if outDirs.isEmpty {
    print("Usage: swift generate_studio_audio.swift <outDir1> [<outDir2> ...]")
    exit(1)
}

for dir in outDirs {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
}

func saveToAll(_ filename: String, _ audio: (left: [Float], right: [Float]), targetPeak: Float = 0.90, repeats: Int = 1) throws {
    for dir in outDirs {
        let fullPath = (dir as NSString).appendingPathComponent(filename)
        try writeStereoWav(path: fullPath, left: audio.left, right: audio.right, targetPeak: targetPeak, repeats: repeats)
    }
    print("Rendered \(filename) (\(audio.left.count) frames, repeats=\(repeats))")
}

try saveToAll("bgm_cyberOverdrive.wav", try buildCyberOverdriveBgm(), targetPeak: 0.90, repeats: 1)
try saveToAll("bgm_funkyCircuit.wav", try buildFunkyCircuitBgm(), targetPeak: 0.90, repeats: 1)
try saveToAll("sfx_countdownBeep.wav", try buildSfxCountdownBeep(), targetPeak: 0.88)
try saveToAll("sfx_countdownGo.wav", try buildSfxCountdownGo(), targetPeak: 0.92)
try saveToAll("sfx_boost.wav", try buildSfxBoost(), targetPeak: 0.90)
try saveToAll("sfx_driftCharge.wav", try buildSfxDriftCharge(), targetPeak: 0.86)
try saveToAll("sfx_coin.wav", try buildSfxCoin(), targetPeak: 0.88)
try saveToAll("sfx_itemPickup.wav", try buildSfxItemPickup(), targetPeak: 0.88)
try saveToAll("sfx_jumpTrick.wav", try buildSfxJumpTrick(), targetPeak: 0.90)
try saveToAll("sfx_shellFire.wav", try buildSfxShellFire(), targetPeak: 0.90)
try saveToAll("sfx_impact.wav", try buildSfxImpact(), targetPeak: 0.92)
try saveToAll("sfx_lapComplete.wav", try buildSfxLapComplete(), targetPeak: 0.90)
try saveToAll("sfx_victoryFanfare.wav", try buildSfxVictoryFanfare(), targetPeak: 0.92)
print("All studio audio files generated successfully!")
