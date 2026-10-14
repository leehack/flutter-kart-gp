import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Represents a sample along the closed racing circuit for fast spatial queries.
class TrackSample {
  const TrackSample({
    required this.distance,
    required this.t,
    required this.position,
    required this.tangent,
    required this.right,
  });

  final double distance;
  final double t;
  final vm.Vector3 position;
  final vm.Vector3 tangent;
  final vm.Vector3 right;
}

/// Result of projecting a 3D world position onto the track centerline.
class TrackProjection {
  const TrackProjection({
    required this.distance,
    required this.closestPoint,
    required this.tangent,
    required this.right,
    required this.lateralOffset,
    required this.curvature,
  });

  /// Arc-length distance along the track (`0 .. trackLength`).
  final double distance;

  /// Closest point on the track centerline (`y = 0`).
  final vm.Vector3 closestPoint;

  /// Forward unit tangent of the track at this point.
  final vm.Vector3 tangent;

  /// Right-hand unit vector (`up.cross(tangent)`) across the track.
  final vm.Vector3 right;

  /// Signed lateral distance from centerline (+ is right, - is left).
  final double lateralOffset;

  /// Approximate signed curvature (radians per meter) for AI cornering.
  final double curvature;
}

class BoostPadData {
  const BoostPadData({
    required this.distance,
    required this.lateralOffset,
    required this.position,
    required this.tangent,
    this.width = 3.6,
    this.length = 6.0,
  });

  final double distance;
  final double lateralOffset;
  final vm.Vector3 position;
  final vm.Vector3 tangent;
  final double width;
  final double length;
}

class JumpRampData {
  const JumpRampData({
    required this.distance,
    required this.lateralOffset,
    required this.position,
    required this.tangent,
    required this.right,
    this.width = 4.2,
    this.length = 5.6,
    this.height = 0.36,
  });

  final double distance;
  final double lateralOffset;
  final vm.Vector3 position;
  final vm.Vector3 tangent;
  final vm.Vector3 right;
  final double width;
  final double length;
  final double height;
}

class ItemBoxData {
  ItemBoxData({
    required this.distance,
    required this.lateralOffset,
    required this.basePosition,
  });

  final double distance;
  final double lateralOffset;
  final vm.Vector3 basePosition;
  double respawnTimer = 0.0;
  Node? node;

  bool get isActive => respawnTimer <= 0.0;
}

class CoinData {
  CoinData({
    required this.distance,
    required this.lateralOffset,
    required this.basePosition,
  });

  final double distance;
  final double lateralOffset;
  final vm.Vector3 basePosition;
  double respawnTimer = 0.0;
  Node? node;

  bool get isActive => respawnTimer <= 0.0;
}

enum ObstacleKind { cone, oilSlick }

class TrackObstacleData {
  TrackObstacleData({
    required this.kind,
    required this.position,
    required this.radius,
  });

  final ObstacleKind kind;
  final vm.Vector3 position;
  final double radius;
  double hitCooldown = 0.0;
  Node? node;
}

/// Closed-circuit track definition, spatial queries, checkpoints, and pickups.
class TrackCircuit {
  TrackCircuit() {
    _buildCircuit();
  }

  /// Drivable asphalt width in meters.
  static const double roadWidth = 14.0;
  static const double roadHalfWidth = roadWidth * 0.5;

  /// Curb width on each side of the road.
  static const double curbWidth = 1.4;

  /// Outer barrier wall half-width from centerline.
  static const double barrierHalfWidth = roadHalfWidth + 3.2;

  /// Number of checkpoints around the circuit.
  static const int checkpointCount = 6;

  late final ScenePath path;
  late final double totalLength;
  final List<TrackSample> _samples = [];
  final List<BoostPadData> boostPads = [];
  final List<JumpRampData> jumpRamps = [];
  final List<ItemBoxData> itemBoxes = [];
  final List<CoinData> coins = [];
  final List<TrackObstacleData> obstacles = [];

  static final vm.Vector3 _worldUp = vm.Vector3(0, 1, 0);

