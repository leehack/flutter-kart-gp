import 'dart:js_interop';
import 'dart:typed_data';

import 'sound_backend_stub.dart';
import 'sound_manager.dart';

export 'sound_backend_stub.dart' show PlatformSoundBackend;

@JS('Audio')
extension type _HtmlAudio._(JSObject _) implements JSObject {
  external factory _HtmlAudio([String src]);
  external set loop(bool value);
  external bool get paused;
  external set volume(double value);
  external set playbackRate(double value);
  external set currentTime(double value);
  external JSPromise<JSAny?> play();
  external void pause();
}

PlatformSoundBackend createPlatformSoundBackend() => _WebSoundBackend();

class _WebSoundBackend implements PlatformSoundBackend {
  final Map<BgmTrack, _HtmlAudio> _bgmElements = {};
  BgmTrack _activeTrack = BgmTrack.off;
  bool _bgmPlaying = false;
  bool _needsAutoplayRetry = false;

  static String _assetUrl(String fileName) => 'assets/assets/audio/$fileName';

  @override
  Future<void> initialize({
    required ({Map<ArcadeSfx, Uint8List> sfx, Map<BgmTrack, Uint8List> bgm})
        Function()
    synthesizeFallback,
  }) async {
    for (final track in [BgmTrack.cyberOverdrive, BgmTrack.funkyCircuit]) {
      try {
        final audio = _HtmlAudio(_assetUrl('bgm_${track.name}.wav'));
        audio.loop = true;
        _bgmElements[track] = audio;
      } catch (_) {}
    }
  }

  @override
  void startBgm({
    required BgmTrack track,
    required double volume,
    required double playbackRate,
  }) {
    if (track == BgmTrack.off) {
      stopBgm();
      return;
    }

    if (_activeTrack != track) {
      final prev = _bgmElements[_activeTrack];
      if (prev != null) {
        try {
          prev.pause();
          prev.currentTime = 0.0;
        } catch (_) {}
      }
      _activeTrack = track;
      _bgmPlaying = false;
    }

    final audio = _bgmElements[track];
    if (audio == null) return;

    try {
      audio.loop = true;
      audio.volume = volume.clamp(0.05, 1.0);
      audio.playbackRate = playbackRate.clamp(0.5, 2.0);
      if (!_bgmPlaying || audio.paused || _needsAutoplayRetry) {
        _bgmPlaying = true;
        _needsAutoplayRetry = false;
        audio.play().toDart.catchError((_) {
          // Browser blocked autoplay until first user gesture; retry on next tick/input
          _needsAutoplayRetry = true;
          return null;
        });
      }
    } catch (_) {}
  }

  @override
  void stopBgm() {
    _bgmPlaying = false;
    _needsAutoplayRetry = false;
    for (final audio in _bgmElements.values) {
      try {
        audio.pause();
      } catch (_) {}
    }
  }

  @override
  void playSfx(
    ArcadeSfx sfx, {
    required double volume,
    required double pitchRate,
  }) {
    try {
      final audio = _HtmlAudio(_assetUrl('sfx_${sfx.name}.wav'));
      audio.volume = volume.clamp(0.05, 1.0);
      audio.playbackRate = pitchRate.clamp(0.5, 2.0);
      audio.play().toDart.catchError((_) => null);
    } catch (_) {}
  }
}
