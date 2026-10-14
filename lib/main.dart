import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';

import 'game/kart_race_game.dart';
import 'ui/race_hud.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KartRacerApp());
}

class KartRacerApp extends StatelessWidget {
  const KartRacerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Scene 3D Kart Racer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const KartRaceScreen(),
    );
  }
}

class KartRaceScreen extends StatefulWidget {
  const KartRaceScreen({super.key});

  @override
  State<KartRaceScreen> createState() => _KartRaceScreenState();
}

class _KartRaceScreenState extends State<KartRaceScreen> {
  final KartRaceGame _game = KartRaceGame();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  final Set<LogicalKeyboardKey> _heldKeys = <LogicalKeyboardKey>{};

  // Touch input state
  bool _showTouchControls = true;
  double _touchSteer = 0.0;
  bool _touchGas = false;
  bool _touchBrake = false;
  bool _touchDrift = false;

  @override
  void initState() {
    super.initState();
    _game.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _game.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _heldKeys.add(key);

      if (event is KeyDownEvent) {
        if (_game.phase == GamePhase.titleScreen) {
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            _game.startGrandPrixWithCutscene();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.tab) {
            _game.togglePlayerCharacter();
            return KeyEventResult.handled;
          }
        } else if (_game.phase == GamePhase.introCutscene) {
          if (key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.escape) {
            _game.skipCutsceneAndStartRace();
            return KeyEventResult.handled;
          }
        }

        if (key == LogicalKeyboardKey.keyE ||
            key == LogicalKeyboardKey.keyF ||
            key == LogicalKeyboardKey.enter) {
          _game.triggerPlayerUseItem();
        } else if (key == LogicalKeyboardKey.keyB) {
          _game.toggleLookBack();
        } else if (key == LogicalKeyboardKey.keyC) {
          _game.cycleCameraPreset();
        } else if (key == LogicalKeyboardKey.keyV) {
          _game.toggleDirectorCam();
        } else if (key == LogicalKeyboardKey.keyG) {
          _game.toggleSmartSteer();
        } else if (key == LogicalKeyboardKey.keyT) {
          _game.toggleAutoAccelerate();
        } else if (key == LogicalKeyboardKey.keyR) {
          _game.resetPlayerToTrack();
        } else if (key == LogicalKeyboardKey.tab) {
          _game.togglePlayerCharacter();
        } else if (key == LogicalKeyboardKey.keyP ||
            key == LogicalKeyboardKey.escape) {
          _game.togglePause();
        } else if (key == LogicalKeyboardKey.keyM) {
          _game.toggleSoundMute();
        } else if (key == LogicalKeyboardKey.keyL) {
          _game.cycleTrackTheme();
        }
      }
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(key);
    }
    _syncPlayerInput();
    return KeyEventResult.handled;
  }

  void _syncPlayerInput() {
    if (!_game.isInitialized || _game.isTrailerActive) return;
    final input = _game.playerKart.input;

    final keyGas =
        _heldKeys.contains(LogicalKeyboardKey.keyW) ||
        _heldKeys.contains(LogicalKeyboardKey.arrowUp);
    final keyBrake =
        _heldKeys.contains(LogicalKeyboardKey.keyS) ||
        _heldKeys.contains(LogicalKeyboardKey.arrowDown);
    final keyLeft =
        _heldKeys.contains(LogicalKeyboardKey.keyA) ||
        _heldKeys.contains(LogicalKeyboardKey.arrowLeft);
    final keyRight =
        _heldKeys.contains(LogicalKeyboardKey.keyD) ||
        _heldKeys.contains(LogicalKeyboardKey.arrowRight);
    final keyDrift =
        _heldKeys.contains(LogicalKeyboardKey.space) ||
        _heldKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        _heldKeys.contains(LogicalKeyboardKey.shiftRight);

    final isBraking = keyBrake || _touchBrake;
    final autoGasActive =
        _game.autoAccelerate && _game.isRaceStarted && !isBraking;
    // Also auto-accelerate when steering on mobile touch pad unless braking
    final mobileSteerGas =
        _touchSteer.abs() > 0.02 && _game.isRaceStarted && !isBraking;

    input.throttle =
        (keyGas || _touchGas || autoGasActive || mobileSteerGas) ? 1.0 : 0.0;
    input.brake = isBraking ? 1.0 : 0.0;

    var keySteer = 0.0;
    if (keyLeft) keySteer -= 1.0;
    if (keyRight) keySteer += 1.0;

    input.steer = _touchSteer.abs() > 0.01 ? _touchSteer : keySteer;
    input.driftHeld = keyDrift || _touchDrift;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (_) {
            if (!_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
          },
          child: !_game.isInitialized
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFFC107)),
                      SizedBox(height: 16),
                      Text(
                        'INITIALIZING FLUTTER GPU & 3D CIRCUIT...',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                )
              : RepaintBoundary(
                  key: _repaintBoundaryKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 3D Viewport driven by flutter_scene
                      SceneView(
                        _game.scene,
                        warmUp: true,
                        onTick: (elapsed, deltaSeconds) {
                          _syncPlayerInput();
                          _game.tick(deltaSeconds);
                        },
                      ),

                      // Interactive Arcade HUD + Multi-Touch Controls
                      ListenableBuilder(
                        listenable: _game,
                        builder: (context, _) {
                          return RaceHudOverlay(
                            game: _game,
                            showTouchControls:
                                _showTouchControls && !_game.isTrailerActive,
                            onToggleTouchControls: () {
                              setState(
                                () => _showTouchControls = !_showTouchControls,
                              );
                            },
                            onTouchSteerChanged: (val) {
                              _touchSteer = val;
                              _syncPlayerInput();
                            },
                            onTouchGasChanged: (val) {
                              _touchGas = val;
                              _syncPlayerInput();
                            },
                            onTouchBrakeChanged: (val) {
                              _touchBrake = val;
                              _syncPlayerInput();
                            },
                            onTouchDriftChanged: (val) {
                              _touchDrift = val;
                              _syncPlayerInput();
                            },
                            onUseItem: _game.triggerPlayerUseItem,
                          );
                        },
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
