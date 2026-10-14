import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'pbr_assets.dart';

/// Playable and AI mascot characters in the 3D Kart Racer.
enum RacerCharacter {
  flutterDash(
    displayName: 'Flutter Dash',
    badge: 'DASH',
    subtitle: 'Sky Hummingbird • Aero V8',
  ),
  llama(
    displayName: 'Turbo Llama',
    badge: 'LLAMA',
    subtitle: 'Andean Woolly • Alpaca GT',
  ),
  androidBot(
    displayName: 'Bugdroid Bot',
    badge: 'DROID',
    subtitle: 'Green Cyborg • Pixel RS',
  ),
  chromeDino(
    displayName: 'Blaze Dino',
    badge: 'DINO',
    subtitle: 'Offline Rex • Meteor X',
  );

  const RacerCharacter({
    required this.displayName,
    required this.badge,
    required this.subtitle,
  });

  final String displayName;
  final String badge;
  final String subtitle;
}

/// Visual rig for a single 3D Kart + Hero Mascot Driver, exposing articulated
/// nodes, GPU particle emitters, brake lights, and tire trails.
class KartVisualRig {
  KartVisualRig({
    required this.rootNode,
    required this.chassisNode,
    required this.steeringWheelNode,
    required this.driverNode,
    required this.driverHeadNode,
    required this.driverLeftAppendage,
    required this.driverRightAppendage,
    required this.frontLeftPivot,
    required this.frontRightPivot,
    required this.wheelSpinNodes,
    required this.leftSparkNode,
    required this.rightSparkNode,
    required this.sparkMaterial,
    required this.exhaustFlameMaterial,
    required this.leftExhaustEmitter,
    required this.rightExhaustEmitter,
    required this.leftSparkEmitter,
    required this.rightSparkEmitter,
    required this.brakeLightMaterial,
    required this.shieldNode,
    required this.leftTrail,
    required this.rightTrail,
    required this.character,
  });

  final Node rootNode;
  final Node chassisNode;
  final Node steeringWheelNode;
  final Node driverNode;
  final Node driverHeadNode;
  final Node driverLeftAppendage;
  final Node driverRightAppendage;
  final Node frontLeftPivot;
  final Node frontRightPivot;
  final List<Node> wheelSpinNodes;
  final Node leftSparkNode;
  final Node rightSparkNode;
  final PhysicallyBasedMaterial sparkMaterial;
  final SpriteMaterial exhaustFlameMaterial;
  final ParticleEmitterComponent leftExhaustEmitter;
  final ParticleEmitterComponent rightExhaustEmitter;
  final ParticleEmitterComponent leftSparkEmitter;
  final ParticleEmitterComponent rightSparkEmitter;
  final PhysicallyBasedMaterial brakeLightMaterial;
  final Node shieldNode;
  final TrailComponent leftTrail;
  final TrailComponent rightTrail;
  final RacerCharacter character;

  double _wheelSpinAngle = 0.0;
  double _animClock = 0.0;

  /// Updates wheel spin, steering angle, chassis roll/pitch, hero mascot
  /// animations (Dash wing flapping / Llama ear bobbing / 3/4 profile head turns),
  /// brake lights, and GPU particles.
  void updateVisuals({
    required double dt,
    required double speed,
    required double steerInput,
    required bool isDrifting,
    required double driftDirection,
    required int driftLevel,
    required double hopOffset,
    required double spinOutAngle,
    double trickRollAngle = 0.0,
    required bool hasShield,
    required bool isBoosting,
    required bool isBraking,
  }) {
    _animClock += dt;
    const wheelRadius = 0.32;
    _wheelSpinAngle =
        (_wheelSpinAngle + (speed * dt) / wheelRadius) % (math.pi * 2.0);

    for (final wheel in wheelSpinNodes) {
      wheel.rotation = vm.Quaternion.axisAngle(
        vm.Vector3(1, 0, 0),
        _wheelSpinAngle,
      );
    }

    // Front wheel steering angle
    final visualSteer =
        (steerInput * 0.46 + (isDrifting ? driftDirection * 0.26 : 0.0))
            .clamp(-0.65, 0.65);
    frontLeftPivot.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      visualSteer,
    );
    frontRightPivot.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      visualSteer,
    );

    // Steering wheel rotation
    steeringWheelNode.rotation =
        vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.48) *
        vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -visualSteer * 2.0);

    // Hero Mascot Driver lean + torso yaw into turn so camera sees 3/4 profile!
    final driverLean = -visualSteer * 0.36;
    final torsoYaw = visualSteer * 0.45;
    final excitedBob = (isBoosting || driftLevel > 0)
        ? math.sin(_animClock * 20.0) * 0.045
        : math.sin(_animClock * 4.5) * 0.012;
    driverNode.position = vm.Vector3(0, 0.50 + excitedBob, -0.06);
    driverNode.rotation = vm.Quaternion.euler(
      torsoYaw,
      isBoosting ? -0.08 : 0.0,
      driverLean,
    );

    // Expressive Head look into turn (plus celebratory glance when boosting!)
    final boostGlance =
        isBoosting ? math.sin(_animClock * 10.0) * 0.55 : 0.0;
    final headYaw = (visualSteer * 0.72 + boostGlance).clamp(-1.15, 1.15);
    final headPitch = isBoosting ? -0.16 : 0.0;
    driverHeadNode.rotation = vm.Quaternion.euler(
      headYaw,
      headPitch,
      driverLean * 0.35,
    );

    // Character-specific appendage animations (Dash wings / Llama ears)
    switch (character) {
      case RacerCharacter.flutterDash:
        final flapSpeed = isBoosting
            ? 30.0
            : (isDrifting ? 20.0 : (5.5 + speed.abs() * 0.18));
        final flapAmp = isBoosting ? 0.68 : (isDrifting ? 0.45 : 0.18);
        final flap = math.sin(_animClock * flapSpeed) * flapAmp;
        driverLeftAppendage.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 0, 1),
          0.28 + flap,
        );
        driverRightAppendage.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 0, 1),
          -0.28 - flap,
        );
      case RacerCharacter.llama:
        // Long perky banana ears bob back with speed and sway with steering
        final earBack =
            (speed / 45.0).clamp(0.0, 0.38) +
            math.sin(_animClock * 14.0) * (isBoosting ? 0.22 : 0.09);
        final earSway = -visualSteer * 0.48;
        driverLeftAppendage.rotation = vm.Quaternion.euler(
          earSway,
          -0.22 - earBack,
          0.22,
        );
        driverRightAppendage.rotation = vm.Quaternion.euler(
          earSway,
          -0.22 - earBack,
          -0.22,
        );
      case RacerCharacter.androidBot:
      case RacerCharacter.chromeDino:
        final wave = math.sin(_animClock * 12.0) * (isBoosting ? 0.35 : 0.10);
        driverLeftAppendage.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          wave,
        );
        driverRightAppendage.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          -wave,
        );
    }

    // Chassis suspension roll, acceleration squat, hop, aerial trick roll & spin-out
    final bodyRoll =
        steerInput * 0.085 * (speed / 35.0).clamp(0.0, 1.2) +
        (isDrifting ? driftDirection * 0.075 : 0.0) +
        trickRollAngle;
    final bodyPitch = hopOffset > 0.20
        ? -(hopOffset * 0.14).clamp(0.0, 0.22)
        : (isBoosting
              ? -0.065
              : (isBraking ? 0.05 : -(speed / 45.0).clamp(-0.02, 0.03)));

    chassisNode.position = vm.Vector3(0, hopOffset, 0);
    chassisNode.rotation = vm.Quaternion.euler(
      spinOutAngle + (isDrifting ? driftDirection * 0.22 : 0.0),
      bodyPitch,
      bodyRoll,
    );

    // Dynamic LED brake light bar
    if (isBraking) {
      brakeLightMaterial.emissiveFactor = vm.Vector4(1.0, 0.08, 0.05, 1.0);
      brakeLightMaterial.emissiveStrength = 8.0;
    } else {
      brakeLightMaterial.emissiveFactor = vm.Vector4(0.85, 0.05, 0.05, 1.0);
      brakeLightMaterial.emissiveStrength = 1.8;
    }

    // Exhaust afterburner particle rate & color
    if (isBoosting) {
      leftExhaustEmitter.system.spawner.rate = 60.0;
      rightExhaustEmitter.system.spawner.rate = 60.0;
      exhaustFlameMaterial.tint = vm.Vector4(0.30, 0.85, 1.0, 1.0);
    } else if (speed.abs() > 3.0) {
      final throttleRate = 16.0 + (speed.abs() / 42.0) * 26.0;
      leftExhaustEmitter.system.spawner.rate = throttleRate;
      rightExhaustEmitter.system.spawner.rate = throttleRate;
      exhaustFlameMaterial.tint = vm.Vector4(1.0, 0.62, 0.22, 0.85);
    } else {
      leftExhaustEmitter.system.spawner.rate = 6.0;
      rightExhaustEmitter.system.spawner.rate = 6.0;
      exhaustFlameMaterial.tint = vm.Vector4(0.8, 0.5, 0.3, 0.45);
    }

    // Drift sparks (blue -> orange -> purple) + GPU spark streaks
    if (isDrifting && driftLevel > 0) {
      leftSparkNode.visible = true;
      rightSparkNode.visible = true;
      leftSparkEmitter.system.spawner.rate = 25.0 * driftLevel;
      rightSparkEmitter.system.spawner.rate = 25.0 * driftLevel;

      final pulse = 0.85 + 0.25 * math.sin(_animClock * 28.0);
      final scale = (0.16 + driftLevel * 0.10) * pulse;
      leftSparkNode.scale = vm.Vector3.all(scale);
      rightSparkNode.scale = vm.Vector3.all(scale);

      if (driftLevel == 1) {
        sparkMaterial.baseColorFactor = vm.Vector4(0.15, 0.72, 1.0, 0.9);
        sparkMaterial.emissiveFactor = vm.Vector4(0.15, 0.72, 1.0, 1.0);
        sparkMaterial.emissiveStrength = 5.5;
      } else if (driftLevel == 2) {
        sparkMaterial.baseColorFactor = vm.Vector4(1.0, 0.52, 0.05, 0.92);
        sparkMaterial.emissiveFactor = vm.Vector4(1.0, 0.48, 0.05, 1.0);
        sparkMaterial.emissiveStrength = 8.0;
      } else {
        sparkMaterial.baseColorFactor = vm.Vector4(0.88, 0.2, 1.0, 0.95);
        sparkMaterial.emissiveFactor = vm.Vector4(0.88, 0.18, 1.0, 1.0);
        sparkMaterial.emissiveStrength = 11.0;
      }
    } else if (isBoosting) {
      leftSparkNode.visible = true;
      rightSparkNode.visible = true;
      leftSparkEmitter.system.spawner.rate = 36.0;
      rightSparkEmitter.system.spawner.rate = 36.0;
      leftSparkNode.scale = vm.Vector3(0.22, 0.22, 0.52);
      rightSparkNode.scale = vm.Vector3(0.22, 0.22, 0.52);
      sparkMaterial.baseColorFactor = vm.Vector4(0.25, 0.92, 1.0, 0.92);
      sparkMaterial.emissiveFactor = vm.Vector4(0.2, 0.88, 1.0, 1.0);
      sparkMaterial.emissiveStrength = 9.5;
    } else {
      leftSparkNode.visible = false;
      rightSparkNode.visible = false;
      leftSparkEmitter.system.spawner.rate = 0.0;
      rightSparkEmitter.system.spawner.rate = 0.0;
    }

    shieldNode.visible = hasShield;
    if (hasShield) {
      shieldNode.rotation = vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        _animClock * 2.4,
      );
    }
  }
}

