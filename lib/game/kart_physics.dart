import 'dart:math' as math;
import 'package:flutter/material.dart' show Color;
import 'package:vector_math/vector_math.dart' as vm;

import 'kart_builder.dart';
import 'track_data.dart';

enum KartItemType {
  none,
  turboMushroom,
  tripleTurbo,
  homingShell,
  bananaHazard,
  energyShield,
  empShockwave,
}

class KartInput {
  double throttle = 0.0; // 0..1
  double brake = 0.0; // 0..1
  double steer = 0.0; // -1 (left) .. +1 (right)
  bool driftHeld = false;
  bool useItemPressed = false;

  void reset() {
    throttle = 0.0;
    brake = 0.0;
    steer = 0.0;
    driftHeld = false;
    useItemPressed = false;
  }
}

class KartRacer {
  KartRacer({
    required this.id,
    required this.displayName,
    required this.uiColor,
    required this.isPlayer,
    required this.rig,
    required this.startPosition,
    required this.startYaw,
    this.aiSkill = 1.0,
    this.preferredLaneOffset = 0.0,
  }) : position = startPosition.clone(),
       yaw = startYaw;

  final int id;
  String displayName;
  Color uiColor;
  final bool isPlayer;
  KartVisualRig rig;
  final vm.Vector3 startPosition;
  final double startYaw;
  final double aiSkill;
  double preferredLaneOffset;

  RacerCharacter get character => rig.character;

  // Spatial & Physics State
  vm.Vector3 position;
  double yaw;
  double forwardSpeed = 0.0;
  double lateralVelocity = 0.0;
  vm.Vector3 externalVelocity = vm.Vector3.zero();

  // Hop, Jump Ramp & Drift State
  double hopHeight = 0.0;
  double hopVerticalVel = 0.0;
  double rampCooldown = 0.0;
  double trickSpinTimer = 0.0;
  bool trickArmed = false;
  bool isDrifting = false;
  int driftDirection = 0; // -1 left, +1 right
  double driftCharge = 0.0;
  double visualDriftSlipAngle = 0.0;
  double visualRollAngle = 0.0;
  double visualPitchAngle = 0.0;
  double visualSteerAngle = 0.0;
  double smoothedSteer = 0.0;
  double wheelSpinAngle = 0.0;
  double dynamicAiScale = 1.0;

  double get trickRollAngle => trickSpinTimer > 0.0
      ? ((0.55 - trickSpinTimer) / 0.55).clamp(0.0, 1.0) * math.pi * 2.0
      : 0.0;

  // Boost, Shield, Drafting, Rocket-Start & Hazard State
  double boostTimer = 0.0;
  double boostBonusSpeed = 0.0;
  double shieldTimer = 0.0;
  double spinOutTimer = 0.0;
  double spinOutVisualAngle = 0.0;
  double draftCharge = 0.0;
  double rocketStartCharge = 0.0;
  bool isOffRoad = false;
  bool isWrongWay = false;

  // Coins & Items
  int coins = 0;
  KartItemType heldItem = KartItemType.none;
  int remainingTripleBoosts = 0;

  // Race / Lap Progress
  int currentLap = 1;
  int nextCheckpointIndex = 1;
  double trackDistance = 0.0;
  double totalProgress = 0.0;
  int raceRank = 1; // 1..4
  bool isFinished = false;
  double finishTime = 0.0;
  double currentLapTime = 0.0;
  double? bestLapTime;
  double? lastLapTime;

  final KartInput input = KartInput();

  // Balanced Arcade Physics Constants (comfortable, controllable cruising speed
  // with clear off-road & wall-contact penalties)
  static const double baseMaxSpeed = 20.0;
  static const double reverseMaxSpeed = 8.0;
  static const double baseAcceleration = 16.0;
  static const double brakeDeceleration = 26.0;
  static const double coastDrag = 7.5;
  static const double offRoadMaxSpeed = 13.0;
  static const int maxCoins = 10;

