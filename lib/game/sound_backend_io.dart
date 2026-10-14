import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'sound_backend_stub.dart';
import 'sound_manager.dart';

export 'sound_backend_stub.dart' show PlatformSoundBackend;

PlatformSoundBackend createPlatformSoundBackend() => _IoSoundBackend();

class _IoSoundBackend implements PlatformSoundBackend {
  final Map<ArcadeSfx, String> _sfxPaths = {};
  final Map<BgmTrack, String> _bgmPaths = {};

  Process? _bgmProcess;
  bool _bgmLaunching = false;
  int _bgmSessionId = 0;
  int _activeSfxProcesses = 0;

  BgmTrack _activeTrack = BgmTrack.off;
  double _activeVolume = 0.38;
  double _activeRate = 1.0;
  bool _shouldLoop = false;

  @override
  Future<void> initialize({
    required ({Map<ArcadeSfx, Uint8List> sfx, Map<BgmTrack, Uint8List> bgm})
        Function()
    synthesizeFallback,
  }) async {
    try {
      if (Platform.isMacOS) {
        try {
          await Process.run('/usr/bin/pkill', ['-f', 'flutter_kart_']);
        } catch (_) {}
      }

      final studioDir = Directory(
        '${Directory.systemTemp.path}/flutter_kart_studio_v2',
      );
      if (!await studioDir.exists()) {
        await studioDir.create(recursive: true);
      }

      var missingAny = false;

      for (final sfx in ArcadeSfx.values) {
        final fileName = 'sfx_${sfx.name}.wav';
        final file = File('${studioDir.path}/$fileName');
        try {
          final byteData = await rootBundle.load('assets/audio/$fileName');
          if (!await file.exists() ||
              await file.length() < byteData.lengthInBytes) {
            final bytes = byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            );
            await file.writeAsBytes(bytes, flush: true);
          }
          _sfxPaths[sfx] = file.path;
        } catch (_) {
          if (await file.exists() && await file.length() > 1024) {
            _sfxPaths[sfx] = file.path;
          } else {
            missingAny = true;
          }
        }
      }

      for (final track in [BgmTrack.cyberOverdrive, BgmTrack.funkyCircuit]) {
        final fileName = 'bgm_${track.name}.wav';
        final file = File('${studioDir.path}/$fileName');
        try {
          final byteData = await rootBundle.load('assets/audio/$fileName');
          final srcBytes = byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          );
          final expectedLen = 44 + (srcBytes.length - 44) * 6;
          if (!await file.exists() || await file.length() != expectedLen) {
            final expanded = _expandWavLoopRepeats(srcBytes, repeats: 6);
            await file.writeAsBytes(expanded, flush: true);
          }
          _bgmPaths[track] = file.path;
        } catch (_) {
          if (await file.exists() && await file.length() > 4096) {
            _bgmPaths[track] = file.path;
          } else {
            missingAny = true;
          }
        }
      }

      if (missingAny) {
        final generated = await Isolate.run(synthesizeFallback);
        for (final entry in generated.sfx.entries) {
          if (_sfxPaths.containsKey(entry.key)) continue;
          final file = File('${studioDir.path}/sfx_${entry.key.name}.wav');
          await file.writeAsBytes(entry.value, flush: true);
          _sfxPaths[entry.key] = file.path;
        }
        for (final entry in generated.bgm.entries) {
          if (_bgmPaths.containsKey(entry.key)) continue;
          final file = File('${studioDir.path}/bgm_${entry.key.name}.wav');
          await file.writeAsBytes(entry.value, flush: true);
          _bgmPaths[entry.key] = file.path;
        }
      }

