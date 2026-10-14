import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'sound_backend.dart';

enum ArcadeSfx {
  countdownBeep,
  countdownGo,
  boost,
  driftCharge,
  coin,
  itemPickup,
  jumpTrick,
  shellFire,
  impact,
  lapComplete,
  victoryFanfare,
}

enum BgmTrack {
  cyberOverdrive(
    label: 'Cyber Overdrive',
    shortLabel: 'OVERDRIVE',
    subtitle: '132 BPM OutRun Synthwave',
  ),
  funkyCircuit(
    label: 'Turbo Funk GP',
    shortLabel: 'TURBO FUNK',
    subtitle: '128 BPM Jazz-Kart Groove',
  ),
  off(
    label: 'Music Off',
    shortLabel: 'BGM OFF',
    subtitle: 'Arcade SFX Only',
  );

  const BgmTrack({
    required this.label,
    required this.shortLabel,
    required this.subtitle,
  });

  final String label;
  final String shortLabel;
  final String subtitle;
}

/// Multi-track Stereo 16-bit PCM Synthesizer & Background Music Engine.
///
/// Supports both native desktop/mobile audio playback and Web HTML5 Audio
/// playback (`HTMLAudioElement`) with zero platform-specific import errors.
class ArcadeSoundManager {
  static final ArcadeSoundManager instance = ArcadeSoundManager();

  final PlatformSoundBackend _backend = createPlatformSoundBackend();

  bool soundEnabled = true;
  bool get isMuted => !soundEnabled;

  BgmTrack currentBgmTrack = BgmTrack.cyberOverdrive;
  double _bgmPlaybackRate = 1.0;
  double _bgmVolume = 0.38;
  bool _bgmShouldPlay = false;

  bool _initialized = false;
  final Map<ArcadeSfx, DateTime> _lastPlayed = {};

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _backend.initialize(synthesizeFallback: _synthesizeAllAudio);

