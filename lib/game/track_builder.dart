import 'dart:math' as math;

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/noise.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'pbr_assets.dart';
import 'track_data.dart';

/// Holds references to dynamic track scene nodes (rotating item boxes,
/// scrolling boost pads, obstacle nodes, hot-air balloons, blimp, and clouds).
class TrackWorldVisuals {
  TrackWorldVisuals({
    required this.rootNode,
    required this.itemBoxNodes,
    required this.itemCoreNodes,
    required this.coinNodes,
    required this.boostPadMaterial,
    required this.jumpRampMaterial,
    required this.obstacleNodes,
    required this.balloonNodes,
    required this.balloonBasePositions,
    required this.blimpNode,
    required this.cloudRingNode,
  });

  final Node rootNode;
  final List<Node> itemBoxNodes;
  final List<Node> itemCoreNodes;
  final List<Node> coinNodes;
  final PhysicallyBasedMaterial boostPadMaterial;
  final PhysicallyBasedMaterial jumpRampMaterial;
  final List<Node> obstacleNodes;
  final List<Node> balloonNodes;
  final List<vm.Vector3> balloonBasePositions;
  final Node blimpNode;
  final Node cloudRingNode;

  double _clock = 0.0;

  /// Animates floating item crystals, spinning gold coins, scrolling boost
  /// chevrons, bobbing hot-air balloons, stadium blimp, and drifting clouds.
  void update(double dt, TrackCircuit track) {
    _clock += dt;

    // 1. Scroll boost pad & jump ramp chevron UVs forward at high speed
    final scrollOffset = vm.Vector2(0.0, -(_clock * 2.4) % 1.0);
    final uvTransform = TextureTransform(offset: scrollOffset);
    boostPadMaterial.baseColorTextureTransform = uvTransform;
    boostPadMaterial.emissiveTextureTransform = uvTransform;
    jumpRampMaterial.baseColorTextureTransform = uvTransform;
    jumpRampMaterial.emissiveTextureTransform = uvTransform;

    // 2. Rotate & bob item boxes and counter-rotate their inner power cores
    for (var i = 0; i < track.itemBoxes.length; i++) {
      final box = track.itemBoxes[i];
      final node = itemBoxNodes[i];
      if (box.isActive) {
        final bob = math.sin(_clock * 3.4 + i * 0.8) * 0.24;
        node.position = vm.Vector3(
          box.basePosition.x,
          box.basePosition.y + bob,
          box.basePosition.z,
        );
        node.rotation = vm.Quaternion.euler(
          _clock * 1.9 + i * 0.5,
          0.52,
          _clock * 1.1,
        );
        itemCoreNodes[i].rotation = vm.Quaternion.euler(
          -_clock * 3.2,
          _clock * 2.1,
          0.0,
        );
      }
    }

    // 3. Spin & bob Gold Coins along the racing line
    for (var i = 0; i < track.coins.length; i++) {
      final coin = track.coins[i];
      final node = coinNodes[i];
      if (coin.isActive) {
        final bob = math.sin(_clock * 4.2 + i * 0.55) * 0.14;
        node.position = vm.Vector3(
          coin.basePosition.x,
          coin.basePosition.y + bob,
          coin.basePosition.z,
        );
        node.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          _clock * 3.6 + i * 0.35,
        );
      }
    }

    // 4. Gently bob & sway 3D Hot-Air Balloons in the sky
    for (var i = 0; i < balloonNodes.length; i++) {
      final base = balloonBasePositions[i];
      final bobY = math.sin(_clock * 0.75 + i * 1.3) * 1.8;
      final swayX = math.cos(_clock * 0.35 + i * 0.9) * 1.4;
      balloonNodes[i].position = vm.Vector3(
        base.x + swayX,
        base.y + bobY,
        base.z,
      );
      balloonNodes[i].rotation = vm.Quaternion.euler(
        _clock * 0.18 + i,
        0.0,
        math.sin(_clock * 0.9 + i) * 0.05,
      );
    }

    // 5. Cruise the Aerial Stadium Blimp around the Grand Prix circuit
    final blimpAngle = _clock * 0.085;
    const blimpOrbitR = 115.0;
    final bx = 58.0 + math.cos(blimpAngle) * blimpOrbitR;
    final bz = -20.0 + math.sin(blimpAngle) * (blimpOrbitR * 0.85);
    final by = 48.0 + math.sin(_clock * 0.6) * 1.2;
    // Tangent direction of orbit: (-sin(blimpAngle), 0, cos(blimpAngle) * 0.85)
    final tangentYaw = math.atan2(
      -math.sin(blimpAngle),
      math.cos(blimpAngle) * 0.85,
    );
    blimpNode
      ..position = vm.Vector3(bx, by, bz)
      ..rotation = vm.Quaternion.euler(
        tangentYaw,
        math.sin(_clock * 0.8) * 0.03,
        -0.06,
      );

    // 6. Slowly drift upper cumulus cloud ring
    cloudRingNode.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      _clock * 0.012,
    );
  }
}

/// Builds the complete 3D track circuit, continuous swept FIA curbs, PBR
/// tarmac, sculpted mountain backdrop, infield lake, grandstands, and props.
class TrackBuilder {
  static TrackWorldVisuals buildTrackWorld(TrackCircuit track) {
    final pbr = PbrAssets.instance;
    final root = Node(name: 'TrackWorld');

    // 1. Lush Textured Grass Ground + Glitch-Free Sculpted 3D Alpine Panorama + Infield Lake
    root.add(_buildTerrainAndGround(pbr));
    root.add(_buildInfieldLake());
    final skyLandmarks = _buildSkyLandmarks();
    root.add(skyLandmarks.container);

    // 2. Main Asphalt Road Ribbon with PBR Albedo, Normal & Roughness Maps
    final pathPoints = track.samples.map((s) => s.position).toList();
    pathPoints.add(track.samples.first.position.clone());
    final catmullPath = CatmullRomPath(pathPoints);

    // Asphalt Shoulder Base Ribbon
    final shoulderGeo = RibbonGeometry(
      catmullPath,
      width: TrackCircuit.roadHalfWidth * 2.0 + TrackCircuit.curbWidth * 2.4,
      stations: 320,
      alignment: RibbonAlignment.ground,
    );
    final shoulderMat = PhysicallyBasedMaterial(
      normalTexture: pbr.roadNormal,
    )
      ..baseColorFactor = vm.Vector4(0.18, 0.19, 0.22, 1.0)
      ..roughnessFactor = 0.88
      ..metallicFactor = 0.04
      ..normalScale = 0.8
      ..normalTextureTransform = TextureTransform(
        scale: vm.Vector2(2.0, track.totalLength / 14.0),
      );
    final shoulderNode = Node(
      name: 'TrackShoulder',
      mesh: Mesh(shoulderGeo, shoulderMat),
    )
      ..position = vm.Vector3(0, -0.025, 0)
      ..shadowStatic = true;
    root.add(shoulderNode);

    // Main PBR Asphalt Road Surface (includes white edge lines, racing groove & dashed centerline)
    final roadGeo = RibbonGeometry(
      catmullPath,
      width: TrackCircuit.roadHalfWidth * 2.0,
      stations: 360,
      alignment: RibbonAlignment.ground,
    );
    // RibbonGeometry v runs 0..track.totalLength, so scaling V by 1/14 tiles every 14m
    final roadUvTransform = TextureTransform(
      scale: vm.Vector2(1.0, 1.0 / 14.0),
    );
    final roadMaterial = PhysicallyBasedMaterial(
      baseColorTexture: pbr.roadAlbedo,
      normalTexture: pbr.roadNormal,
      metallicRoughnessTexture: pbr.roadRoughness,
    )
      ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0)
      ..roughnessFactor = 1.0
      ..metallicFactor = 1.0
      ..normalScale = 1.35
      ..baseColorTextureTransform = roadUvTransform
      ..normalTextureTransform = roadUvTransform
      ..metallicRoughnessTextureTransform = roadUvTransform;