      if (_shouldLoop && _activeTrack != BgmTrack.off) {
        _launchBgmLoop();
      }
    } catch (_) {}
  }

  @override
  void startBgm({
    required BgmTrack track,
    required double volume,
    required double playbackRate,
  }) {
    final trackChanged = _activeTrack != track;
    final rateChanged = (_activeRate - playbackRate).abs() > 0.02;
    final volChanged = (_activeVolume - volume).abs() > 0.10;
    final playChanged = !_shouldLoop;

    _activeTrack = track;
    _activeVolume = volume;
    _activeRate = playbackRate;
    _shouldLoop = true;

    if (playChanged ||
        trackChanged ||
        rateChanged ||
        volChanged ||
        (_bgmProcess == null && !_bgmLaunching)) {
      _launchBgmLoop();
    }
  }

  @override
  void stopBgm() {
    _shouldLoop = false;
    _bgmSessionId++;
    _bgmLaunching = false;
    final proc = _bgmProcess;
    _bgmProcess = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }
  }

  void _launchBgmLoop() {
    _bgmSessionId++;
    _bgmLaunching = false;
    final prev = _bgmProcess;
    _bgmProcess = null;
    if (prev != null) {
      try {
        prev.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }

    if (!_shouldLoop || _activeTrack == BgmTrack.off || !Platform.isMacOS) {
      return;
    }

    final path = _bgmPaths[_activeTrack];
    if (path == null) return;

    final session = _bgmSessionId;
    _bgmLaunching = true;
    final args = <String>[
      '-v',
      _activeVolume.clamp(0.05, 1.0).toStringAsFixed(2),
      if ((_activeRate - 1.0).abs() > 0.01) ...[
        '-r',
        _activeRate.clamp(0.5, 2.0).toStringAsFixed(2),
      ],
      path,
    ];

    Process.start('/usr/bin/afplay', args).then((proc) {
      if (session != _bgmSessionId) {
        try {
          proc.kill(ProcessSignal.sigterm);
        } catch (_) {}
        return;
      }
      _bgmLaunching = false;
      _bgmProcess = proc;
      proc.exitCode.then((_) {
        if (session == _bgmSessionId) {
          _bgmProcess = null;
          _bgmLaunching = false;
          if (_shouldLoop && _activeTrack != BgmTrack.off) {
            _launchBgmLoop();
          }
        }
      });
    }).catchError((_) {
      if (session == _bgmSessionId) {
        _bgmLaunching = false;
        _bgmProcess = null;
      }
    });
  }

  @override
  void playSfx(
    ArcadeSfx sfx, {
    required double volume,
    required double pitchRate,
  }) {
    try {
      if (Platform.isIOS || Platform.isAndroid) {
        switch (sfx) {
          case ArcadeSfx.boost:
          case ArcadeSfx.jumpTrick:
          case ArcadeSfx.impact:
          case ArcadeSfx.lapComplete:
            HapticFeedback.mediumImpact();
          case ArcadeSfx.coin:
          case ArcadeSfx.countdownBeep:
          case ArcadeSfx.driftCharge:
            HapticFeedback.lightImpact();
          case ArcadeSfx.countdownGo:
          case ArcadeSfx.victoryFanfare:
            HapticFeedback.heavyImpact();
          case ArcadeSfx.itemPickup:
          case ArcadeSfx.shellFire:
            HapticFeedback.selectionClick();
        }
      }
    } catch (_) {}

    final path = _sfxPaths[sfx];
    if (path == null || _activeSfxProcesses >= 6) return;

    if (Platform.isMacOS) {
      _activeSfxProcesses++;
      final args = <String>[
        '-v',
        volume.clamp(0.05, 1.0).toStringAsFixed(2),
        if ((pitchRate - 1.0).abs() > 0.01) ...[
          '-r',
          pitchRate.clamp(0.5, 2.0).toStringAsFixed(2),
        ],
        path,
      ];
      Process.start('/usr/bin/afplay', args).then((proc) {
        proc.exitCode.whenComplete(() {
          _activeSfxProcesses = math.max(0, _activeSfxProcesses - 1);
        });
      }).catchError((_) {
        _activeSfxProcesses = math.max(0, _activeSfxProcesses - 1);
      });
    }
  }

  /// Repeats a 44-byte RIFF WAV file's PCM payload [repeats] times so macOS
  /// `afplay` plays ~90s continuously while the repo/Web asset stays 1x size.
  static Uint8List _expandWavLoopRepeats(Uint8List src, {int repeats = 6}) {
    if (src.length <= 44 || repeats <= 1) return src;
    final singleBlockBytes = src.length - 44;
    final totalDataBytes = singleBlockBytes * repeats;
    final out = Uint8List(44 + totalDataBytes);
    out.setRange(0, 44, src);

    final pcmSlice = Uint8List.sublistView(src, 44);
    for (var r = 0; r < repeats; r++) {
      out.setRange(44 + r * singleBlockBytes, 44 + (r + 1) * singleBlockBytes, pcmSlice);
    }

    final bd = ByteData.sublistView(out);
    bd.setUint32(4, 36 + totalDataBytes, Endian.little);
    bd.setUint32(40, totalDataBytes, Endian.little);
    return out;
  }
}