  /// Character-specific top speed multiplier matching the Start Screen stats.
  double get characterTopSpeedFactor => switch (character) {
    RacerCharacter.flutterDash => 1.00,
    RacerCharacter.llama => 1.02,
    RacerCharacter.androidBot => 0.98,
    RacerCharacter.chromeDino => 1.04,
  };

  /// Character-specific steering & cornering agility multiplier.
  double get characterHandlingFactor => switch (character) {
    RacerCharacter.flutterDash => 1.04,
    RacerCharacter.llama => 0.97,
    RacerCharacter.androidBot => 1.08,
    RacerCharacter.chromeDino => 0.93,
  };

  /// Character-specific turbo boost power multiplier.
  double get characterBoostFactor => switch (character) {
    RacerCharacter.flutterDash => 1.02,
    RacerCharacter.llama => 1.08,
    RacerCharacter.androidBot => 0.98,
    RacerCharacter.chromeDino => 1.00,
  };

  /// Drift level: 0 = none, 1 = Blue Mini-Turbo, 2 = Orange Super-Turbo, 3 = Purple Ultra-Turbo
  int get driftLevel {
    if (!isDrifting) return 0;
    if (driftCharge >= 1.85) return 3;
    if (driftCharge >= 1.05) return 2;
    if (driftCharge >= 0.45) return 1;
    return 0;
  }

  /// Speed in arcade KM/H for HUD display.
  int get speedKmh => (forwardSpeed.abs() * 5.2).round();

  vm.Vector3 get forwardDir => vm.Vector3(math.sin(yaw), 0.0, math.cos(yaw));
  vm.Vector3 get rightDir => vm.Vector3(math.cos(yaw), 0.0, -math.sin(yaw));

  static double _wrapAngle(double angle) {
    var a = angle % (2.0 * math.pi);
    if (a > math.pi) a -= 2.0 * math.pi;
    if (a < -math.pi) a += 2.0 * math.pi;
    return a;
  }

  void resetForRace() {
    position = startPosition.clone();
    yaw = startYaw;
    forwardSpeed = 0.0;
    lateralVelocity = 0.0;
    externalVelocity = vm.Vector3.zero();
    hopHeight = 0.0;
    hopVerticalVel = 0.0;
    rampCooldown = 0.0;
    trickSpinTimer = 0.0;
    trickArmed = false;
    isDrifting = false;
    driftDirection = 0;
    driftCharge = 0.0;
    visualDriftSlipAngle = 0.0;
    visualRollAngle = 0.0;
    visualPitchAngle = 0.0;
    visualSteerAngle = 0.0;
    smoothedSteer = 0.0;
    dynamicAiScale = 1.0;
    boostTimer = 0.0;
    boostBonusSpeed = 0.0;
    shieldTimer = 0.0;
    spinOutTimer = 0.0;
    spinOutVisualAngle = 0.0;
    draftCharge = 0.0;
    rocketStartCharge = 0.0;
    isOffRoad = false;
    isWrongWay = false;
    coins = 0;
    heldItem = KartItemType.none;
    remainingTripleBoosts = 0;
    currentLap = 1;
    nextCheckpointIndex = 1;
    trackDistance = 0.0;
    totalProgress = 0.0;
    isFinished = false;
    finishTime = 0.0;
    currentLapTime = 0.0;
    bestLapTime = null;
    lastLapTime = null;
    input.reset();
    rig.leftTrail.clear();
    rig.rightTrail.clear();
    syncVisualTransforms(0.016);
  }

  /// Launches the kart into the air off a 3D Aero Jump Ramp.
  /// Returns `true` if a 360° Aerial Trick was armed at launch.
  bool launchOffRamp({required bool performTrick}) {
    rampCooldown = 1.15;
    hopHeight = math.max(hopHeight, 0.28);
    hopVerticalVel = 6.8;
    if (performTrick) {
      trickSpinTimer = 0.55;
      trickArmed = true;
      return true;
    }
    return false;
  }