    final roadNode = Node(
      name: 'RoadSurface',
      mesh: Mesh(roadGeo, roadMaterial),
    )..shadowStatic = true;
    root.add(roadNode);

    // 3. Continuous Swept 3D FIA Beveled Curbs (Zero Coplanar Overlaps!)
    root.add(_buildSweptCurbs(track, pbr));

    // 4. Continuous Swept Metallic Armco Crash Barriers
    root.add(_buildSweptBarriers(track));

    // 5. Start/Finish Grand Prix Gantry & Starting Grid
    root.add(_buildStartFinishGantry(track, pbr));

    // 6. Checkpoint Laser Gates
    root.add(_buildCheckpointGates(track));

    // 7. Scrolling Neon Chevron Boost Pads & 3D Aero Jump Ramps
    final boostVisuals = _buildBoostPads(track, pbr);
    root.add(boostVisuals.container);
    final jumpRampVisuals = _buildJumpRamps(track, pbr);
    root.add(jumpRampVisuals.container);

    // 8. Holo-Crystal Item Boxes
    final itemVisuals = _buildItemBoxes(track);
    root.add(itemVisuals.container);

    // 8b. Spinning 3D Gold Coins
    final coinVisuals = _buildCoins(track);
    root.add(coinVisuals.container);

    // 9. High-Detail Track Obstacles (Cones & Iridescent Oil Slicks)
    final obstacleVisuals = _buildObstacles(track);
    root.add(obstacleVisuals.container);

    // 10. Grandstands, Floodlight Towers, and Multi-Tier Trees
    root.add(_buildEnvironmentScenery(track, pbr));

