import 'dart:typed_data';
import 'sound_manager.dart';

abstract class PlatformSoundBackend {
  Future<void> initialize({
    required ({Map<ArcadeSfx, Uint8List> sfx, Map<BgmTrack, Uint8List> bgm})
        Function()
    synthesizeFallback,
  });

  void startBgm({
    required BgmTrack track,
    required double volume,
    required double playbackRate,
  });

  void stopBgm();

  void playSfx(
    ArcadeSfx sfx, {
    required double volume,
    required double pitchRate,
  });
}

PlatformSoundBackend createPlatformSoundBackend() => _StubSoundBackend();

class _StubSoundBackend implements PlatformSoundBackend {
  @override
  Future<void> initialize({
    required ({Map<ArcadeSfx, Uint8List> sfx, Map<BgmTrack, Uint8List> bgm})
        Function()
    synthesizeFallback,
  }) async {}

  @override
  void startBgm({
    required BgmTrack track,
    required double volume,
    required double playbackRate,
  }) {}

  @override
  void stopBgm() {}

  @override
  void playSfx(
    ArcadeSfx sfx, {
    required double volume,
    required double pitchRate,
  }) {}
}
