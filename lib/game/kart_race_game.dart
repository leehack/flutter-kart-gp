import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kart_builder.dart';
import 'kart_physics.dart';
import 'sound_manager.dart';
import 'track_builder.dart';
import 'track_data.dart';

enum GamePhase {
  titleScreen,
  introCutscene,
  racing,
  victoryCutscene,
}

enum TrackTheme {
  sapphireDay(
    label: 'Sapphire Bay',
    subtitle: 'Alpine Daylight',
  ),
  sunsetCanyon(
    label: 'Sunset Canyon',
    subtitle: 'Golden Hour Glow',
  ),
  cyberNight(
    label: 'Neon Cyber',
    subtitle: 'Twilight Overdrive',
  );

  const TrackTheme({
    required this.label,
    required this.subtitle,
  });

  final String label;
  final String subtitle;
}

enum SpeedClass {
  cc50(
    label: '50cc',
    subtitle: 'Chill Cruise',
    speedMultiplier: 0.80,
  ),
  cc100(
    label: '100cc',
    subtitle: 'Grand Prix',
    speedMultiplier: 0.96,
  ),
  cc150(
    label: '150cc',
    subtitle: 'Hyper Turbo',
    speedMultiplier: 1.12,
  );

  const SpeedClass({
    required this.label,
    required this.subtitle,
    required this.speedMultiplier,
  });

  final String label;
  final String subtitle;
  final double speedMultiplier;
}

enum CameraPreset {
  chaseHero('Hero Close-Up', distance: 4.35, height: 1.92, lookAhead: 3.6),
  chaseStandard('Standard Chase', distance: 5.8, height: 2.45, lookAhead: 4.4),
  chaseWide('Wide Dynamic', distance: 7.8, height: 3.3, lookAhead: 5.2),
  frontShowcase('Front Hero Cam', distance: -3.85, height: 1.72, lookAhead: -0.6);

  const CameraPreset(
    this.label, {
    required this.distance,
    required this.height,
    required this.lookAhead,
  });

  final String label;
  final double distance;
  final double height;
  final double lookAhead;
}

class _ActiveHomingShell {
  _ActiveHomingShell({
    required this.owner,
    required this.node,
    required this.trackDistance,
    required this.lateralOffset,
    required this.position,
  });

  final KartRacer owner;
  final Node node;
  double trackDistance;
  double lateralOffset;
  vm.Vector3 position;
  double age = 0.0;
}

class _ActiveBananaHazard {
  _ActiveBananaHazard({
    required this.node,
    required this.position,
  });

  final Node node;
  final vm.Vector3 position;
  double age = 0.0;
  double armTimer = 0.45;
}

/// Owns the 3D `Scene`, track, player & AI karts (Flutter Dash, Turbo Llama,
/// Bugdroid Bot, Blaze Dino), chase/cinematic camera rig, and race state.
class KartRaceGame extends ChangeNotifier {
  final Scene scene = Scene();
  final TrackCircuit track = TrackCircuit();
  final List<KartRacer> karts = [];
  final math.Random _rng = math.Random(2026);
  final ArcadeSoundManager _sfx = ArcadeSoundManager.instance;

  static const int totalLaps = 3;
  static const double introCutsceneDuration = 8.8;

  TrackWorldVisuals? _trackVisuals;
  late final Node _projectilesRoot;
  final List<_ActiveHomingShell> _activeShells = [];
  final List<_ActiveBananaHazard> _activeBananas = [];

  late final Node _cameraNode;
  late final PerspectiveProjection _cameraProjection;
  final CameraShake _cameraShake = CameraShake(
    decayRate: 1.8,
    frequency: 26.0,
    maxTranslation: vm.Vector3(0.24, 0.18, 0.12),
    maxRotation: vm.Vector3(0.035, 0.035, 0.025),
  );

  GamePhase phase = GamePhase.titleScreen;
  TrackTheme trackTheme = TrackTheme.cyberNight;
  SpeedClass speedClass = SpeedClass.cc100;
  CameraPreset cameraPreset = CameraPreset.chaseHero;
  bool isLookBackHeld = false;
  bool isDirectorCamActive = false;
  bool titleFlyoverMode = false;

  // Optional driving assists (OFF by default for pure arcade skill control)
  bool smartSteerEnabled = false;
  bool autoAccelerate = false;

  bool get isSoundMuted => _sfx.isMuted;
  BgmTrack get bgmTrack => _sfx.currentBgmTrack;

  double _titleOrbitClock = 0.0;
  double _cutsceneClock = 0.0;
  double _victoryClock = 0.0;
  double _characterShowcaseTimer = 0.0;
  vm.Vector3 _smoothedCamEye = vm.Vector3(0, 3.5, -12);
  vm.Vector3 _smoothedCamTarget = vm.Vector3(0, 1.0, 4);
  double _cameraOrbitYaw = 0.0;
  bool isPaused = false;

  // Race timing & banners
  double countdownTimer = 3.5; // > 0 means countdown before green light
  double goBannerTimer = 0.0;
  double raceElapsedTime = 0.0;
  String? statusBanner;
  double _statusBannerTimer = 0.0;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  KartRacer get playerKart => karts.first;
  RacerCharacter get selectedCharacter =>
      karts.isNotEmpty ? playerKart.character : RacerCharacter.flutterDash;
  bool get isRaceStarted => phase == GamePhase.racing && countdownTimer <= 0.0;
  bool get isRaceFinished =>
      phase == GamePhase.victoryCutscene ||
      (karts.isNotEmpty && playerKart.isFinished);

  double get cutsceneProgress =>
      (_cutsceneClock / introCutsceneDuration).clamp(0.0, 1.0);

  int get currentCutsceneShotIndex {
    if (_cutsceneClock < 2.2) return 1;
    if (_cutsceneClock < 4.4) return 2;
    if (_cutsceneClock < 6.6) return 3;
    return 4;
  }

