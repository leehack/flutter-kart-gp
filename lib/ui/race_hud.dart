import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../game/kart_builder.dart';
import '../game/kart_physics.dart';
import '../game/kart_race_game.dart';
import '../game/sound_manager.dart';
import '../game/track_data.dart';

class RaceHudOverlay extends StatelessWidget {
  const RaceHudOverlay({
    super.key,
    required this.game,
    required this.showTouchControls,
    required this.onToggleTouchControls,
    required this.onTouchSteerChanged,
    required this.onTouchGasChanged,
    required this.onTouchBrakeChanged,
    required this.onTouchDriftChanged,
    required this.onUseItem,
  });

  final KartRaceGame game;
  final bool showTouchControls;
  final VoidCallback onToggleTouchControls;
  final ValueChanged<double> onTouchSteerChanged;
  final ValueChanged<bool> onTouchGasChanged;
  final ValueChanged<bool> onTouchBrakeChanged;
  final ValueChanged<bool> onTouchDriftChanged;
  final VoidCallback onUseItem;

  @override
  Widget build(BuildContext context) {
    if (game.phase == GamePhase.titleScreen) {
      return _TitleScreenOverlay(game: game);
    }

    if (game.phase == GamePhase.introCutscene) {
      return _IntroCutsceneOverlay(game: game);
    }

    final player = game.playerKart;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < 780 || constraints.maxHeight < 520;

          return Padding(
            padding: EdgeInsets.all(isCompact ? 8 : 14),
            child: Stack(
              children: [
                // 1. Top-Left: Position Badge + Lap/Timers + Driver Selector + Assist Chips
                Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _RankBadge(rank: player.raceRank, compact: isCompact),
                          const SizedBox(width: 10),
                          _LapAndTimersCard(
                            lap: player.currentLap,
                            totalLaps: KartRaceGame.totalLaps,
                            currentLapTime: player.currentLapTime,
                            bestLapTime: player.bestLapTime,
                            coins: player.coins,
                            compact: isCompact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (!isCompact)
                            _CharacterSelectorPill(
                              selected: game.selectedCharacter,
                              onSelect: game.selectPlayerCharacter,
                            ),
                          _AssistToggleChip(
                            label: 'SMART STEER',
                            icon: Icons.auto_fix_high_rounded,
                            active: game.smartSteerEnabled,
                            activeColor: const Color(0xFF00E676),
                            onTap: game.toggleSmartSteer,
                          ),
                          _AssistToggleChip(
                            label: 'AUTO-GAS',
                            icon: Icons.speed_rounded,
                            active: game.autoAccelerate,
                            activeColor: const Color(0xFF29B6F6),
                            onTap: game.toggleAutoAccelerate,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 2. Top-Center: Arcade Item Box Slot + TV Broadcast Indicator
                Align(
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ItemSlotCard(
                        heldItem: player.heldItem,
                        tripleCount: player.remainingTripleBoosts,
                        onTap: onUseItem,
                        compact: isCompact,
                      ),
                      if (game.isDirectorCamActive) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xDD1A0F1D),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFF5252),
                              width: 1.5,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fiber_manual_record_rounded,
                                color: Color(0xFFFF5252),
                                size: 12,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'LIVE TV DIRECTOR CAM (V)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 3. Top-Right: Circuit Minimap + Quick Action Toolbar
                Align(
                  alignment: Alignment.topRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isCompact || constraints.maxWidth > 620)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _CircuitMinimap(
                            track: game.track,
                            karts: game.karts,
                            size: isCompact ? 112 : 148,
                          ),
                        ),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        alignment: WrapAlignment.end,
                        children: [
                          _SmallHudIconButton(
                            icon: game.isSoundMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            tooltip: 'Toggle Arcade SFX & Audio (M)',
                            isActive: !game.isSoundMuted,
                            onPressed: game.toggleSoundMute,
                          ),
                          _SmallHudIconButton(
                            icon: Icons.music_note_rounded,
                            tooltip:
                                'Cycle Soundtrack: ${game.bgmTrack.label} (L)',
                            isActive: game.bgmTrack != BgmTrack.off &&
                                !game.isSoundMuted,
                            onPressed: game.cycleBgmTrack,
                          ),
                          _SmallHudIconButton(
                            icon: Icons.live_tv_rounded,
                            tooltip: 'TV Broadcast Camera (V)',
                            isActive: game.isDirectorCamActive,
                            onPressed: game.toggleDirectorCam,
                          ),
                          _SmallHudIconButton(
                            icon: Icons.flip_camera_android_rounded,
                            tooltip: 'Front Hero View / Look-Back (B)',
                            isActive: game.isLookBackHeld,
                            onPressed: game.toggleLookBack,
                          ),
                          _SmallHudIconButton(
                            icon: Icons.videocam_rounded,
                            tooltip: 'Camera Preset (C)',
                            onPressed: game.cycleCameraPreset,
                          ),
                          _SmallHudIconButton(
                            icon: Icons.u_turn_left_rounded,
                            tooltip: 'Reset to Track (R)',
                            onPressed: game.resetPlayerToTrack,
                          ),
                          _SmallHudIconButton(
                            icon: showTouchControls
                                ? Icons.gamepad_rounded
                                : Icons.gamepad_outlined,
                            tooltip: 'Toggle On-Screen Mobile Controls',
                            isActive: showTouchControls,
                            onPressed: onToggleTouchControls,
                          ),
                          _SmallHudIconButton(
                            icon: game.isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            tooltip: 'Pause / Resume (P)',
                            isActive: game.isPaused,
                            onPressed: game.togglePause,
                          ),
                          _SmallHudIconButton(
                            icon: Icons.refresh_rounded,
                            tooltip: 'Restart Race',
                            onPressed: game.restartRace,
                          ),
                          _SmallHudIconButton(
                            icon: Icons.home_rounded,
                            tooltip: 'Return to Title Screen',
                            onPressed: game.returnToTitleScreen,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 4. Center Countdown / Event Banner
                Align(
                  alignment: Alignment.center,
                  child: IgnorePointer(
                    child: _CenterRaceBanners(game: game),
                  ),
                ),

                // 5. Bottom-Center: Speedometer, Drift Turbo Gauge & Key Hints
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _SpeedAndDriftCluster(
                    player: player,
                    compact: isCompact,
                    smartSteerEnabled: game.smartSteerEnabled,
                  ),
                ),

                // 6. Bottom-Left & Bottom-Right: Zero-Slop Multi-Touch Steering & Pedals
                if (showTouchControls && !game.isRaceFinished && !game.isPaused) ...[
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: _TouchSteeringPad(
                      compact: isCompact,
                      onSteerChanged: onTouchSteerChanged,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: _TouchActionPedals(
                      compact: isCompact,
                      hasItem: player.heldItem != KartItemType.none,
                      autoGasActive: game.autoAccelerate,
                      onGasChanged: onTouchGasChanged,
                      onBrakeChanged: onTouchBrakeChanged,
                      onDriftChanged: onTouchDriftChanged,
                      onUseItem: onUseItem,
                    ),
                  ),
                ],

                // 7. Pause Menu Modal
                if (game.isPaused && !game.isRaceFinished)
                  Align(
                    alignment: Alignment.center,
                    child: _PauseMenuModal(game: game),
                  ),

                // 8. Race Finished Summary & Podium Cutscene Modal
                if (game.isRaceFinished)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: isCompact ? 8 : 24),
                      child: _RaceResultsModal(game: game),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TitleScreenOverlay extends StatelessWidget {
  const _TitleScreenOverlay({required this.game});
  final KartRaceGame game;

  static const _characterSpecs = <({
    RacerCharacter character,
    String title,
    String subtitle,
    Color color,
    IconData icon,
    double speedStat,
    double handlingStat,
    double boostStat,
  })>[
    (
      character: RacerCharacter.flutterDash,
      title: 'FLUTTER DASH',
      subtitle: 'Aero Wing Racer • Balanced Apex Precision',
      color: Color(0xFF29B6F6),
      icon: Icons.flutter_dash_rounded,
      speedStat: 0.88,
      handlingStat: 0.96,
      boostStat: 0.92,
    ),
    (
      character: RacerCharacter.llama,
      title: 'TURBO LLAMA',
      subtitle: 'Andean Wool Rocket • High Drift Boost Torque',
      color: Color(0xFFFFB300),
      icon: Icons.pets_rounded,
      speedStat: 0.94,
      handlingStat: 0.88,
      boostStat: 0.95,
    ),
    (
      character: RacerCharacter.androidBot,
      title: 'BUGDROID BOT',
      subtitle: 'Cybernetic Grip Chassis • Cornering Specialist',
      color: Color(0xFF00E676),
      icon: Icons.adb_rounded,
      speedStat: 0.86,
      handlingStat: 0.98,
      boostStat: 0.88,
    ),
    (
      character: RacerCharacter.chromeDino,
      title: 'BLAZE DINO',
      subtitle: 'Volcanic V8 Monster • Top-End Straightaway Speed',
      color: Color(0xFFFF5252),
      icon: Icons.local_fire_department_rounded,
      speedStat: 0.97,
      handlingStat: 0.84,
      boostStat: 0.90,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = game.selectedCharacter;
    final activeSpec = _characterSpecs.firstWhere(
      (s) => s.character == selected,
      orElse: () => _characterSpecs.first,
    );

    return Stack(
      children: [
        // Subtle top & bottom cinematic gradient vignettes so UI pops over 3D scene
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.58),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                  stops: const [0.0, 0.24, 0.62, 1.0],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact =
                  constraints.maxWidth < 760 || constraints.maxHeight < 540;

              return Padding(
                padding: EdgeInsets.all(isCompact ? 12 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Header Row: Title Logo + Camera View Toggle
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0288D1)
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF29B6F6),
                                  ),
                                ),
                                child: const Text(
                                  'FLUTTER SCENE 3D ENGINE • SAPPHIRE BAY GRAND PRIX',
                                  style: TextStyle(
                                    color: Color(0xFF81D4FA),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'FLUTTER KART GP',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isCompact ? 30 : 44,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: 1.5,
                                  height: 1.0,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0xFF0288D1),
                                      blurRadius: 20,
                                    ),
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 10,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Camera Showcase Toggle Button
                        Material(
                          color: const Color(0xCC0F141D),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: game.toggleTitleCameraMode,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: game.titleFlyoverMode
                                      ? const Color(0xFFFFD54F)
                                      : Colors.white30,
                                  width: 1.6,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    game.titleFlyoverMode
                                        ? Icons.flight_rounded
                                        : Icons.threed_rotation_rounded,
                                    color: game.titleFlyoverMode
                                        ? const Color(0xFFFFD54F)
                                        : const Color(0xFF29B6F6),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    game.titleFlyoverMode
                                        ? 'CIRCUIT FLYOVER CAM'
                                        : 'PADDOCK TURNTABLE CAM',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // Bottom Interactive Dock: Driver Cards + Stats/Assists + Start CTA
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        // Left: 4-Driver Selection Grid + Active Driver Stat Bars
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isCompact
                                ? constraints.maxWidth
                                : math.min(540, constraints.maxWidth * 0.56),
                          ),
                          child: Container(
                            padding: EdgeInsets.all(isCompact ? 12 : 16),
                            decoration: BoxDecoration(
                              color: const Color(0xDD0D131C),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: activeSpec.color.withValues(alpha: 0.7),
                                width: 1.8,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black87,
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      activeSpec.icon,
                                      color: activeSpec.color,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'SELECT YOUR MASCOT RACER',
                                            style: TextStyle(
                                              color: activeSpec.color,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          Text(
                                            '${activeSpec.title} — ${activeSpec.subtitle}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // 4 Character Buttons
                                Row(
                                  children: [
                                    for (final spec in _characterSpecs)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          child: _DriverSelectCard(
                                            title: spec.title.split(' ').last,
                                            icon: spec.icon,
                                            color: spec.color,
                                            selected:
                                                spec.character == selected,
                                            onTap: () =>
                                                game.selectPlayerCharacter(
                                                  spec.character,
                                                ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (!isCompact) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _MiniStatBar(
                                          label: 'TOP SPEED',
                                          value: activeSpec.speedStat,
                                          color: activeSpec.color,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _MiniStatBar(
                                          label: 'CORNERING',
                                          value: activeSpec.handlingStat,
                                          color: activeSpec.color,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _MiniStatBar(
                                          label: 'TURBO BOOST',
                                          value: activeSpec.boostStat,
                                          color: activeSpec.color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // Right: Track Theme, Speed Class, Driving Assists + Launch Buttons
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isCompact
                                ? constraints.maxWidth
                                : math.min(410, constraints.maxWidth * 0.42),
                          ),
                          child: Container(
                            padding: EdgeInsets.all(isCompact ? 12 : 16),
                            decoration: BoxDecoration(
                              color: const Color(0xDD0D131C),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFFFD54F)
                                    .withValues(alpha: 0.7),
                                width: 1.8,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black87,
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Soundtrack & Engine Class Selector
                                const Text(
                                  'SOUNDTRACK & ENGINE CLASS',
                                  style: TextStyle(
                                    color: Color(0xFFFFD54F),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    for (final track in BgmTrack.values)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2.5,
                                          ),
                                          child: _CompactOptionPill(
                                            label: track.shortLabel,
                                            selected: game.bgmTrack == track,
                                            activeColor: const Color(0xFFFFB300),
                                            onTap: () =>
                                                game.selectBgmTrack(track),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    for (final cc in SpeedClass.values)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2.5,
                                          ),
                                          child: _CompactOptionPill(
                                            label: cc.label,
                                            selected: game.speedClass == cc,
                                            activeColor: const Color(0xFF29B6F6),
                                            onTap: () =>
                                                game.selectSpeedClass(cc),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _AssistToggleChip(
                                        label: 'SMART STEER',
                                        icon: Icons.auto_fix_high_rounded,
                                        active: game.smartSteerEnabled,
                                        activeColor: const Color(0xFF00E676),
                                        onTap: game.toggleSmartSteer,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _AssistToggleChip(
                                        label: 'AUTO-GAS',
                                        icon: Icons.speed_rounded,
                                        active: game.autoAccelerate,
                                        activeColor: const Color(0xFF29B6F6),
                                        onTap: game.toggleAutoAccelerate,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFC107),
                                    foregroundColor: Colors.black,
                                    padding: EdgeInsets.symmetric(
                                      vertical: isCompact ? 12 : 15,
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 8,
                                  ),
                                  onPressed: game.startGrandPrixWithCutscene,
                                  icon: const Icon(
                                    Icons.movie_filter_rounded,
                                    size: 22,
                                  ),
                                  label: const Text(
                                    'START GRAND PRIX',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white38,
                                      width: 1.4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: game.skipCutsceneAndStartRace,
                                  icon: const Icon(
                                    Icons.bolt_rounded,
                                    size: 18,
                                    color: Color(0xFF29B6F6),
                                  ),
                                  label: const Text(
                                    'QUICK RACE (SKIP CUTSCENE)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.9,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompactOptionPill extends StatelessWidget {
  const _CompactOptionPill({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.25)
              : const Color(0xFF161E2B),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? activeColor : Colors.white24,
            width: selected ? 1.6 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _DriverSelectCard extends StatelessWidget {
  const _DriverSelectCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: selected ? 2.2 : 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? color : Colors.white70,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStatBar extends StatelessWidget {
  const _MiniStatBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _IntroCutsceneOverlay extends StatelessWidget {
  const _IntroCutsceneOverlay({required this.game});
  final KartRaceGame game;

  @override
  Widget build(BuildContext context) {
    final caption = game.currentCutsceneCaption;
    final shotIndex = game.currentCutsceneShotIndex;

    return Stack(
      children: [
        // Top Cinema Letterbox Bar
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 68,
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.86),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.fiber_manual_record_rounded,
                        color: Color(0xFFFF5252),
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'GRAND PRIX BROADCAST • CAMERA $shotIndex/4',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFFD54F),
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: game.skipCutsceneAndStartRace,
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: const Text(
                      'SKIP INTRO (SPACE)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bottom Cinema Letterbox Bar with Broadcast Lower-Third Caption
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 96,
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.88),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF29B6F6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              caption.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              caption.subtitle,
                              style: const TextStyle(
                                color: Color(0xFF81D4FA),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: game.cutsceneProgress,
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFD54F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssistToggleChip extends StatelessWidget {
  const _AssistToggleChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.22)
              : const Color(0xCC0F141D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? activeColor : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? activeColor : Colors.white54,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label: ${active ? "ON" : "OFF"}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white60,
                  fontSize: 10.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, this.compact = false});
  final int rank;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, suffix, color) = switch (rank) {
      1 => ('1', 'ST', const Color(0xFFFFD54F)),
      2 => ('2', 'ND', const Color(0xFFE0E0E0)),
      3 => ('3', 'RD', const Color(0xFFFFAB40)),
      _ => ('$rank', 'TH', const Color(0xFF90A4AE)),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xCC0F141D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.85), width: 2.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 32 : 42,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: color,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            suffix,
            style: TextStyle(
              fontSize: compact ? 14 : 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LapAndTimersCard extends StatelessWidget {
  const _LapAndTimersCard({
    required this.lap,
    required this.totalLaps,
    required this.currentLapTime,
    required this.bestLapTime,
    required this.coins,
    this.compact = false,
  });

  final int lap;
  final int totalLaps;
  final double currentLapTime;
  final double? bestLapTime;
  final int coins;
  final bool compact;

  static String _formatSeconds(double? sec) {
    if (sec == null) return '--:--.--';
    final mins = (sec ~/ 60).toString().padLeft(2, '0');
    final rem = (sec % 60).toStringAsFixed(2).padLeft(5, '0');
    return '$mins:$rem';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xCC0F141D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LAP $lap/$totalLaps',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x33FFD600),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD600)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: Color(0xFFFFD600),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$coins/10',
                      style: const TextStyle(
                        color: Color(0xFFFFD600),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'TIME  ${_formatSeconds(currentLapTime)}',
            style: const TextStyle(
              color: Color(0xFF81D4FA),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (!compact)
            Text(
              'BEST  ${_formatSeconds(bestLapTime)}',
              style: const TextStyle(
                color: Color(0xFFFFD54F),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemSlotCard extends StatelessWidget {
  const _ItemSlotCard({
    required this.heldItem,
    required this.tripleCount,
    required this.onTap,
    this.compact = false,
  });

  final KartItemType heldItem;
  final int tripleCount;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (heldItem) {
      KartItemType.none => ('ITEM BOX', Icons.help_outline_rounded, Colors.white38),
      KartItemType.turboMushroom => (
        'TURBO BOOST',
        Icons.rocket_launch_rounded,
        const Color(0xFFFF5252),
      ),
      KartItemType.tripleTurbo => (
        'TRIPLE TURBO x$tripleCount',
        Icons.bolt_rounded,
        const Color(0xFFFFAB00),
      ),
      KartItemType.homingShell => (
        'HOMING SHELL',
        Icons.gps_fixed_rounded,
        const Color(0xFF00E676),
      ),
      KartItemType.bananaHazard => (
        'BANANA TRAP',
        Icons.warning_amber_rounded,
        const Color(0xFFFFEA00),
      ),
      KartItemType.energyShield => (
        'ENERGY SHIELD',
        Icons.shield_rounded,
        const Color(0xFF00E5FF),
      ),
      KartItemType.empShockwave => (
        'EMP SHOCKWAVE',
        Icons.flash_on_rounded,
        const Color(0xFFE040FB),
      ),
    };

    final hasItem = heldItem != KartItemType.none;

    return GestureDetector(
      onTap: hasItem ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: compact ? 132 : 156,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 9,
        ),
        decoration: BoxDecoration(
          color: const Color(0xDD0F141D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasItem ? color : Colors.white24,
            width: hasItem ? 2.4 : 1.5,
          ),
          boxShadow: hasItem
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 24 : 30,
              color: hasItem ? color : Colors.white30,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hasItem ? Colors.white : Colors.white38,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            if (hasItem && !compact)
              const Text(
                'TAP OR PRESS E',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CircuitMinimap extends StatelessWidget {
  const _CircuitMinimap({
    required this.track,
    required this.karts,
    this.size = 148,
  });

  final TrackCircuit track;
  final List<KartRacer> karts;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xCC0F141D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: CustomPaint(
        painter: _MinimapPainter(track: track, karts: karts),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({required this.track, required this.karts});

  final TrackCircuit track;
  final List<KartRacer> karts;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = track.samples;
    if (samples.isEmpty) return;

    double minX = samples.first.position.x;
    double maxX = samples.first.position.x;
    double minZ = samples.first.position.z;
    double maxZ = samples.first.position.z;

    for (final s in samples) {
      minX = math.min(minX, s.position.x);
      maxX = math.max(maxX, s.position.x);
      minZ = math.min(minZ, s.position.z);
      maxZ = math.max(maxZ, s.position.z);
    }

    final spanX = math.max(1.0, maxX - minX);
    final spanZ = math.max(1.0, maxZ - minZ);
    final scale = math.min(size.width / spanX, size.height / spanZ) * 0.88;

    Offset toCanvas(double x, double z) {
      final cx = (x - (minX + maxX) * 0.5) * scale + size.width * 0.5;
      final cy = (z - (minZ + maxZ) * 0.5) * scale + size.height * 0.5;
      return Offset(cx, cy);
    }

    final roadPath = Path();
    for (int i = 0; i < samples.length; i += 2) {
      final pt = toCanvas(samples[i].position.x, samples[i].position.z);
      if (i == 0) {
        roadPath.moveTo(pt.dx, pt.dy);
      } else {
        roadPath.lineTo(pt.dx, pt.dy);
      }
    }
    roadPath.close();

    canvas.drawPath(
      roadPath,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      roadPath,
      Paint()
        ..color = const Color(0xFF90A4AE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );

    // Start line tick
    final startPos = toCanvas(samples.first.position.x, samples.first.position.z);
    canvas.drawCircle(startPos, 4.0, Paint()..color = Colors.white);

    // Draw karts
    for (final k in karts.reversed) {
      final p = toCanvas(k.position.x, k.position.z);
      final radius = k.isPlayer ? 5.6 : 4.2;
      canvas.drawCircle(
        p,
        radius + 1.5,
        Paint()..color = Colors.black87,
      );
      canvas.drawCircle(
        p,
        radius,
        Paint()..color = k.uiColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) => true;
}

class _CenterRaceBanners extends StatelessWidget {
  const _CenterRaceBanners({required this.game});
  final KartRaceGame game;

  @override
  Widget build(BuildContext context) {
    if (game.countdownTimer > 0.0) {
      final count = game.countdownTimer.ceil().clamp(1, 3);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 92,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: Color(0xFFFFD54F),
              shadows: [
                Shadow(color: Colors.black, blurRadius: 24),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'HOLD GAS ON "2" FOR ROCKET START!',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      );
    }

    if (game.goBannerTimer > 0.0) {
      return const Text(
        'GO!!',
        style: TextStyle(
          fontSize: 88,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          color: Color(0xFF00E676),
          shadows: [
            Shadow(color: Colors.black, blurRadius: 24),
          ],
        ),
      );
    }

    if (game.playerKart.isWrongWay) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xDDFF1744),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.u_turn_left_rounded, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'WRONG WAY! TURN AROUND',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      );
    }

    if (game.statusBanner != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xCC0F141D),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFFD54F), width: 1.8),
        ),
        child: Text(
          game.statusBanner!,
          style: const TextStyle(
            color: Color(0xFFFFD54F),
            fontSize: 18,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 1.2,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _SpeedAndDriftCluster extends StatelessWidget {
  const _SpeedAndDriftCluster({
    required this.player,
    this.compact = false,
    this.smartSteerEnabled = false,
  });

  final KartRacer player;
  final bool compact;
  final bool smartSteerEnabled;

  @override
  Widget build(BuildContext context) {
    final kmh = player.speedKmh;
    final isBoosting = player.boostTimer > 0.01;
    final driftLevel = player.driftLevel;

    final driftColor = switch (driftLevel) {
      1 => const Color(0xFF29B6F6),
      2 => const Color(0xFFFF9100),
      3 => const Color(0xFFE040FB),
      _ => Colors.white24,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 20,
        vertical: compact ? 7 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xCC0F141D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isBoosting
              ? const Color(0xFF00E5FF)
              : (driftLevel > 0 ? driftColor : Colors.white24),
          width: isBoosting || driftLevel > 0 ? 2.2 : 1.4,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$kmh',
                style: TextStyle(
                  fontSize: compact ? 28 : 36,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: isBoosting ? const Color(0xFF00E5FF) : Colors.white,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'KM/H',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white60,
                ),
              ),
              if (player.isDrifting) ...[
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: driftColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: driftColor),
                  ),
                  child: Text(
                    switch (driftLevel) {
                      1 => 'MINI-TURBO READY',
                      2 => 'SUPER-TURBO READY',
                      3 => 'ULTRA-TURBO MAX!',
                      _ => 'DRIFT CHARGING...',
                    },
                    style: TextStyle(
                      color: driftColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(
              'WASD/Arrows: Drive  •  Space: Drift  •  E: Item  •  G: Smart Steer (${smartSteerEnabled ? "ON" : "OFF"})  •  V: TV Cam',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Zero-slop raw pointer `Listener` steering pad for instant 0ms mobile & touch
/// response. Supports both thumb dragging and instant tap-left / tap-right!
class _TouchSteeringPad extends StatefulWidget {
  const _TouchSteeringPad({
    required this.onSteerChanged,
    this.compact = false,
  });

  final ValueChanged<double> onSteerChanged;
  final bool compact;

  @override
  State<_TouchSteeringPad> createState() => _TouchSteeringPadState();
}

class _TouchSteeringPadState extends State<_TouchSteeringPad> {
  int? _activePointerId;
  double _knobX = 0.0; // -1..1

  void _updateFromLocalDx(double dx, double width) {
    final half = width * 0.5;
    final norm = ((dx - half) / (half * 0.76)).clamp(-1.0, 1.0);
    if ((_knobX - norm).abs() > 0.005) {
      setState(() => _knobX = norm);
    }
    widget.onSteerChanged(norm);
  }

  void _release() {
    _activePointerId = null;
    if (_knobX != 0.0) {
      setState(() => _knobX = 0.0);
    }
    widget.onSteerChanged(0.0);
  }

  @override
  Widget build(BuildContext context) {
    final padWidth = widget.compact ? 168.0 : 194.0;
    final padHeight = widget.compact ? 82.0 : 94.0;
    final isSteering = _activePointerId != null;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _activePointerId ??= e.pointer;
        if (_activePointerId == e.pointer) {
          _updateFromLocalDx(e.localPosition.dx, padWidth);
        }
      },
      onPointerMove: (e) {
        if (_activePointerId == e.pointer) {
          _updateFromLocalDx(e.localPosition.dx, padWidth);
        }
      },
      onPointerUp: (e) {
        if (_activePointerId == e.pointer) {
          _release();
        }
      },
      onPointerCancel: (e) {
        if (_activePointerId == e.pointer) {
          _release();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: padWidth,
        height: padHeight,
        decoration: BoxDecoration(
          color: const Color(0xBB0F141D),
          borderRadius: BorderRadius.circular(padHeight * 0.5),
          border: Border.all(
            color: isSteering ? const Color(0xFFFFC107) : Colors.white30,
            width: isSteering ? 2.4 : 1.8,
          ),
          boxShadow: isSteering
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFC107).withValues(alpha: 0.28),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Icon(
                    Icons.keyboard_double_arrow_left_rounded,
                    color: _knobX < -0.15
                        ? const Color(0xFFFFC107)
                        : Colors.white54,
                    size: 24,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'TOUCH STEER',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      isSteering ? 'AUTO-GAS ACTIVE' : 'SLIDE OR TAP',
                      style: TextStyle(
                        color: isSteering
                            ? const Color(0xFF00E676)
                            : Colors.white24,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    color: _knobX > 0.15
                        ? const Color(0xFFFFC107)
                        : Colors.white54,
                    size: 24,
                  ),
                ),
              ],
            ),
            Transform.translate(
              offset: Offset(_knobX * (padWidth * 0.30), 0),
              child: Container(
                width: widget.compact ? 48 : 54,
                height: widget.compact ? 48 : 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFC107),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFC107).withValues(alpha: 0.5),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.black87,
                  size: 26,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TouchActionPedals extends StatelessWidget {
  const _TouchActionPedals({
    required this.hasItem,
    required this.autoGasActive,
    required this.onGasChanged,
    required this.onBrakeChanged,
    required this.onDriftChanged,
    required this.onUseItem,
    this.compact = false,
  });

  final bool hasItem;
  final bool autoGasActive;
  final ValueChanged<bool> onGasChanged;
  final ValueChanged<bool> onBrakeChanged;
  final ValueChanged<bool> onDriftChanged;
  final VoidCallback onUseItem;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final btnW = compact ? 72.0 : 84.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasItem) ...[
              _HoldPedalButton(
                label: 'USE ITEM',
                color: const Color(0xFFD500F9),
                width: btnW,
                height: compact ? 46 : 52,
                onChanged: (down) {
                  if (down) onUseItem();
                },
              ),
              const SizedBox(height: 8),
            ],
            _HoldPedalButton(
              label: 'BRAKE',
              color: const Color(0xFFFF5252),
              width: btnW,
              height: compact ? 52 : 60,
              onChanged: onBrakeChanged,
            ),
          ],
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HoldPedalButton(
              label: 'DRIFT',
              color: const Color(0xFF40C4FF),
              width: btnW + 8,
              height: compact ? 52 : 58,
              onChanged: onDriftChanged,
            ),
            const SizedBox(height: 8),
            _HoldPedalButton(
              label: autoGasActive ? 'AUTO GAS' : 'GAS',
              color: const Color(0xFF00E676),
              width: btnW + 8,
              height: compact ? 64 : 74,
              isHighlighted: autoGasActive,
              onChanged: onGasChanged,
            ),
          ],
        ),
      ],
    );
  }
}

class _HoldPedalButton extends StatefulWidget {
  const _HoldPedalButton({
    required this.label,
    required this.color,
    required this.width,
    required this.height,
    required this.onChanged,
    this.isHighlighted = false,
  });

  final String label;
  final Color color;
  final double width;
  final double height;
  final ValueChanged<bool> onChanged;
  final bool isHighlighted;

  @override
  State<_HoldPedalButton> createState() => _HoldPedalButtonState();
}

class _HoldPedalButtonState extends State<_HoldPedalButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final active = _pressed || widget.isHighlighted;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? widget.color.withValues(alpha: _pressed ? 0.88 : 0.35)
              : const Color(0xBB0F141D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: widget.color,
            width: active ? 2.5 : 1.8,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: _pressed ? Colors.black : Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

class _SmallHudIconButton extends StatelessWidget {
  const _SmallHudIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive ? const Color(0xFF1E88E5) : const Color(0xCC0F141D),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive ? const Color(0xFF81D4FA) : Colors.white24,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

class _PauseMenuModal extends StatelessWidget {
  const _PauseMenuModal({required this.game});
  final KartRaceGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xEE0D121A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF29B6F6), width: 2.2),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 28),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pause_circle_filled_rounded, color: Color(0xFF29B6F6), size: 26),
              SizedBox(width: 8),
              Text(
                'RACE PAUSED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: game.togglePause,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              'RESUME RACE (P)',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            onPressed: game.restartRace,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text(
              'RESTART RACE',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFD54F),
              side: const BorderSide(color: Color(0x88FFD54F)),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            onPressed: game.returnToTitleScreen,
            icon: const Icon(Icons.home_rounded, size: 18),
            label: const Text(
              'RETURN TO TITLE SCREEN',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceResultsModal extends StatelessWidget {
  const _RaceResultsModal({required this.game});
  final KartRaceGame game;

  @override
  Widget build(BuildContext context) {
    final standings = List<KartRacer>.from(game.karts)
      ..sort((a, b) => a.raceRank.compareTo(b.raceRank));

    return Container(
      width: 360,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xEE0D121A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD54F), width: 2.2),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 28),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFFFD54F),
                size: 26,
              ),
              SizedBox(width: 8),
              Text(
                'VICTORY PODIUM',
                style: TextStyle(
                  color: Color(0xFFFFD54F),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final k in standings)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: k.isPlayer
                    ? const Color(0x33FFC107)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: k.isPlayer ? const Color(0xFFFFC107) : Colors.white12,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '#${k.raceRank}',
                    style: TextStyle(
                      color: k.uiColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      k.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (k.bestLapTime != null)
                    Text(
                      'Best ${k.bestLapTime!.toStringAsFixed(2)}s',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: game.restartRace,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text(
                    'RACE AGAIN',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: game.returnToTitleScreen,
                  icon: const Icon(Icons.home_rounded, size: 18),
                  label: const Text(
                    'TITLE MENU',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CharacterSelectorPill extends StatelessWidget {
  const _CharacterSelectorPill({
    required this.selected,
    required this.onSelect,
  });

  final RacerCharacter selected;
  final ValueChanged<RacerCharacter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC0F141D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            character: RacerCharacter.flutterDash,
            label: 'DASH',
            accent: const Color(0xFF29B6F6),
            icon: Icons.flutter_dash_rounded,
          ),
          const SizedBox(width: 4),
          _buildOption(
            character: RacerCharacter.llama,
            label: 'LLAMA',
            accent: const Color(0xFFFFB300),
            icon: Icons.pets_rounded,
          ),
          const SizedBox(width: 4),
          _buildOption(
            character: RacerCharacter.androidBot,
            label: 'DROID',
            accent: const Color(0xFF00E676),
            icon: Icons.adb_rounded,
          ),
          const SizedBox(width: 4),
          _buildOption(
            character: RacerCharacter.chromeDino,
            label: 'DINO',
            accent: const Color(0xFFFF5252),
            icon: Icons.local_fire_department_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required RacerCharacter character,
    required String label,
    required Color accent,
    required IconData icon,
  }) {
    final isSelected = selected == character;
    return GestureDetector(
      onTap: () => onSelect(character),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accent : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? accent : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