  void triggerBoost({required double duration, required double bonusSpeed}) {
    final scaledBonus = bonusSpeed * characterBoostFactor;
    if (duration > boostTimer) {
      boostTimer = duration;
    }
    if (scaledBonus > boostBonusSpeed) {
      boostBonusSpeed = scaledBonus;
    }
    // Smooth initial impulse rather than an instant teleport jump
    final targetFloor = baseMaxSpeed * 0.78 + scaledBonus * 0.35;
    if (forwardSpeed < targetFloor) {
      forwardSpeed = math.min(targetFloor, forwardSpeed + scaledBonus * 0.45);
    }
  }

  void triggerSpinOut() {
    if (shieldTimer > 0.0 || spinOutTimer > 0.0) return;
    spinOutTimer = 0.85;
    isDrifting = false;
    driftDirection = 0;
    driftCharge = 0.0;
    draftCharge = 0.0;
    trickArmed = false;
    trickSpinTimer = 0.0;
    coins = math.max(0, coins - 1);
    forwardSpeed *= 0.45;
  }

  /// Updates AI steering, throttle, drift, rubber-banding, and item usage.
  void updateAiInput(
    TrackCircuit track,
    List<KartRacer> allKarts,
    double dt,
    math.Random rng,
  ) {
    final proj = track.project(position);

    // Friendly rubber-banding relative to the human player
    KartRacer? human;
    for (final k in allKarts) {
      if (k.isPlayer) {
        human = k;
        break;
      }
    }
    if (human != null && !isPlayer) {
      final leadDelta = totalProgress - human.totalProgress;
      if (leadDelta > 16.0) {
        // AI is ahead of player -> ease off slightly so player can catch up!
        dynamicAiScale = (0.91 - (leadDelta - 16.0) * 0.0025).clamp(0.82, 0.91);
      } else if (leadDelta < -22.0) {
        // AI is far behind -> catch up briskly to keep pack exciting
        dynamicAiScale = 0.99;
      } else {
        dynamicAiScale = 0.94;
      }
    } else {
      dynamicAiScale = 1.0;
    }

    // Look ahead along the spline
    final lookAheadDist = (11.0 + forwardSpeed * 0.35).clamp(10.0, 22.0);
    final targetSample = track.sampleAtDistance(proj.distance + lookAheadDist);

    // Gently vary lane offset if an obstacle is ahead
    var laneTarget = preferredLaneOffset;
    for (final obs in track.obstacles) {
      final dObs = (obs.position - position).length;
      if (dObs < 18.0) {
        final obsProj = track.project(obs.position);
        if ((obsProj.lateralOffset - laneTarget).abs() < 2.4) {
          laneTarget = obsProj.lateralOffset > 0 ? -3.2 : 3.2;
        }
      }
    }

    final targetWorldPos =
        targetSample.position + targetSample.right * laneTarget;
    final toTarget = targetWorldPos - position;
    final desiredYaw = math.atan2(toTarget.x, toTarget.z);
    final angleDiff = _wrapAngle(desiredYaw - yaw);

    input.steer = (angleDiff * 2.4).clamp(-1.0, 1.0);

    // Regulate speed in sharp turns and drift through sweeping corners
    final absAngle = angleDiff.abs();
    input.throttle = absAngle > 0.65 ? 0.75 : 1.0;
    input.brake = absAngle > 1.15 ? 0.35 : 0.0;
    input.driftHeld = absAngle > 0.32 && forwardSpeed > 14.0;

    // Use held items opportunistically
    if (heldItem != KartItemType.none && rng.nextDouble() < dt * 0.75) {
      input.useItemPressed = true;
    } else {
      input.useItemPressed = false;
    }
  }