  ({String title, String subtitle}) get currentCutsceneCaption {
    if (_cutsceneClock < 2.2) {
      return (
        title: 'FLUTTER KART GRAND PRIX',
        subtitle: '${bgmTrack.label.toUpperCase()} • ${speedClass.label} CLASS',
      );
    } else if (_cutsceneClock < 4.4) {
      return (
        title: 'CRYSTAL LAGOON & AERO RAMPS',
        subtitle: 'HIGH-SPEED S-CHICANE, JUMP RAMPS & HYPER-BOOST PADS',
      );
    } else if (_cutsceneClock < 6.6) {
      return (
        title: 'MASCOT GRID SHOWDOWN',
        subtitle: 'FLUTTER DASH • TURBO LLAMA • BUGDROID • BLAZE DINO',
      );
    } else {
      return (
        title: 'ENGINES ARMED — GET READY!',
        subtitle: 'HOLD GAS ON "2" FOR A ROCKET START BOOST!',
      );
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await Scene.preload(
      physicalMaterials: true,
      smaa: true,
    );
    await _sfx.initialize();

    _configureLightingAndAtmosphere();

    // Build and mount the 3D circuit, PBR road, swept curbs, hills & lake
    _trackVisuals = TrackBuilder.buildTrackWorld(track);
    scene.add(_trackVisuals!.rootNode);

    // Container for dynamic 3D Homing Shells & Banana Hazards
    _projectilesRoot = Node(name: 'DynamicProjectiles');
    scene.add(_projectilesRoot);

    // Build Player + 3 Mascot Opponent Karts on the starting grid
    _spawnRacers();

    // Mount primary Chase Camera node
    _cameraProjection = PerspectiveProjection(
      fovRadiansY: 54.0 * vm.degrees2Radians,
      near: 0.15,
      far: 950.0,
    );
    _cameraNode = Node(name: 'PlayerChaseCamera')
      ..addComponent(
        CameraComponent(
          projection: _cameraProjection,
          activateOnMount: true,
        ),
      );
    scene.add(_cameraNode);

    _snapCameraToPlayer();
    _isInitialized = true;
    _syncBgmState();
    notifyListeners();
  }

  void selectTrackTheme(TrackTheme theme) {
    if (trackTheme == theme) return;
    trackTheme = theme;
    _configureLightingAndAtmosphere();
    notifyListeners();
  }

  void cycleTrackTheme() {
    cycleBgmTrack();
  }

  void selectBgmTrack(BgmTrack track) {
    _sfx.selectBgmTrack(track);
    _syncBgmState();
    _showBanner('MUSIC: ${track.label.toUpperCase()}');
    notifyListeners();
  }

  void cycleBgmTrack() {
    _sfx.cycleBgmTrack();
    _syncBgmState();
    _showBanner('MUSIC: ${_sfx.currentBgmTrack.label.toUpperCase()}');
    notifyListeners();
  }

  void selectSpeedClass(SpeedClass targetClass) {
    if (speedClass == targetClass) return;
    speedClass = targetClass;
    _showBanner('CLASS: ${targetClass.label} (${targetClass.subtitle.toUpperCase()})');
    notifyListeners();
  }

  void toggleSoundMute() {
    _sfx.toggleMute();
    _syncBgmState();
    _showBanner(_sfx.isMuted ? 'AUDIO: MUTED' : 'AUDIO: ON');
    notifyListeners();
  }

  void _syncBgmState() {
    if (!_isInitialized || isPaused) {
      _sfx.setBgmState(playing: false);
      return;
    }
    switch (phase) {
      case GamePhase.titleScreen:
      case GamePhase.introCutscene:
        _sfx.setBgmState(playing: true, playbackRate: 1.0, volume: 0.38);
      case GamePhase.racing:
        if (karts.isNotEmpty && playerKart.currentLap >= totalLaps) {
          _sfx.setBgmState(playing: true, playbackRate: 1.14, volume: 0.44);
        } else {
          _sfx.setBgmState(playing: true, playbackRate: 1.0, volume: 0.38);
        }
      case GamePhase.victoryCutscene:
        if (_victoryClock < 2.5) {
          _sfx.setBgmState(playing: false);
        } else {
          _sfx.setBgmState(playing: true, playbackRate: 1.0, volume: 0.38);
        }
    }
  }

  void _configureLightingAndAtmosphere() {
    final sunDir = vm.Vector3(0.42, 0.56, -0.45).normalized();
    final sky = GradientSkySource(
      zenithColor: vm.Vector3(0.05, 0.12, 0.30),
      horizonColor: vm.Vector3(0.16, 0.32, 0.58),
      groundColor: vm.Vector3(0.10, 0.16, 0.14),
      sunDirection: sunDir,
      sunColor: vm.Vector3(1.25, 1.18, 1.08),
      sunSharpness: 320.0,
    );
    final skybox = Skybox(sky);
    final skyEnv = SkyEnvironment(
      sky,
      refresh: SkyEnvironmentRefresh.manual,
    );
    final sunLight = SunLight(
      sky,
      castsShadow: true,
      color: vm.Vector3(0.92, 0.95, 1.00),
      intensityScale: 0.85,
      shadowMaxDistance: 185.0,
      shadowCascadeCount: 3,
      shadowMapResolution: 1024,
      shadowSoftness: 0.06,
      shadowAmbientStrength: 0.48,
      contactShadows: true,
      contactShadowDistance: 0.35,
    );

    scene.environmentSettings = EnvironmentSettings(
      skybox: skybox,
      skyEnvironment: skyEnv,
      sunLight: sunLight,
      toneMapping: ToneMappingMode.aces,
      exposure: 0.98,
      colorGradingEnabled: true,
      saturation: 1.20,
      contrast: 1.06,
      bloomEnabled: true,
      bloomThreshold: 1.02,
      bloomIntensity: 0.28,
      bloomScatter: 0.70,
      lensFlareEnabled: false,
      screenSpaceReflectionsEnabled: true,
      screenSpaceReflectionsIntensity: 0.38,
      screenSpaceReflectionsResolutionScale: 0.5,
      ambientOcclusionEnabled: true,
      ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
      ambientOcclusionHalfResolution: false,
      ambientOcclusionIntensity: 0.80,
      fogEnabled: true,
      fogMode: FogMode.exponential,
      fogDensity: 0.0008,
      fogColor: vm.Vector3(0.14, 0.24, 0.44),
      fogSkyColorInfluence: 0.65,
      fogSunInScatter: 0.12,
      godRaysEnabled: false,
      vignetteEnabled: true,
      vignetteIntensity: 0.14,
    );
  }

  void _spawnRacers() {
    final specs = <({
      RacerCharacter character,
      String name,
      Color uiColor,
      vm.Vector4 primary,
      vm.Vector4 accent,
      vm.Vector4 rim,
      double startDist,
      double lateral,
      double aiSkill,
      double laneOffset,
    })>[
      (
        character: RacerCharacter.flutterDash,
        name: 'YOU • Flutter Dash',
        uiColor: const Color(0xFF29B6F6),
        primary: vm.Vector4(0.12, 0.64, 0.96, 1.0),
        accent: vm.Vector4(0.96, 0.98, 1.0, 1.0),
        rim: vm.Vector4(0.18, 0.78, 1.0, 1.0),
        startDist: track.totalLength - 8.5,
        lateral: -2.4,
        aiSkill: 1.0,
        laneOffset: 0.0,
      ),
      (
        character: RacerCharacter.llama,
        name: 'Turbo Llama',
        uiColor: const Color(0xFFFFB300),
        primary: vm.Vector4(0.98, 0.68, 0.10, 1.0),
        accent: vm.Vector4(0.88, 0.14, 0.48, 1.0),
        rim: vm.Vector4(1.0, 0.82, 0.22, 1.0),
        startDist: track.totalLength - 6.0,
        lateral: 2.4,
        aiSkill: 0.96,
        laneOffset: 2.1,
      ),
      (
        character: RacerCharacter.androidBot,
        name: 'Bugdroid Bot',
        uiColor: const Color(0xFF69F0AE),
        primary: vm.Vector4(0.18, 0.84, 0.46, 1.0),
        accent: vm.Vector4(0.12, 0.16, 0.22, 1.0),
        rim: vm.Vector4(0.30, 0.95, 0.58, 1.0),
        startDist: track.totalLength - 13.0,
        lateral: -2.4,
        aiSkill: 0.92,
        laneOffset: -2.2,
      ),
      (
        character: RacerCharacter.chromeDino,
        name: 'Blaze Dino',
        uiColor: const Color(0xFFFF5252),
        primary: vm.Vector4(0.94, 0.26, 0.14, 1.0),
        accent: vm.Vector4(1.0, 0.82, 0.14, 1.0),
        rim: vm.Vector4(1.0, 0.45, 0.20, 1.0),
        startDist: track.totalLength - 10.5,
        lateral: 2.4,
        aiSkill: 0.89,
        laneOffset: 0.4,
      ),
    ];

    for (var i = 0; i < specs.length; i++) {
      final s = specs[i];
      final sample = track.sampleAtDistance(s.startDist);
      final startPos = sample.position + sample.right * s.lateral;
      final startYaw = math.atan2(sample.tangent.x, sample.tangent.z);

      final rig = KartBuilder.buildKart(
        name: 'Kart_$i',
        character: s.character,
        primaryColor: s.primary,
        accentColor: s.accent,
        rimColor: s.rim,
        isPlayer: i == 0,
      );
      scene.add(rig.rootNode);

      final racer = KartRacer(
        id: i,
        displayName: s.name,
        uiColor: s.uiColor,
        isPlayer: i == 0,
        rig: rig,
        startPosition: startPos,
        startYaw: startYaw,
        aiSkill: s.aiSkill,
        preferredLaneOffset: s.laneOffset,
      )..trackDistance = s.startDist;

      racer.syncVisualTransforms(0.016);
      karts.add(racer);
    }
  }

  /// Switches the human player between **Flutter Dash**, **Turbo Llama**,
  /// **Bugdroid Bot**, or **Blaze Dino**, swapping rigs with the rival kart
  /// so all 4 characters remain on the circuit!
  void selectPlayerCharacter(RacerCharacter targetCharacter) {
    if (karts.isEmpty || playerKart.character == targetCharacter) {
      titleFlyoverMode = false;
      notifyListeners();
      return;
    }

    final partnerIndex = karts.indexWhere(
      (k) => !k.isPlayer && k.character == targetCharacter,
    );
    if (partnerIndex < 0) return;

    final player = playerKart;
    final partner = karts[partnerIndex];

    // Swap visual rigs & UI colors
    final oldPlayerRig = player.rig;
    final oldPlayerColor = player.uiColor;
    final oldPlayerChar = player.character;

    player.rig = partner.rig;
    player.uiColor = partner.uiColor;
    player.displayName = 'YOU • ${targetCharacter.displayName}';

    partner.rig = oldPlayerRig;
    partner.uiColor = oldPlayerColor;
    partner.displayName = oldPlayerChar.displayName;

    player.rig.leftTrail.clear();
    player.rig.rightTrail.clear();
    partner.rig.leftTrail.clear();
    partner.rig.rightTrail.clear();

    player.syncVisualTransforms(0.016);
    partner.syncVisualTransforms(0.016);

    titleFlyoverMode = false;
    // Briefly swing camera to a 3/4 hero angle if stationary or in countdown
    if (player.forwardSpeed.abs() < 6.0) {
      _characterShowcaseTimer = 1.1;
    }

    _showBanner('DRIVER: ${targetCharacter.displayName.toUpperCase()}!');
    notifyListeners();
  }

  /// Toggles the player between Flutter Dash and Turbo Llama.
  void togglePlayerCharacter() {
    final next = playerKart.character == RacerCharacter.flutterDash
        ? RacerCharacter.llama
        : RacerCharacter.flutterDash;
    selectPlayerCharacter(next);
  }

  void toggleLookBack() {
    isLookBackHeld = !isLookBackHeld;
    notifyListeners();
  }

  void toggleDirectorCam() {
    isDirectorCamActive = !isDirectorCamActive;
    _showBanner(
      isDirectorCamActive ? 'TV DIRECTOR CAM: ON' : 'CHASE CAM RESTORED',
    );
    notifyListeners();
  }

  void toggleSmartSteer() {
    smartSteerEnabled = !smartSteerEnabled;
    _showBanner(
      smartSteerEnabled ? 'SMART STEER ASSIST: ON' : 'SMART STEER ASSIST: OFF',
    );
    notifyListeners();
  }

  void toggleAutoAccelerate() {
    autoAccelerate = !autoAccelerate;
    _showBanner(
      autoAccelerate ? 'AUTO-GAS: ON' : 'AUTO-GAS: OFF',
    );
    notifyListeners();
  }

  void toggleTitleCameraMode() {
    titleFlyoverMode = !titleFlyoverMode;
    notifyListeners();
  }

  /// Launches the 4-shot Pre-Race Intro Cutscene from the Title Screen (or replays it).
  void startGrandPrixWithCutscene() {
    _resetGridState();
    phase = GamePhase.introCutscene;
    _cutsceneClock = 0.0;
    notifyListeners();
  }

  /// Skips the Intro Cutscene (or starts immediately) and enters the 3-2-1 Countdown.
  void skipCutsceneAndStartRace() {
    _resetGridState();
    phase = GamePhase.racing;
    countdownTimer = 3.5;
    _snapCameraToPlayer();
    notifyListeners();
  }

  /// Returns to the interactive 3D Title Screen / Paddock Showcase.
  void returnToTitleScreen() {
    _resetGridState();
    phase = GamePhase.titleScreen;
    titleFlyoverMode = false;
    notifyListeners();
  }

  void restartRace() {
    skipCutsceneAndStartRace();
  }

  void _resetGridState() {
    countdownTimer = 3.5;
    goBannerTimer = 0.0;
    raceElapsedTime = 0.0;
    statusBanner = null;
    _statusBannerTimer = 0.0;
    _characterShowcaseTimer = 0.0;
    _victoryClock = 0.0;
    isLookBackHeld = false;
    isDirectorCamActive = false;
    isPaused = false;

    for (final box in track.itemBoxes) {
      box.respawnTimer = 0.0;
      box.node?.visible = true;
    }
    for (final coin in track.coins) {
      coin.respawnTimer = 0.0;
      coin.node?.visible = true;
    }

    for (final s in _activeShells) {
      _projectilesRoot.remove(s.node);
    }
    _activeShells.clear();

    for (final b in _activeBananas) {
      _projectilesRoot.remove(b.node);
    }
    _activeBananas.clear();

    scene.screenDistortion.pulses.clear();
    scene.screenDistortion.enabled = false;

    for (var i = 0; i < karts.length; i++) {
      final k = karts[i];
      k.resetForRace();
      k.trackDistance = track.project(k.position).distance;
      k.raceRank = i + 1;
    }
  }

  void resetPlayerToTrack() {
    final p = playerKart;
    final proj = track.project(p.position);
    p.position = proj.closestPoint.clone();
    p.yaw = math.atan2(proj.tangent.x, proj.tangent.z);
    p.forwardSpeed = 0.0;
    p.lateralVelocity = 0.0;
    p.isDrifting = false;
    p.driftCharge = 0.0;
    p.spinOutTimer = 0.0;
    p.syncVisualTransforms(0.016);
    _showBanner('BACK ON TRACK!');
  }

  void cycleCameraPreset() {
    isDirectorCamActive = false;
    final values = CameraPreset.values;
    cameraPreset = values[(cameraPreset.index + 1) % values.length];
    _showBanner('CAM: ${cameraPreset.label.toUpperCase()}');
    notifyListeners();
  }

  void togglePause() {
    isPaused = !isPaused;
    _syncBgmState();
    notifyListeners();
  }

  void _showBanner(String text, {double duration = 1.6}) {
    statusBanner = text;
    _statusBannerTimer = duration;
  }

  void triggerPlayerUseItem() {
    if (playerKart.heldItem != KartItemType.none) {
      playerKart.input.useItemPressed = true;
    }
  }

  void _triggerScreenPulse({double strength = 0.024}) {
    final pulses = scene.screenDistortion.pulses;
    if (pulses.length >= ScreenDistortionSettings.maxPulses) {
      pulses.removeAt(0);
    }
    pulses.add(
      DistortionPulse(
        center: vm.Vector2(0.5, 0.58),
        radius: 0.05,
        thickness: 0.11,
        strength: strength,
        chromaticAberration: 0.45,
      ),
    );
    scene.screenDistortion.enabled = true;
  }

  void _updateScreenPulses(double dt) {
    final pulses = scene.screenDistortion.pulses;
    if (pulses.isEmpty) return;
    for (var i = pulses.length - 1; i >= 0; i--) {
      final p = pulses[i];
      p.radius += dt * 1.65;
      p.strength = math.max(0.0, p.strength - dt * 0.055);
      if (p.radius > 0.85 || p.strength <= 0.0005) {
        pulses.removeAt(i);
      }
    }
    if (pulses.isEmpty) {
      scene.screenDistortion.enabled = false;
    }
  }

  /// Main per-frame simulation step driven by `SceneView.onTick`.
  void tick(double rawDt) {
    if (!_isInitialized || isPaused) return;

    // Clamp deltaSeconds to avoid spiral on tab switches
    final dt = rawDt.clamp(0.001, 0.05);

    _syncBgmState();
    _updateScreenPulses(dt);
    _trackVisuals?.update(dt, track);

    if (_characterShowcaseTimer > 0.0) {
      _characterShowcaseTimer = math.max(0.0, _characterShowcaseTimer - dt);
    }

    // Handle Title Screen & Pre-Race Cutscene phases
    if (phase == GamePhase.titleScreen) {
      _titleOrbitClock += dt;
      // Animate mascot idle expressions on the starting grid
      for (var i = 0; i < karts.length; i++) {
        final k = karts[i];
        k.rig.updateVisuals(
          dt: dt,
          speed: 8.0,
          steerInput: math.sin(_titleOrbitClock * 1.8 + i) * 0.45,
          isDrifting: false,
          driftDirection: 0.0,
          driftLevel: 0,
          hopOffset: 0.0,
          spinOutAngle: 0.0,
          hasShield: false,
          isBoosting: i == 0,
          isBraking: false,
        );
      }
      _updateTitleScreenCamera(dt);
      notifyListeners();
      return;
    }

    if (phase == GamePhase.introCutscene) {
      _cutsceneClock += dt;
      // Animate mascots revving engines on the grid during the cutscene
      for (var i = 0; i < karts.length; i++) {
        final k = karts[i];
        k.rig.updateVisuals(
          dt: dt,
          speed: 18.0,
          steerInput: math.sin(_cutsceneClock * 2.6 + i * 1.1) * 0.65,
          isDrifting: false,
          driftDirection: 0.0,
          driftLevel: 0,
          hopOffset: 0.0,
          spinOutAngle: 0.0,
          hasShield: false,
          isBoosting: _cutsceneClock > 4.4,
          isBraking: false,
        );
      }
      _updateIntroCutsceneCamera(dt);
      if (_cutsceneClock >= introCutsceneDuration) {
        skipCutsceneAndStartRace();
      } else {
        notifyListeners();
      }
      return;
    }

    // 1. Countdown & race clock
    if (countdownTimer > 0.0) {
      final prevCeil = countdownTimer.ceil();
      countdownTimer = math.max(0.0, countdownTimer - dt);
      final newCeil = countdownTimer.ceil();
      if (newCeil < prevCeil && newCeil >= 1 && newCeil <= 3) {
        _sfx.play(ArcadeSfx.countdownBeep);
      }
      if (countdownTimer <= 0.0 && prevCeil > 0) {
        goBannerTimer = 1.2;
        _sfx.play(ArcadeSfx.countdownGo);
        _syncBgmState();
        // Evaluate Rocket Start on green light!
        if (playerKart.rocketStartCharge >= 0.30 &&
            playerKart.rocketStartCharge <= 1.22) {
          playerKart.triggerBoost(duration: 1.30, bonusSpeed: 5.0);
          _showBanner('ROCKET START!', duration: 1.5);
          _cameraShake.addTrauma(0.35);
          _triggerScreenPulse(strength: 0.028);
          _sfx.play(ArcadeSfx.boost);
        }
      }
    } else {
      if (goBannerTimer > 0.0) {
        goBannerTimer = math.max(0.0, goBannerTimer - dt);
      }
      if (!playerKart.isFinished) {
        raceElapsedTime += dt;
      }
    }

    if (_statusBannerTimer > 0.0) {
      _statusBannerTimer = math.max(0.0, _statusBannerTimer - dt);
      if (_statusBannerTimer <= 0.0) {
        statusBanner = null;
      }
    }

    final canDrive = isRaceStarted;

    // 2. Update AI inputs & step all karts
    final playerLapBefore = playerKart.currentLap;
    for (final kart in karts) {
      if (!kart.isPlayer || kart.isFinished) {
        kart.updateAiInput(track, karts, dt, _rng);
        if (kart.isPlayer && kart.isFinished) {
          // Celebratory victory lap boost!
          kart.boostTimer = 0.5;
          kart.boostBonusSpeed = 4.0;
        }
      }
      final boosted = kart.stepPhysics(
        dt: dt,
        track: track,
        canDrive: canDrive,
        smartSteerEnabled: smartSteerEnabled,
        speedClassScale: speedClass.speedMultiplier,
        onEmpShockwave: _handleEmpShockwave,
        onSpawnHomingShell: _spawnHomingShell,
        onDropBanana: _dropBananaHazard,
        onPlayerCameraShake: _cameraShake.addTrauma,
        onWallImpact: kart.isPlayer ? () => _sfx.play(ArcadeSfx.impact) : null,
        onTrickStarted: kart.isPlayer
            ? () {
                _showBanner('360° AERIAL TRICK!', duration: 1.2);
                _sfx.play(ArcadeSfx.jumpTrick);
              }
            : null,
        onDriftTierUnlocked: kart.isPlayer
            ? (tier) {
                final pitch = switch (tier) {
                  1 => 1.00,
                  2 => 1.22,
                  _ => 1.48,
                };
                _sfx.play(ArcadeSfx.driftCharge, pitchRate: pitch);
              }
            : null,
      );
      if (boosted && kart.isPlayer && !kart.isFinished) {
        _showBanner('TURBO BOOST!');
        _triggerScreenPulse();
        _sfx.play(ArcadeSfx.boost);
      }

      // Check race completion
      if (!kart.isFinished && kart.currentLap > totalLaps) {
        kart.isFinished = true;
        kart.currentLap = totalLaps;
        kart.finishTime = raceElapsedTime;
        if (kart.isPlayer) {
          phase = GamePhase.victoryCutscene;
          _victoryClock = 0.0;
          _syncBgmState();
          _showBanner(
            'FINISH! ${_ordinal(kart.raceRank)} PLACE!',
            duration: 4.0,
          );
          _triggerScreenPulse(strength: 0.035);
          _sfx.play(ArcadeSfx.victoryFanfare);
        }
      }
    }

    if (!playerKart.isFinished && playerKart.currentLap > playerLapBefore) {
      if (playerKart.currentLap == totalLaps) {
        _showBanner('FINAL LAP!', duration: 2.2);
        _sfx.play(ArcadeSfx.lapComplete, pitchRate: 1.18);
        _syncBgmState();
      } else {
        _showBanner('LAP ${playerKart.currentLap} / $totalLaps', duration: 1.8);
        _sfx.play(ArcadeSfx.lapComplete);
      }
    }

    // 3. Check Item Boxes, Coins, Boost Pads, Jump Ramps, Projectiles, and Obstacles
    _updateTrackInteractables(dt);
    _updateProjectilesAndHazards(dt);
    if (canDrive) {
      _updateSlipstreamDrafting(dt);
    }

    // 4. Kart-to-Kart Bump Collisions
    _resolveKartCollisions();

    // 5. Sort Race Positions (1st..4th)
    _updateRaceStandings();

    // 6. Update Camera Rig (Victory Cutscene, TV Director Cam, or Chase Cam)
    if (phase == GamePhase.victoryCutscene) {
      _victoryClock += dt;
      _updateVictoryCutsceneCamera(dt);
    } else if (isDirectorCamActive) {
      _updateDirectorBroadcastCamera(dt);
    } else {
      _updateChaseCamera(dt);
    }

    notifyListeners();
  }

  void _handleEmpShockwave(KartRacer attacker) {
    if (attacker.isPlayer) {
      _showBanner('EMP SHOCKWAVE!');
      _cameraShake.addTrauma(0.45);
      _triggerScreenPulse(strength: 0.038);
      _sfx.play(ArcadeSfx.shellFire);
    }
    for (final target in karts) {
      if (identical(target, attacker)) continue;
      final dist = (target.position - attacker.position).length;
      if (dist < 32.0) {
        target.triggerSpinOut();
        if (target.isPlayer) {
          _showBanner('HIT BY EMP!');
          _cameraShake.addTrauma(0.55);
          _sfx.play(ArcadeSfx.impact);
        }
      }
    }
  }

  void _spawnHomingShell(KartRacer attacker) {
    final proj = track.project(attacker.position);
    final spawnDist = track.wrapDistance(proj.distance + 2.4);
    final spawnSample = track.sampleAtDistance(spawnDist);
    final spawnPos =
        spawnSample.position +
        spawnSample.right * proj.lateralOffset +
        vm.Vector3(0, 0.45, 0);

    final shellRoot = Node(name: 'HomingShell')..position = spawnPos.clone();

    final shellCarapaceMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.08, 0.88, 0.52, 1.0)
      ..emissiveFactor = vm.Vector4(0.05, 0.72, 0.42, 1.0)
      ..emissiveStrength = 2.8
      ..roughnessFactor = 0.18
      ..metallicFactor = 0.45;

    final shellRimMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.98, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.25, 0.90, 1.0, 1.0)
      ..emissiveStrength = 3.5
      ..roughnessFactor = 0.20;