/// Builds production-level 3D Kart rigs and hero-scale sculpted mascot drivers
/// (**Flutter Dash**, **Turbo Llama**, **Bugdroid Bot**, and **Blaze Dino**).
class KartBuilder {
  static MeshGeometry? _cachedMonocoqueMesh;

  /// Builds a complete [KartVisualRig] for the given [character] and livery.
  static KartVisualRig buildKart({
    required String name,
    required RacerCharacter character,
    required vm.Vector4 primaryColor,
    required vm.Vector4 accentColor,
    required vm.Vector4 rimColor,
    bool isPlayer = false,
  }) {
    final pbr = PbrAssets.instance;
    final rootNode = Node(name: name);
    final chassisNode = Node(name: '${name}_Chassis');
    rootNode.add(chassisNode);

    // --- Shared PBR Materials ---
    final bodyPaintMat = PhysicallyBasedMaterial()
      ..baseColorFactor = primaryColor
      ..roughnessFactor = 0.16
      ..metallicFactor = 0.38
      ..specular = 1.0
      ..clearcoat = 0.88
      ..clearcoatRoughness = 0.06;

    final accentPaintMat = PhysicallyBasedMaterial()
      ..baseColorFactor = accentColor
      ..roughnessFactor = 0.20
      ..metallicFactor = 0.32
      ..clearcoat = 0.78
      ..clearcoatRoughness = 0.08;

    final carbonMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.carbonAlbedo,
      normalTexture: pbr.carbonNormal,
    )
      ..baseColorFactor = vm.Vector4(0.9, 0.92, 0.96, 1.0)
      ..roughnessFactor = 0.30
      ..metallicFactor = 0.22
      ..normalScale = 0.95
      ..clearcoat = 0.55
      ..clearcoatRoughness = 0.14
      ..baseColorTextureTransform = TextureTransform(
        scale: vm.Vector2(4.0, 4.0),
      )
      ..normalTextureTransform = TextureTransform(
        scale: vm.Vector2(4.0, 4.0),
      );