  /// Steps arcade kart physics, drift charging, aerial trick landing, Smart
  /// Steer assist, track boundaries, and visuals.
  /// Returns `true` if a drift/trick boost or item was just activated.
  bool stepPhysics({
    required double dt,
    required TrackCircuit track,
    required bool canDrive,
    required bool smartSteerEnabled,
    double speedClassScale = 1.0,
    required void Function(KartRacer source) onEmpShockwave,
    required void Function(KartRacer source) onSpawnHomingShell,
    required void Function(KartRacer source) onDropBanana,
    required void Function(double trauma) onPlayerCameraShake,
    void Function()? onWallImpact,
    void Function()? onTrickStarted,
    void Function(int tier)? onDriftTierUnlocked,
  }) {
    var activatedBoost = false;

    // Smooth steering input for responsive yet jitter-free control on keyboard & mobile
    final steerRate = input.steer.abs() > smoothedSteer.abs() ? 15.0 : 20.0;
    smoothedSteer +=
        (input.steer - smoothedSteer) * (steerRate * dt).clamp(0.0, 1.0);
    if (smoothedSteer.abs() < 0.005 && input.steer.abs() < 0.005) {
      smoothedSteer = 0.0;
    }

    // 1. Cooldown timers
    if (boostTimer > 0.0) {
      boostTimer = math.max(0.0, boostTimer - dt);
      if (boostTimer <= 0.0) {
        boostBonusSpeed = 0.0;
      }
    }
    if (shieldTimer > 0.0) {
      shieldTimer = math.max(0.0, shieldTimer - dt);
    }
    if (rampCooldown > 0.0) {
      rampCooldown = math.max(0.0, rampCooldown - dt);
    }
    if (trickSpinTimer > 0.0) {
      trickSpinTimer = math.max(0.0, trickSpinTimer - dt);
    }

    if (!canDrive) {
      // Allow charging Rocket Start during the 3-2-1 countdown
      if (input.throttle > 0.1) {
        rocketStartCharge = (rocketStartCharge + dt * 0.55).clamp(0.0, 1.35);
      } else {
        rocketStartCharge = math.max(0.0, rocketStartCharge - dt * 0.8);
      }
      syncVisualTransforms(dt);
      return false;
    }

    currentLapTime += dt;

    // 2. Item usage
    if (input.useItemPressed && heldItem != KartItemType.none) {
      input.useItemPressed = false;
      switch (heldItem) {
        case KartItemType.turboMushroom:
          triggerBoost(duration: 1.30, bonusSpeed: 5.2);
          heldItem = KartItemType.none;
          activatedBoost = true;
        case KartItemType.tripleTurbo:
          triggerBoost(duration: 1.10, bonusSpeed: 4.8);
          remainingTripleBoosts--;
          if (remainingTripleBoosts <= 0) {
            heldItem = KartItemType.none;
          }
          activatedBoost = true;
        case KartItemType.homingShell:
          onSpawnHomingShell(this);
          heldItem = KartItemType.none;
        case KartItemType.bananaHazard:
          onDropBanana(this);
          heldItem = KartItemType.none;
        case KartItemType.energyShield:
          shieldTimer = 8.5;
          heldItem = KartItemType.none;
        case KartItemType.empShockwave:
          onEmpShockwave(this);
          heldItem = KartItemType.none;
          activatedBoost = true;
        case KartItemType.none:
          break;
      }
    }

    // 3. Spin-out recovery state
    if (spinOutTimer > 0.0) {
      spinOutTimer = math.max(0.0, spinOutTimer - dt);
      spinOutVisualAngle += dt * math.pi * 6.0;
      forwardSpeed *= math.pow(0.32, dt).toDouble();
      position += forwardDir * (forwardSpeed * dt);
      syncVisualTransforms(dt);
      return false;
    } else {
      spinOutVisualAngle = 0.0;
    }

    // 4. Hop, Mid-Air Trick & Drift state machine
    if (hopHeight > 0.35 && !trickArmed && input.driftHeld) {
      trickSpinTimer = 0.55;
      trickArmed = true;
      onTrickStarted?.call();
    }

    final canStayDrifting =
        input.driftHeld && forwardSpeed > 7.5 && !isOffRoad && hopHeight < 0.35;

    if (canStayDrifting) {
      if (!isDrifting) {
        if (smoothedSteer.abs() > 0.14 && hopHeight <= 0.01) {
          isDrifting = true;
          driftDirection = smoothedSteer > 0 ? 1 : -1;
          driftCharge = 0.0;
          hopVerticalVel = 2.5;
        }
      } else {
        // Charge drift turbo when steering into the drift
        final prevTier = driftLevel;
        final intoDrift =
            (smoothedSteer * driftDirection) > 0 ? 1.35 : 0.85;
        driftCharge += dt * intoDrift;
        final newTier = driftLevel;
        if (newTier > prevTier) {
          onDriftTierUnlocked?.call(newTier);
        }
      }
    } else if (isDrifting) {
      // Release drift -> award Mini / Super / Ultra Turbo!
      final level = driftLevel;
      if (level == 3) {
        triggerBoost(duration: 1.45, bonusSpeed: 5.8);
        activatedBoost = true;
      } else if (level == 2) {
        triggerBoost(duration: 1.10, bonusSpeed: 4.5);
        activatedBoost = true;
      } else if (level == 1) {
        triggerBoost(duration: 0.75, bonusSpeed: 3.4);
        activatedBoost = true;
      }
      isDrifting = false;
      driftDirection = 0;
      driftCharge = 0.0;
    }

    // Integrate hop / jump ramp vertical motion & award Trick Boost on landing
    if (hopHeight > 0.0 || hopVerticalVel != 0.0) {
      hopHeight += hopVerticalVel * dt;
      hopVerticalVel -= 18.0 * dt;
      if (hopHeight <= 0.0) {
        hopHeight = 0.0;
        hopVerticalVel = 0.0;
        if (trickArmed) {
          trickArmed = false;
          trickSpinTimer = 0.0;
          triggerBoost(duration: 1.10, bonusSpeed: 4.8);
          activatedBoost = true;
        }
      }
    }

    // 5. Determine surface (on-road + FIA curbs = full grip; outside curbs = off-road)
    final projBefore = track.project(position);
    isOffRoad =
        hopHeight < 0.25 &&
        projBefore.lateralOffset.abs() >
            TrackCircuit.roadHalfWidth + TrackCircuit.curbWidth * 1.05;

    // 6. Forward acceleration, braking, and top speed (+0.8% per Gold Coin up to +8%)
    final coinBonusMultiplier = 1.0 + (coins.clamp(0, maxCoins) * 0.008);
    final racerScale = isPlayer
        ? characterTopSpeedFactor
        : (aiSkill * dynamicAiScale * characterTopSpeedFactor);
    var effectiveMaxSpeed =
        (isOffRoad && boostTimer <= 0.0 ? offRoadMaxSpeed : baseMaxSpeed) *
        speedClassScale *
        racerScale *
        coinBonusMultiplier;
    if (boostTimer > 0.0) {
      effectiveMaxSpeed += boostBonusSpeed * speedClassScale;
    }

    final accel =
        baseAcceleration *
        speedClassScale *
        (boostTimer > 0.0 ? 1.40 : 1.0) *
        (isOffRoad && boostTimer <= 0.0 ? 0.68 : 1.0);

    if (input.throttle > 0.01) {
      forwardSpeed += accel * input.throttle * dt;
    } else if (input.brake > 0.01) {
      if (forwardSpeed > 0.5) {
        forwardSpeed -= brakeDeceleration * input.brake * dt;
      } else {
        forwardSpeed -= (baseAcceleration * 0.6) * input.brake * dt;
      }
    } else {
      // Natural coasting drag
      if (forwardSpeed.abs() < coastDrag * dt) {
        forwardSpeed = 0.0;
      } else {
        forwardSpeed -= forwardSpeed.sign * coastDrag * dt;
      }
    }

    // Soft cap above effectiveMaxSpeed so boosts decay smoothly
    if (forwardSpeed > effectiveMaxSpeed) {
      forwardSpeed = math.max(
        effectiveMaxSpeed,
        forwardSpeed - 14.0 * dt,
      );
    } else if (forwardSpeed < -reverseMaxSpeed) {
      forwardSpeed = -reverseMaxSpeed;
    }

    // 7. Progressive Arcade Steering + High-Grip Drift Control
    final speedFactor = (forwardSpeed.abs() / baseMaxSpeed).clamp(0.0, 1.2);
    final reverseSign = forwardSpeed >= -0.2 ? 1.0 : -1.0;
    final curvedSteer =
        smoothedSteer.sign *
        (0.55 * smoothedSteer.abs() + 0.45 * smoothedSteer * smoothedSteer);

    if (isDrifting) {
      // High-authority inside/outside line control while drifting
      final driftSteer =
          (driftDirection * 0.58 + curvedSteer * 0.65) *
          characterHandlingFactor;
      yaw += driftSteer * 2.05 * dt;
      // Controlled lateral slide so drifting carves the apex
      final targetSlide = -driftDirection * forwardSpeed * 0.06;
      lateralVelocity +=
          (targetSlide - lateralVelocity) * (9.5 * dt).clamp(0.0, 1.0);
    } else {
      final turnRate =
          2.25 *
          characterHandlingFactor *
          (0.42 + 0.58 * speedFactor.clamp(0.0, 1.0));
      if (forwardSpeed.abs() > 0.4) {
        yaw += curvedSteer * turnRate * reverseSign * dt;
      }
      lateralVelocity *= math.pow(0.015, dt).toDouble();
    }

    // 7b. Optional Gentle Smart Steer (only nudges steering angle slightly
    // while on the asphalt; never teleports position or propels the kart)
    if (smartSteerEnabled && isPlayer && !isOffRoad && forwardSpeed > 4.0) {
      final lookAheadSample = track.sampleAtDistance(
        projBefore.distance + (9.0 + forwardSpeed * 0.25),
      );
      final trackTangentYaw = math.atan2(
        lookAheadSample.tangent.x,
        lookAheadSample.tangent.z,
      );
      final headingError = _wrapAngle(trackTangentYaw - yaw);

      // Only apply a subtle steering nudge when near the outer curb and not actively counter-steering
      final absLat = projBefore.lateralOffset.abs();
      final edgeFactor =
          ((absLat - TrackCircuit.roadHalfWidth * 0.65) /
                  (TrackCircuit.roadHalfWidth * 0.35))
              .clamp(0.0, 1.0);
      final assistStrength =
          (smoothedSteer.abs() < 0.10 ? 0.35 : 0.15) + edgeFactor * 0.65;
      yaw += headingError * (assistStrength * dt).clamp(0.0, 0.12);
    }

    // 8. Integrate world position
    final velocity =
        forwardDir * forwardSpeed +
        rightDir * lateralVelocity +
        externalVelocity;
    position += velocity * dt;
    externalVelocity *= math.pow(0.02, dt).toDouble();

    // 9. Solid Barrier Collision Penalty (NO wall-glide or auto-turning!)
    // Hitting a barrier cancels active boosts and drifts, and penalizes speed
    // so wall-riding can never be abused.
    final projAfter = track.project(position);

    if (projAfter.lateralOffset.abs() > TrackCircuit.barrierHalfWidth) {
      final clampedSide = projAfter.lateralOffset.sign;
      final excess =
          projAfter.lateralOffset.abs() - TrackCircuit.barrierHalfWidth;
      position -= projAfter.right * (clampedSide * excess);

      // Measure how directly the kart is driving into the barrier (0 = parallel, 1 = head-on)
      final wallNormal = projAfter.right * clampedSide;
      final impactDot = forwardDir.dot(wallNormal).clamp(0.0, 1.0);

      // Cancel any active boost and cancel any drift charge on barrier hit
      boostTimer = 0.0;
      boostBonusSpeed = 0.0;
      if (isDrifting) {
        isDrifting = false;
        driftDirection = 0;
        driftCharge = 0.0;
      }

      // Penalize forward speed based on impact angle and cap scraping speed
      final retention = (0.72 - 0.45 * impactDot).clamp(0.25, 0.72);
      forwardSpeed *= retention;
      if (forwardSpeed > offRoadMaxSpeed * 0.78) {
        forwardSpeed = offRoadMaxSpeed * 0.78;
      }

      // Small physical rebound away from the barrier
      lateralVelocity = -clampedSide * (1.8 + 2.5 * impactDot);

      if (isPlayer && forwardSpeed.abs() > 4.0) {
        onPlayerCameraShake(0.22 + 0.20 * impactDot);
        onWallImpact?.call();
      }
    }

    // Check if player is driving the wrong way along the circuit
    isWrongWay =
        forwardSpeed > 4.0 && forwardDir.dot(projAfter.tangent) < -0.35;

    _updateTrackProgress(track, projAfter);
    syncVisualTransforms(dt);

    if (activatedBoost && isPlayer) {
      onPlayerCameraShake(0.28);
    }
    return activatedBoost;
  }