  /// Control points for a fun grand-prix style closed circuit.
  /// Point 0 is at (0, 0, 0) heading along +Z (north) on the main straight.
  static final List<vm.Vector3> _controlLoop = <vm.Vector3>[
    vm.Vector3(0, 0, 0), // Start / Finish line heading +Z
    vm.Vector3(0, 0, 52),
    vm.Vector3(24, 0, 95), // Turn 1 sweeping right
    vm.Vector3(74, 0, 110),
    vm.Vector3(120, 0, 84), // Turn 2 wide hairpin entry
    vm.Vector3(136, 0, 32),
    vm.Vector3(104, 0, -10), // Chicane S-bend inward
    vm.Vector3(68, 0, -34),
    vm.Vector3(96, 0, -80), // Back-sector technical loop
    vm.Vector3(120, 0, -124),
    vm.Vector3(70, 0, -156), // South sweeping curve
    vm.Vector3(14, 0, -140),
    vm.Vector3(-16, 0, -96), // Final corner onto main straight
    vm.Vector3(0, 0, -48),
  ];

  static vm.Vector3 _catmullRomPos(
    vm.Vector3 p0,
    vm.Vector3 p1,
    vm.Vector3 p2,
    vm.Vector3 p3,
    double s,
  ) {
    final s2 = s * s;
    final s3 = s2 * s;
    return (p1 * 2.0 +
            (p2 - p0) * s +
            (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * s2 +
            (p1 * 3.0 - p0 - p2 * 3.0 + p3) * s3) *
        0.5;
  }

  static vm.Vector3 _catmullRomTan(
    vm.Vector3 p0,
    vm.Vector3 p1,
    vm.Vector3 p2,
    vm.Vector3 p3,
    double s,
  ) {
    final derivative =
        ((p2 - p0) +
            (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * (2.0 * s) +
            (p1 * 3.0 - p0 - p2 * 3.0 + p3) * (3.0 * s * s)) *
        0.5;
    if (derivative.length2 < 1e-12) return vm.Vector3(0, 0, 1);
    return derivative.normalized();
  }

  void _buildCircuit() {
    final n = _controlLoop.length;
    const rawCount = 720;
    final rawPoints = <vm.Vector3>[];
    final rawTangents = <vm.Vector3>[];
    final cumLengths = List<double>.filled(rawCount + 1, 0.0);

    for (var i = 0; i <= rawCount; i++) {
      final u = (i / rawCount) * n;
      final seg = u.floor() % n;
      final localS = u - u.floor();
      final p0 = _controlLoop[(seg - 1 + n) % n];
      final p1 = _controlLoop[seg];
      final p2 = _controlLoop[(seg + 1) % n];
      final p3 = _controlLoop[(seg + 2) % n];
      final pos = _catmullRomPos(p0, p1, p2, p3, localS);
      final tan = _catmullRomTan(p0, p1, p2, p3, localS);
      rawPoints.add(pos);
      rawTangents.add(tan);
      if (i > 0) {
        cumLengths[i] = cumLengths[i - 1] + pos.distanceTo(rawPoints[i - 1]);
      }
    }

    totalLength = cumLengths.last;
    path = PolylinePath(rawPoints);

    const sampleCount = 360;
    var rawCursor = 0;
    for (var i = 0; i < sampleCount; i++) {
      final targetDist = totalLength * (i / sampleCount);
      while (rawCursor < rawCount - 1 && cumLengths[rawCursor + 1] < targetDist) {
        rawCursor++;
      }
      final segLen = cumLengths[rawCursor + 1] - cumLengths[rawCursor];
      final alpha =
          segLen > 1e-9 ? (targetDist - cumLengths[rawCursor]) / segLen : 0.0;
      final pos =
          rawPoints[rawCursor] * (1.0 - alpha) +
          rawPoints[rawCursor + 1] * alpha;
      final tan =
          (rawTangents[rawCursor] * (1.0 - alpha) +
                  rawTangents[rawCursor + 1] * alpha)
              .normalized();
      // Left-handed view space: right is up.cross(forward)
      final right = _worldUp.cross(tan).normalized();
      _samples.add(
        TrackSample(
          distance: targetDist,
          t: i / sampleCount,
          position: pos,
          tangent: tan,
          right: right,
        ),
      );
    }

    _populateTrackFeatures();
  }

  void _populateTrackFeatures() {
    // 1. Boost pads placed on straights and corner exits
    final boostSpecs = <(double fraction, double lateral)>[
      (0.08, -2.6),
      (0.24, 2.2),
      (0.42, 0.0),
      (0.62, -2.5),
      (0.78, 2.5),
      (0.92, 0.0),
    ];

    for (final (frac, lat) in boostSpecs) {
      final dist = (frac * totalLength) % totalLength;
      final sample = sampleAtDistance(dist);
      final worldPos = sample.position + sample.right * lat;
      boostPads.add(
        BoostPadData(
          distance: dist,
          lateralOffset: lat,
          position: worldPos,
          tangent: sample.tangent,
        ),
      );
    }

    // 1b. 3D Aero Jump Ramps for Aerial Trick Boosts
    final rampSpecs = <(double fraction, double lateral)>[
      (0.11, 2.0), // Main straight exit into Turn 1
      (0.33, -1.8), // Wide hairpin exit
      (0.65, 1.8), // Back-sector high-speed straight
      (0.85, -1.8), // Final corner approach
    ];
    for (final (frac, lat) in rampSpecs) {
      final dist = (frac * totalLength) % totalLength;
      final sample = sampleAtDistance(dist);
      final worldPos = sample.position + sample.right * lat;
      jumpRamps.add(
        JumpRampData(
          distance: dist,
          lateralOffset: lat,
          position: worldPos,
          tangent: sample.tangent,
          right: sample.right,
        ),
      );
    }

    // 2. Item box rows (3 or 4 boxes across the track at 3 locations)
    final itemRowFractions = <double>[0.15, 0.50, 0.83];
    const lateralSlots = <double>[-3.9, -1.3, 1.3, 3.9];
    for (final frac in itemRowFractions) {
      final dist = (frac * totalLength) % totalLength;
      final sample = sampleAtDistance(dist);
      for (final lat in lateralSlots) {
        final pos =
            sample.position + sample.right * lat + vm.Vector3(0, 1.15, 0);
        itemBoxes.add(
          ItemBoxData(
            distance: dist,
            lateralOffset: lat,
            basePosition: pos,
          ),
        );
      }
    }

    // 3. Track obstacles (cones & oil slicks)
    final coneSpecs = <(double fraction, double lateral)>[
      (0.29, -3.4),
      (0.30, -2.2),
      (0.56, 3.2),
      (0.57, 2.0),
      (0.71, -1.8),
      (0.87, 3.0),
    ];
    for (final (frac, lat) in coneSpecs) {
      final dist = (frac * totalLength) % totalLength;
      final sample = sampleAtDistance(dist);
      obstacles.add(
        TrackObstacleData(
          kind: ObstacleKind.cone,
          position: sample.position + sample.right * lat,
          radius: 0.85,
        ),
      );
    }

    final oilSpecs = <(double fraction, double lateral)>[
      (0.38, 2.2),
      (0.72, -2.2),
      (0.95, -2.2),
    ];
    for (final (frac, lat) in oilSpecs) {
      final dist = (frac * totalLength) % totalLength;
      final sample = sampleAtDistance(dist);
      obstacles.add(
        TrackObstacleData(
          kind: ObstacleKind.oilSlick,
          position: sample.position + sample.right * lat,
          radius: 1.65,
        ),
      );
    }

    // 4. Gold Coin racing lines along corner apexes and straights
    final coinSpecs = <(double fraction, double lateral)>[
      // Main straight & Turn 1 entry arc
      (0.04, 1.8),
      (0.055, 2.2),
      (0.07, 2.6),
      // Turn 2 sweeping apex
      (0.19, 3.0),
      (0.205, 3.2),
      (0.22, 3.0),
      // Chicane S-bend racing line
      (0.38, -2.0),
      (0.395, -1.0),
      (0.41, 0.0),
      // Back-sector technical loop
      (0.58, -2.8),
      (0.595, -2.8),
      (0.61, -2.6),
      // South sweeping curve apex
      (0.73, 2.6),
      (0.745, 2.8),
      (0.76, 2.6),
      // Final corner exit onto main straight
      (0.88, -2.2),
      (0.895, -1.6),
      (0.91, -1.0),
    ];
    for (final (frac, lat) in coinSpecs) {
      final dist = (frac * totalLength) % totalLength;
      final sample = sampleAtDistance(dist);
      final pos = sample.position + sample.right * lat + vm.Vector3(0, 0.78, 0);
      coins.add(
        CoinData(
          distance: dist,
          lateralOffset: lat,
          basePosition: pos,
        ),
      );
    }
  }

  /// Wraps any arc-length distance into `[0, totalLength)`.
  double wrapDistance(double d) {
    var r = d % totalLength;
    if (r < 0) r += totalLength;
    return r;
  }

  /// Interpolates a [TrackSample] at arc-length distance [d] around the loop.
  TrackSample sampleAtDistance(double d) {
    final wrapped = wrapDistance(d);
    final n = _samples.length;
    final exactIdx = (wrapped / totalLength) * n;
    final i0 = exactIdx.floor() % n;
    final i1 = (i0 + 1) % n;
    final alpha = exactIdx - exactIdx.floor();

    final s0 = _samples[i0];
    final s1 = _samples[i1];
    final pos = s0.position * (1.0 - alpha) + s1.position * alpha;
    final tan = (s0.tangent * (1.0 - alpha) + s1.tangent * alpha).normalized();
    final right = _worldUp.cross(tan).normalized();
    return TrackSample(
      distance: wrapped,
      t: wrapped / totalLength,
      position: pos,
      tangent: tan,
      right: right,
    );
  }

  /// Projects a 3D world position onto the closest point on the closed track.
  TrackProjection project(vm.Vector3 worldPos) {
    var bestIndex = 0;
    var bestDistSq = double.infinity;

    for (var i = 0; i < _samples.length; i++) {
      final p = _samples[i].position;
      final dx = worldPos.x - p.x;
      final dz = worldPos.z - p.z;
      final dSq = dx * dx + dz * dz;
      if (dSq < bestDistSq) {
        bestDistSq = dSq;
        bestIndex = i;
      }
    }

    final n = _samples.length;
    final prevSample = _samples[(bestIndex - 1 + n) % n];
    final currSample = _samples[bestIndex];
    final nextSample = _samples[(bestIndex + 1) % n];

    // Refine along the local tangent segment
    final stepDist = totalLength / n;
    final toPos = vm.Vector3(
      worldPos.x - currSample.position.x,
      0,
      worldPos.z - currSample.position.z,
    );
    final along = toPos.dot(currSample.tangent).clamp(-stepDist, stepDist);
    final refinedDistance = wrapDistance(currSample.distance + along);
    final refined = sampleAtDistance(refinedDistance);

    final offsetVec = vm.Vector3(
      worldPos.x - refined.position.x,
      0,
      worldPos.z - refined.position.z,
    );
    final lateral = offsetVec.dot(refined.right);

    // Estimate curvature from adjacent tangents
    final dTan = nextSample.tangent - prevSample.tangent;
    final signedCurvature = dTan.dot(currSample.right) / (2.0 * stepDist);

    return TrackProjection(
      distance: refinedDistance,
      closestPoint: refined.position,
      tangent: refined.tangent,
      right: refined.right,
      lateralOffset: lateral,
      curvature: signedCurvature,
    );
  }

  /// Returns evenly spaced centerline points for minimap and geometry.
  List<TrackSample> get samples => _samples;

  /// Returns checkpoint arc-length distances around the loop.
  List<double> get checkpointDistances => <double>[
    for (var i = 0; i < checkpointCount; i++)
      (i / checkpointCount) * totalLength,
  ];
}