    final chromeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.92, 0.95, 0.98, 1.0)
      ..roughnessFactor = 0.12
      ..metallicFactor = 0.95;

    final gunmetalMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.20, 0.22, 0.27, 1.0)
      ..roughnessFactor = 0.38
      ..metallicFactor = 0.80;

    final seatLeatherMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.11, 0.12, 0.16, 1.0)
      ..roughnessFactor = 0.62
      ..metallicFactor = 0.08;

    final tireRubberMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.tireAlbedo,
      normalTexture: pbr.tireNormal,
    )
      ..baseColorFactor = vm.Vector4(0.92, 0.92, 0.95, 1.0)
      ..roughnessFactor = 0.80
      ..metallicFactor = 0.05
      ..normalScale = 1.25;

    final alloyRimMat = PhysicallyBasedMaterial()
      ..baseColorFactor = rimColor
      ..roughnessFactor = 0.20
      ..metallicFactor = 0.90;

    final headlightMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.98, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.85, 0.95, 1.0, 1.0)
      ..emissiveStrength = 6.0
      ..roughnessFactor = 0.08;

    final brakeLightMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.08, 0.08, 1.0)
      ..emissiveFactor = vm.Vector4(0.85, 0.05, 0.05, 1.0)
      ..emissiveStrength = 1.8
      ..roughnessFactor = 0.18;

    // 1. Carbon-Fiber Undertray Floorpan & Sculpted Front Aero Splitter
    chassisNode.add(
      Node(
        name: '${name}_Floorpan',
        mesh: Mesh(CuboidGeometry(vm.Vector3(1.22, 0.09, 2.28)), carbonMat),
      )..position = vm.Vector3(0, 0.18, -0.02),
    );

    final splitterPath = CatmullRomPath(<vm.Vector3>[
      vm.Vector3(-0.72, 0.18, 1.18),
      vm.Vector3(-0.38, 0.17, 1.38),
      vm.Vector3(0.0, 0.17, 1.44),
      vm.Vector3(0.38, 0.17, 1.38),
      vm.Vector3(0.72, 0.18, 1.18),
    ]);
    chassisNode.add(
      Node(
        name: '${name}_FrontBumperTube',
        mesh: Mesh(
          TubeGeometry(
            splitterPath,
            radius: 0.055,
            radialSegments: 12,
            stations: 20,
          ),
          accentPaintMat,
        ),
      ),
    );

    // 2. Smooth-Shaded Multi-Station Lofted Monocoque Bodywork
    final monocoqueMesh =
        _cachedMonocoqueMesh ??= _buildSculptedMonocoqueMesh();
    chassisNode.add(
      Node(
        name: '${name}_Monocoque',
        mesh: Mesh(monocoqueMesh, bodyPaintMat),
      )..position = vm.Vector3(0, 0.22, 0.0),
    );

    // 3. Sculpted Side Pods, Bargeboards & Twin LED Headlights
    for (final side in const [-1.0, 1.0]) {
      // Contoured sidepod capsule
      chassisNode.add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.175, height: 0.92, radialSegments: 20),
            bodyPaintMat,
          ),
        )
          ..position = vm.Vector3(side * 0.64, 0.34, 0.02)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(1, 0, 0),
            math.pi / 2,
          ),
      );

      // Sidepod swept accent trim tube
      final sideTrimPath = CatmullRomPath(<vm.Vector3>[
        vm.Vector3(side * 0.72, 0.38, -0.45),
        vm.Vector3(side * 0.76, 0.40, 0.02),
        vm.Vector3(side * 0.68, 0.36, 0.50),
      ]);
      chassisNode.add(
        Node(
          mesh: Mesh(
            TubeGeometry(
              sideTrimPath,
              radius: 0.032,
              radialSegments: 10,
              stations: 12,
            ),
            accentPaintMat,
          ),
        ),
      );

      // Twin LED Headlight pods on nose
      chassisNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.062,
              topRadius: 0.052,
              height: 0.08,
              radialSegments: 14,
            ),
            headlightMat,
          ),
        )
          ..position = vm.Vector3(side * 0.27, 0.36, 1.22)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(1, 0, 0),
            math.pi / 2,
          ),
      );
    }

    // Forward SpotLight on player kart so tarmac normal map glints ahead
    if (isPlayer) {
      final headlightBeam = Node(name: '${name}_HeadlightBeam')
        ..position = vm.Vector3(0, 0.55, 1.35)
        ..addComponent(
          SpotLightComponent(
            SpotLight(
              color: vm.Vector3(0.95, 0.98, 1.0),
              intensity: 850.0,
              range: 28.0,
              direction: vm.Vector3(0, -0.18, 1.0),
              innerConeAngle: 0.28,
              outerConeAngle: 0.68,
              castsShadow: false,
            ),
          ),
        );
      chassisNode.add(headlightBeam);
    }

    // 4. Tubular Suspension Wishbones & Drive Axles
    for (final side in const [-1.0, 1.0]) {
      chassisNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.025,
              topRadius: 0.025,
              height: 0.44,
              radialSegments: 10,
            ),
            gunmetalMat,
          ),
        )
          ..position = vm.Vector3(side * 0.55, 0.31, 0.84)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            math.pi / 2,
          ),
      );
      chassisNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.036,
              topRadius: 0.036,
              height: 0.46,
              radialSegments: 10,
            ),
            gunmetalMat,
          ),
        )
          ..position = vm.Vector3(side * 0.56, 0.31, -0.78)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            math.pi / 2,
          ),
      );
    }

    // 5. Low-Slung Cockpit Bucket Bolster & F1 Steering Wheel
    // (Low profile in the rear so the hero mascot character is 100% unobstructed!)
    chassisNode.add(
      Node(
        mesh: Mesh(
          CapsuleGeometry(radius: 0.14, height: 0.38, radialSegments: 16),
          seatLeatherMat,
        ),
      )
        ..position = vm.Vector3(0, 0.44, -0.36)
        ..rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 0, 1),
          math.pi / 2,
        ),
    );

    // Steering Column & F1-Style Steering Wheel
    chassisNode.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 0.034,
            topRadius: 0.034,
            height: 0.48,
            radialSegments: 12,
          ),
          gunmetalMat,
        ),
      )
        ..position = vm.Vector3(0, 0.54, 0.48)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.68),
    );

    final steeringWheelNode = Node(name: '${name}_SteeringWheel')
      ..position = vm.Vector3(0, 0.72, 0.32)
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.48);

    steeringWheelNode.add(
      Node(
        mesh: Mesh(
          TorusGeometry(
            radius: 0.16,
            tubeRadius: 0.028,
            radialSegments: 20,
            tubularSegments: 12,
          ),
          seatLeatherMat,
        ),
      )..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
    );
    chassisNode.add(steeringWheelNode);

    // 6. Low-Slung V-Twin Rear Engine, Swept Exhausts & Split Outboard Winglets
    // (Positioned on the outer flanks so the center behind the character is open!)
    chassisNode.add(
      Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(0.46, 0.24, 0.42)), gunmetalMat),
      )..position = vm.Vector3(0, 0.38, -0.82),
    );

    for (final side in const [-1.0, 1.0]) {
      // Angled V-Twin cylinder head
      chassisNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.11,
              topRadius: 0.12,
              height: 0.22,
              radialSegments: 16,
            ),
            chromeMat,
          ),
        )
          ..position = vm.Vector3(side * 0.20, 0.52, -0.80)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            -side * 0.52,
          ),
      );

      // Swept tubular exhaust header & angled megaphone muffler tip
      final headerPath = CatmullRomPath(<vm.Vector3>[
        vm.Vector3(side * 0.24, 0.52, -0.78),
        vm.Vector3(side * 0.36, 0.50, -0.96),
        vm.Vector3(side * 0.34, 0.52, -1.18),
        vm.Vector3(side * 0.32, 0.55, -1.36),
      ]);
      chassisNode.add(
        Node(
          mesh: Mesh(
            TubeGeometry(
              headerPath,
              radius: 0.048,
              radialSegments: 12,
              stations: 16,
            ),
            chromeMat,
          ),
        ),
      );

      // Twin Outboard Le Mans Rear Winglets (leaves center driver view wide open!)
      chassisNode.add(
        Node(
          mesh: Mesh(CuboidGeometry(vm.Vector3(0.32, 0.045, 0.28)), carbonMat),
        )
          ..position = vm.Vector3(side * 0.54, 0.64, -1.06)
          ..rotation = vm.Quaternion.euler(0.0, 0.18, -side * 0.12),
      );
      chassisNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(0.045, 0.26, 0.38)),
            accentPaintMat,
          ),
        )..position = vm.Vector3(side * 0.70, 0.64, -1.06),
      );
    }

    // Rear Diffuser LED Brake Light Bar (aft of rear bumper so no face is coplanar)
    brakeLightMaterial.depthLayer = 1;
    chassisNode.add(
      Node(
        name: '${name}_BrakeLight',
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.42, 0.062, 0.045)),
          brakeLightMaterial,
        ),
      )..position = vm.Vector3(0, 0.32, -1.24),
    );

    // 7. HERO-SCALE Sculpted Mascot Driver (Flutter Dash / Llama / Bot / Dino)
    final mascotRig = _buildMascotDriver(
      character: character,
      primaryColor: primaryColor,
      accentColor: accentColor,
      pbr: pbr,
    );
    chassisNode.add(mascotRig.driverRoot);

    // 8. Four Multi-Part 5-Spoke Racing Wheels + Brake Calipers
    final wheelSpinNodes = <Node>[];
    final frontLeftPivot = Node(name: '${name}_FL_Pivot')
      ..position = vm.Vector3(-0.74, 0.31, 0.84);
    final frontRightPivot = Node(name: '${name}_FR_Pivot')
      ..position = vm.Vector3(0.74, 0.31, 0.84);
    final rearLeftPivot = Node(name: '${name}_RL_Pivot')
      ..position = vm.Vector3(-0.84, 0.34, -0.78);
    final rearRightPivot = Node(name: '${name}_RR_Pivot')
      ..position = vm.Vector3(0.84, 0.34, -0.78);

    Node buildWheel({required bool isRear, required bool isRightSide}) {
      final spinNode = Node();
      final radius = isRear ? 0.34 : 0.30;
      final width = isRear ? 0.34 : 0.25;
      final outSign = isRightSide ? 1.0 : -1.0;

      // Grooved racing slick tire tread (open ends; sidewalls & rim close hub)
      spinNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: radius,
              topRadius: radius,
              height: width,
              radialSegments: 28,
              topCap: false,
              bottomCap: false,
            ),
            tireRubberMat,
          ),
        )..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            math.pi / 2,
          ),
      );

      // Rounded tire shoulder torus rings on inner & outer sidewalls
      for (final side in const [-1.0, 1.0]) {
        spinNode.add(
          Node(
            mesh: Mesh(
              TorusGeometry(
                radius: radius - 0.045,
                tubeRadius: 0.048,
                radialSegments: 24,
                tubularSegments: 12,
              ),
              tireRubberMat,
            ),
          )
            ..position = vm.Vector3(side * (width * 0.44), 0, 0)
            ..rotation = vm.Quaternion.axisAngle(
              vm.Vector3(0, 0, 1),
              math.pi / 2,
            ),
        );
      }

      // Colored Pirelli-style sidewall ring on outer face
      spinNode.add(
        Node(
          mesh: Mesh(
            RingGeometry(
              innerRadius: radius * 0.64,
              outerRadius: radius * 0.78,
              segments: 24,
            ),
            accentPaintMat,
          ),
        )
          ..position = vm.Vector3(outSign * (width * 0.515), 0, 0)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            -outSign * math.pi / 2,
          ),
      );

      // Deep-dish alloy rim barrel + 5 star spokes
      spinNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: radius * 0.56,
              topRadius: radius * 0.56,
              height: width * 0.86,
              radialSegments: 20,
            ),
            gunmetalMat,
          ),
        )..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            math.pi / 2,
          ),
      );

      for (var s = 0; s < 5; s++) {
        final spokeAngle = (s / 5.0) * math.pi * 2.0;
        spinNode.add(
          Node(
            mesh: Mesh(
              CapsuleGeometry(
                radius: 0.022,
                height: radius * 0.85,
                radialSegments: 8,
              ),
              alloyRimMat,
            ),
          )
            ..position = vm.Vector3(outSign * (width * 0.44), 0, 0)
            ..rotation = vm.Quaternion.axisAngle(
              vm.Vector3(1, 0, 0),
              spokeAngle,
            ),
        );
      }

      // Center wheel locknut cap
      spinNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.068,
              topRadius: 0.048,
              height: 0.06,
              radialSegments: 14,
            ),
            chromeMat,
          ),
        )
          ..position = vm.Vector3(outSign * (width * 0.48), 0, 0)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            -outSign * math.pi / 2,
          ),
      );

      wheelSpinNodes.add(spinNode);
      return spinNode;
    }

    frontLeftPivot.add(buildWheel(isRear: false, isRightSide: false));
    frontRightPivot.add(buildWheel(isRear: false, isRightSide: true));
    rearLeftPivot.add(buildWheel(isRear: true, isRightSide: false));
    rearRightPivot.add(buildWheel(isRear: true, isRightSide: true));

    chassisNode
      ..add(frontLeftPivot)
      ..add(frontRightPivot)
      ..add(rearLeftPivot)
      ..add(rearRightPivot);

    // 9. GPU Exhaust Flame Particle Emitters + Drift Spark Emitters
    final exhaustFlameMaterial = SpriteMaterial(
      colorTexture: pbr.particleGlowSprite,
    )
      ..blendMode = SpriteBlendMode.additive
      ..tint = vm.Vector4(1.0, 0.62, 0.22, 0.85);

    ParticleEmitterComponent createExhaustEmitter(int seed) {
      final sys = ParticleSystem(
        maxParticles: 64,
        seed: seed,
        shape: const ConeEmitterShape(angle: 0.22, radius: 0.03),
        spawner: Spawner(rate: 14.0),
        lifetime: const UniformFloat(0.12, 0.26),
        startSpeed: const UniformFloat(4.5, 8.5),
        startSize: const UniformFloat(0.18, 0.32),
        modules: <ParticleModule>[
          SizeOverLifeModule(
            CurveFloat(ParticleCurve.linear(from: 1.0, to: 0.15)),
          ),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient(<ColorStop>[
                ColorStop(0.0, vm.Vector4(1.0, 0.95, 0.75, 1.0)),
                ColorStop(0.45, vm.Vector4(1.0, 0.48, 0.12, 0.85)),
                ColorStop(1.0, vm.Vector4(0.35, 0.08, 0.02, 0.0)),
              ]),
            ),
          ),
          TurbulenceModule(strength: 2.5, frequency: 2.0, seed: seed),
        ],
      );
      return ParticleEmitterComponent(
        system: sys,
        material: exhaustFlameMaterial,
      );
    }

    final leftExhaustEmitter = createExhaustEmitter(101);
    final rightExhaustEmitter = createExhaustEmitter(202);

    final exhaustRot = vm.Quaternion.axisAngle(
      vm.Vector3(1, 0, 0),
      -math.pi / 2,
    );
    chassisNode.add(
      Node(name: '${name}_ExhaustL')
        ..position = vm.Vector3(-0.32, 0.55, -1.40)
        ..rotation = exhaustRot
        ..addComponent(leftExhaustEmitter),
    );
    chassisNode.add(
      Node(name: '${name}_ExhaustR')
        ..position = vm.Vector3(0.32, 0.55, -1.40)
        ..rotation = exhaustRot
        ..addComponent(rightExhaustEmitter),
    );

    // Velocity-stretched Drift Spark Particle Emitters
    final sparkSpriteMat = SpriteMaterial(colorTexture: pbr.sparkStreakSprite)
      ..blendMode = SpriteBlendMode.additive
      ..tint = vm.Vector4(1.0, 0.85, 0.35, 1.0);

    ParticleEmitterComponent createSparkEmitter(int seed) {
      final sys = ParticleSystem(
        maxParticles: 64,
        seed: seed,
        shape: const ConeEmitterShape(angle: 0.48, radius: 0.05),
        spawner: Spawner(rate: 0.0),
        lifetime: const UniformFloat(0.14, 0.30),
        startSpeed: const UniformFloat(6.0, 12.0),
        startSize: const UniformFloat(0.12, 0.20),
        gravity: vm.Vector3(0, -14.0, 0),
        modules: <ParticleModule>[
          SizeOverLifeModule(
            CurveFloat(ParticleCurve.linear(from: 1.0, to: 0.2)),
          ),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient(<ColorStop>[
                ColorStop(0.0, vm.Vector4(1.0, 0.95, 0.65, 1.0)),
                ColorStop(0.5, vm.Vector4(1.0, 0.45, 0.10, 0.9)),
                ColorStop(1.0, vm.Vector4(0.8, 0.1, 0.0, 0.0)),
              ]),
            ),
          ),
        ],
      );
      return ParticleEmitterComponent(system: sys, material: sparkSpriteMat)
        ..facing = BillboardFacing.velocityStretched
        ..velocityStretch = 0.06;
    }

    final leftSparkEmitter = createSparkEmitter(303);
    final rightSparkEmitter = createSparkEmitter(404);

    // Drift Spark Core Orbs at Rear Wheels
    final sparkMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.2, 0.7, 1.0, 0.9)
      ..emissiveFactor = vm.Vector4(0.2, 0.7, 1.0, 1.0)
      ..emissiveStrength = 5.0
      ..alphaMode = AlphaMode.blend
      ..roughnessFactor = 0.1;

    final sparkGeo = IcosphereGeometry(radius: 1.0, subdivisions: 1);
    final leftSparkNode = Node(
      name: '${name}_SparkL',
      mesh: Mesh(sparkGeo, sparkMaterial),
    )
      ..position = vm.Vector3(-0.76, 0.16, -1.06)
      ..scale = vm.Vector3.all(0.18)
      ..visible = false;
    final rightSparkNode = Node(
      name: '${name}_SparkR',
      mesh: Mesh(sparkGeo, sparkMaterial),
    )
      ..position = vm.Vector3(0.76, 0.16, -1.06)
      ..scale = vm.Vector3.all(0.18)
      ..visible = false;

    chassisNode
      ..add(leftSparkNode)
      ..add(rightSparkNode)
      ..add(
        Node(name: '${name}_SparkEmitL')
          ..position = vm.Vector3(-0.76, 0.16, -1.06)
          ..rotation = exhaustRot
          ..addComponent(leftSparkEmitter),
      )
      ..add(
        Node(name: '${name}_SparkEmitR')
          ..position = vm.Vector3(0.76, 0.16, -1.06)
          ..rotation = exhaustRot
          ..addComponent(rightSparkEmitter),
      );

    // 10. Energy Shield Bubble (Item Effect)
    final shieldMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.15, 0.92, 0.85, 0.26)
      ..emissiveFactor = vm.Vector4(0.1, 0.85, 0.75, 1.0)
      ..emissiveStrength = 2.4
      ..alphaMode = AlphaMode.blend
      ..roughnessFactor = 0.08
      ..metallicFactor = 0.1;

    final shieldNode = Node(
      name: '${name}_Shield',
      mesh: Mesh(IcosphereGeometry(radius: 1.85, subdivisions: 2), shieldMat),
    )
      ..position = vm.Vector3(0, 0.85, 0)
      ..visible = false;
    chassisNode.add(shieldNode);

    // 11. Tire Trail Components
    final leftTrailNode = Node(name: '${name}_TrailL')
      ..position = vm.Vector3(-0.78, 0.05, -0.82);
    final rightTrailNode = Node(name: '${name}_TrailR')
      ..position = vm.Vector3(0.78, 0.05, -0.82);

    final leftTrail = TrailComponent(
      maxPoints: 36,
      lifetime: 0.75,
      width: 0.26,
      minVertexDistance: 0.35,
      widthOverTrail: ParticleCurve.linear(from: 1.0, to: 0.08),
      colorOverTrail: ColorGradient(<ColorStop>[
        ColorStop(0.0, vm.Vector4(0.18, 0.18, 0.22, 0.55)),
        ColorStop(1.0, vm.Vector4(0.12, 0.12, 0.15, 0.0)),
      ]),
    );
    final rightTrail = TrailComponent(
      maxPoints: 36,
      lifetime: 0.75,
      width: 0.26,
      minVertexDistance: 0.35,
      widthOverTrail: ParticleCurve.linear(from: 1.0, to: 0.08),
      colorOverTrail: ColorGradient(<ColorStop>[
        ColorStop(0.0, vm.Vector4(0.18, 0.18, 0.22, 0.55)),
        ColorStop(1.0, vm.Vector4(0.12, 0.12, 0.15, 0.0)),
      ]),
    );

    leftTrailNode.addComponent(leftTrail);
    rightTrailNode.addComponent(rightTrail);
    rootNode
      ..add(leftTrailNode)
      ..add(rightTrailNode);

    return KartVisualRig(
      rootNode: rootNode,
      chassisNode: chassisNode,
      steeringWheelNode: steeringWheelNode,
      driverNode: mascotRig.driverRoot,
      driverHeadNode: mascotRig.headNode,
      driverLeftAppendage: mascotRig.leftAppendage,
      driverRightAppendage: mascotRig.rightAppendage,
      frontLeftPivot: frontLeftPivot,
      frontRightPivot: frontRightPivot,
      wheelSpinNodes: wheelSpinNodes,
      leftSparkNode: leftSparkNode,
      rightSparkNode: rightSparkNode,
      sparkMaterial: sparkMaterial,
      exhaustFlameMaterial: exhaustFlameMaterial,
      leftExhaustEmitter: leftExhaustEmitter,
      rightExhaustEmitter: rightExhaustEmitter,
      leftSparkEmitter: leftSparkEmitter,
      rightSparkEmitter: rightSparkEmitter,
      brakeLightMaterial: brakeLightMaterial,
      shieldNode: shieldNode,
      leftTrail: leftTrail,
      rightTrail: rightTrail,
      character: character,
    );
  }

  /// Builds a smooth-shaded, 14-station × 12-point curved aerodynamic monocoque
  /// hull with auto-generated smooth area-weighted vertex normals and zero
  /// internal overlapping faces.
  static MeshGeometry _buildSculptedMonocoqueMesh() {
    // deduplicate: true without explicit .normal() calls lets GeometryBuilder
    // compute smooth area-weighted vertex normals across the whole shell!
    final builder = GeometryBuilder(deduplicate: true);

    // (z, halfWidth, heightTop, crownArch, cockpitDip)
    const stations = <(double, double, double, double, double)>[
      (-1.02, 0.26, 0.22, 0.06, 0.0), // Rear tail tip
      (-0.78, 0.42, 0.30, 0.08, 0.0), // Engine deck
      (-0.46, 0.50, 0.34, 0.08, 0.04), // Rear cockpit bolster
      (-0.12, 0.54, 0.28, 0.04, 0.12), // Cockpit seat well
      (0.22, 0.52, 0.32, 0.06, 0.08), // Cockpit forward well
      (0.50, 0.46, 0.38, 0.10, 0.0), // Front dash scuttle crest
      (0.78, 0.38, 0.31, 0.09, 0.0), // Upper nose slope
      (1.02, 0.30, 0.22, 0.07, 0.0), // Mid nose cone
      (1.22, 0.21, 0.14, 0.05, 0.0), // Lower nose cone
      (1.36, 0.10, 0.08, 0.02, 0.0), // Front nose apex
    ];

    const ringPoints = 12;
    final rings = <List<int>>[];

    for (var s = 0; s < stations.length; s++) {
      final (z, hw, hTop, arch, dip) = stations[s];
      final v = s / (stations.length - 1);
      final ring = <int>[];

      for (var k = 0; k < ringPoints; k++) {
        final u = k / (ringPoints - 1);
        final angle = u * math.pi; // 0 (right bottom) .. pi (left bottom)
        final cosA = math.cos(angle);
        final sinA = math.sin(angle);

        final x = -cosA * hw;
        // Smooth super-elliptical arch profile with optional cockpit dip near top
        final centerFactor = sinA * sinA;
        final y =
            0.02 +
            sinA * hTop +
            centerFactor * arch -
            (centerFactor * centerFactor) * dip;

        builder.texCoord(vm.Vector2(u, v));
        ring.add(builder.addVertex(vm.Vector3(x, y, z)));
      }
      rings.add(ring);
    }

    for (var s = 0; s < rings.length - 1; s++) {
      final r0 = rings[s];
      final r1 = rings[s + 1];
      for (var k = 0; k < ringPoints - 1; k++) {
        final a = r0[k];
        final b = r1[k];
        final c = r1[k + 1];
        final d = r0[k + 1];
        builder
          ..addTriangle(a, b, c)
          ..addTriangle(a, c, d);
      }
    }

    return builder.build();
  }

  /// Builds the HERO-SCALE 3D character mascot rig sitting prominently in the
  /// kart cockpit so it is clearly visible from behind, the sides, and the front!
  static ({
    Node driverRoot,
    Node headNode,
    Node leftAppendage,
    Node rightAppendage,
  }) _buildMascotDriver({
    required RacerCharacter character,
    required vm.Vector4 primaryColor,
    required vm.Vector4 accentColor,
    required PbrAssets pbr,
  }) {
    switch (character) {
      case RacerCharacter.flutterDash:
        return _buildFlutterDashDriver(pbr);
      case RacerCharacter.llama:
        return _buildLlamaDriver(pbr);
      case RacerCharacter.androidBot:
        return _buildAndroidBotDriver();
      case RacerCharacter.chromeDino:
        return _buildChromeDinoDriver(primaryColor, accentColor);
    }
  }

  /// Builds **Flutter Dash** at Hero Scale (2.25x larger than before!):
  /// - Plump sky-blue hummingbird body & head with feather normal map
  /// - Snowy white chest & belly patch + rosy pink cheeks
  /// - 3 large sculpted curved cobalt crest feathers on top of the head
  /// - Wide multi-feather articulated flapping wings spanning outside the cockpit
  /// - 5-feather cobalt & white tail fan over the rear deck
  /// - Brass & cyan aviator racing goggles with wrap-around leather strap & rear buckle
  /// - Flowing red & gold racing scarf streaming behind Dash!
  static ({
    Node driverRoot,
    Node headNode,
    Node leftAppendage,
    Node rightAppendage,
  }) _buildFlutterDashDriver(PbrAssets pbr) {
    final driverRoot = Node(name: 'Driver_FlutterDash')
      ..position = vm.Vector3(0, 0.50, -0.06);

    final dashBlueMat = PhysicallyBasedMaterial(
      normalTexture: pbr.plumageNormal,
    )
      ..baseColorFactor = vm.Vector4(0.16, 0.72, 0.98, 1.0)
      ..roughnessFactor = 0.42
      ..metallicFactor = 0.04
      ..normalScale = 0.55;

    final dashCobaltMat = PhysicallyBasedMaterial(
      normalTexture: pbr.plumageNormal,
    )
      ..baseColorFactor = vm.Vector4(0.04, 0.34, 0.76, 1.0)
      ..roughnessFactor = 0.38
      ..metallicFactor = 0.08
      ..normalScale = 0.65;

    final whitePlumageMat = PhysicallyBasedMaterial(
      normalTexture: pbr.plumageNormal,
    )
      ..baseColorFactor = vm.Vector4(0.97, 0.99, 1.0, 1.0)
      ..roughnessFactor = 0.45
      ..metallicFactor = 0.02
      ..normalScale = 0.40;

    final blushPinkMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.48, 0.62, 1.0)
      ..roughnessFactor = 0.50;

    final beakOrangeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.55, 0.06, 1.0)
      ..roughnessFactor = 0.26
      ..metallicFactor = 0.12;

    final pupilMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.03, 0.04, 0.07, 1.0)
      ..roughnessFactor = 0.06
      ..metallicFactor = 0.6;

    final goggleBrassMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.76, 0.22, 1.0)
      ..roughnessFactor = 0.18
      ..metallicFactor = 0.88;

    final strapLeatherMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.36, 0.20, 0.10, 1.0)
      ..roughnessFactor = 0.55;

    final goggleLensMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.12, 0.88, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.08, 0.55, 0.85, 1.0)
      ..emissiveStrength = 2.2
      ..roughnessFactor = 0.06
      ..metallicFactor = 0.85;

    final scarfRedMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.96, 0.18, 0.24, 1.0)
      ..roughnessFactor = 0.48;

    // 1. Hero-scale plump round Dash body (radius 0.44m!)
    driverRoot.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.44, segments: 28, rings: 20),
          dashBlueMat,
        ),
      )
        ..position = vm.Vector3(0, 0.22, 0.0)
        ..scale = vm.Vector3(1.08, 1.02, 0.96),
    );

    // 2. Snowy white chest & belly plumage
    driverRoot.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.36, segments: 24, rings: 16),
          whitePlumageMat,
        ),
      )
        ..position = vm.Vector3(0, 0.20, 0.16)
        ..scale = vm.Vector3(0.92, 0.92, 0.76),
    );

    // 3. Broad 5-feather cobalt & white tail fan sticking out the back!
    for (var i = -2; i <= 2; i++) {
      final angle = i * 0.24;
      final isOuter = i.abs() == 2;
      driverRoot.add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(
              radius: 0.075,
              height: 0.34,
              radialSegments: 12,
            ),
            isOuter ? whitePlumageMat : dashCobaltMat,
          ),
        )
          ..position = vm.Vector3(
            math.sin(angle) * 0.22,
            0.14,
            -0.44 - math.cos(angle) * 0.06,
          )
          ..rotation = vm.Quaternion.euler(angle, 1.05, 0)
          ..scale = vm.Vector3(0.85, 1.0, 0.55),
      );
    }

    // 4. Flowing Red Racing Scarf collar + twin streaming scarf tails!
    driverRoot.add(
      Node(
        mesh: Mesh(
          TorusGeometry(
            radius: 0.34,
            tubeRadius: 0.055,
            radialSegments: 20,
            tubularSegments: 10,
          ),
          scarfRedMat,
        ),
      )..position = vm.Vector3(0, 0.48, 0.02),
    );
    for (final side in const [-1.0, 1.0]) {
      final scarfPath = CatmullRomPath(<vm.Vector3>[
        vm.Vector3(side * 0.14, 0.48, -0.28),
        vm.Vector3(side * 0.22, 0.44, -0.58),
        vm.Vector3(side * 0.28, 0.50, -0.88),
      ]);
      driverRoot.add(
        Node(
          mesh: Mesh(
            TubeGeometry(
              scarfPath,
              radius: 0.048,
              radialSegments: 10,
              stations: 12,
            ),
            side < 0 ? scarfRedMat : goggleBrassMat,
          ),
        ),
      );
    }

    // 5. Large Multi-Feather Articulated Left & Right Wings (1.48m wingspan!)
    Node buildDashWing(double side) {
      final pivot = Node(
        name: side < 0 ? 'Dash_LeftWing' : 'Dash_RightWing',
      )..position = vm.Vector3(side * 0.42, 0.30, 0.04);

      // Upper cobalt wing shoulder
      pivot.add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.11, height: 0.38, radialSegments: 14),
            dashCobaltMat,
          ),
        )
          ..position = vm.Vector3(side * 0.18, 0.02, 0.04)
          ..rotation = vm.Quaternion.euler(0.0, 0.2, -side * 1.15)
          ..scale = vm.Vector3(1.0, 1.0, 0.65),
      );

      // 3 Fanned Primary Flight Feathers extending outward so they are super visible!
      for (var f = 0; f < 3; f++) {
        pivot.add(
          Node(
            mesh: Mesh(
              CapsuleGeometry(
                radius: 0.068 - f * 0.008,
                height: 0.36 - f * 0.04,
                radialSegments: 12,
              ),
              f == 2 ? dashBlueMat : dashCobaltMat,
            ),
          )
            ..position = vm.Vector3(
              side * (0.30 + f * 0.06),
              -0.04 - f * 0.06,
              -0.04 - f * 0.08,
            )
            ..rotation = vm.Quaternion.euler(
              -side * (0.25 + f * 0.18),
              0.35 + f * 0.15,
              -side * 1.25,
            )
            ..scale = vm.Vector3(0.9, 1.0, 0.52),
        );
      }
      return pivot;
    }

    final leftWingPivot = buildDashWing(-1.0);
    final rightWingPivot = buildDashWing(1.0);
    driverRoot
      ..add(leftWingPivot)
      ..add(rightWingPivot);

    // 6. Hero-Scale Dash Head Node (top of head reaches y = 1.45m, crest = 1.85m!)
    final headNode = Node(name: 'Dash_Head')
      ..position = vm.Vector3(0, 0.62, 0.04);

    headNode.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.39, segments: 28, rings: 20),
          dashBlueMat,
        ),
      )..scale = vm.Vector3(1.06, 0.98, 1.02),
    );

    // 3 Large Sculpted Curved Crest Tuft Feathers on top of Dash's head!
    for (var i = -1; i <= 1; i++) {
      final crestCurve = CatmullRomPath(<vm.Vector3>[
        vm.Vector3(i * 0.06, 0.34, 0.02),
        vm.Vector3(i * 0.11, 0.50, -0.02),
        vm.Vector3(i * 0.16, 0.62 - i.abs() * 0.05, -0.12),
      ]);
      headNode.add(
        Node(
          mesh: Mesh(
            TubeGeometry(
              crestCurve,
              radius: 0.058,
              radialSegments: 12,
              stations: 10,
            ),
            i == 0 ? dashCobaltMat : dashBlueMat,
          ),
        ),
      );
    }

    // Sculpted Orange Hummingbird Cone Beak pointing forward (+Z)
    headNode.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 0.105,
            topRadius: 0.014,
            height: 0.36,
            radialSegments: 18,
          ),
          beakOrangeMat,
        ),
      )
        ..position = vm.Vector3(0, -0.02, 0.46)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
    );

    // Wrap-around Leather Goggle Strap & Gold Rear Clasp (visible from behind!)
    headNode.add(
      Node(
        mesh: Mesh(
          TorusGeometry(
            radius: 0.385,
            tubeRadius: 0.032,
            radialSegments: 24,
            tubularSegments: 10,
          ),
          strapLeatherMat,
        ),
      )
        ..position = vm.Vector3(0, 0.15, 0.0)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.28),
    );
    headNode.add(
      Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(0.14, 0.09, 0.05)), goggleBrassMat),
      )..position = vm.Vector3(0, 0.05, -0.38),
    );

    // Huge Expressive Eyes + Pupils + Catchlights + Rosy Cheeks + Forehead Goggles
    for (final side in const [-1.0, 1.0]) {
      // White sclera
      headNode.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.135, segments: 20, rings: 14),
            whitePlumageMat,
          ),
        )
          ..position = vm.Vector3(side * 0.185, 0.05, 0.29)
          ..scale = vm.Vector3(1.0, 1.10, 0.65),
      );
      // Glossy black pupil
      headNode.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.085, segments: 16, rings: 12),
            pupilMat,
          ),
        )
          ..position = vm.Vector3(side * 0.185, 0.05, 0.355)
          ..scale = vm.Vector3(1.0, 1.05, 0.55),
      );
      // White sparkle catchlight
      headNode.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.028, segments: 10, rings: 8),
            whitePlumageMat,
          ),
        )..position = vm.Vector3(side * 0.185 + 0.03, 0.09, 0.395),
      );
      // Rosy pink cheek blush on side of head (visible from 3/4 rear!)
      headNode.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.075, segments: 14, rings: 10),
            blushPinkMat,
          ),
        )
          ..position = vm.Vector3(side * 0.31, -0.06, 0.20)
          ..scale = vm.Vector3(0.65, 0.85, 1.0),
      );

      // Large Aviator Racing Goggles on Dash's Forehead
      headNode.add(
        Node(
          mesh: Mesh(
            TorusGeometry(
              radius: 0.125,
              tubeRadius: 0.028,
              radialSegments: 20,
              tubularSegments: 10,
            ),
            goggleBrassMat,
          ),
        )
          ..position = vm.Vector3(side * 0.155, 0.24, 0.29)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 1.12),
      );
      headNode.add(
        Node(
          mesh: Mesh(DiscGeometry(radius: 0.108, segments: 18), goggleLensMat),
        )
          ..position = vm.Vector3(side * 0.155, 0.248, 0.298)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 1.12),
      );
    }

    driverRoot.add(headNode);
    return (
      driverRoot: driverRoot,
      headNode: headNode,
      leftAppendage: leftWingPivot,
      rightAppendage: rightWingPivot,
    );
  }

  /// Builds **Turbo Llama** at Hero Scale (rising to y = 2.08m!):
  /// - Big fluffy cream-wool torso with fleece normal map
  /// - Wide patterned Andean woven poncho (`pbr.ponchoAlbedo`) with golden tassels
  /// - Fluffy wagging llama tail at the back
  /// - Tall proud woolly neck + crown topknot puff
  /// - Long curved banana-shaped llama ears (`TubeGeometry`) with pink inner ears
  /// - Sculpted caramel snout/muzzle + wrap-around neon-gold aviator sunglasses!
  static ({
    Node driverRoot,
    Node headNode,
    Node leftAppendage,
    Node rightAppendage,
  }) _buildLlamaDriver(PbrAssets pbr) {
    final driverRoot = Node(name: 'Driver_Llama')
      ..position = vm.Vector3(0, 0.50, -0.06);

    final creamWoolMat = PhysicallyBasedMaterial(
      normalTexture: pbr.plumageNormal,
    )
      ..baseColorFactor = vm.Vector4(0.97, 0.92, 0.82, 1.0)
      ..roughnessFactor = 0.86
      ..metallicFactor = 0.02
      ..normalScale = 0.85;

    final caramelMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.78, 0.54, 0.34, 1.0)
      ..roughnessFactor = 0.68
      ..metallicFactor = 0.04;

    final innerEarPinkMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.96, 0.56, 0.64, 1.0)
      ..roughnessFactor = 0.60;

    final ponchoPatternMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.ponchoAlbedo,
      normalTexture: pbr.plumageNormal,
    )
      ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0)
      ..roughnessFactor = 0.62
      ..normalScale = 0.45;

    final ponchoGoldMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.78, 0.12, 1.0)
      ..roughnessFactor = 0.35
      ..metallicFactor = 0.65;

    final shadesLensMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.45, 0.10, 1.0)
      ..emissiveFactor = vm.Vector4(0.95, 0.35, 0.05, 1.0)
      ..emissiveStrength = 1.8
      ..roughnessFactor = 0.06
      ..metallicFactor = 0.92;

    final darkMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.06, 0.06, 0.10, 1.0)
      ..roughnessFactor = 0.20
      ..metallicFactor = 0.5;

    // 1. Big Fluffy Wool Torso
    driverRoot.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.40, segments: 24, rings: 18),
          creamWoolMat,
        ),
      )
        ..position = vm.Vector3(0, 0.22, -0.02)
        ..scale = vm.Vector3(1.05, 1.0, 1.12),
    );

    // 2. Wide Patterned Andean Woven Poncho Cape + Golden Tassels (super visible from behind!)
    driverRoot.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 0.52,
            topRadius: 0.28,
            height: 0.36,
            radialSegments: 24,
          ),
          ponchoPatternMat,
        ),
      )..position = vm.Vector3(0, 0.32, 0.0),
    );
    driverRoot.add(
      Node(
        mesh: Mesh(
          TorusGeometry(
            radius: 0.30,
            tubeRadius: 0.052,
            radialSegments: 22,
            tubularSegments: 10,
          ),
          ponchoGoldMat,
        ),
      )..position = vm.Vector3(0, 0.48, 0.02),
    );
    // 8 Golden Fringe Tassels hanging around the back & sides of the poncho
    for (var t = 0; t < 8; t++) {
      final angle = math.pi * 0.65 + (t / 7.0) * math.pi * 0.70;
      driverRoot.add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.032, height: 0.10, radialSegments: 8),
            ponchoGoldMat,
          ),
        )
          ..position = vm.Vector3(
            math.sin(angle) * 0.50,
            0.14,
            math.cos(angle) * 0.50,
          ),
      );
    }

    // 3. Fluffy Perky Llama Tail at the rear
    driverRoot.add(
      Node(
        mesh: Mesh(
          CapsuleGeometry(radius: 0.095, height: 0.22, radialSegments: 14),
          creamWoolMat,
        ),
      )
        ..position = vm.Vector3(0, 0.24, -0.48)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.55),
    );

    // 4. Front Woolly Llama Forelegs gripping the steering wheel
    for (final side in const [-1.0, 1.0]) {
      driverRoot.add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.088, height: 0.36, radialSegments: 12),
            creamWoolMat,
          ),
        )
          ..position = vm.Vector3(side * 0.28, 0.24, 0.24)
          ..rotation = vm.Quaternion.euler(-side * 0.25, 1.15, 0),
      );
    }

    // 5. Characteristic Tall Proud Sculpted Llama Neck!
    final neckCurve = CatmullRomPath(<vm.Vector3>[
      vm.Vector3(0, 0.42, 0.02),
      vm.Vector3(0, 0.68, 0.06),
      vm.Vector3(0, 0.94, 0.08),
    ]);
    driverRoot.add(
      Node(
        mesh: Mesh(
          TubeGeometry(
            neckCurve,
            radius: 0.195,
            radialSegments: 18,
            stations: 12,
          ),
          creamWoolMat,
        ),
      ),
    );

    // 6. Hero-Scale Llama Head Node at top of long neck (y = 0.98m above seat!)
    final headNode = Node(name: 'Llama_Head')
      ..position = vm.Vector3(0, 0.98, 0.09);

    // Fluffy cranium
    headNode.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.31, segments: 24, rings: 18),
          creamWoolMat,
        ),
      )..scale = vm.Vector3(0.96, 1.05, 1.12),
    );

    // Big Fluffy Woolly Topknot Puff on Crown (3 overlapping wool puffs)
    for (var i = -1; i <= 1; i++) {
      headNode.add(
        Node(
          mesh: Mesh(
            SphereGeometry(
              radius: i == 0 ? 0.17 : 0.13,
              segments: 16,
              rings: 12,
            ),
            creamWoolMat,
          ),
        )..position = vm.Vector3(i * 0.10, 0.26 - i.abs() * 0.03, 0.05),
      );
    }

    // Sculpted Caramel Llama Snout / Muzzle
    headNode.add(
      Node(
        mesh: Mesh(
          CapsuleGeometry(radius: 0.155, height: 0.26, radialSegments: 18),
          caramelMat,
        ),
      )
        ..position = vm.Vector3(0, -0.04, 0.32)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
    );

    // Cute Dark Llama Nose Tip + Nostrils
    headNode.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.062, segments: 14, rings: 10),
          darkMat,
        ),
      )..position = vm.Vector3(0, 0.02, 0.49),
    );

    // Wrap-Around Neon-Gold Mirror Aviator Sunglasses + Headband Strap!
    headNode.add(
      Node(
        mesh: Mesh(
          TorusGeometry(
            radius: 0.295,
            tubeRadius: 0.026,
            radialSegments: 22,
            tubularSegments: 8,
          ),
          darkMat,
        ),
      )..position = vm.Vector3(0, 0.08, 0.0),
    );
    headNode.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.52, 0.13, 0.12)),
          shadesLensMat,
        ),
      )..position = vm.Vector3(0, 0.09, 0.28),
    );
    headNode.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.54, 0.032, 0.13)),
          ponchoGoldMat,
        ),
      )..position = vm.Vector3(0, 0.16, 0.285),
    );

    // 7. Iconic Tall Curved Banana-Shaped Llama Ears (0.48m tall!)
    Node buildLlamaEar(double side) {
      final pivot = Node(name: side < 0 ? 'Llama_LeftEar' : 'Llama_RightEar')
        ..position = vm.Vector3(side * 0.19, 0.22, -0.04);

      // Curved banana-ear path curving up and inward at the tip!
      final earCurve = CatmullRomPath(<vm.Vector3>[
        vm.Vector3(0.0, 0.0, 0.0),
        vm.Vector3(side * 0.06, 0.18, -0.02),
        vm.Vector3(side * 0.03, 0.36, 0.02),
        vm.Vector3(-side * 0.04, 0.48, 0.05),
      ]);
      pivot.add(
        Node(
          mesh: Mesh(
            TubeGeometry(
              earCurve,
              radius: 0.078,
              radialSegments: 14,
              stations: 12,
            ),
            creamWoolMat,
          ),
        ),
      );
      // Pink inner ear highlight
      pivot.add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.046, height: 0.28, radialSegments: 10),
            innerEarPinkMat,
          ),
        )..position = vm.Vector3(side * 0.02, 0.24, 0.045),
      );
      return pivot;
    }

    final leftEar = buildLlamaEar(-1.0);
    final rightEar = buildLlamaEar(1.0);
    headNode
      ..add(leftEar)
      ..add(rightEar);

    driverRoot.add(headNode);
    return (
      driverRoot: driverRoot,
      headNode: headNode,
      leftAppendage: leftEar,
      rightAppendage: rightEar,
    );
  }

  /// Builds **Bugdroid Bot** at Hero Scale (Android green robot with twin
  /// antennae, glowing eyes & twin chrome jetpack thrusters on its back).
  static ({
    Node driverRoot,
    Node headNode,
    Node leftAppendage,
    Node rightAppendage,
  }) _buildAndroidBotDriver() {
    final driverRoot = Node(name: 'Driver_AndroidBot')
      ..position = vm.Vector3(0, 0.50, -0.06);

    final androidGreenMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.22, 0.88, 0.52, 1.0)
      ..roughnessFactor = 0.24
      ..metallicFactor = 0.20;

    final chromeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.90, 0.93, 0.97, 1.0)
      ..roughnessFactor = 0.15
      ..metallicFactor = 0.92;

    final eyeGlowMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.7, 1.0, 0.9, 1.0)
      ..emissiveStrength = 4.5;

    // Large cylindrical torso
    driverRoot.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 0.36,
            topRadius: 0.36,
            height: 0.48,
            radialSegments: 24,
          ),
          androidGreenMat,
        ),
      )..position = vm.Vector3(0, 0.24, 0),
    );

    // Twin chrome jetpack thrusters on back
    for (final side in const [-1.0, 1.0]) {
      driverRoot.add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.085, height: 0.24, radialSegments: 12),
            chromeMat,
          ),
        )..position = vm.Vector3(side * 0.16, 0.28, -0.36),
      );
    }

    final leftArm = Node(name: 'Bot_LeftArm')
      ..position = vm.Vector3(-0.44, 0.32, 0.04)
      ..add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.085, height: 0.32, radialSegments: 12),
            androidGreenMat,
          ),
        )
          ..position = vm.Vector3(0, 0, 0.14)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 1.25),
      );
    final rightArm = Node(name: 'Bot_RightArm')
      ..position = vm.Vector3(0.44, 0.32, 0.04)
      ..add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.085, height: 0.32, radialSegments: 12),
            androidGreenMat,
          ),
        )
          ..position = vm.Vector3(0, 0, 0.14)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 1.25),
      );
    driverRoot
      ..add(leftArm)
      ..add(rightArm);

    final headNode = Node(name: 'Bot_Head')
      ..position = vm.Vector3(0, 0.56, 0.0);
    headNode.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.36, segments: 24, rings: 16),
          androidGreenMat,
        ),
      ),
    );
    for (final side in const [-1.0, 1.0]) {
      headNode.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.055, segments: 12, rings: 10),
            eyeGlowMat,
          ),
        )..position = vm.Vector3(side * 0.15, 0.08, 0.32),
      );
      headNode.add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.028, height: 0.22, radialSegments: 10),
            androidGreenMat,
          ),
        )
          ..position = vm.Vector3(side * 0.20, 0.38, 0.0)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            -side * 0.48,
          ),
      );
    }
    driverRoot.add(headNode);
    return (
      driverRoot: driverRoot,
      headNode: headNode,
      leftAppendage: leftArm,
      rightAppendage: rightArm,
    );
  }

  /// Builds **Blaze Dino** at Hero Scale (fiery orange T-Rex mascot with
  /// sculpted snout, tail, and 5 golden dorsal crest spikes).
  static ({
    Node driverRoot,
    Node headNode,
    Node leftAppendage,
    Node rightAppendage,
  }) _buildChromeDinoDriver(vm.Vector4 primaryColor, vm.Vector4 accentColor) {
    final driverRoot = Node(name: 'Driver_Dino')
      ..position = vm.Vector3(0, 0.50, -0.06);

    final dinoMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.96, 0.34, 0.14, 1.0)
      ..roughnessFactor = 0.42;
    final spikeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.82, 0.14, 1.0)
      ..roughnessFactor = 0.28
      ..metallicFactor = 0.35;
    final eyeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.98, 0.9, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.85, 0.2, 1.0)
      ..emissiveStrength = 3.0;

    driverRoot.add(
      Node(
        mesh: Mesh(
          CapsuleGeometry(radius: 0.34, height: 0.38, radialSegments: 20),
          dinoMat,
        ),
      )..position = vm.Vector3(0, 0.26, 0),
    );

    // Swept Dino Tail sticking out the back
    final tailCurve = CatmullRomPath(<vm.Vector3>[
      vm.Vector3(0, 0.18, -0.28),
      vm.Vector3(0, 0.22, -0.58),
      vm.Vector3(0, 0.34, -0.86),
    ]);
    driverRoot.add(
      Node(
        mesh: Mesh(
          TubeGeometry(
            tailCurve,
            radius: 0.12,
            radialSegments: 12,
            stations: 10,
          ),
          dinoMat,
        ),
      ),
    );

    final leftArm = Node(name: 'Dino_LeftArm')
      ..position = vm.Vector3(-0.34, 0.34, 0.16)
      ..add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.065, height: 0.24, radialSegments: 10),
            dinoMat,
          ),
        )..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 1.2),
      );
    final rightArm = Node(name: 'Dino_RightArm')
      ..position = vm.Vector3(0.34, 0.34, 0.16)
      ..add(
        Node(
          mesh: Mesh(
            CapsuleGeometry(radius: 0.065, height: 0.24, radialSegments: 10),
            dinoMat,
          ),
        )..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 1.2),
      );
    driverRoot
      ..add(leftArm)
      ..add(rightArm);

    final headNode = Node(name: 'Dino_Head')
      ..position = vm.Vector3(0, 0.66, 0.06);
    headNode.add(
      Node(
        mesh: Mesh(
          CapsuleGeometry(radius: 0.26, height: 0.28, radialSegments: 18),
          dinoMat,
        ),
      )
        ..position = vm.Vector3(0, 0.04, 0.10)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
    );

    // 4 Large Golden Dorsal Crest Spikes down head & neck
    for (var i = 0; i < 4; i++) {
      headNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.085,
              topRadius: 0.01,
              height: 0.22,
              radialSegments: 10,
            ),
            spikeMat,
          ),
        )
          ..position = vm.Vector3(0, 0.32 - i * 0.08, 0.04 - i * 0.15)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.45),
      );
    }
    for (final side in const [-1.0, 1.0]) {
      headNode.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.065, segments: 12, rings: 10),
            eyeMat,
          ),
        )..position = vm.Vector3(side * 0.23, 0.10, 0.18),
      );
    }
    driverRoot.add(headNode);
    return (
      driverRoot: driverRoot,
      headNode: headNode,
      leftAppendage: leftArm,
      rightAppendage: rightArm,
    );
  }
}