  void _updateTrackProgress(TrackCircuit track, TrackProjection proj) {
    final prevDist = trackDistance;
    trackDistance = proj.distance;

    final checkpoints = track.checkpointDistances;
    final cpCount = checkpoints.length;

    // Check if the kart reached its next sequential checkpoint
    if (nextCheckpointIndex < cpCount) {
      final cpDist = checkpoints[nextCheckpointIndex];
      if ((trackDistance - cpDist).abs() < 26.0) {
        nextCheckpointIndex++;
      }
    } else {
      // Waiting to cross the Start/Finish line (distance wraps from high to low)
      final crossedFinish =
          prevDist > track.totalLength * 0.75 &&
          trackDistance < track.totalLength * 0.25;
      if (crossedFinish) {
        lastLapTime = currentLapTime;
        if (bestLapTime == null || currentLapTime < bestLapTime!) {
          bestLapTime = currentLapTime;
        }
        currentLapTime = 0.0;
        currentLap++;
        nextCheckpointIndex = 1;
      }
    }

    totalProgress =
        (currentLap - 1) * track.totalLength +
        (nextCheckpointIndex == 1 && trackDistance > track.totalLength * 0.85
            ? trackDistance - track.totalLength
            : trackDistance);
  }

  /// Updates the 3D scene graph nodes for the kart, wheels, mascot driver,
  /// exhaust particles, drift sparks, brake lights, and shield.
  void syncVisualTransforms(double dt) {
    // Root node world position & heading yaw
    rig.rootNode.position = vm.Vector3(position.x, 0.0, position.z);
    rig.rootNode.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);

    rig.updateVisuals(
      dt: dt,
      speed: forwardSpeed,
      steerInput: input.steer,
      isDrifting: isDrifting,
      driftDirection: driftDirection.toDouble(),
      driftLevel: driftLevel,
      hopOffset: hopHeight,
      spinOutAngle: spinOutVisualAngle,
      trickRollAngle: trickRollAngle,
      hasShield: shieldTimer > 0.0,
      isBoosting: boostTimer > 0.0,
      isBraking: input.brake > 0.1,
    );

    // Tire trails during drift or boost
    final emitTrails = isDrifting || boostTimer > 0.0;
    rig.leftTrail.emitting = emitTrails;
    rig.rightTrail.emitting = emitTrails;
  }
}
