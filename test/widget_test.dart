import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:kart_racer/game/kart_builder.dart';
import 'package:kart_racer/game/kart_physics.dart';
import 'package:kart_racer/game/kart_race_game.dart';
import 'package:kart_racer/game/sound_manager.dart';
import 'package:kart_racer/game/track_data.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('TrackCircuit builds closed loop and projects positions accurately', () {
    final track = TrackCircuit();
    expect(track.totalLength, greaterThan(400.0));
    expect(track.samples, isNotEmpty);
    expect(track.boostPads, isNotEmpty);
    expect(track.jumpRamps, hasLength(4));
    expect(track.itemBoxes, isNotEmpty);
    expect(track.obstacles, isNotEmpty);

    // Project a point slightly to the right of the start line (0, 0, 0)
    final startSample = track.sampleAtDistance(0.0);
    final rightPoint = startSample.position + startSample.right * 3.0;
    final proj = track.project(rightPoint);
    expect(proj.lateralOffset, closeTo(3.0, 0.25));
    expect(proj.closestPoint.distanceTo(vm.Vector3.zero()), lessThan(1.0));
  });

  test('PerimeterHills and InfieldLake stay clear of the entire circuit road', () {
    final track = TrackCircuit();
    const hillCenterX = 60.0;
    const hillCenterZ = -23.0;
    const hillInnerRadius = 240.0;

    final lakeCenter = vm.Vector3(56.0, 0.0, 44.0);
    const lakeOuterRadius = 21.0;

    for (final sample in track.samples) {
      // Every road sample must lie well inside the 240m PerimeterHills inner ring
      final dx = sample.position.x - hillCenterX;
      final dz = (sample.position.z - hillCenterZ) / 0.92;
      final radialDist = math.sqrt(dx * dx + dz * dz);
      expect(
        radialDist + TrackCircuit.barrierHalfWidth,
        lessThan(hillInnerRadius - 20.0),
      );

      // Every road sample + barrier must stay outside the InfieldLake shoreline
      final distToLake = (sample.position - lakeCenter).length;
      expect(
        distToLake,
        greaterThan(lakeOuterRadius + TrackCircuit.barrierHalfWidth + 4.0),
      );
    }
  });

  test('GamePhase, RacerCharacter, BgmTrack, SpeedClass, and ArcadeSfx are configured', () {
    expect(GamePhase.values, containsAll([
      GamePhase.titleScreen,
      GamePhase.introCutscene,
      GamePhase.racing,
      GamePhase.victoryCutscene,
    ]));
    expect(RacerCharacter.values.length, equals(4));
    expect(BgmTrack.values.length, equals(3));
    expect(SpeedClass.values.length, equals(3));
    expect(ArcadeSfx.values, isNotEmpty);
    expect(KartRacer.baseMaxSpeed, closeTo(20.0, 0.5));
    expect(KartRacer.offRoadMaxSpeed, closeTo(13.0, 0.5));
  });
}