    shellRoot.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.52, segments: 14, rings: 10),
          shellCarapaceMat,
        ),
      )..scale = vm.Vector3(1.0, 0.68, 1.05),
    );
    shellRoot.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 0.56,
            topRadius: 0.56,
            height: 0.14,
            radialSegments: 16,
            bottomCap: false,
            topCap: false,
          ),
          shellRimMat,
        ),
      ),
    );

    _projectilesRoot.add(shellRoot);
    _activeShells.add(
      _ActiveHomingShell(
        owner: attacker,
        node: shellRoot,
        trackDistance: spawnDist,
        lateralOffset: proj.lateralOffset,
        position: spawnPos,
      ),
    );

    if (attacker.isPlayer) {
      _showBanner('HOMING SHELL FIRED!', duration: 1.2);
      _sfx.play(ArcadeSfx.shellFire);
    }
  }

  void _dropBananaHazard(KartRacer source) {
    final dropPos =
        source.position - source.forwardDir * 2.35 + vm.Vector3(0, 0.02, 0);
    final bananaRoot = Node(name: 'BananaHazard')..position = dropPos.clone();

    final bananaYellowMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.86, 0.08, 1.0)
      ..emissiveFactor = vm.Vector4(0.35, 0.28, 0.0, 1.0)
      ..roughnessFactor = 0.32;
    final stemMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.38, 0.26, 0.10, 1.0)
      ..roughnessFactor = 0.75;

    // Central upright banana core
    bananaRoot.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 0.26,
            topRadius: 0.08,
            height: 0.62,
            radialSegments: 10,
          ),
          bananaYellowMat,
        ),
      )..position = vm.Vector3(0, 0.32, 0),
    );
    // Brown top stem
    bananaRoot.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 0.07,
            topRadius: 0.05,
            height: 0.14,
            radialSegments: 8,
          ),
          stemMat,
        ),
      )..position = vm.Vector3(0, 0.68, 0),
    );
    // 3 peeled yellow petals splayed outward on the asphalt
    for (var i = 0; i < 3; i++) {
      final angle = i * (math.pi * 2.0 / 3.0);
      bananaRoot.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(0.18, 0.08, 0.52)),
            bananaYellowMat,
          ),
        )
          ..position = vm.Vector3(
            math.sin(angle) * 0.34,
            0.06,
            math.cos(angle) * 0.34,
          )
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), angle),
      );
    }

    _projectilesRoot.add(bananaRoot);
    _activeBananas.add(
      _ActiveBananaHazard(
        node: bananaRoot,
        position: dropPos,
      ),
    );

    if (source.isPlayer) {
      _showBanner('BANANA DROPPED!', duration: 1.0);
    }
  }

  void _updateProjectilesAndHazards(double dt) {
    // 1. Update Homing Plasma Shells
    const shellSpeed = 38.0;
    for (var i = _activeShells.length - 1; i >= 0; i--) {
      final shell = _activeShells[i];
      shell.age += dt;
      if (shell.age > 6.5) {
        _projectilesRoot.remove(shell.node);
        _activeShells.removeAt(i);
        continue;
      }

      shell.trackDistance = track.wrapDistance(
        shell.trackDistance + shellSpeed * dt,
      );

      // Home laterally toward the closest rival kart ahead within 38m
      KartRacer? bestTarget;
      var bestAheadDist = 38.0;
      for (final candidate in karts) {
        if (identical(candidate, shell.owner) && shell.age < 0.6) continue;
        var ahead = candidate.trackDistance - shell.trackDistance;
        if (ahead < 0) ahead += track.totalLength;
        if (ahead < bestAheadDist) {
          bestAheadDist = ahead;
          bestTarget = candidate;
        }
      }

      if (bestTarget != null) {
        final targetProj = track.project(bestTarget.position);
        final latDiff = targetProj.lateralOffset - shell.lateralOffset;
        shell.lateralOffset += latDiff.clamp(-1.0, 1.0) * 9.5 * dt;
      } else {
        // Return gently toward track center
        shell.lateralOffset *= math.pow(0.4, dt).toDouble();
      }

      final sample = track.sampleAtDistance(shell.trackDistance);
      shell.position =
          sample.position +
          sample.right * shell.lateralOffset +
          vm.Vector3(0, 0.45, 0);
      shell.node.position = shell.position;
      shell.node.rotation = vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        shell.age * 16.0,
      );

      // Check impact with karts
      var hit = false;
      for (final kart in karts) {
        if (identical(kart, shell.owner) && shell.age < 0.5) continue;
        final dx = kart.position.x - shell.position.x;
        final dz = kart.position.z - shell.position.z;
        if (dx * dx + dz * dz < 2.4) {
          if (kart.shieldTimer > 0.0) {
            if (kart.isPlayer) _showBanner('SHELL BLOCKED BY SHIELD!');
          } else {
            kart.triggerSpinOut();
            if (kart.isPlayer) {
              _showBanner('HIT BY HOMING SHELL!', duration: 1.5);
              _cameraShake.addTrauma(0.55);
              _sfx.play(ArcadeSfx.impact);
            } else if (shell.owner.isPlayer) {
              _showBanner(
                'SHELL HIT ${kart.character.displayName.toUpperCase()}!',
              );
              _sfx.play(ArcadeSfx.impact);
            }
          }
          hit = true;
          break;
        }
      }

      if (hit) {
        _projectilesRoot.remove(shell.node);
        _activeShells.removeAt(i);
      }
    }

    // 2. Update Dropped Banana Hazards
    for (var i = _activeBananas.length - 1; i >= 0; i--) {
      final banana = _activeBananas[i];
      banana.age += dt;
      if (banana.armTimer > 0.0) {
        banana.armTimer = math.max(0.0, banana.armTimer - dt);
        continue;
      }
      if (banana.age > 28.0) {
        _projectilesRoot.remove(banana.node);
        _activeBananas.removeAt(i);
        continue;
      }

      var triggered = false;
      for (final kart in karts) {
        // Airborne karts flying above 0.42m jump cleanly over dropped bananas
        if (kart.hopHeight > 0.42) continue;
        final dx = kart.position.x - banana.position.x;
        final dz = kart.position.z - banana.position.z;
        if (dx * dx + dz * dz < 1.95) {
          if (kart.shieldTimer > 0.0) {
            if (kart.isPlayer) _showBanner('BANANA BLOCKED!');
          } else {
            kart.triggerSpinOut();
            if (kart.isPlayer) {
              _showBanner('SLIPPED ON BANANA!', duration: 1.4);
              _cameraShake.addTrauma(0.48);
              _sfx.play(ArcadeSfx.impact);
            }
          }
          triggered = true;
          break;
        }
      }

      if (triggered) {
        _projectilesRoot.remove(banana.node);
        _activeBananas.removeAt(i);
      }
    }
  }

  void _updateSlipstreamDrafting(double dt) {
    for (final follower in karts) {
      if (follower.forwardSpeed < 10.5 || follower.boostTimer > 0.0) {
        follower.draftCharge = math.max(0.0, follower.draftCharge - dt * 0.6);
        continue;
      }

      var inDraftPocket = false;
      for (final leader in karts) {
        if (identical(follower, leader)) continue;
        final toLeader = leader.position - follower.position;
        final dist = toLeader.length;
        if (dist > 3.2 && dist < 13.5) {
          final forwardDot = follower.forwardDir.dot(toLeader / dist);
          if (forwardDot > 0.90) {
            inDraftPocket = true;
            break;
          }
        }
      }

      if (inDraftPocket) {
        follower.draftCharge += dt;
        if (follower.draftCharge >= 1.15) {
          follower.draftCharge = 0.0;
          follower.triggerBoost(duration: 1.05, bonusSpeed: 4.4);
          if (follower.isPlayer) {
            _showBanner('SLIPSTREAM DRAFT!', duration: 1.3);
            _cameraShake.addTrauma(0.25);
            _triggerScreenPulse(strength: 0.020);
            _sfx.play(ArcadeSfx.boost);
          }
        }
      } else {
        follower.draftCharge = math.max(0.0, follower.draftCharge - dt * 0.5);
      }
    }
  }

  void _updateTrackInteractables(double dt) {
    // 1. Boost pads (only trigger when tires are near the road surface)
    for (final pad in track.boostPads) {
      for (final kart in karts) {
        if (kart.hopHeight > 0.32) continue;
        final dx = kart.position.x - pad.position.x;
        final dz = kart.position.z - pad.position.z;
        if (dx * dx + dz * dz < 11.5) {
          final wasBoosting = kart.boostTimer > 0.2;
          kart.triggerBoost(duration: 1.00, bonusSpeed: 5.2);
          if (kart.isPlayer && !wasBoosting) {
            _showBanner('BOOST PAD!', duration: 1.0);
            _cameraShake.addTrauma(0.22);
            _triggerScreenPulse(strength: 0.022);
            _sfx.play(ArcadeSfx.boost);
          }
        }
      }
    }

    // 1b. 3D Aero Jump Ramps & 360° Aerial Trick Launches
    for (final ramp in track.jumpRamps) {
      for (final kart in karts) {
        if (kart.rampCooldown > 0.0 ||
            kart.forwardSpeed < 6.0 ||
            kart.hopHeight > 0.35) {
          continue;
        }
        final rel = vm.Vector3(
          kart.position.x - ramp.position.x,
          0.0,
          kart.position.z - ramp.position.z,
        );
        final along = rel.dot(ramp.tangent);
        final across = rel.dot(ramp.right);
        if (along.abs() < ramp.length * 0.52 &&
            across.abs() < ramp.width * 0.55) {
          final wantTrick = kart.isPlayer
              ? (kart.input.driftHeld || kart.isDrifting)
              : (_rng.nextDouble() < 0.72);
          final armedTrick = kart.launchOffRamp(performTrick: wantTrick);
          kart.triggerBoost(duration: 0.85, bonusSpeed: 3.8);
          if (kart.isPlayer) {
            if (armedTrick) {
              _showBanner('360° AERIAL TRICK! +BOOST', duration: 1.4);
            } else {
              _showBanner('AERO RAMP! (TAP DRIFT FOR TRICK!)', duration: 1.3);
            }
            _cameraShake.addTrauma(0.26);
            _triggerScreenPulse(strength: 0.022);
            _sfx.play(ArcadeSfx.jumpTrick);
          }
        }
      }
    }

    // 2. Floating Item Boxes (generous pickup radius)
    for (var i = 0; i < track.itemBoxes.length; i++) {
      final box = track.itemBoxes[i];
      if (box.respawnTimer > 0.0) {
        box.respawnTimer = math.max(0.0, box.respawnTimer - dt);
        if (box.respawnTimer <= 0.0) {
          box.node?.visible = true;
        }
        continue;
      }

      // Check pickup by any kart
      for (final kart in karts) {
        final dx = kart.position.x - box.basePosition.x;
        final dz = kart.position.z - box.basePosition.z;
        if (dx * dx + dz * dz < 4.8) {
          box.respawnTimer = 4.2;
          box.node?.visible = false;
          if (kart.heldItem == KartItemType.none) {
            _grantRandomItem(kart);
          }
          if (kart.isPlayer) {
            _sfx.play(ArcadeSfx.itemPickup);
          }
          break;
        }
      }
    }

    // 3. Spinning 3D Gold Coins (+0.8% top speed per coin, up to +8%)
    for (var i = 0; i < track.coins.length; i++) {
      final coin = track.coins[i];
      if (coin.respawnTimer > 0.0) {
        coin.respawnTimer = math.max(0.0, coin.respawnTimer - dt);
        if (coin.respawnTimer <= 0.0) {
          coin.node?.visible = true;
        }
        continue;
      }

      for (final kart in karts) {
        final dx = kart.position.x - coin.basePosition.x;
        final dz = kart.position.z - coin.basePosition.z;
        if (dx * dx + dz * dz < 3.8) {
          coin.respawnTimer = 7.5;
          coin.node?.visible = false;
          if (kart.coins < KartRacer.maxCoins) {
            kart.coins++;
          }
          // Small instant speed kick on coin pickup
          kart.forwardSpeed = math.min(
            kart.forwardSpeed + 1.2,
            KartRacer.baseMaxSpeed * 1.12,
          );
          if (kart.isPlayer) {
            _sfx.play(ArcadeSfx.coin);
          }
          break;
        }
      }
    }

    // 4. Track Obstacles (Cones & Oil Slicks — airborne karts fly cleanly over!)
    for (final obs in track.obstacles) {
      if (obs.hitCooldown > 0.0) {
        obs.hitCooldown = math.max(0.0, obs.hitCooldown - dt);
        continue;
      }
      for (final kart in karts) {
        // Oil slicks are flat on the asphalt (y=0.02); cones are ~0.6m tall.
        // If the kart is flying in the air from a Jump Ramp or hop, it clears them!
        final clearanceHeight =
            obs.kind == ObstacleKind.oilSlick ? 0.20 : 0.62;
        if (kart.hopHeight > clearanceHeight) continue;

        final dx = kart.position.x - obs.position.x;
        final dz = kart.position.z - obs.position.z;
        final hitRadius = obs.radius + 0.65;
        if (dx * dx + dz * dz < hitRadius * hitRadius) {
          obs.hitCooldown = 1.5;
          if (kart.shieldTimer > 0.0) {
            if (kart.isPlayer) _showBanner('BLOCKED BY SHIELD!', duration: 1.0);
            continue;
          }
          if (obs.kind == ObstacleKind.oilSlick) {
            kart.triggerSpinOut();
            if (kart.isPlayer) {
              _showBanner('OIL SLICK SPIN-OUT!', duration: 1.4);
              _cameraShake.addTrauma(0.42);
              _sfx.play(ArcadeSfx.impact);
            }
          } else {
            kart.forwardSpeed *= 0.72;
            if (kart.isPlayer) {
              _showBanner('CONE IMPACT!', duration: 1.0);
              _cameraShake.addTrauma(0.28);
              _sfx.play(ArcadeSfx.impact);
            }
          }
        }
      }
    }
  }

  void _grantRandomItem(KartRacer kart) {
    final roll = _rng.nextDouble();
    if (kart.raceRank == 1) {
      if (roll < 0.35) {
        kart.heldItem = KartItemType.bananaHazard;
      } else if (roll < 0.65) {
        kart.heldItem = KartItemType.turboMushroom;
      } else if (roll < 0.90) {
        kart.heldItem = KartItemType.energyShield;
      } else {
        kart.heldItem = KartItemType.homingShell;
      }
    } else {
      if (roll < 0.28) {
        kart.heldItem = KartItemType.homingShell;
      } else if (roll < 0.56) {
        kart.heldItem = KartItemType.tripleTurbo;
        kart.remainingTripleBoosts = 3;
      } else if (roll < 0.78) {
        kart.heldItem = KartItemType.turboMushroom;
      } else if (roll < 0.92) {
        kart.heldItem = KartItemType.empShockwave;
      } else {
        kart.heldItem = KartItemType.energyShield;
      }
    }
  }

  void _resolveKartCollisions() {
    const minSeparation = 1.85;
    for (var i = 0; i < karts.length; i++) {
      for (var j = i + 1; j < karts.length; j++) {
        final a = karts[i];
        final b = karts[j];
        final diff = vm.Vector3(
          b.position.x - a.position.x,
          0.0,
          b.position.z - a.position.z,
        );
        final dist = diff.length;
        if (dist > 1e-4 && dist < minSeparation) {
          final normal = diff / dist;
          final overlap = (minSeparation - dist) * 0.5;
          a.position -= normal * overlap;
          b.position += normal * overlap;

          // Elastic bump impulse
          a.externalVelocity -= normal * 5.0;
          b.externalVelocity += normal * 5.0;

          if (a.isPlayer || b.isPlayer) {
            _cameraShake.addTrauma(0.18);
          }
        }
      }
    }
  }

  void _updateRaceStandings() {
    final sorted = List<KartRacer>.from(karts)
      ..sort((a, b) {
        if (a.isFinished && b.isFinished) {
          return a.finishTime.compareTo(b.finishTime);
        }
        if (a.isFinished) return -1;
        if (b.isFinished) return 1;
        return b.totalProgress.compareTo(a.totalProgress);
      });

    for (var i = 0; i < sorted.length; i++) {
      sorted[i].raceRank = i + 1;
    }
  }

  void _snapCameraToPlayer() {
    final p = playerKart;
    _cameraOrbitYaw = p.yaw;
    final forward = vm.Vector3(
      math.sin(_cameraOrbitYaw),
      0,
      math.cos(_cameraOrbitYaw),
    );
    _smoothedCamEye =
      p.position -
      forward * cameraPreset.distance +
      vm.Vector3(0, cameraPreset.height, 0);
    _smoothedCamTarget =
      p.position +
      forward * cameraPreset.lookAhead +
      vm.Vector3(0, 1.32, 0);
    _cameraNode.lookAtFrom(_smoothedCamEye, _smoothedCamTarget);
  }

  /// Title Screen 3D Camera: either a close-up Paddock Hero Turntable orbiting
  /// the selected mascot kart on the starting grid, or a sweeping Aerial
  /// Circuit Flyover when `titleFlyoverMode` is enabled.
  void _updateTitleScreenCamera(double dt) {
    final p = playerKart;
    vm.Vector3 desiredEye;
    vm.Vector3 desiredTarget;

    if (titleFlyoverMode) {
      // Sweeping aerial drone orbit around the circuit & Crystal Lagoon
      final flyDist = (_titleOrbitClock * 22.0) % track.totalLength;
      final sample = track.sampleAtDistance(flyDist);
      final lookSample = track.sampleAtDistance(flyDist + 28.0);
      desiredEye =
          sample.position +
          sample.right * (math.sin(_titleOrbitClock * 0.45) * 14.0) +
          vm.Vector3(0, 15.0 + math.cos(_titleOrbitClock * 0.6) * 4.0, 0);
      desiredTarget = lookSample.position + vm.Vector3(0, 2.5, 0);
    } else {
      // Paddock Hero Turntable orbiting the player's selected mascot driver
      // (oscillates around a front-3/4 angle so Dash/Llama face the camera!)
      final heroAngle =
          p.yaw +
          math.pi * 0.76 +
          math.sin(_titleOrbitClock * 0.65) * 0.52;
      const radius = 3.85;
      desiredEye =
          p.position +
          vm.Vector3(
            math.sin(heroAngle) * radius,
            1.68 + math.sin(_titleOrbitClock * 0.9) * 0.16,
            math.cos(heroAngle) * radius,
          );
      desiredTarget = p.position + vm.Vector3(0, 1.18, 0);
    }

    final blend = (6.5 * dt).clamp(0.0, 1.0);
    _smoothedCamEye += (desiredEye - _smoothedCamEye) * blend;
    _smoothedCamTarget += (desiredTarget - _smoothedCamTarget) * blend;
    _cameraNode.lookAtFrom(_smoothedCamEye, _smoothedCamTarget);
    _cameraProjection.fovRadiansY = 50.0 * vm.degrees2Radians;
  }

  /// 4-Shot Pre-Race Director's Cutscene (8.8s total):
  /// - Shot 1 (0.0–2.2s): Crane descent from Start/Finish Gantry over the grid
  /// - Shot 2 (2.2–4.4s): Low helicopter skim across Crystal Lagoon & Turn 1
  /// - Shot 3 (4.4–6.6s): Dramatic low-angle dolly pan across the 4 mascot karts
  /// - Shot 4 (6.6–8.8s): Hero 360° sweep into the player's rear chase position
  void _updateIntroCutsceneCamera(double dt) {
    final t = _cutsceneClock;
    final p = playerKart;

    if (t < 2.2) {
      // Shot 1: Sweeping crane shot descending from the Grand Prix Gantry
      final u = (t / 2.2).clamp(0.0, 1.0);
      final smoothU = u * u * (3.0 - 2.0 * u);
      final eye = vm.Vector3(
        -10.0 + smoothU * 16.0,
        14.5 - smoothU * 8.5,
        24.0 - smoothU * 22.0,
      );
      final target = vm.Vector3(
        0.0,
        1.8 - smoothU * 0.5,
        -8.5,
      );
      _smoothedCamEye = eye;
      _smoothedCamTarget = target;
      _cameraProjection.fovRadiansY = 54.0 * vm.degrees2Radians;
    } else if (t < 4.4) {
      // Shot 2: High-speed helicopter tracking shot skimming Crystal Lagoon & Turn 1
      final u = ((t - 2.2) / 2.2).clamp(0.0, 1.0);
      final trackDist = 36.0 + u * 85.0;
      final sample = track.sampleAtDistance(trackDist);
      final aheadSample = track.sampleAtDistance(trackDist + 24.0);
      final eye =
          sample.position -
          sample.right * 8.5 +
          vm.Vector3(0, 5.2 + math.sin(u * math.pi) * 2.5, 0);
      // Pan from the turquoise Infield Lake spire toward the neon apex
      final lakeFocus = vm.Vector3(56.0, 4.5, 44.0);
      final roadFocus = aheadSample.position + vm.Vector3(0, 1.5, 0);
      final target = lakeFocus + (roadFocus - lakeFocus) * (0.35 + u * 0.65);
      _smoothedCamEye = eye;
      _smoothedCamTarget = target;
      _cameraProjection.fovRadiansY = 58.0 * vm.degrees2Radians;
    } else if (t < 6.6) {
      // Shot 3: Low-angle dolly pan across the 4 mascot karts revving on the grid
      final u = ((t - 4.4) / 2.2).clamp(0.0, 1.0);
      final smoothU = u * u * (3.0 - 2.0 * u);
      final llamaKart = karts.length > 1 ? karts[1] : p;
      final startFocus = llamaKart.position + vm.Vector3(0, 1.25, 0);
      final endFocus = p.position + vm.Vector3(0, 1.25, 0);
      final target = startFocus + (endFocus - startFocus) * smoothU;
      final eye = vm.Vector3(
        3.8 - smoothU * 7.2,
        1.55 + math.sin(u * math.pi) * 0.25,
        -2.8 - smoothU * 2.2,
      );
      _smoothedCamEye = eye;
      _smoothedCamTarget = target;
      _cameraProjection.fovRadiansY = 48.0 * vm.degrees2Radians;
    } else {
      // Shot 4: Hero orbit from front-3/4 showcase into rear chase camera
      final u = ((t - 6.6) / 2.2).clamp(0.0, 1.0);
      final smoothU = u * u * (3.0 - 2.0 * u);
      final orbitYaw = p.yaw + (1.0 - smoothU) * (math.pi * 0.85);
      final forward = vm.Vector3(math.sin(orbitYaw), 0, math.cos(orbitYaw));
      final dist = 3.8 + smoothU * (cameraPreset.distance - 3.8);
      final height = 1.65 + smoothU * (cameraPreset.height - 1.65);
      _smoothedCamEye =
          p.position - forward * dist + vm.Vector3(0, height, 0);
      _smoothedCamTarget =
          p.position +
          forward * (smoothU * cameraPreset.lookAhead) +
          vm.Vector3(0, 1.28, 0);
      _cameraOrbitYaw = orbitYaw;
      _cameraProjection.fovRadiansY = 53.0 * vm.degrees2Radians;
    }

    _cameraNode.lookAtFrom(_smoothedCamEye, _smoothedCamTarget);
  }

  /// Post-Race Victory Podium / Champion Broadcast Cutscene Camera:
  /// Orbits the player's kart as it cruises a celebratory victory lap.
  void _updateVictoryCutsceneCamera(double dt) {
    final p = playerKart;
    final orbitAngle = p.yaw + math.pi * 0.72 + _victoryClock * 0.55;
    const radius = 4.4;
    final desiredEye =
        p.position +
        vm.Vector3(
          math.sin(orbitAngle) * radius,
          1.85 + math.sin(_victoryClock * 1.1) * 0.35,
          math.cos(orbitAngle) * radius,
        );
    final desiredTarget = p.position + vm.Vector3(0, 1.25, 0);

    final blend = (8.0 * dt).clamp(0.0, 1.0);
    _smoothedCamEye += (desiredEye - _smoothedCamEye) * blend;
    _smoothedCamTarget += (desiredTarget - _smoothedCamTarget) * blend;
    _cameraNode.lookAtFrom(_smoothedCamEye, _smoothedCamTarget);
    _cameraProjection.fovRadiansY = 50.0 * vm.degrees2Radians;
  }

  /// Live TV Broadcast Director Camera: alternates between trackside panning
  /// tripod cameras and a low helicopter chase shot following the player.
  void _updateDirectorBroadcastCamera(double dt) {
    final p = playerKart;
    // Place a virtual trackside broadcast tripod every 65 meters along the circuit
    const segmentLen = 65.0;
    final tripodDist =
        ((p.trackDistance ~/ segmentLen) * segmentLen + segmentLen * 0.55) %
        track.totalLength;
    final tripodSample = track.sampleAtDistance(tripodDist);
    final sideSign = ((p.trackDistance ~/ segmentLen).isEven) ? 1.0 : -1.0;

    final tripodEye =
        tripodSample.position +
        tripodSample.right * (sideSign * 11.5) +
        vm.Vector3(0, 3.8, 0);
    final target = p.position + vm.Vector3(0, 1.2, 0);

    _smoothedCamEye = tripodEye;
    final blend = (14.0 * dt).clamp(0.0, 1.0);
    _smoothedCamTarget += (target - _smoothedCamTarget) * blend;
    _cameraNode.lookAtFrom(_smoothedCamEye, _smoothedCamTarget);

    // Subtle broadcast telephoto zoom as kart approaches/passes tripod
    final distToTripod = (p.position - tripodEye).length;
    final fovDeg = (62.0 - (distToTripod * 0.35).clamp(0.0, 22.0));
    _cameraProjection.fovRadiansY = fovDeg * vm.degrees2Radians;
  }

  void _updateChaseCamera(double dt) {
    final p = playerKart;

    // During the first part of the 3-2-1 countdown (or right after switching
    // characters while stationary), orbit from a front-3/4 hero showcase angle
    // so the player gets a close-up look at Flutter Dash & Turbo Llama!
    var introFrontAngleOffset = 0.0;
    if (countdownTimer > 0.75) {
      final t = ((countdownTimer - 0.75) / 2.2).clamp(0.0, 1.0);
      final smoothT = t * t * (3.0 - 2.0 * t);
      introFrontAngleOffset = smoothT * (math.pi * 0.80);
    } else if (_characterShowcaseTimer > 0.0) {
      final t = (_characterShowcaseTimer / 1.1).clamp(0.0, 1.0);
      final smoothT = math.sin(t * math.pi);
      introFrontAngleOffset = smoothT * (math.pi * 0.78);
    }

    // Smoothly lag the camera yaw behind the kart's heading + slight drift swing
    final targetYaw =
        p.yaw +
        introFrontAngleOffset +
        (p.isDrifting ? p.driftDirection * 0.14 : 0.0);
    var yawDiff = (targetYaw - _cameraOrbitYaw) % (2.0 * math.pi);
    if (yawDiff > math.pi) yawDiff -= 2.0 * math.pi;
    if (yawDiff < -math.pi) yawDiff += 2.0 * math.pi;
    _cameraOrbitYaw += yawDiff * (9.5 * dt).clamp(0.0, 1.0);

    final camForward = vm.Vector3(
      math.sin(_cameraOrbitYaw),
      0.0,
      math.cos(_cameraOrbitYaw),
    );

    // Pull back slightly and widen FOV when boosting; support Look-Back / Front Hero toggle
    final boostFactor = p.boostTimer > 0.0 ? 1.0 : 0.0;
    final activePreset = isLookBackHeld
        ? CameraPreset.frontShowcase
        : cameraPreset;
    final desiredDist =
        activePreset.distance +
        (activePreset.distance > 0 ? boostFactor * 0.85 : 0.0);

    final desiredEye =
        p.position -
        camForward * desiredDist +
        vm.Vector3(0, activePreset.height + p.hopHeight * 0.35, 0);
    final desiredTarget =
        p.position +
        camForward *
            (introFrontAngleOffset > 0.15 ? 0.0 : activePreset.lookAhead) +
        vm.Vector3(0, 1.28 + p.hopHeight * 0.25, 0);

    final posBlend = (13.5 * dt).clamp(0.0, 1.0);
    _smoothedCamEye += (desiredEye - _smoothedCamEye) * posBlend;
    _smoothedCamTarget += (desiredTarget - _smoothedCamTarget) * posBlend;

    // Apply CameraShake offset from flutter_scene/kit.dart
    final shakeOffset = _cameraShake.update(dt);
    final shakenEye = _smoothedCamEye + shakeOffset.translation;

    _cameraNode.lookAtFrom(shakenEye, _smoothedCamTarget);

    // Dynamic FOV punch during boosts for an exhilarating sense of speed!
    final targetFov =
        (53.0 +
            (p.forwardSpeed / KartRacer.baseMaxSpeed).clamp(0.0, 1.2) * 5.0 +
            boostFactor * 7.5) *
        vm.degrees2Radians;
    _cameraProjection.fovRadiansY +=
        (targetFov - _cameraProjection.fovRadiansY) *
        (8.0 * dt).clamp(0.0, 1.0);
  }

  bool isTrailerActive = false;

  void _placePackAtTrackFraction(double fraction) {
    final baseDist = (track.totalLength * fraction) % track.totalLength;
    const offsets = [
      (distOffset: 0.0, lat: 0.0, speed: 20.5),
      (distOffset: 5.5, lat: -2.2, speed: 19.2),
      (distOffset: -4.5, lat: 2.1, speed: 19.8),
      (distOffset: 9.0, lat: 1.8, speed: 18.8),
    ];
    for (var i = 0; i < karts.length; i++) {
      final k = karts[i];
      final o = offsets[i % offsets.length];
      final d = (baseDist + o.distOffset) % track.totalLength;
      final sample = track.sampleAtDistance(d);
      k.position = sample.position + sample.right * o.lat;
      k.yaw = math.atan2(sample.tangent.x, sample.tangent.z);
      k.forwardSpeed = o.speed;
      k.lateralVelocity = 0.0;
      k.trackDistance = d;
      k.totalProgress = track.totalLength + d;
      k.currentLap = 2;
      k.hopHeight = 0.0;
      k.hopVerticalVel = 0.0;
      k.spinOutTimer = 0.0;
      k.syncVisualTransforms(0.016);
    }
    _snapCameraToPlayer();
  }

  /// Advances one deterministic 30 FPS frame of the official 15-second (450-frame)
  /// Gameplay & Cinematic Trailer Showcase.
  void stepTrailerFrame(int frame) {
    const dt = 1.0 / 30.0;
    isTrailerActive = true;

    if (frame == 0) {
      returnToTitleScreen();
      selectPlayerCharacter(RacerCharacter.flutterDash);
      _titleOrbitClock = 0.25;
    } else if (frame == 32) {
      selectPlayerCharacter(RacerCharacter.llama);
    } else if (frame == 52) {
      selectPlayerCharacter(RacerCharacter.flutterDash);
    } else if (frame == 60) {
      startGrandPrixWithCutscene();
      _cutsceneClock = 2.25; // Shot 2: Crystal Lagoon & Aero Ramps
    } else if (frame == 96) {
      _cutsceneClock = 4.55; // Shot 3: Mascot Grid Showdown
    } else if (frame == 132) {
      skipCutsceneAndStartRace();
      countdownTimer = 0.85; // Show "1" -> "GO!!"
      playerKart.rocketStartCharge = 0.65;
    } else if (frame == 245) {
      selectPlayerCharacter(RacerCharacter.llama);
      _characterShowcaseTimer = 0.0;
      isDirectorCamActive = false;
      isLookBackHeld = false;
      _placePackAtTrackFraction(0.212); // Approach Aero Jump Ramp #1 (0.24)
      playerKart.coins = 6;
    } else if (frame == 315) {
      selectPlayerCharacter(RacerCharacter.flutterDash);
      _characterShowcaseTimer = 0.0;
      isDirectorCamActive = false;
      isLookBackHeld = false;
      _placePackAtTrackFraction(0.435);
      playerKart.coins = 9;
      playerKart.heldItem = KartItemType.homingShell;
    } else if (frame == 326) {
      triggerPlayerUseItem();
    } else if (frame == 352) {
      isDirectorCamActive = true;
      _showBanner('LIVE TV DIRECTOR CAM!', duration: 1.4);
    } else if (frame == 384) {
      isDirectorCamActive = false;
      isLookBackHeld = true;
      playerKart.currentLap = totalLaps;
      playerKart.triggerBoost(duration: 1.5, bonusSpeed: 5.2);
      _showBanner('FINAL LAP OVERDRIVE!', duration: 1.4);
    } else if (frame == 410) {
      isDirectorCamActive = false;
      isLookBackHeld = false;
      phase = GamePhase.victoryCutscene;
      playerKart.isFinished = true;
      playerKart.raceRank = 1;
      playerKart.finishTime = 58.42;
      playerKart.bestLapTime = 18.94;
      _victoryClock = 0.35;
      _showBanner('1ST PLACE — GRAND PRIX CHAMPION!', duration: 4.0);
    }

    // Drive the player kart with pro AI steering during racing segments
    if (phase == GamePhase.racing && countdownTimer <= 0.0) {
      playerKart.updateAiInput(track, karts, dt, _rng);
      playerKart.input.throttle = 1.0;
      playerKart.input.brake = 0.0;

      // Showcase Blue -> Orange -> Purple drift sparks around Turn 1
      if (frame >= 188 && frame <= 222) {
        playerKart.input.driftHeld = true;
        playerKart.isDrifting = true;
        playerKart.driftDirection = -1;
        playerKart.driftCharge = (frame - 188) * 0.065;
      } else if (frame == 223) {
        playerKart.input.driftHeld = false;
      } else if (frame >= 248 && frame <= 285) {
        // Hold drift while hitting Aero Jump Ramp #1 to arm 360° Aerial Trick!
        playerKart.input.driftHeld = true;
        playerKart.input.steer = 0.0;
      } else {
        playerKart.input.driftHeld = false;
      }
    }

    tick(dt);
  }

  void stopTrailerShowcase() {
    isTrailerActive = false;
    isDirectorCamActive = false;
    isLookBackHeld = false;
    returnToTitleScreen();
  }

  @override
  void dispose() {
    _sfx.setBgmState(playing: false);
    super.dispose();
  }

  static String _ordinal(int rank) => switch (rank) {
    1 => '1ST',
    2 => '2ND',
    3 => '3RD',
    _ => '${rank}TH',
  };
}