    if (_bgmShouldPlay && soundEnabled && currentBgmTrack != BgmTrack.off) {
      _backend.startBgm(
        track: currentBgmTrack,
        volume: _bgmVolume,
        playbackRate: _bgmPlaybackRate,
      );
    }
  }

  void toggleMute() {
    soundEnabled = !soundEnabled;
    if (!soundEnabled) {
      _backend.stopBgm();
    } else if (_bgmShouldPlay && currentBgmTrack != BgmTrack.off) {
      _backend.startBgm(
        track: currentBgmTrack,
        volume: _bgmVolume,
        playbackRate: _bgmPlaybackRate,
      );
    }
  }

  void selectBgmTrack(BgmTrack track) {
    if (currentBgmTrack == track) return;
    currentBgmTrack = track;
    if (track == BgmTrack.off || !soundEnabled) {
      _backend.stopBgm();
    } else if (_bgmShouldPlay) {
      _backend.startBgm(
        track: currentBgmTrack,
        volume: _bgmVolume,
        playbackRate: _bgmPlaybackRate,
      );
    }
  }

  void cycleBgmTrack() {
    final values = BgmTrack.values;
    selectBgmTrack(values[(currentBgmTrack.index + 1) % values.length]);
  }

  /// Starts or updates the background music state (e.g. normal tempo vs Final Lap).
  void setBgmState({
    required bool playing,
    double playbackRate = 1.0,
    double volume = 0.38,
  }) {
    _bgmShouldPlay = playing;
    _bgmPlaybackRate = playbackRate;
    _bgmVolume = volume;

    if (!playing || !soundEnabled || currentBgmTrack == BgmTrack.off) {
      _backend.stopBgm();
      return;
    }

    _backend.startBgm(
      track: currentBgmTrack,
      volume: _bgmVolume,
      playbackRate: _bgmPlaybackRate,
    );
  }

  void play(
    ArcadeSfx sfx, {
    double volume = 0.65,
    double pitchRate = 1.0,
  }) {
    if (!soundEnabled) return;

    // Rate-limit identical sound effects so rapid triggers never stack harshly
    final now = DateTime.now();
    final prev = _lastPlayed[sfx];
    final minGapMs = sfx == ArcadeSfx.driftCharge ? 140 : 65;
    if (prev != null && now.difference(prev).inMilliseconds < minGapMs) {
      return;
    }
    _lastPlayed[sfx] = now;

    _backend.playSfx(sfx, volume: volume, pitchRate: pitchRate);
  }

  // ===========================================================================
  // PURE-DART STEREO SYNTHESIS ENGINE (32 kHz, 16-bit Stereo PCM)
  // ===========================================================================

  static const int _sampleRate = 32000;

  static ({Map<ArcadeSfx, Uint8List> sfx, Map<BgmTrack, Uint8List> bgm})
      _synthesizeAllAudio() {
    final sfx = <ArcadeSfx, Uint8List>{
      ArcadeSfx.countdownBeep: _synthCountdownBeep(),
      ArcadeSfx.countdownGo: _synthCountdownGo(),
      ArcadeSfx.boost: _synthBoostWhoosh(),
      ArcadeSfx.driftCharge: _synthDriftCharge(),
      ArcadeSfx.coin: _synthCoinDing(),
      ArcadeSfx.itemPickup: _synthItemArpeggio(),
      ArcadeSfx.jumpTrick: _synthJumpTrickChord(),
      ArcadeSfx.shellFire: _synthShellLaser(),
      ArcadeSfx.impact: _synthImpactThud(),
      ArcadeSfx.lapComplete: _synthLapComplete(),
      ArcadeSfx.victoryFanfare: _synthVictoryFanfare(),
    };

    final bgm = <BgmTrack, Uint8List>{
      BgmTrack.cyberOverdrive: _synthCyberOverdriveBgm(),
      BgmTrack.funkyCircuit: _synthFunkyCircuitBgm(),
    };

    return (sfx: sfx, bgm: bgm);
  }

  /// Encodes interleaved Left/Right stereo samples into a 16-bit PCM WAV file.
  /// If [repeats] > 1, duplicates the stereo PCM block back-to-back for long
  /// seamless BGM playback.
  static Uint8List _encodeStereoWav(
    Float64List left,
    Float64List right, {
    int repeats = 1,
  }) {
    final frames = left.length;
    final singleBlockBytes = frames * 4; // 2 channels * 2 bytes
    final totalDataBytes = singleBlockBytes * repeats;
    final buffer = ByteData(44 + totalDataBytes);

    // RIFF header
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, 36 + totalDataBytes, Endian.little);
    buffer.setUint8(8, 0x57); // 'W'
    buffer.setUint8(9, 0x41); // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6D); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // PCM chunk size
    buffer.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    buffer.setUint16(22, 2, Endian.little); // Stereo (2 channels)
    buffer.setUint32(24, _sampleRate, Endian.little);
    buffer.setUint32(28, _sampleRate * 4, Endian.little); // ByteRate
    buffer.setUint16(32, 4, Endian.little); // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample

    // data subchunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, totalDataBytes, Endian.little);

    for (var i = 0; i < frames; i++) {
      // Soft-clipping saturator for warm analog loudness without harsh clipping
      final l = _softClip(left[i]);
      final r = _softClip(right[i]);
      final pcmL = (l * 32767.0).round().clamp(-32768, 32767);
      final pcmR = (r * 32767.0).round().clamp(-32768, 32767);
      final offset = 44 + i * 4;
      buffer.setInt16(offset, pcmL, Endian.little);
      buffer.setInt16(offset + 2, pcmR, Endian.little);
    }

    final bytes = buffer.buffer.asUint8List();
    if (repeats > 1) {
      for (var rep = 1; rep < repeats; rep++) {
        final dstStart = 44 + rep * singleBlockBytes;
        bytes.setRange(dstStart, dstStart + singleBlockBytes, bytes, 44);
      }
    }
    return bytes;
  }

  static double _softClip(double x) {
    if (x > 1.2) return 1.0;
    if (x < -1.2) return -1.0;
    return x - (x * x * x) / 4.32;
  }

  /// Applies a lush stereo ping-pong delay to [left] and [right] in place.
  static void _applyStereoPingPongDelay(
    Float64List left,
    Float64List right, {
    double delaySec = 0.11,
    double feedback = 0.30,
    double wet = 0.24,
  }) {
    final delaySamples = (delaySec * _sampleRate).round().clamp(1, left.length);
    final bufL = Float64List(delaySamples);
    final bufR = Float64List(delaySamples);
    var cursor = 0;

    for (var i = 0; i < left.length; i++) {
      final dL = bufL[cursor];
      final dR = bufR[cursor];
      final inL = left[i];
      final inR = right[i];

      bufL[cursor] = inL + dR * feedback;
      bufR[cursor] = inR + dL * feedback;

      left[i] = inL + dL * wet;
      right[i] = inR + dR * wet;

      cursor++;
      if (cursor >= delaySamples) cursor = 0;
    }
  }

  /// Band-limited sawtooth approximation + sub-harmonic for warm synth leads/pads.
  static double _saw(double phase) {
    final p = (phase / (2.0 * math.pi)) % 1.0;
    return 2.0 * (p < 0 ? p + 1.0 : p) - 1.0;
  }

  static double _pulse(double phase, double duty) {
    final p = (phase / (2.0 * math.pi)) % 1.0;
    final norm = p < 0 ? p + 1.0 : p;
    return norm < duty ? 1.0 : -1.0;
  }

  static double _midiToFreq(int midi) =>
      440.0 * math.pow(2.0, (midi - 69) / 12.0);

  // ===========================================================================
  // STEREO SOUND EFFECTS (SFX)
  // ===========================================================================

  /// 1. Arcade Countdown Beep ("3... 2... 1..."): FM Electric Brass + Sub Punch.
  static Uint8List _synthCountdownBeep() {
    const duration = 0.32;
    final len = (_sampleRate * duration).round();
    final left = Float64List(len);
    final right = Float64List(len);

    for (var i = 0; i < len; i++) {
      final t = i / _sampleRate;
      final attack = 1.0 - math.exp(-t * 260.0);
      final decay = math.exp(-t * 11.5);
      final env = attack * decay;

      // Sub-kick transient punch at start of beep
      final punchEnv = math.exp(-t * 55.0);
      final punch = math.sin(2.0 * math.pi * (160.0 * math.exp(-t * 30.0) + 55.0) * t) *
          punchEnv *
          0.35;

      // Stereo detuned FM brass (A4 = 440Hz + E5 = 659.25Hz + A5 = 880Hz)
      final fmIndex = 2.4 * math.exp(-t * 14.0) + 0.4;
      final mod = math.sin(2.0 * math.pi * 880.0 * t) * fmIndex;
      final carrierL =
          0.55 * math.sin(2.0 * math.pi * 440.0 * t + mod) +
          0.30 * _saw(2.0 * math.pi * 881.5 * t) +
          0.20 * math.sin(2.0 * math.pi * 659.25 * t);
      final carrierR =
          0.55 * math.sin(2.0 * math.pi * 440.8 * t + mod) +
          0.30 * _saw(2.0 * math.pi * 878.5 * t) +
          0.20 * math.sin(2.0 * math.pi * 660.0 * t);

      left[i] = (carrierL * env + punch) * 0.78;
      right[i] = (carrierR * env + punch) * 0.78;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.065,
      feedback: 0.25,
      wet: 0.22,
    );
    return _encodeStereoWav(left, right);
  }

  /// 2. Countdown "GO!!": Lush Stereo Supersaw + FM Brass Major-9th Power Fanfare!
  static Uint8List _synthCountdownGo() {
    const duration = 0.78;
    final len = (_sampleRate * duration).round();
    final left = Float64List(len);
    final right = Float64List(len);
    final rng = math.Random(7);

    // C5, E5, G5, B5, D6 (Bright Cmaj9 stadium chord)
    const chord = [523.25, 659.25, 783.99, 987.77, 1174.66];

    for (var i = 0; i < len; i++) {
      final t = i / _sampleRate;
      final attack = 1.0 - math.exp(-t * 220.0);
      final env = attack * math.exp(-t * 3.4);

      // Pitch-slide into the chord over first 35ms for authentic brass excitement
      final bend = 1.0 - 0.08 * math.exp(-t * 48.0);

      var sumL = 0.0;
      var sumR = 0.0;
      for (var c = 0; c < chord.length; c++) {
        final f = chord[c] * bend;
        final fm = math.sin(2.0 * math.pi * f * 2.0 * t) *
            (1.6 * math.exp(-t * 8.0) + 0.3);
        final oscL = 0.6 * math.sin(2.0 * math.pi * f * 0.998 * t + fm) +
            0.4 * _saw(2.0 * math.pi * f * 1.003 * t);
        final oscR = 0.6 * math.sin(2.0 * math.pi * f * 1.002 * t + fm) +
            0.4 * _saw(2.0 * math.pi * f * 0.997 * t);
        final pan = c / (chord.length - 1); // 0.0 .. 1.0
        sumL += oscL * (1.0 - pan * 0.45);
        sumR += oscR * (0.55 + pan * 0.45);
      }

      // Snare/cymbal impact shimmer + sub-bass root (C3 = 130.8Hz)
      final sub = math.sin(2.0 * math.pi * 130.81 * t) * math.exp(-t * 5.0) * 0.45;
      final crash = (rng.nextDouble() * 2.0 - 1.0) * math.exp(-t * 14.0) * 0.18;

      left[i] = (sumL * 0.24 * env + sub + crash) * 0.85;
      right[i] = (sumR * 0.24 * env + sub - crash) * 0.85;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.095,
      feedback: 0.34,
      wet: 0.28,
    );
    return _encodeStereoWav(left, right);
  }

  /// 3. Turbo Boost Whoosh: Twin-Turbo Spool Whistle + Resonant Filter Sweep + Jet Roar.
  static Uint8List _synthBoostWhoosh() {
    const duration = 0.68;
    final len = (_sampleRate * duration).round();
    final left = Float64List(len);
    final right = Float64List(len);
    final rng = math.Random(42);

    var phase1 = 0.0;
    var phase2 = 0.0;
    var whistlePhase = 0.0;
    var bpL = 0.0;
    var lpL = 0.0;
    var bpR = 0.0;
    var lpR = 0.0;

    for (var i = 0; i < len; i++) {
      final t = i / _sampleRate;
      final progress = t / duration;
      final env = math.sin(math.pow(progress, 0.55) * math.pi);

      // Rising engine + turbine pitch
      final baseFreq = 95.0 + 320.0 * math.pow(progress, 0.65);
      final whistleFreq = 680.0 + 1450.0 * math.pow(progress, 0.5);

      phase1 += (2.0 * math.pi * baseFreq) / _sampleRate;
      phase2 += (2.0 * math.pi * baseFreq * 1.504) / _sampleRate;
      whistlePhase += (2.0 * math.pi * whistleFreq) / _sampleRate;

      final rawL = _saw(phase1) * 0.45 +
          _saw(phase2) * 0.35 +
          (rng.nextDouble() * 2.0 - 1.0) * 0.55;
      final rawR = _saw(phase1 * 1.006) * 0.45 +
          _saw(phase2 * 0.994) * 0.35 +
          (rng.nextDouble() * 2.0 - 1.0) * 0.55;

      // State-variable resonant filter sweep
      final cutoff = 280.0 + 2600.0 * math.sin(progress * math.pi * 0.85);
      final f = (2.0 * math.sin(math.pi * cutoff / _sampleRate)).clamp(0.02, 0.75);
      const q = 0.28;

      final hpL = rawL - lpL - q * bpL;
      bpL += f * hpL;
      lpL += f * bpL;

      final hpR = rawR - lpR - q * bpR;
      bpR += f * hpR;
      lpR += f * bpR;

      final whistle = math.sin(whistlePhase) * 0.18 * math.exp(-t * 2.2);
      final subPunch =
          math.sin(2.0 * math.pi * (140.0 * math.exp(-t * 16.0) + 48.0) * t) *
          math.exp(-t * 9.0) *
          0.45;

      left[i] = ((lpL * 0.65 + bpL * 0.45 + whistle) * env + subPunch) * 0.82;
      right[i] = ((lpR * 0.65 + bpR * 0.45 - whistle) * env + subPunch) * 0.82;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.055,
      feedback: 0.25,
      wet: 0.20,
    );
    return _encodeStereoWav(left, right);
  }

  /// 4. Drift Spark Tier Lock-In ("Mini-Turbo / Super-Turbo / Ultra-Turbo Charge").
  static Uint8List _synthDriftCharge() {
    const duration = 0.28;
    final len = (_sampleRate * duration).round();
    final left = Float64List(len);
    final right = Float64List(len);

    const notes = [587.33, 739.99, 880.00, 1174.66]; // D5 - F#5 - A5 - D6
    for (var i = 0; i < len; i++) {
      final t = i / _sampleRate;
      final idx = ((t / duration) * notes.length).floor().clamp(0, notes.length - 1);
      final freq = notes[idx];
      final env = (1.0 - math.exp(-t * 180.0)) * math.exp(-t * 7.5);
      final mod = math.sin(2.0 * math.pi * freq * 2.0 * t) * 1.2;

      left[i] = (0.6 * math.sin(2.0 * math.pi * freq * t + mod) +
              0.3 * _pulse(2.0 * math.pi * freq * 1.003 * t, 0.35)) *
          env *
          0.70;
      right[i] = (0.6 * math.sin(2.0 * math.pi * freq * 1.002 * t + mod) +
              0.3 * _pulse(2.0 * math.pi * freq * 0.997 * t, 0.65)) *
          env *
          0.70;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.045,
      feedback: 0.28,
      wet: 0.25,
    );
    return _encodeStereoWav(left, right);
  }

  /// 5. Golden Coin Chime: Authentic B5 -> E6 FM Crystal Bell with Shimmer Tail.
  static Uint8List _synthCoinDing() {
    const duration = 0.38;
    final len = (_sampleRate * duration).round();
    final left = Float64List(len);
    final right = Float64List(len);

    for (var i = 0; i < len; i++) {
      final t = i / _sampleRate;
      // Note 1: B5 (987.77 Hz) for first 68ms, then Note 2: E6 (1318.51 Hz)
      final isSecond = t >= 0.068;
      final localT = isSecond ? (t - 0.068) : t;
      final freq = isSecond ? 1318.51 : 987.77;
      final env = (1.0 - math.exp(-localT * 320.0)) *
          math.exp(-localT * (isSecond ? 10.5 : 16.0));

      // FM Metallic Bell ratio (1 : 2.0 : 3.0)
      final mod = math.sin(2.0 * math.pi * freq * 3.0 * localT) *
          1.4 *
          math.exp(-localT * 24.0);
      final bellL = 0.68 * math.sin(2.0 * math.pi * freq * localT + mod) +
          0.22 * math.sin(2.0 * math.pi * freq * 2.0 * localT) +
          0.10 * math.sin(2.0 * math.pi * freq * 4.02 * localT);
      final bellR = 0.68 * math.sin(2.0 * math.pi * (freq * 1.0015) * localT + mod) +
          0.22 * math.sin(2.0 * math.pi * (freq * 1.998) * localT) +
          0.10 * math.sin(2.0 * math.pi * freq * 3.98 * localT);

      left[i] = bellL * env * 0.72;
      right[i] = bellR * env * 0.72;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.055,
      feedback: 0.26,
      wet: 0.24,
    );
    return _encodeStereoWav(left, right);
  }

  /// 6. Item Box Smash + 8-Note Stereo Arcade Roulette Arpeggio.
  static Uint8List _synthItemArpeggio() {
    const notes = [
      523.25, // C5
      659.25, // E5
      783.99, // G5
      987.77, // B5
      1046.50, // C6
      1318.51, // E6
      1567.98, // G6
      2093.00, // C7
    ];
    const noteLen = 0.056;
    final totalSec = noteLen * notes.length + 0.14;
    final totalLen = (_sampleRate * totalSec).round();
    final left = Float64List(totalLen);
    final right = Float64List(totalLen);
    final rng = math.Random(19);

    for (var i = 0; i < totalLen; i++) {
      final t = i / _sampleRate;
      // Initial crystal cube shatter sparkle
      final shatter = (rng.nextDouble() * 2.0 - 1.0) *
          math.sin(2.0 * math.pi * 2400.0 * t) *
          math.exp(-t * 36.0) *
          0.32;

      final noteIdx = (t ~/ noteLen).clamp(0, notes.length - 1);
      final localT = t - noteIdx * noteLen;
      final freq = notes[noteIdx];
      final decayRate = noteIdx == notes.length - 1 ? 8.5 : 22.0;
      final env = (1.0 - math.exp(-localT * 260.0)) * math.exp(-localT * decayRate);

      final fm = math.sin(2.0 * math.pi * freq * 2.0 * localT) *
          1.3 *
          math.exp(-localT * 20.0);
      final tone = 0.65 * math.sin(2.0 * math.pi * freq * t + fm) +
          0.35 * _pulse(2.0 * math.pi * freq * 0.5 * t, 0.5);

      // Stereo pan bounces left-to-right across the 8 roulette notes
      final pan = noteIdx.isEven ? 0.25 : 0.75;
      left[i] = (tone * env * (1.0 - pan * 0.5) + shatter) * 0.75;
      right[i] = (tone * env * (0.5 + pan * 0.5) - shatter) * 0.75;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.068,
      feedback: 0.30,
      wet: 0.26,
    );
    return _encodeStereoWav(left, right);
  }

  /// 7. Aero Jump Ramp Trick: Hydraulic Spring Launch + Sparkling Stereo Glissando!
  static Uint8List _synthJumpTrickChord() {
    const duration = 0.58;
    final len = (_sampleRate * duration).round();
    final left = Float64List(len);
    final right = Float64List(len);

    // E5, G#5, B5, D#6, F#6, B6 (E major 9th aerial sparkle)
    const chord = [659.25, 830.61, 987.77, 1244.51, 1479.98, 1975.53];

    var springPhase = 0.0;
    for (var i = 0; i < len; i++) {
      final t = i / _sampleRate;
      // Fast upward spring launch sweep in first 120ms
      final springFreq = 180.0 + 920.0 * (1.0 - math.exp(-t * 18.0));
      springPhase += (2.0 * math.pi * springFreq) / _sampleRate;
      final spring = math.sin(springPhase) * math.exp(-t * 12.0) * 0.35;

      // Arpeggiated chord entry + sustained shimmer
      var chordL = 0.0;
      var chordR = 0.0;
      for (var c = 0; c < chord.length; c++) {
        final onset = c * 0.024;
        if (t >= onset) {
          final lt = t - onset;
          final f = chord[c];
          final env = (1.0 - math.exp(-lt * 200.0)) * math.exp(-lt * 5.2);
          final vibrato = 1.0 + 0.004 * math.sin(2.0 * math.pi * 14.0 * lt);
          final sig = 0.6 * math.sin(2.0 * math.pi * f * vibrato * lt) +
              0.4 * _saw(2.0 * math.pi * f * 1.002 * lt);
          if (c.isEven) {
            chordL += sig * env * 0.9;
            chordR += sig * env * 0.45;
          } else {
            chordL += sig * env * 0.45;
            chordR += sig * env * 0.9;
          }
        }
      }

      left[i] = (chordL * 0.28 + spring) * 0.82;
      right[i] = (chordR * 0.28 + spring) * 0.82;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.075,
      feedback: 0.35,
      wet: 0.30,
    );
    return _encodeStereoWav(left, right);
  }

  /// 8. Homing Shell Plasma Cannon: Sub-Kick + Stereo FM Laser Sweep.
  static Uint8List _synthShellLaser() {
    const duration = 0.42;
    final len = (_sampleRate * duration).round();
    final left = Float64List(len);
    final right = Float64List(len);

    var phaseL = 0.0;
    var phaseR = 0.0;
    for (var i = 0; i < len; i++) {
      final t = i / _sampleRate;
      final freq = 1350.0 * math.exp(-t * 8.5) + 110.0;
      final mod = math.sin(2.0 * math.pi * 95.0 * t) * 1.8 * math.exp(-t * 5.0);
      phaseL += (2.0 * math.pi * freq) / _sampleRate;
      phaseR += (2.0 * math.pi * (freq * 1.012)) / _sampleRate;

      final env = (1.0 - math.exp(-t * 250.0)) * math.exp(-t * 6.8);
      final laserL = 0.65 * math.sin(phaseL + mod) + 0.35 * _saw(phaseL * 0.5);
      final laserR = 0.65 * math.sin(phaseR - mod) + 0.35 * _saw(phaseR * 0.5);

      left[i] = laserL * env * 0.76;
      right[i] = laserR * env * 0.76;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.050,
      feedback: 0.28,
      wet: 0.24,
    );
    return _encodeStereoWav(left, right);
  }

  /// 9. Impact / Hazard Hit: Heavy Sub-Bass Thud + Metallic Crunch + Tire Skid Wobble.
  static Uint8List _synthImpactThud() {
    const duration = 0.46;
    final len = (_sampleRate * duration).round();
    final left = Float64List(len);
    final right = Float64List(len);
    final rng = math.Random(99);

    var bassPhase = 0.0;
    var skidPhase = 0.0;
    var lpNoiseL = 0.0;
    var lpNoiseR = 0.0;

    for (var i = 0; i < len; i++) {
      final t = i / _sampleRate;
      // Heavy sub-bass thump (175Hz -> 38Hz)
      final bassFreq = 175.0 * math.exp(-t * 14.0) + 38.0;
      bassPhase += (2.0 * math.pi * bassFreq) / _sampleRate;
      final bass = math.sin(bassPhase) * math.exp(-t * 8.5) * 0.75;

      // Filtered crunch noise
      lpNoiseL = lpNoiseL * 0.72 + (rng.nextDouble() * 2.0 - 1.0) * 0.28;
      lpNoiseR = lpNoiseR * 0.72 + (rng.nextDouble() * 2.0 - 1.0) * 0.28;
      final crunchEnv = math.exp(-t * 18.0);

      // Arcade tire-skid wobble on spin-out
      final skidFreq =
          360.0 - 140.0 * t + 48.0 * math.sin(2.0 * math.pi * 19.0 * t);
      skidPhase += (2.0 * math.pi * skidFreq) / _sampleRate;
      final skidEnv = math.sin((t / duration) * math.pi) * math.exp(-t * 4.2);
      final skid = _pulse(skidPhase, 0.35) * skidEnv * 0.24;

      left[i] = (bass + lpNoiseL * crunchEnv * 0.55 + skid) * 0.85;
      right[i] = (bass + lpNoiseR * crunchEnv * 0.55 - skid) * 0.85;
    }

    return _encodeStereoWav(left, right);
  }

  /// 10. Lap Complete Checkpoint Jingle: Upbeat 5-Note Stadium Fanfare!
  static Uint8List _synthLapComplete() {
    const notes = [
      (392.00, 0.08), // G4
      (523.25, 0.08), // C5
      (659.25, 0.08), // E5
      (783.99, 0.10), // G5
      (1046.50, 0.32), // C6
    ];
    final totalSec = notes.fold<double>(0.0, (s, n) => s + n.$2) + 0.12;
    final totalLen = (_sampleRate * totalSec).round();
    final left = Float64List(totalLen);
    final right = Float64List(totalLen);

    var cursorSec = 0.0;
    for (var idx = 0; idx < notes.length; idx++) {
      final (freq, dur) = notes[idx];
      final startIdx = (cursorSec * _sampleRate).round();
      final count = ((dur + 0.08) * _sampleRate).round();
      for (var j = 0; j < count && (startIdx + j) < totalLen; j++) {
        final lt = j / _sampleRate;
        final env = (1.0 - math.exp(-lt * 200.0)) * math.exp(-lt * 6.5);
        final fm = math.sin(2.0 * math.pi * freq * 2.0 * lt) * 1.1 * math.exp(-lt * 10.0);
        final sigL = 0.6 * math.sin(2.0 * math.pi * freq * lt + fm) +
            0.4 * _saw(2.0 * math.pi * freq * 1.003 * lt);
        final sigR = 0.6 * math.sin(2.0 * math.pi * freq * 1.002 * lt + fm) +
            0.4 * _saw(2.0 * math.pi * freq * 0.997 * lt);
        left[startIdx + j] += sigL * env * 0.62;
        right[startIdx + j] += sigR * env * 0.62;
      }
      cursorSec += dur;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.085,
      feedback: 0.32,
      wet: 0.26,
    );
    return _encodeStereoWav(left, right);
  }

  /// 11. Grand Prix Victory Fanfare: Full Stereo Brass + Synth Lead + Bass + Finale Chord!
  static Uint8List _synthVictoryFanfare() {
    // Classic arcade podium melody: C5 - C5 - C5 -C5 - Ab4 - Bb4 - C5 - Bb4 - C5!!
    const melody = [
      (523.25, 0.13), // C5
      (523.25, 0.13), // C5
      (523.25, 0.13), // C5
      (523.25, 0.30), // C5
      (415.30, 0.28), // Ab4
      (466.16, 0.28), // Bb4
      (523.25, 0.18), // C5
      (466.16, 0.14), // Bb4
      (523.25, 0.68), // C5 (Grand Finale!)
    ];
    const bassRoots = [
      130.81,
      130.81,
      130.81,
      130.81,
      103.83, // Ab2
      116.54, // Bb2
      130.81,
      116.54,
      130.81, // C3
    ];

    final totalSec = melody.fold<double>(0.0, (s, n) => s + n.$2) + 0.25;
    final totalLen = (_sampleRate * totalSec).round();
    final left = Float64List(totalLen);
    final right = Float64List(totalLen);

    var cursorSec = 0.0;
    for (var n = 0; n < melody.length; n++) {
      final (freq, dur) = melody[n];
      final bassFreq = bassRoots[n];
      final startIdx = (cursorSec * _sampleRate).round();
      final ringDur = n == melody.length - 1 ? dur + 0.22 : dur + 0.04;
      final count = (ringDur * _sampleRate).round();

      for (var j = 0; j < count && (startIdx + j) < totalLen; j++) {
        final lt = j / _sampleRate;
        final decay = n == melody.length - 1 ? 2.6 : 6.2;
        final env = (1.0 - math.exp(-lt * 200.0)) * math.exp(-lt * decay);
        final fm = math.sin(2.0 * math.pi * freq * 2.0 * lt) *
            (1.5 * math.exp(-lt * 9.0) + 0.35);

        // Lead + Major 3rd & 5th harmony brass
        final leadL = 0.50 * math.sin(2.0 * math.pi * freq * lt + fm) +
            0.30 * _saw(2.0 * math.pi * freq * 1.003 * lt) +
            0.25 * _saw(2.0 * math.pi * (freq * 1.25) * lt) +
            0.22 * _saw(2.0 * math.pi * (freq * 1.50) * lt);
        final leadR = 0.50 * math.sin(2.0 * math.pi * freq * 1.002 * lt + fm) +
            0.30 * _saw(2.0 * math.pi * freq * 0.997 * lt) +
            0.25 * _saw(2.0 * math.pi * (freq * 1.253) * lt) +
            0.22 * _saw(2.0 * math.pi * (freq * 1.498) * lt);

        final bass = (0.65 * math.sin(2.0 * math.pi * bassFreq * lt) +
                0.35 * _saw(2.0 * math.pi * bassFreq * 2.0 * lt)) *
            env *
            0.42;

        left[startIdx + j] += (leadL * env * 0.52 + bass);
        right[startIdx + j] += (leadR * env * 0.52 + bass);
      }
      cursorSec += dur;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: 0.11,
      feedback: 0.35,
      wet: 0.28,
    );
    return _encodeStereoWav(left, right);
  }

  // ===========================================================================
  // FULL STEREO MULTI-TRACK BACKGROUND MUSIC SEQUENCERS
  // ===========================================================================

  /// BGM Track 1: "Cyber Overdrive" — 132 BPM OutRun / Synthwave Arcade Anthem.
  /// 8-bar progression (Am7 - Fmaj7 - Cmaj7 - G6 - Dm7 - Em7 - Fmaj7 - E7),
  /// repeated 2x per WAV file (~29.1 seconds) with seamless loop wrap.
  static Uint8List _synthCyberOverdriveBgm() {
    const bpm = 132.0;
    const stepSec = 60.0 / bpm / 4.0; // 16th-note duration (~0.1136s)
    const totalSteps = 128; // 8 bars * 16 steps
    final totalSamples = (totalSteps * stepSec * _sampleRate).round();

    final left = Float64List(totalSamples);
    final right = Float64List(totalSamples);
    final rng = math.Random(1337);

    // 8-bar chord table (MIDI notes for [BassRoot, ChordTone1, ChordTone2, ChordTone3, ChordTone4])
    const bars = <List<int>>[
      [45, 57, 60, 64, 67], // Bar 0: Am7  (A2, A3, C4, E4, G4)
      [41, 53, 57, 60, 64], // Bar 1: Fmaj7(F2, F3, A3, C4, E4)
      [48, 60, 64, 67, 71], // Bar 2: Cmaj7(C3, C4, E4, G4, B4)
      [43, 55, 59, 62, 64], // Bar 3: G6   (G2, G3, B3, D4, E4)
      [50, 57, 60, 62, 65], // Bar 4: Dm7  (D3, A3, C4, D4, F4)
      [40, 55, 59, 62, 64], // Bar 5: Em7  (E2, G3, B3, D4, E4)
      [41, 53, 57, 60, 64], // Bar 6: Fmaj7(F2, F3, A3, C4, E4)
      [40, 56, 59, 62, 64], // Bar 7: E7   (E2, G#3, B3, D4, E4)
    ];

    // Catchy 8-bar Synthwave Lead Melody (128 sixteenth-note steps; 0 = rest, >0 = MIDI note)
    const leadMidi = <int>[
      // Bar 0 (Am7)
      69, 0, 72, 0, 76, 76, 79, 76, 74, 0, 72, 0, 69, 0, 67, 0,
      // Bar 1 (Fmaj7)
      65, 0, 69, 0, 72, 72, 76, 72, 74, 0, 72, 69, 67, 0, 0, 0,
      // Bar 2 (Cmaj7)
      72, 0, 76, 0, 79, 79, 81, 79, 76, 0, 74, 0, 72, 0, 67, 0,
      // Bar 3 (G6)
      71, 0, 74, 0, 79, 0, 76, 0, 74, 74, 72, 71, 69, 0, 67, 0,
      // Bar 4 (Dm7)
      69, 0, 74, 0, 77, 77, 81, 77, 76, 0, 74, 0, 72, 0, 69, 0,
      // Bar 5 (Em7)
      71, 0, 76, 0, 79, 79, 83, 79, 76, 0, 74, 0, 71, 0, 67, 0,
      // Bar 6 (Fmaj7)
      69, 0, 72, 0, 76, 0, 81, 0, 79, 0, 76, 0, 74, 0, 72, 0,
      // Bar 7 (E7 turnaround)
      71, 0, 74, 0, 76, 0, 80, 0, 83, 0, 81, 79, 76, 0, 0, 0,
    ];

    const arpPattern = [1, 2, 3, 4, 3, 2, 4, 3];

    for (var i = 0; i < totalSamples; i++) {
      final t = i / _sampleRate;
      final stepFloat = t / stepSec;
      final step = stepFloat.floor() % totalSteps;
      final stepFrac = stepFloat - stepFloat.floor();
      final stepT = stepFrac * stepSec;

      final barIdx = (step ~/ 16) % 8;
      final stepInBar = step % 16;
      final chord = bars[barIdx];

      // 1. DRUMS (Kick on 0, 4, 8, 12; Snare on 4, 12 + fill on bar 7; 16th Hi-Hats)
      var drumL = 0.0;
      var drumR = 0.0;

      final isKickStep =
          (stepInBar % 4 == 0) || (barIdx % 4 == 3 && stepInBar == 14);
      if (isKickStep) {
        final kFreq = 135.0 * math.exp(-stepT * 38.0) + 45.0;
        final kEnv = math.exp(-stepT * 15.0);
        final kick = math.sin(2.0 * math.pi * kFreq * stepT) * kEnv * 0.55;
        drumL += kick;
        drumR += kick;
      }

      final isSnareStep = (stepInBar == 4 || stepInBar == 12) ||
          (barIdx == 7 && stepInBar >= 13);
      if (isSnareStep) {
        final sEnv = math.exp(-stepT * 22.0);
        final body = math.sin(2.0 * math.pi * 185.0 * stepT) * math.exp(-stepT * 35.0);
        final noiseL = (rng.nextDouble() * 2.0 - 1.0) * sEnv;
        final noiseR = (rng.nextDouble() * 2.0 - 1.0) * sEnv;
        drumL += (body * 0.4 + noiseL * 0.6) * 0.34;
        drumR += (body * 0.4 + noiseR * 0.6) * 0.34;
      }

      // Crisp 16th-note Hi-Hats (open hat on off-beats 2, 6, 10, 14)
      final isOpenHat = stepInBar % 4 == 2;
      final hatDecay = isOpenHat ? 24.0 : 68.0;
      final hatAmp = isOpenHat ? 0.14 : (stepInBar.isEven ? 0.09 : 0.05);
      final hatEnv = math.exp(-stepT * hatDecay);
      final hatNoise = (rng.nextDouble() * 2.0 - 1.0) *
          math.sin(2.0 * math.pi * 6800.0 * t) *
          hatEnv *
          hatAmp;
      drumL += hatNoise * 1.1;
      drumR += hatNoise * 0.9;

      // 2. OCTAVE-PUMPING SYNTHWAVE BASSLINE
      final bassRootMidi = chord[0] + (stepInBar.isOdd ? 12 : 0);
      final bassFreq = _midiToFreq(bassRootMidi);
      final bassEnv = (1.0 - math.exp(-stepT * 240.0)) * math.exp(-stepT * 14.0);
      final bassWave = 0.55 * _saw(2.0 * math.pi * bassFreq * t) +
          0.45 * math.sin(2.0 * math.pi * bassFreq * t);
      final bassSig = bassWave * bassEnv * 0.30;

      // 3. SIDECHAINED STEREO SUPERSAW CHORD PAD
      final beatFrac = (stepFloat % 4.0) / 4.0;
      final sidechain = 0.35 + 0.65 * (1.0 - math.exp(-beatFrac * 5.0));
      var padL = 0.0;
      var padR = 0.0;
      for (var c = 1; c <= 4; c++) {
        final f = _midiToFreq(chord[c]);
        padL += _saw(2.0 * math.pi * (f * 0.997) * t) +
            0.5 * math.sin(2.0 * math.pi * f * t);
        padR += _saw(2.0 * math.pi * (f * 1.003) * t) +
            0.5 * math.sin(2.0 * math.pi * f * t);
      }
      padL *= 0.042 * sidechain;
      padR *= 0.042 * sidechain;

      // 4. 16TH-NOTE STEREO ARPEGGIATOR
      final arpToneIdx = arpPattern[stepInBar % arpPattern.length];
      final arpFreq = _midiToFreq(chord[arpToneIdx] + 12);
      final arpEnv = (1.0 - math.exp(-stepT * 260.0)) * math.exp(-stepT * 20.0);
      final arpSig = _pulse(2.0 * math.pi * arpFreq * t, 0.35) * arpEnv * 0.11;
      final arpPan = stepInBar.isEven ? 0.3 : 0.7;

      // 5. HERO SYNTH LEAD MELODY
      var leadL = 0.0;
      var leadR = 0.0;
      final noteMidi = leadMidi[step];
      if (noteMidi > 0) {
        final leadFreq = _midiToFreq(noteMidi);
        final vibPhase = 0.35 * math.sin(2.0 * math.pi * 6.0 * stepT);
        final lEnv = (1.0 - math.exp(-stepT * 180.0)) * math.exp(-stepT * 6.5);
        final fm = math.sin(2.0 * math.pi * leadFreq * 2.0 * stepT) *
            0.8 *
            math.exp(-stepT * 12.0);
        leadL = (0.55 * _saw(2.0 * math.pi * leadFreq * 0.999 * stepT + vibPhase) +
                0.45 * math.sin(2.0 * math.pi * leadFreq * stepT + vibPhase + fm)) *
            lEnv *
            0.22;
        leadR = (0.55 * _saw(2.0 * math.pi * leadFreq * 1.001 * stepT + vibPhase) +
                0.45 * math.sin(2.0 * math.pi * leadFreq * stepT + vibPhase + fm)) *
            lEnv *
            0.22;
      }

      left[i] = drumL + bassSig + padL + arpSig * (1.0 - arpPan) + leadL;
      right[i] = drumR + bassSig + padR + arpSig * arpPan + leadR;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: stepSec * 1.5, // Dotted-16th rhythmic stereo echo!
      feedback: 0.26,
      wet: 0.18,
    );
    return _encodeStereoWav(left, right, repeats: 2);
  }

  /// BGM Track 2: "Turbo Funk GP" — 128 BPM Upbeat Jazz-Fusion Kart Groove.
  /// 8-bar progression (Fmaj9 - Em7/A7 - Dm9 - G13 - Em7 - Am7 - Abmaj7 - G9sus4),
  /// repeated 2x per WAV file (~30.0 seconds).
  static Uint8List _synthFunkyCircuitBgm() {
    const bpm = 128.0;
    const stepSec = 60.0 / bpm / 4.0;
    const totalSteps = 128;
    final totalSamples = (totalSteps * stepSec * _sampleRate).round();

    final left = Float64List(totalSamples);
    final right = Float64List(totalSamples);
    final rng = math.Random(2026);

    const bars = <List<int>>[
      [41, 57, 60, 64, 67], // Bar 0: Fmaj9 (F2, A3, C4, E4, G4)
      [40, 55, 59, 62, 67], // Bar 1: Em7   (E2, G3, B3, D4, G4)
      [38, 53, 57, 60, 64], // Bar 2: Dm9   (D2, F3, A3, C4, E4)
      [43, 55, 59, 64, 65], // Bar 3: G13   (G2, G3, B3, E4, F4)
      [40, 55, 59, 62, 67], // Bar 4: Em7   (E2, G3, B3, D4, G4)
      [45, 57, 60, 64, 67], // Bar 5: Am7   (A2, A3, C4, E4, G4)
      [44, 56, 60, 63, 67], // Bar 6: Abmaj7(Ab2, Ab3, C4, Eb4, G4)
      [43, 55, 60, 62, 65], // Bar 7: G9sus4(G2, G3, C4, D4, F4)
    ];

    const leadMidi = <int>[
      // Bar 0 (Fmaj9)
      72, 0, 76, 79, 81, 0, 79, 0, 76, 72, 74, 0, 69, 0, 0, 0,
      // Bar 1 (Em7)
      71, 0, 74, 76, 79, 0, 76, 0, 74, 71, 69, 0, 67, 0, 0, 0,
      // Bar 2 (Dm9)
      69, 0, 72, 74, 77, 0, 81, 0, 79, 0, 76, 74, 72, 0, 0, 0,
      // Bar 3 (G13)
      74, 76, 79, 0, 83, 0, 81, 79, 76, 0, 74, 0, 72, 0, 71, 0,
      // Bar 4 (Em7)
      76, 0, 79, 83, 84, 0, 83, 0, 79, 76, 74, 0, 71, 0, 0, 0,
      // Bar 5 (Am7)
      72, 0, 76, 79, 81, 0, 84, 0, 81, 79, 76, 0, 72, 0, 0, 0,
      // Bar 6 (Abmaj7 lift!)
      75, 0, 79, 80, 84, 0, 82, 80, 79, 0, 75, 0, 72, 0, 0, 0,
      // Bar 7 (G9sus4 turnaround)
      74, 0, 77, 79, 81, 0, 83, 0, 84, 0, 83, 81, 79, 0, 0, 0,
    ];

    // Syncopated funk chord stab steps within a 16-step bar
    const stabSteps = {0, 3, 6, 10, 12};

    for (var i = 0; i < totalSamples; i++) {
      final t = i / _sampleRate;
      final stepFloat = t / stepSec;
      final step = stepFloat.floor() % totalSteps;
      final stepFrac = stepFloat - stepFloat.floor();
      final stepT = stepFrac * stepSec;

      final barIdx = (step ~/ 16) % 8;
      final stepInBar = step % 16;
      final chord = bars[barIdx];

      // 1. FUNK DRUM GROOVE (Syncopated Kick on 0, 3, 6, 10; Snare on 4, 12)
      var drumL = 0.0;
      var drumR = 0.0;
      if (stepInBar == 0 || stepInBar == 3 || stepInBar == 6 || stepInBar == 10) {
        final kFreq = 130.0 * math.exp(-stepT * 40.0) + 48.0;
        final kick = math.sin(2.0 * math.pi * kFreq * stepT) *
            math.exp(-stepT * 16.0) *
            0.52;
        drumL += kick;
        drumR += kick;
      }
      if (stepInBar == 4 || stepInBar == 12 || (barIdx == 7 && stepInBar >= 14)) {
        final sEnv = math.exp(-stepT * 24.0);
        final body = math.sin(2.0 * math.pi * 205.0 * stepT) * math.exp(-stepT * 38.0);
        final nL = (rng.nextDouble() * 2.0 - 1.0) * sEnv;
        final nR = (rng.nextDouble() * 2.0 - 1.0) * sEnv;
        drumL += (body * 0.45 + nL * 0.55) * 0.34;
        drumR += (body * 0.45 + nR * 0.55) * 0.34;
      }
      final hatEnv = math.exp(-stepT * (stepInBar % 4 == 2 ? 26.0 : 72.0));
      final hat = (rng.nextDouble() * 2.0 - 1.0) * hatEnv * 0.075;
      drumL += hat;
      drumR += hat;

      // 2. SLAP FUNK FM BASS
      final isOctavePop = stepInBar == 2 || stepInBar == 7 || stepInBar == 11 || stepInBar == 15;
      final bassMidi = chord[0] + (isOctavePop ? 12 : 0);
      final bFreq = _midiToFreq(bassMidi);
      final bEnv = (1.0 - math.exp(-stepT * 280.0)) * math.exp(-stepT * 16.0);
      final bMod = math.sin(2.0 * math.pi * bFreq * 2.0 * stepT) *
          (isOctavePop ? 2.2 : 1.1) *
          math.exp(-stepT * 28.0);
      final bassSig = math.sin(2.0 * math.pi * bFreq * t + bMod) * bEnv * 0.32;

      // 3. ELECTRIC PIANO / BRASS SYNCOPATED CHORD STABS
      var stabL = 0.0;
      var stabR = 0.0;
      if (stabSteps.contains(stepInBar)) {
        final sEnv = (1.0 - math.exp(-stepT * 220.0)) * math.exp(-stepT * 9.5);
        for (var c = 1; c <= 4; c++) {
          final cf = _midiToFreq(chord[c]);
          final fm = math.sin(2.0 * math.pi * cf * 3.0 * stepT) *
              0.7 *
              math.exp(-stepT * 22.0);
          stabL += math.sin(2.0 * math.pi * cf * 0.999 * t + fm);
          stabR += math.sin(2.0 * math.pi * cf * 1.001 * t + fm);
        }
        stabL *= 0.065 * sEnv;
        stabR *= 0.065 * sEnv;
      }

      // 4. JAZZ-KART BRASS / SYNTH LEAD
      var leadL = 0.0;
      var leadR = 0.0;
      final noteMidi = leadMidi[step];
      if (noteMidi > 0) {
        final lf = _midiToFreq(noteMidi);
        final bendPhase = -0.35 * math.exp(-stepT * 45.0);
        final lEnv = (1.0 - math.exp(-stepT * 200.0)) * math.exp(-stepT * 7.5);
        final fm = math.sin(2.0 * math.pi * lf * 2.0 * stepT) *
            1.2 *
            math.exp(-stepT * 14.0);
        leadL = (0.55 * math.sin(2.0 * math.pi * lf * stepT + bendPhase + fm) +
                0.45 * _pulse(2.0 * math.pi * lf * 1.001 * stepT + bendPhase, 0.42)) *
            lEnv *
            0.22;
        leadR = (0.55 * math.sin(2.0 * math.pi * lf * 1.001 * stepT + bendPhase + fm) +
                0.45 * _pulse(2.0 * math.pi * lf * 0.999 * stepT + bendPhase, 0.58)) *
            lEnv *
            0.22;
      }

      left[i] = drumL + bassSig + stabL + leadL;
      right[i] = drumR + bassSig + stabR + leadR;
    }

    _applyStereoPingPongDelay(
      left,
      right,
      delaySec: stepSec * 1.5,
      feedback: 0.24,
      wet: 0.16,
    );
    return _encodeStereoWav(left, right, repeats: 2);
  }
}