    return TrackWorldVisuals(
      rootNode: root,
      itemBoxNodes: itemVisuals.outerNodes,
      itemCoreNodes: itemVisuals.coreNodes,
      coinNodes: coinVisuals.nodes,
      boostPadMaterial: boostVisuals.material,
      jumpRampMaterial: jumpRampVisuals.material,
      obstacleNodes: obstacleVisuals.nodes,
      balloonNodes: skyLandmarks.balloonNodes,
      balloonBasePositions: skyLandmarks.balloonBasePositions,
      blimpNode: skyLandmarks.blimpNode,
      cloudRingNode: skyLandmarks.cloudRingNode,
    );
  }

  /// Builds the textured turf ground plane centered on the circuit and a
  /// glitch-free 3D sculpted Alpine mountain panorama completely outside the
  /// circuit perimeter (no UV wrap seams, no ground z-fighting, no track clipping).
  static Node _buildTerrainAndGround(PbrAssets pbr) {
    final container = Node(name: 'TerrainAndGround');

    // True geometric center of the circuit loop (X: -16..136, Z: -156..110)
    const centerX = 60.0;
    const centerZ = -23.0;

    final grassUv = TextureTransform(scale: vm.Vector2(36.0, 36.0));
    final grassMaterial = PhysicallyBasedMaterial(
      baseColorTexture: pbr.grassAlbedo,
      normalTexture: pbr.grassNormal,
    )
      ..baseColorFactor = vm.Vector4(0.95, 1.0, 0.92, 1.0)
      ..roughnessFactor = 0.93
      ..metallicFactor = 0.01
      ..normalScale = 0.35
      ..baseColorTextureTransform = grassUv
      ..normalTextureTransform = grassUv;

    final groundNode = Node(
      name: 'GroundGrass',
      mesh: Mesh(
        PlaneGeometry(width: 960, depth: 960, segmentsX: 4, segmentsZ: 4),
        grassMaterial,
      ),
    )
      ..position = vm.Vector3(centerX, -0.14, centerZ)
      ..shadowStatic = true;
    container.add(groundNode);

    // Sculpted 3D Alpine Mountain Range outside the entire circuit + scenery
    final hillNoise = FastNoiseLite(seed: 909)
      ..noiseType = NoiseType.openSimplex2
      ..frequency = 0.0085
      ..fractalType = FractalType.fbm
      ..octaves = 4;

    const angularSteps = 96;
    const radialRings = 9;
    const innerRadius = 240.0;
    const outerRadius = 460.0;

    // Use angularSteps + 1 columns so column `angularSteps` duplicates column 0
    // spatially without wrapping UVs backwards across a triangle!
    final positionsGrid = List.generate(
      radialRings,
      (_) => List<vm.Vector3>.filled(angularSteps + 1, vm.Vector3.zero()),
    );
    final colorsGrid = List.generate(
      radialRings,
      (_) => List<vm.Vector4>.filled(angularSteps + 1, vm.Vector4.zero()),
    );

    for (var r = 0; r < radialRings; r++) {
      final tR = r / (radialRings - 1);
      final radius = innerRadius + (outerRadius - innerRadius) * tR;
      final arch = math.sin(tR * math.pi);

      for (var a = 0; a <= angularSteps; a++) {
        final wrappedA = a % angularSteps;
        final theta = (wrappedA / angularSteps) * math.pi * 2.0;
        final x = centerX + math.cos(theta) * radius;
        final z = centerZ + math.sin(theta) * radius * 0.94;

        double height;
        if (r == 0 || r == radialRings - 1) {
          // Tuck inner & outer skirt edges well below GroundGrass (-0.14m)
          // so the mountain base intersects the ground steeply with zero z-fighting!
          height = -2.8;
        } else {
          final n = (hillNoise.getNoise2(x, z) + 1.0) * 0.5;
          final ridge =
              math.pow(n, 1.35).toDouble() * 44.0 +
              (math.sin(theta * 5.0) * 6.5 + math.cos(theta * 9.0) * 4.5).abs();
          height = 2.5 + arch * (10.0 + ridge);
        }

        // Rich vertex color gradient: lush emerald foothills -> alpine slate -> snow summits
        vm.Vector4 vColor;
        if (height < 6.0) {
          vColor = vm.Vector4(0.20, 0.50, 0.24, 1.0);
        } else if (height < 22.0) {
          final f = ((height - 6.0) / 16.0).clamp(0.0, 1.0);
          vColor = vm.Vector4(
            0.20 + f * 0.22,
            0.50 - f * 0.06,
            0.24 + f * 0.22,
            1.0,
          );
        } else if (height < 36.0) {
          final f = ((height - 22.0) / 14.0).clamp(0.0, 1.0);
          vColor = vm.Vector4(
            0.42 + f * 0.16,
            0.44 + f * 0.15,
            0.46 + f * 0.18,
            1.0,
          );
        } else {
          final f = ((height - 36.0) / 16.0).clamp(0.0, 1.0);
          vColor = vm.Vector4(
            0.58 + f * 0.38,
            0.59 + f * 0.38,
            0.64 + f * 0.35,
            1.0,
          );
        }

        positionsGrid[r][a] = vm.Vector3(x, height, z);
        colorsGrid[r][a] = vColor;
      }
    }

    // Pure smooth vertex-colored material without high-frequency normal texture
    // so distant horizon peaks never moiré or shimmer.
    final hillMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0)
      ..roughnessFactor = 0.88
      ..metallicFactor = 0.02
      ..doubleSided = true;

    // Split PerimeterHills into 8 angular sector meshes (12 steps = 45° each)
    // so the camera is NEVER inside the bounding box of a single 360° ring mesh!
    // This allows flutter_scene to keep optimal depth precision and frustum culling.
    const sectorCount = 8;
    const stepsPerSector = angularSteps ~/ sectorCount;

    for (var s = 0; s < sectorCount; s++) {
      final aStart = s * stepsPerSector;
      final sectorBuilder = GeometryBuilder();

      final sectorIndices = List.generate(
        radialRings,
        (_) => List<int>.filled(stepsPerSector + 1, 0),
      );

      for (var r = 0; r < radialRings; r++) {
        final tR = r / (radialRings - 1);
        for (var localA = 0; localA <= stepsPerSector; localA++) {
          final a = aStart + localA;
          final prevA = (a - 1 + angularSteps) % angularSteps;
          final nextA = (a + 1) % angularSteps;
          final prevR = math.max(0, r - 1);
          final nextR = math.min(radialRings - 1, r + 1);

          final tangentA = positionsGrid[r][nextA] - positionsGrid[r][prevA];
          final tangentR = positionsGrid[nextR][a] - positionsGrid[prevR][a];
          var normal = tangentA.cross(tangentR);
          if (normal.length2 < 1e-6) {
            normal = vm.Vector3(0, 1, 0);
          } else {
            normal.normalize();
            if (normal.y < 0) normal.negate();
          }

          sectorBuilder
            ..normal(normal)
            ..color(colorsGrid[r][a])
            ..texCoord(vm.Vector2(a / angularSteps * 16.0, tR * 4.0));
          sectorIndices[r][localA] = sectorBuilder.addVertex(positionsGrid[r][a]);
        }
      }

      for (var r = 0; r < radialRings - 1; r++) {
        for (var localA = 0; localA < stepsPerSector; localA++) {
          final i00 = sectorIndices[r][localA];
          final i10 = sectorIndices[r + 1][localA];
          final i11 = sectorIndices[r + 1][localA + 1];
          final i01 = sectorIndices[r][localA + 1];
          sectorBuilder
            ..addTriangle(i00, i11, i10)
            ..addTriangle(i00, i01, i11);
        }
      }

      container.add(
        Node(
          name: 'PerimeterHills_Sector_$s',
          mesh: Mesh(sectorBuilder.build(), hillMat),
        )..shadowStatic = true,
      );
    }

    return container;
  }

  /// Builds a scenic turquoise lake in the true north infield `(56, 0, 44)`
  /// with a sandy shore and an island crystal lighthouse spire landmark.
  static Node _buildInfieldLake() {
    final lakeRoot = Node(name: 'InfieldLake')
      ..position = vm.Vector3(56.0, 0.0, 44.0);

    // Sandy beach ring
    final sandMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.90, 0.82, 0.62, 1.0)
      ..roughnessFactor = 0.85
      ..depthLayer = 1;
    lakeRoot.add(
      Node(
        name: 'LakeBeach',
        mesh: Mesh(
          RingGeometry(innerRadius: 14.5, outerRadius: 19.5, segments: 36),
          sandMat,
        ),
      )..position = vm.Vector3(0, -0.05, 0),
    );

    // Reflective turquoise water surface disc with WaterSurfaceComponent
    final waterMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.06, 0.58, 0.78, 0.94)
      ..roughnessFactor = 0.08
      ..metallicFactor = 0.15
      ..ior = 1.33
      ..specular = 1.0
      ..depthLayer = 2;

    final waterNode = Node(
      name: 'LakeWater',
      mesh: Mesh(DiscGeometry(radius: 15.2, segments: 36), waterMat),
    )
      ..position = vm.Vector3(0, -0.03, 0)
      ..addComponent(WaterSurfaceComponent());
    lakeRoot.add(waterNode);

    // Center island rock & lighthouse/spire monument
    final rockMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.45, 0.47, 0.52, 1.0)
      ..roughnessFactor = 0.78;
    final spireMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.96, 0.98, 1.0)
      ..roughnessFactor = 0.25
      ..metallicFactor = 0.3;
    final stripeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.92, 0.18, 0.16, 1.0)
      ..roughnessFactor = 0.30;
    final beaconMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.1, 0.9, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.1, 0.85, 1.0, 1.0)
      ..emissiveStrength = 6.0;

    lakeRoot.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 4.5,
            topRadius: 3.0,
            height: 1.8,
            radialSegments: 16,
          ),
          rockMat,
        ),
      )..position = vm.Vector3(0, 0.8, 0),
    );
    lakeRoot.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 1.4,
            topRadius: 0.70,
            height: 9.5,
            radialSegments: 16,
          ),
          spireMat,
        ),
      )..position = vm.Vector3(0, 6.2, 0),
    );
    lakeRoot.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 1.18,
            topRadius: 0.98,
            height: 2.2,
            radialSegments: 16,
            topCap: false,
            bottomCap: false,
          ),
          stripeMat,
        ),
      )..position = vm.Vector3(0, 6.5, 0),
    );
    lakeRoot.add(
      Node(
        mesh: Mesh(IcosphereGeometry(radius: 1.15, subdivisions: 2), beaconMat),
      )..position = vm.Vector3(0, 11.6, 0),
    );

    return lakeRoot;
  }

  /// Builds festive 3D sky landmarks: 6 colorful Hot-Air Balloons, an orbiting
  /// Grand Prix Stadium Blimp, and a high-altitude ring of sculpted 3D clouds.
  static ({
    Node container,
    List<Node> balloonNodes,
    List<vm.Vector3> balloonBasePositions,
    Node blimpNode,
    Node cloudRingNode,
  }) _buildSkyLandmarks() {
    final container = Node(name: 'SkyLandmarks');
    final balloonNodes = <Node>[];
    final balloonBasePositions = <vm.Vector3>[];

    final balloonSpecs = <(vm.Vector3, vm.Vector4, vm.Vector4)>[
      (
        vm.Vector3(-42.0, 28.0, 72.0),
        vm.Vector4(0.98, 0.26, 0.34, 1.0),
        vm.Vector4(1.0, 0.82, 0.16, 1.0),
      ),
      (
        vm.Vector3(48.0, 34.0, 146.0),
        vm.Vector4(0.14, 0.68, 0.98, 1.0),
        vm.Vector4(0.98, 0.98, 1.0, 1.0),
      ),
      (
        vm.Vector3(172.0, 30.0, 56.0),
        vm.Vector4(1.0, 0.62, 0.12, 1.0),
        vm.Vector4(0.58, 0.18, 0.92, 1.0),
      ),
      (
        vm.Vector3(164.0, 32.0, -96.0),
        vm.Vector4(0.18, 0.86, 0.52, 1.0),
        vm.Vector4(1.0, 0.92, 0.22, 1.0),
      ),
      (
        vm.Vector3(42.0, 29.0, -190.0),
        vm.Vector4(0.88, 0.22, 0.78, 1.0),
        vm.Vector4(0.18, 0.88, 1.0, 1.0),
      ),
      (
        vm.Vector3(-56.0, 31.0, -64.0),
        vm.Vector4(1.0, 0.76, 0.10, 1.0),
        vm.Vector4(0.12, 0.58, 0.96, 1.0),
      ),
    ];

    final basketMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.56, 0.38, 0.20, 1.0)
      ..roughnessFactor = 0.82;
    final burnerMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.72, 0.18, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.58, 0.12, 1.0)
      ..emissiveStrength = 5.5;

    for (var i = 0; i < balloonSpecs.length; i++) {
      final (basePos, primaryCol, bandCol) = balloonSpecs[i];
      final bNode = Node(name: 'HotAirBalloon_$i')..position = basePos.clone();

      final envMat = PhysicallyBasedMaterial()
        ..baseColorFactor = primaryCol
        ..roughnessFactor = 0.42;
      final bandMat = PhysicallyBasedMaterial()
        ..baseColorFactor = bandCol
        ..roughnessFactor = 0.38;

      // Upper balloon dome
      bNode.add(
        Node(
          mesh: Mesh(SphereGeometry(radius: 4.2, segments: 20, rings: 14), envMat),
        )..scale = vm.Vector3(1.0, 1.18, 1.0),
      );
      // Equatorial accent band torus
      bNode.add(
        Node(
          mesh: Mesh(
            TorusGeometry(
              radius: 4.05,
              tubeRadius: 0.42,
              radialSegments: 20,
              tubularSegments: 10,
            ),
            bandMat,
          ),
        )..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
      );
      // Lower tapered throat cone
      bNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 1.2,
              topRadius: 3.1,
              height: 3.2,
              radialSegments: 16,
            ),
            bandMat,
          ),
        )..position = vm.Vector3(0, -3.6, 0),
      );
      // Glowing burner flame
      bNode.add(
        Node(
          mesh: Mesh(SphereGeometry(radius: 0.55, segments: 10, rings: 8), burnerMat),
        )..position = vm.Vector3(0, -5.5, 0),
      );
      // Suspended wicker gondola basket
      bNode.add(
        Node(
          mesh: Mesh(CuboidGeometry(vm.Vector3(1.6, 1.2, 1.6)), basketMat),
        )..position = vm.Vector3(0, -6.9, 0),
      );

      container.add(bNode);
      balloonNodes.add(bNode);
      balloonBasePositions.add(basePos);
    }

    // Giant "FLUTTER GP" Aerial Stadium Blimp
    final blimpNode = Node(name: 'StadiumBlimp')
      ..position = vm.Vector3(173.0, 48.0, -20.0);
    final blimpHullMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.96, 0.98, 1.0, 1.0)
      ..roughnessFactor = 0.25
      ..metallicFactor = 0.12;
    final blimpStripeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.12, 0.64, 0.96, 1.0)
      ..emissiveFactor = vm.Vector4(0.05, 0.32, 0.65, 1.0)
      ..emissiveStrength = 1.4
      ..roughnessFactor = 0.28;
    final blimpFinMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.72, 0.08, 1.0)
      ..roughnessFactor = 0.32;

    // Streamlined ellipsoid hull along +Z
    blimpNode.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 4.2, segments: 24, rings: 16),
          blimpHullMat,
        ),
      )..scale = vm.Vector3(1.0, 0.92, 2.65),
    );
    // Blue racing stripe band
    blimpNode.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 4.05,
            topRadius: 4.05,
            height: 4.5,
            radialSegments: 20,
            topCap: false,
            bottomCap: false,
          ),
          blimpStripeMat,
        ),
      )..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
    );
    // Gondola cabin underneath
    blimpNode.add(
      Node(
        mesh: Mesh(
          CapsuleGeometry(radius: 0.95, height: 3.6, radialSegments: 12),
          blimpStripeMat,
        ),
      )
        ..position = vm.Vector3(0, -4.1, 0.5)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
    );
    // 4 cruciform tail fins at the stern (-Z)
    blimpNode.add(
      Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(0.28, 5.6, 3.4)), blimpFinMat),
      )..position = vm.Vector3(0, 0, -8.8),
    );
    blimpNode.add(
      Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(5.6, 0.28, 3.15)), blimpFinMat),
      )..position = vm.Vector3(0, 0, -8.85),
    );
    container.add(blimpNode);

    // High-altitude ring of 12 sculpted 3D Cumulus Cloud Clusters
    final cloudRingNode = Node(name: 'SkyCloudRing')
      ..position = vm.Vector3(60.0, 68.0, -23.0);
    final cloudMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.98, 0.99, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.18, 0.22, 0.28, 1.0)
      ..roughnessFactor = 0.92
      ..metallicFactor = 0.0;

    for (var c = 0; c < 12; c++) {
      final angle = (c / 12.0) * math.pi * 2.0;
      final dist = 210.0 + (c % 3) * 32.0;
      final cloudCluster = Node(name: 'Cloud_$c')
        ..position = vm.Vector3(
          math.cos(angle) * dist,
          (c % 4) * 4.5,
          math.sin(angle) * dist * 0.92,
        )
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -angle);

      // 3 overlapping puff spheres per cumulus cloud
      cloudCluster.add(
        Node(
          mesh: Mesh(SphereGeometry(radius: 7.5, segments: 12, rings: 10), cloudMat),
        )..scale = vm.Vector3(1.6, 0.68, 1.1),
      );
      cloudCluster.add(
        Node(
          mesh: Mesh(SphereGeometry(radius: 5.8, segments: 12, rings: 10), cloudMat),
        )
          ..position = vm.Vector3(-6.8, -1.1, 0.8)
          ..scale = vm.Vector3(1.3, 0.65, 1.0),
      );
      cloudCluster.add(
        Node(
          mesh: Mesh(SphereGeometry(radius: 6.2, segments: 12, rings: 10), cloudMat),
        )
          ..position = vm.Vector3(6.5, -0.9, -0.6)
          ..scale = vm.Vector3(1.35, 0.65, 1.0),
      );
      cloudRingNode.add(cloudCluster);
    }
    container.add(cloudRingNode);

    return (
      container: container,
      balloonNodes: balloonNodes,
      balloonBasePositions: balloonBasePositions,
      blimpNode: blimpNode,
      cloudRingNode: cloudRingNode,
    );
  }

  /// Builds continuous, closed 3D beveled FIA rumble-strip curbs along the left
  /// and right edges of the road. Because the geometry is a single stitched
  /// strip along the circuit samples, adjacent pieces share vertices and never
  /// produce coplanar overlaps.
  static Node _buildSweptCurbs(TrackCircuit track, PbrAssets pbr) {
    final container = Node(name: 'SweptCurbs');
    final samples = track.samples;
    final n = samples.length;

    final curbMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.curbAlbedo,
      normalTexture: pbr.curbNormal,
    )
      ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0)
      ..roughnessFactor = 0.52
      ..metallicFactor = 0.06
      ..normalScale = 1.4
      ..depthLayer = 1;

    MeshGeometry buildSideCurbMesh(double sideSign) {
      final builder = GeometryBuilder(deduplicate: false);
      const innerOff = TrackCircuit.roadHalfWidth - 0.08;
      const midOff = TrackCircuit.roadHalfWidth + TrackCircuit.curbWidth * 0.35;
      const outerOff = TrackCircuit.roadHalfWidth + TrackCircuit.curbWidth;

      final ringBases = <int>[];

      for (var i = 0; i <= n; i++) {
        final s = samples[i % n];
        final dist = i == n ? track.totalLength : s.distance;
        final vCoord = dist / 5.5; // Repeats 4 red/white blocks every 5.5m

        final pInner =
            s.position + s.right * (sideSign * innerOff) + vm.Vector3(0, 0.015, 0);
        final pMid =
            s.position + s.right * (sideSign * midOff) + vm.Vector3(0, 0.115, 0);
        final pOuter =
            s.position + s.right * (sideSign * outerOff) + vm.Vector3(0, 0.085, 0);
        final pSkirt =
            s.position + s.right * (sideSign * (outerOff + 0.08)) + vm.Vector3(0, -0.02, 0);

        final base = builder.vertexCount;
        ringBases.add(base);

        builder
          ..normal(vm.Vector3(0, 0.92, 0).normalized())
          ..texCoord(vm.Vector2(0.0, vCoord))
          ..addVertex(pInner)
          ..normal(vm.Vector3(0, 1.0, 0))
          ..texCoord(vm.Vector2(0.45, vCoord))
          ..addVertex(pMid)
          ..normal(vm.Vector3(0, 0.96, 0).normalized())
          ..texCoord(vm.Vector2(0.88, vCoord))
          ..addVertex(pOuter)
          ..normal(s.right * sideSign)
          ..texCoord(vm.Vector2(1.0, vCoord))
          ..addVertex(pSkirt);
      }

      for (var i = 0; i < n; i++) {
        final b0 = ringBases[i];
        final b1 = ringBases[i + 1];
        for (var j = 0; j < 3; j++) {
          final a = b0 + j;
          final b = b0 + j + 1;
          final c = b1 + j;
          final d = b1 + j + 1;
          if (sideSign > 0) {
            builder
              ..addTriangle(a, c, b)
              ..addTriangle(b, c, d);
          } else {
            builder
              ..addTriangle(a, b, c)
              ..addTriangle(b, d, c);
          }
        }
      }

      return builder.build();
    }

    container.add(
      Node(
        name: 'LeftSweptCurb',
        mesh: Mesh(buildSideCurbMesh(-1.0), curbMat),
      )..shadowStatic = true,
    );
    container.add(
      Node(
        name: 'RightSweptCurb',
        mesh: Mesh(buildSideCurbMesh(1.0), curbMat),
      )..shadowStatic = true,
    );

    return container;
  }

  /// Builds continuous metallic Armco crash barriers along both outer track
  /// boundaries, plus spaced support posts.
  static Node _buildSweptBarriers(TrackCircuit track) {
    final container = Node(name: 'SweptBarriers');
    final samples = track.samples;
    final n = samples.length;

    final steelBarrierMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.76, 0.80, 0.86, 1.0)
      ..roughnessFactor = 0.34
      ..metallicFactor = 0.82;

    MeshGeometry buildBarrierWall(double sideSign) {
      final builder = GeometryBuilder(deduplicate: false);
      const wallOffset = TrackCircuit.roadHalfWidth + 3.6;
      final ringBases = <int>[];

      for (var i = 0; i <= n; i += 2) {
        final idx = i >= n ? 0 : i;
        final s = samples[idx];
        final u = (i / n) * 40.0;

        final basePos = s.position + s.right * (sideSign * wallOffset);
        final pBot = basePos + vm.Vector3(0, 0.15, 0);
        final pMid =
            basePos - s.right * (sideSign * 0.12) + vm.Vector3(0, 0.52, 0);
        final pTop = basePos + vm.Vector3(0, 0.88, 0);

        final inwardNormal = -s.right * sideSign;
        ringBases.add(builder.vertexCount);

        builder
          ..normal(inwardNormal)
          ..texCoord(vm.Vector2(0.0, u))
          ..addVertex(pBot)
          ..normal((inwardNormal + vm.Vector3(0, 0.25, 0)).normalized())
          ..texCoord(vm.Vector2(0.5, u))
          ..addVertex(pMid)
          ..normal((inwardNormal + vm.Vector3(0, 0.5, 0)).normalized())
          ..texCoord(vm.Vector2(1.0, u))
          ..addVertex(pTop);
      }

      for (var r = 0; r < ringBases.length - 1; r++) {
        final b0 = ringBases[r];
        final b1 = ringBases[r + 1];
        for (var j = 0; j < 2; j++) {
          final a = b0 + j;
          final b = b0 + j + 1;
          final c = b1 + j;
          final d = b1 + j + 1;
          // Double-sided barrier strip so it shades from both camera directions
          builder
            ..addTriangle(a, b, c)
            ..addTriangle(b, d, c)
            ..addTriangle(a, c, b)
            ..addTriangle(b, c, d);
        }
      }
      return builder.build();
    }

    container.add(
      Node(
        name: 'LeftArmcoBarrier',
        mesh: Mesh(buildBarrierWall(-1.0), steelBarrierMat),
      )..shadowStatic = true,
    );
    container.add(
      Node(
        name: 'RightArmcoBarrier',
        mesh: Mesh(buildBarrierWall(1.0), steelBarrierMat),
      )..shadowStatic = true,
    );

    return container;
  }

  /// Builds the Start/Finish Checkered Line, Starting Grid Boxes, and Overhead
  /// Grand Prix Truss Gantry with 5 F1 Starting Lights.
  static Node _buildStartFinishGantry(TrackCircuit track, PbrAssets pbr) {
    final gantryRoot = Node(name: 'StartFinishGantry');
    final startSample = track.sampleAtDistance(0.0);
    final yaw = math.atan2(startSample.tangent.x, startSample.tangent.z);

    gantryRoot.position = startSample.position.clone();
    gantryRoot.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);

    final pillarMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.carbonAlbedo,
      normalTexture: pbr.carbonNormal,
    )
      ..baseColorFactor = vm.Vector4(0.85, 0.88, 0.92, 1.0)
      ..roughnessFactor = 0.30
      ..metallicFactor = 0.65;

    final bannerMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.checkeredAlbedo,
    )
      ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0)
      ..roughnessFactor = 0.35
      ..depthLayer = 2;

    final neonTrimMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.1, 0.85, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.1, 0.80, 1.0, 1.0)
      ..emissiveStrength = 4.5;

    final startLightMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.15, 0.12, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.12, 0.08, 1.0)
      ..emissiveStrength = 5.5;

    // 1. Checkered Start/Finish Line Strip on the Road
    const roadWidth = TrackCircuit.roadHalfWidth * 1.92;
    gantryRoot.add(
      Node(
        name: 'StartLineCheckers',
        mesh: Mesh(PlaneGeometry(width: roadWidth, depth: 2.8), bannerMat),
      )..position = vm.Vector3(0, 0.025, 0),
    );

    // 2. Twin Gantry Truss Towers on Left & Right
    const spanX = TrackCircuit.roadHalfWidth + 1.9;
    for (final side in const [-1.0, 1.0]) {
      gantryRoot.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.48,
              topRadius: 0.38,
              height: 8.8,
              radialSegments: 16,
            ),
            pillarMat,
          ),
        )
          ..position = vm.Vector3(side * spanX, 4.4, 0)
          ..shadowStatic = true,
      );
      // Neon vertical accent rib on outer side of tower
      gantryRoot.add(
        Node(
          mesh: Mesh(CuboidGeometry(vm.Vector3(0.14, 7.6, 0.22)), neonTrimMat),
        )..position = vm.Vector3(side * (spanX + 0.52), 4.4, 0),
      );
    }

    // 3. Overhead Checkered Bridge Beam (raised above pillar tops to avoid overlap)
    gantryRoot.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(spanX * 2.15, 1.55, 1.35)),
          bannerMat,
        ),
      )
        ..position = vm.Vector3(0, 9.65, 0)
        ..shadowStatic = true,
    );

    // Top & Bottom Neon Trim Rails on Bridge
    gantryRoot.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(spanX * 2.18, 0.16, 1.48)),
          neonTrimMat,
        ),
      )..position = vm.Vector3(0, 10.55, 0),
    );

    // 4. Five F1 Starting Light Pods Suspended Under Gantry
    for (var i = -2; i <= 2; i++) {
      final podX = i * 2.2;
      gantryRoot.add(
        Node(
          mesh: Mesh(CuboidGeometry(vm.Vector3(0.75, 0.95, 0.45)), pillarMat),
        )..position = vm.Vector3(podX, 8.25, 0.55),
      );
      gantryRoot.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.22, segments: 12, rings: 8),
            startLightMat,
          ),
        )..position = vm.Vector3(podX, 8.05, 0.82),
      );
    }

    return gantryRoot;
  }

  /// Builds futuristic Checkpoint Laser Gates along the circuit.
  static Node _buildCheckpointGates(TrackCircuit track) {
    final container = Node(name: 'CheckpointGates');

    final pylonMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.16, 0.20, 0.28, 1.0)
      ..roughnessFactor = 0.30
      ..metallicFactor = 0.75;

    final beaconMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.1, 0.92, 0.98, 1.0)
      ..emissiveFactor = vm.Vector4(0.08, 0.85, 1.0, 1.0)
      ..emissiveStrength = 4.0;

    final laserBeamMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.1, 0.90, 1.0, 0.22)
      ..emissiveFactor = vm.Vector4(0.05, 0.80, 1.0, 1.0)
      ..emissiveStrength = 2.5
      ..alphaMode = AlphaMode.blend;

    for (var i = 1; i < track.checkpointDistances.length; i++) {
      final dist = track.checkpointDistances[i];
      final s = track.sampleAtDistance(dist);
      final yaw = math.atan2(s.tangent.x, s.tangent.z);

      final gateNode = Node(name: 'Checkpoint_$i')
        ..position = s.position.clone()
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);

      const pylonOffset = TrackCircuit.roadHalfWidth + 1.75;
      for (final side in const [-1.0, 1.0]) {
        gateNode.add(
          Node(
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: 0.32,
                topRadius: 0.18,
                height: 5.2,
                radialSegments: 12,
              ),
              pylonMat,
            ),
          )
            ..position = vm.Vector3(side * pylonOffset, 2.6, 0)
            ..rotation = vm.Quaternion.axisAngle(
              vm.Vector3(0, 0, 1),
              -side * 0.12,
            ),
        );
        gateNode.add(
          Node(
            mesh: Mesh(
              SphereGeometry(radius: 0.36, segments: 12, rings: 8),
              beaconMat,
            ),
          )..position = vm.Vector3(side * (pylonOffset - 0.32), 5.35, 0),
        );
      }

      // Overhead holographic laser ribbon connecting the two checkpoint pylons
      gateNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(pylonOffset * 1.92, 0.18, 0.12)),
            laserBeamMat,
          ),
        )..position = vm.Vector3(0, 5.35, 0),
      );

      container.add(gateNode);
    }

    return container;
  }

  /// Builds flush road-embedded Boost Pads with scrolling neon chevron textures.
  static ({Node container, PhysicallyBasedMaterial material}) _buildBoostPads(
    TrackCircuit track,
    PbrAssets pbr,
  ) {
    final container = Node(name: 'BoostPads');

    final boostMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.boostPadEmissive,
      emissiveTexture: pbr.boostPadEmissive,
    )
      ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.35, 0.92, 1.0, 1.0)
      ..emissiveStrength = 4.5
      ..roughnessFactor = 0.18
      ..metallicFactor = 0.5
      ..depthLayer = 2;

    final frameMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.15, 0.18, 0.24, 1.0)
      ..roughnessFactor = 0.35
      ..metallicFactor = 0.85
      ..depthLayer = 1;

    for (var i = 0; i < track.boostPads.length; i++) {
      final pad = track.boostPads[i];
      final yaw = math.atan2(pad.tangent.x, pad.tangent.z);

      final padNode = Node(name: 'BoostPad_$i')
        ..position = pad.position + vm.Vector3(0, 0.025, 0)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);

      // Glowing scrolling chevron surface
      padNode.add(
        Node(
          mesh: Mesh(
            PlaneGeometry(width: pad.width, depth: pad.length),
            boostMat,
          ),
        )..position = vm.Vector3(0, 0.015, 0),
      );

      // Metallic side rails flanking the boost pad
      for (final side in const [-1.0, 1.0]) {
        padNode.add(
          Node(
            mesh: Mesh(
              CuboidGeometry(vm.Vector3(0.18, 0.08, pad.length)),
              frameMat,
            ),
          )..position = vm.Vector3(side * (pad.width * 0.5 + 0.12), 0.04, 0),
        );
      }

      container.add(padNode);
    }

    return (container: container, material: boostMat);
  }

  /// Builds sleek low-profile 3D Aero Trick Launch Ramps with forward-scrolling
  /// golden-amber chevron decks, metallic side rails, and hydraulic struts.
  static ({Node container, PhysicallyBasedMaterial material}) _buildJumpRamps(
    TrackCircuit track,
    PbrAssets pbr,
  ) {
    final container = Node(name: 'JumpRamps');

    final jumpDeckMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.boostPadEmissive,
      emissiveTexture: pbr.boostPadEmissive,
    )
      ..baseColorFactor = vm.Vector4(1.0, 0.78, 0.28, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.56, 0.08, 1.0)
      ..emissiveStrength = 4.6
      ..roughnessFactor = 0.18
      ..metallicFactor = 0.50
      ..doubleSided = true
      ..depthLayer = 2;

    final rampFrameMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.16, 0.19, 0.26, 1.0)
      ..roughnessFactor = 0.34
      ..metallicFactor = 0.85
      ..depthLayer = 1;

    final neonLipMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.82, 0.18, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.65, 0.10, 1.0)
      ..emissiveStrength = 5.2
      ..roughnessFactor = 0.20;

    for (var i = 0; i < track.jumpRamps.length; i++) {
      final ramp = track.jumpRamps[i];
      final yaw = math.atan2(ramp.tangent.x, ramp.tangent.z);
      final halfW = ramp.width * 0.5;
      final halfL = ramp.length * 0.5;
      final h = ramp.height;
      final slopeLen = math.sqrt(ramp.length * ramp.length + h * h);
      final slopeAngle = math.atan2(h, ramp.length);

      final rampNode = Node(name: 'JumpRamp_$i')
        ..position = ramp.position.clone()
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);

      // Pitched slope assembly: rear edge sits flush at y=0.03, front launch lip rises to y=h+0.03
      final slopeNode = Node(name: 'JumpRampSlope_$i')
        ..position = vm.Vector3(0.0, h * 0.5 + 0.03, 0.0)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -slopeAngle);

      // 1. Glowing forward-scrolling golden chevron deck (PlaneGeometry is never back-face culled)
      slopeNode.add(
        Node(
          name: 'JumpRampDeck_$i',
          mesh: Mesh(
            PlaneGeometry(width: ramp.width, depth: slopeLen),
            jumpDeckMat,
          ),
        )..position = vm.Vector3(0, 0.015, 0),
      );

      // 2. Metallic side rails + glowing golden LED trim flanking the ramp deck
      for (final side in const [-1.0, 1.0]) {
        slopeNode.add(
          Node(
            mesh: Mesh(
              CuboidGeometry(vm.Vector3(0.20, 0.09, slopeLen)),
              rampFrameMat,
            ),
          )..position = vm.Vector3(side * (halfW + 0.14), 0.03, 0),
        );
        slopeNode.add(
          Node(
            mesh: Mesh(
              CuboidGeometry(vm.Vector3(0.08, 0.03, slopeLen * 0.92)),
              neonLipMat,
            ),
          )..position = vm.Vector3(side * (halfW + 0.14), 0.10, 0),
        );
      }

      // 3. Glowing front launch-lip bar across the top exit edge
      slopeNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(ramp.width, 0.06, 0.16)),
            neonLipMat,
          ),
        )..position = vm.Vector3(0, 0.04, slopeLen * 0.5 - 0.08),
      );

      rampNode.add(slopeNode);

      // 4. Clean hydraulic support struts under the raised front launch lip
      for (final side in const [-1.0, 1.0]) {
        rampNode.add(
          Node(
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: 0.10,
                topRadius: 0.08,
                height: h,
                radialSegments: 8,
              ),
              rampFrameMat,
            ),
          )..position = vm.Vector3(
            side * (halfW - 0.35),
            h * 0.5 + 0.01,
            halfL - 0.35,
          ),
        );
      }

      container.add(rampNode);
    }

    return (container: container, material: jumpDeckMat);
  }

  /// Builds floating Holo-Crystal Item Boxes with a translucent outer diamond
  /// shell and a counter-rotating golden inner star core.
  static ({
    Node container,
    List<Node> outerNodes,
    List<Node> coreNodes,
  }) _buildItemBoxes(TrackCircuit track) {
    final container = Node(name: 'ItemBoxes');
    final outerNodes = <Node>[];
    final coreNodes = <Node>[];

    final crystalGeo = IcosphereGeometry(radius: 0.92, subdivisions: 0);
    final coreGeo = CuboidGeometry(vm.Vector3.all(0.58));

    final palette = <vm.Vector4>[
      vm.Vector4(0.15, 0.92, 1.0, 0.58),
      vm.Vector4(1.0, 0.32, 0.85, 0.58),
      vm.Vector4(1.0, 0.78, 0.15, 0.58),
      vm.Vector4(0.32, 1.0, 0.55, 0.58),
    ];

    final coreMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.92, 0.35, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.80, 0.20, 1.0)
      ..emissiveStrength = 4.2
      ..roughnessFactor = 0.15
      ..metallicFactor = 0.8;

    for (var i = 0; i < track.itemBoxes.length; i++) {
      final box = track.itemBoxes[i];
      final color = palette[i % palette.length];
      final shellMat = PhysicallyBasedMaterial()
        ..baseColorFactor = color
        ..emissiveFactor = vm.Vector4(color.x, color.y, color.z, 1.0)
        ..emissiveStrength = 1.8
        ..roughnessFactor = 0.08
        ..metallicFactor = 0.2
        ..alphaMode = AlphaMode.blend;

      final outerNode = Node(
        name: 'ItemBox_$i',
        mesh: Mesh(crystalGeo, shellMat),
      )..position = box.basePosition.clone();

      final coreNode = Node(
        name: 'ItemCore_$i',
        mesh: Mesh(coreGeo, coreMat),
      );
      outerNode.add(coreNode);
      box.node = outerNode;

      container.add(outerNode);
      outerNodes.add(outerNode);
      coreNodes.add(coreNode);
    }

    return (
      container: container,
      outerNodes: outerNodes,
      coreNodes: coreNodes,
    );
  }

  /// Builds 3D embossed spinning Gold Coins placed along corner apexes and
  /// racing lines. Collecting up to 10 coins permanently increases top speed.
  static ({Node container, List<Node> nodes}) _buildCoins(TrackCircuit track) {
    final container = Node(name: 'GoldCoins');
    final nodes = <Node>[];

    final goldRimMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.84, 0.16, 1.0)
      ..emissiveFactor = vm.Vector4(0.85, 0.58, 0.05, 1.0)
      ..emissiveStrength = 1.6
      ..roughnessFactor = 0.16
      ..metallicFactor = 0.94;

    final goldEmblemMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.95, 0.55, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.82, 0.22, 1.0)
      ..emissiveStrength = 2.4
      ..roughnessFactor = 0.12
      ..metallicFactor = 0.96;

    final coinDiscGeo = CylinderGeometry(
      bottomRadius: 0.44,
      topRadius: 0.44,
      height: 0.11,
      radialSegments: 18,
    );
    final coinStarGeo = CuboidGeometry(vm.Vector3(0.32, 0.18, 0.08));

    for (var i = 0; i < track.coins.length; i++) {
      final coin = track.coins[i];
      final coinRoot = Node(name: 'GoldCoin_$i')
        ..position = coin.basePosition.clone();

      // Upright gold disc (rotated 90° around X so cylinder faces along Z)
      coinRoot.add(
        Node(
          mesh: Mesh(coinDiscGeo, goldRimMat),
        )..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(1, 0, 0),
            math.pi * 0.5,
          ),
      );

      // Raised diamond emblem protruding cleanly past both faces
      coinRoot.add(
        Node(
          mesh: Mesh(coinStarGeo, goldEmblemMat),
        )..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 0, 1),
            math.pi * 0.25,
          ),
      );

      coin.node = coinRoot;
      container.add(coinRoot);
      nodes.add(coinRoot);
    }

    return (container: container, nodes: nodes);
  }

  /// Builds high-detail Traffic Cones (with stacked non-overlapping reflective
  /// white collars) and iridescent Oil Slicks.
  static ({Node container, List<Node> nodes}) _buildObstacles(
    TrackCircuit track,
  ) {
    final container = Node(name: 'TrackObstacles');
    final nodes = <Node>[];

    final coneOrangeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.36, 0.04, 1.0)
      ..emissiveFactor = vm.Vector4(0.35, 0.08, 0.0, 1.0)
      ..roughnessFactor = 0.38;

    final coneReflectiveMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.96, 0.97, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.25, 0.26, 0.30, 1.0)
      ..roughnessFactor = 0.22;

    final coneBaseMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.14, 0.15, 0.18, 1.0)
      ..roughnessFactor = 0.80;

    final oilSlickMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.05, 0.04, 0.08, 1.0)
      ..emissiveFactor = vm.Vector4(0.18, 0.06, 0.28, 1.0)
      ..emissiveStrength = 0.8
      ..roughnessFactor = 0.04
      ..metallicFactor = 0.92
      ..depthLayer = 2;

    for (var i = 0; i < track.obstacles.length; i++) {
      final obs = track.obstacles[i];
      if (obs.kind == ObstacleKind.oilSlick) {
        final oilNode = Node(
          name: 'OilSlick_$i',
          mesh: Mesh(
            DiscGeometry(radius: obs.radius, segments: 24),
            oilSlickMat,
          ),
        )..position = obs.position + vm.Vector3(0, 0.02, 0);
        obs.node = oilNode;
        container.add(oilNode);
        nodes.add(oilNode);
      } else {
        final coneGroup = Node(name: 'TrafficCone_$i')
          ..position = obs.position.clone();
        // Hexagonal rubber base (y = 0.00..0.12)
        coneGroup.add(
          Node(
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: obs.radius * 0.95,
                topRadius: obs.radius * 0.90,
                height: 0.12,
                radialSegments: 8,
              ),
              coneBaseMat,
            ),
          )..position = vm.Vector3(0, 0.06, 0),
        );
        // Lower orange cone frustum (y = 0.14..0.68, open caps)
        coneGroup.add(
          Node(
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: obs.radius * 0.68,
                topRadius: obs.radius * 0.44,
                height: 0.54,
                radialSegments: 16,
                bottomCap: false,
                topCap: false,
              ),
              coneOrangeMat,
            ),
          )..position = vm.Vector3(0, 0.41, 0),
        );
        // Middle reflective white collar frustum (y = 0.70..1.02, open caps)
        coneGroup.add(
          Node(
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: obs.radius * 0.43,
                topRadius: obs.radius * 0.27,
                height: 0.32,
                radialSegments: 16,
                bottomCap: false,
                topCap: false,
              ),
              coneReflectiveMat,
            ),
          )..position = vm.Vector3(0, 0.86, 0),
        );
        // Upper orange cone tip (y = 1.04..1.38)
        coneGroup.add(
          Node(
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: obs.radius * 0.26,
                topRadius: 0.09,
                height: 0.34,
                radialSegments: 16,
                bottomCap: false,
              ),
              coneOrangeMat,
            ),
          )..position = vm.Vector3(0, 1.21, 0),
        );
        obs.node = coneGroup;
        container.add(coneGroup);
        nodes.add(coneGroup);
      }
    }

    return (container: container, nodes: nodes);
  }

  /// Builds Instanced Multi-Tier Trees, Covered Stadium Grandstands with Crowd
  /// Textures, and Floodlight Towers around the circuit.
  static Node _buildEnvironmentScenery(TrackCircuit track, PbrAssets pbr) {
    final container = Node(name: 'EnvironmentScenery');
    final rng = math.Random(42);

    // 1. Instanced Two-Tier Pine & Cypress Trees
    final trunkGeo = CylinderGeometry(
      bottomRadius: 0.42,
      topRadius: 0.26,
      height: 2.8,
      radialSegments: 8,
    );
    final trunkMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.38, 0.24, 0.14, 1.0)
      ..roughnessFactor = 0.88;

    final lowerFoliageGeo = CylinderGeometry(
      bottomRadius: 2.35,
      topRadius: 0.45,
      height: 4.2,
      radialSegments: 10,
    );
    final upperFoliageGeo = CylinderGeometry(
      bottomRadius: 1.75,
      topRadius: 0.08,
      height: 3.6,
      radialSegments: 10,
    );
    final foliageMatDark = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.14, 0.48, 0.22, 1.0)
      ..roughnessFactor = 0.78;
    final foliageMatBright = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.20, 0.60, 0.28, 1.0)
      ..roughnessFactor = 0.74;

    final trunkInstances = InstancedMesh(geometry: trunkGeo, material: trunkMat);
    final lowerCrownInstances = InstancedMesh(
      geometry: lowerFoliageGeo,
      material: foliageMatDark,
    );
    final upperCrownInstances = InstancedMesh(
      geometry: upperFoliageGeo,
      material: foliageMatBright,
    );

    const minClearance = TrackCircuit.roadHalfWidth + 9.2;
    const circuitCenterX = 58.0;
    const circuitCenterZ = -22.0;
    final lakeCenter = vm.Vector3(56.0, 0.0, 44.0);

    final grandstandFractions = <double>[0.04, 0.28, 0.54, 0.78, 0.94];
    final grandstandCenters = <vm.Vector3>[
      for (final frac in grandstandFractions)
        () {
          final s = track.sampleAtDistance(track.totalLength * frac);
          return s.position + s.right * (TrackCircuit.roadHalfWidth + 14.5);
        }(),
    ];

    var placedTrees = 0;
    var attempts = 0;

    while (placedTrees < 185 && attempts < 1200) {
      attempts++;
      final angle = rng.nextDouble() * math.pi * 2.0;
      final isInfield = rng.nextDouble() < 0.28;
      final radius = isInfield
          ? (18.0 + rng.nextDouble() * 48.0)
          : (102.0 + rng.nextDouble() * 68.0);

      final x = circuitCenterX + math.cos(angle) * radius;
      final z = circuitCenterZ + math.sin(angle) * (radius * 0.92);
      final candidate = vm.Vector3(x, 0, z);

      // Keep clear of the infield lake, grandstands & track road
      if (candidate.distanceTo(lakeCenter) < 26.5) {
        continue;
      }
      var nearStand = false;
      for (final standPos in grandstandCenters) {
        if (candidate.distanceTo(standPos) < 16.5) {
          nearStand = true;
          break;
        }
      }
      if (nearStand) continue;

      final proj = track.project(candidate);
      if (proj.lateralOffset.abs() < minClearance) {
        continue;
      }

      final scale = 0.82 + rng.nextDouble() * 0.72;
      final rotY = rng.nextDouble() * math.pi * 2.0;

      final trunkM = vm.Matrix4.translation(vm.Vector3(x, 1.35 * scale, z))
        ..rotateY(rotY)
        ..scaleByVector3(vm.Vector3.all(scale));
      final lowerM = vm.Matrix4.translation(vm.Vector3(x, 3.8 * scale, z))
        ..rotateY(rotY)
        ..scaleByVector3(vm.Vector3.all(scale));
      final upperM = vm.Matrix4.translation(vm.Vector3(x, 6.1 * scale, z))
        ..rotateY(rotY + 0.4)
        ..scaleByVector3(vm.Vector3.all(scale));

      trunkInstances.addInstance(trunkM);
      lowerCrownInstances.addInstance(lowerM);
      upperCrownInstances.addInstance(upperM);
      placedTrees++;
    }

    container.add(
      Node(name: 'TreeTrunks')
        ..addComponent(InstancedMeshComponent(trunkInstances))
        ..shadowStatic = true,
    );
    container.add(
      Node(name: 'TreeLowerCrowns')
        ..addComponent(InstancedMeshComponent(lowerCrownInstances))
        ..shadowStatic = true,
    );
    container.add(
      Node(name: 'TreeUpperCrowns')
        ..addComponent(InstancedMeshComponent(upperCrownInstances))
        ..shadowStatic = true,
    );

    // 2. Covered Stadium Grandstands with Crowd Texture & Floodlight Towers
    final standStructureMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.24, 0.27, 0.34, 1.0)
      ..roughnessFactor = 0.55
      ..metallicFactor = 0.45;

    final crowdSeatsMat = PhysicallyBasedMaterial(
      baseColorTexture: pbr.crowdAlbedo,
    )
      ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0)
      ..roughnessFactor = 0.65;

    final canopyMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.94, 0.96, 0.99, 1.0)
      ..roughnessFactor = 0.32
      ..metallicFactor = 0.20;

    final floodlightMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.98, 0.90, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.95, 0.82, 1.0)
      ..emissiveStrength = 7.0;

    for (var i = 0; i < grandstandFractions.length; i++) {
      final s = track.sampleAtDistance(
        track.totalLength * grandstandFractions[i],
      );
      final yaw = math.atan2(s.tangent.x, s.tangent.z);
      final standPos = grandstandCenters[i];

      final standNode = Node(name: 'Grandstand_$i')
        ..position = standPos
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw)
        ..shadowStatic = true;

      // Concrete base structure
      standNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(7.0, 2.2, 22.0)),
            standStructureMat,
          ),
        )..position = vm.Vector3(0, 1.1, 0),
      );

      // Sloped spectator seating bank with vibrant crowd texture
      standNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(6.6, 0.6, 21.4)),
            crowdSeatsMat,
          ),
        )
          ..position = vm.Vector3(-0.2, 3.6, 0)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 0.42),
      );

      // Rear wall & roof support columns (seated cleanly above base podium)
      standNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(0.8, 4.6, 21.6)),
            standStructureMat,
          ),
        )..position = vm.Vector3(3.0, 4.55, 0),
      );

      // Cantilevered white stadium canopy roof
      standNode.add(
        Node(
          mesh: Mesh(CuboidGeometry(vm.Vector3(8.8, 0.38, 22.8)), canopyMat),
        )
          ..position = vm.Vector3(-0.4, 7.2, 0)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -0.10),
      );

      // Tall Stadium Floodlight Tower beside each grandstand
      standNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.35,
              topRadius: 0.22,
              height: 14.0,
              radialSegments: 10,
            ),
            standStructureMat,
          ),
        )..position = vm.Vector3(2.5, 7.0, 13.0),
      );
      standNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(0.45, 1.4, 3.2)),
            floodlightMat,
          ),
        )
          ..position = vm.Vector3(2.1, 14.2, 13.0)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 0.35),
      );

      container.add(standNode);
    }

    // 3. Corner Apex Chevron Warning Boards along high-speed turns
    final signBoardMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.10, 0.12, 0.16, 1.0)
      ..roughnessFactor = 0.45
      ..metallicFactor = 0.65;
    final signChevronMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.80, 0.10, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.72, 0.08, 1.0)
      ..emissiveStrength = 3.6;

    final cornerSignSpecs = <({double frac, double side})>[
      (frac: 0.11, side: 1.0),
      (frac: 0.135, side: 1.0),
      (frac: 0.31, side: 1.0),
      (frac: 0.335, side: 1.0),
      (frac: 0.46, side: -1.0),
      (frac: 0.60, side: 1.0),
      (frac: 0.625, side: 1.0),
      (frac: 0.83, side: 1.0),
      (frac: 0.855, side: 1.0),
    ];

    for (var i = 0; i < cornerSignSpecs.length; i++) {
      final spec = cornerSignSpecs[i];
      final s = track.sampleAtDistance(track.totalLength * spec.frac);
      final yaw = math.atan2(s.tangent.x, s.tangent.z);
      final signPos =
          s.position + s.right * (spec.side * (TrackCircuit.roadHalfWidth + 3.4));

      final signNode = Node(name: 'ApexChevronSign_$i')
        ..position = signPos
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw)
        ..shadowStatic = true;

      // Support post
      signNode.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.10,
              topRadius: 0.10,
              height: 1.8,
              radialSegments: 8,
            ),
            standStructureMat,
          ),
        )..position = vm.Vector3(0, 0.9, 0),
      );
      // Dark backing board facing oncoming karts
      signNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(2.1, 1.05, 0.14)),
            signBoardMat,
          ),
        )..position = vm.Vector3(0, 1.85, 0),
      );
      // Glowing amber chevron stripes on front face (separated cleanly to prevent z-fighting)
      final chevronArmGeo = CuboidGeometry(vm.Vector3(0.20, 0.36, 0.04));
      for (final xOff in <double>[-0.52, 0.18]) {
        signNode.add(
          Node(mesh: Mesh(chevronArmGeo, signChevronMat))
            ..position = vm.Vector3(xOff, 2.08, -0.10)
            ..rotation = vm.Quaternion.axisAngle(
              vm.Vector3(0, 0, 1),
              spec.side * 0.52,
            ),
        );
        signNode.add(
          Node(mesh: Mesh(chevronArmGeo, signChevronMat))
            ..position = vm.Vector3(xOff, 1.62, -0.10)
            ..rotation = vm.Quaternion.axisAngle(
              vm.Vector3(0, 0, 1),
              -spec.side * 0.52,
            ),
        );
      }

      container.add(signNode);
    }

    return container;
  }
}
