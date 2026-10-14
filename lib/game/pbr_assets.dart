import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/noise.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Procedural PBR texture & material generator for the 3D Kart Racer.
///
/// Generates GPU-mipmapped albedo, tangent-space normal, metallic-roughness,
/// emissive, and particle sprite textures entirely in memory at startup.
class PbrAssets {
  PbrAssets._();

  static PbrAssets? _instance;
  static PbrAssets get instance => _instance ??= PbrAssets._().._init();

  late final Texture2D roadAlbedo;
  late final Texture2D roadNormal;
  late final Texture2D roadRoughness;

  late final Texture2D curbAlbedo;
  late final Texture2D curbNormal;

  late final Texture2D grassAlbedo;
  late final Texture2D grassNormal;

  late final Texture2D carbonAlbedo;
  late final Texture2D carbonNormal;

  late final Texture2D tireAlbedo;
  late final Texture2D tireNormal;

  late final Texture2D checkeredAlbedo;
  late final Texture2D boostPadEmissive;
  late final Texture2D crowdAlbedo;
  late final Texture2D ponchoAlbedo;
  late final Texture2D plumageNormal;
  late final Texture2D particleGlowSprite;
  late final Texture2D sparkStreakSprite;

  void _init() {
    _buildRoadTextures();
    _buildCurbTextures();
    _buildGrassTextures();
    _buildCarbonTextures();
    _buildTireTextures();
    checkeredAlbedo = _buildCheckeredTexture();
    boostPadEmissive = _buildBoostPadTexture();
    crowdAlbedo = _buildCrowdTexture();
    ponchoAlbedo = _buildPonchoTexture();
    plumageNormal = _buildPlumageNormalTexture();
    particleGlowSprite = _buildParticleGlowTexture();
    sparkStreakSprite = _buildSparkStreakTexture();
  }

  /// Builds the road cross-section albedo, tangent-space normal map, and
  /// metallic-roughness texture.
  ///
  /// U spans across the road width [0..1], V tiles every 12 meters along the
  /// track arc length.
  void _buildRoadTextures() {
    const w = 256;
    const h = 256;
    final albedo = Uint8List(w * h * 4);
    final normal = Uint8List(w * h * 4);
    final mr = Uint8List(w * h * 4);

    final fineNoise = FastNoiseLite(seed: 101)
      ..noiseType = NoiseType.openSimplex2
      ..frequency = 0.18
      ..fractalType = FractalType.fbm
      ..octaves = 3;

    final macroNoise = FastNoiseLite(seed: 202)
      ..noiseType = NoiseType.openSimplex2
      ..frequency = 0.04
      ..fractalType = FractalType.fbm
      ..octaves = 2;

    final heightField = Float32List(w * h);

    for (var y = 0; y < h; y++) {
      final v = y / h;
      for (var x = 0; x < w; x++) {
        final u = x / w;
        final idx = (y * w + x) * 4;

        // Tileable sampling using periodic coordinates on Y and X
        final nFine = fineNoise.getNoise2(x.toDouble(), y.toDouble());
        final nMacro = macroNoise.getNoise2(x.toDouble(), y.toDouble());
        final grain = nFine * 0.65 + nMacro * 0.35;
        heightField[y * w + x] = grain;

        // Base dark asphalt color
        var r = 38.0 + grain * 12.0;
        var g = 40.0 + grain * 12.0;
        var b = 46.0 + grain * 13.0;
        var rough = 0.84 + grain * 0.08;
        var metal = 0.04;

        // Twin darker rubberized racing grooves around u = 0.28 and u = 0.72
        final leftGroove = math.exp(-math.pow((u - 0.28) / 0.14, 2));
        final rightGroove = math.exp(-math.pow((u - 0.72) / 0.14, 2));
        final groove = math.max(leftGroove, rightGroove);
        r *= (1.0 - groove * 0.22);
        g *= (1.0 - groove * 0.22);
        b *= (1.0 - groove * 0.20);
        rough -= groove * 0.22; // Polished rubber skid line

        // Crisp white edge lines at u in [0.035..0.060] and [0.940..0.965]
        final isEdgeLine =
            (u >= 0.035 && u <= 0.060) || (u >= 0.940 && u <= 0.965);
        if (isEdgeLine) {
          r = 232.0 + grain * 8.0;
          g = 236.0 + grain * 8.0;
          b = 242.0 + grain * 8.0;
          rough = 0.45;
        }

        // Center dashed yellow/amber line at u in [0.490..0.510]
        final isCenterLine =
            (u >= 0.490 && u <= 0.510) && ((v * 4.0) % 1.0 < 0.52);
        if (isCenterLine) {
          r = 245.0;
          g = 198.0;
          b = 48.0;
          rough = 0.42;
        }

        albedo[idx] = r.round().clamp(0, 255);
        albedo[idx + 1] = g.round().clamp(0, 255);
        albedo[idx + 2] = b.round().clamp(0, 255);
        albedo[idx + 3] = 255;

        // glTF Metallic-Roughness convention: G = roughness, B = metallic, R = 255
        mr[idx] = 255;
        mr[idx + 1] = (rough.clamp(0.05, 1.0) * 255).round();
        mr[idx + 2] = (metal.clamp(0.0, 1.0) * 255).round();
        mr[idx + 3] = 255;
      }
    }

    _bakeNormalFromHeight(heightField, w, h, normal, strength: 2.2);

    roadAlbedo = Texture2D.fromPixels(
      albedo,
      w,
      h,
      content: TextureContent.color,
    );
    roadNormal = Texture2D.fromPixels(
      normal,
      w,
      h,
      content: TextureContent.normal,
    );
    roadRoughness = Texture2D.fromPixels(
      mr,
      w,
      h,
      content: TextureContent.data,
    );
  }

  /// Builds FIA red/white rumble-strip curb albedo & ribbed normal map.
  void _buildCurbTextures() {
    const w = 64;
    const h = 256;
    final albedo = Uint8List(w * h * 4);
    final normal = Uint8List(w * h * 4);
    final heightField = Float32List(w * h);

    final scuffNoise = FastNoiseLite(seed: 303)
      ..noiseType = NoiseType.openSimplex2
      ..frequency = 0.14;

    for (var y = 0; y < h; y++) {
      final v = y / h;
      // 4 alternating red & white blocks per tile
      final blockPhase = (v * 4.0) % 1.0;
      final isRed = ((y * 4) ~/ h).isEven;
      // Sawtooth rumble-strip ridges inside each block
      final ridge = math.sin(v * math.pi * 32.0) * 0.45;
      // Seam groove between blocks
      final seam = (blockPhase < 0.04 || blockPhase > 0.96) ? -0.8 : 0.0;

      for (var x = 0; x < w; x++) {
        final u = x / w;
        final idx = (y * w + x) * 4;
        final scuff = scuffNoise.getNoise2(x.toDouble(), y.toDouble());

        heightField[y * w + x] = ridge + seam + scuff * 0.15;

        // Tire rubber marks near inner edge (u ~ 0.15..0.55)
        final tireWear =
            math.exp(-math.pow((u - 0.35) / 0.25, 2)) *
            ((scuff + 1.0) * 0.16);

        double r, g, b;
        if (seam < -0.4) {
          r = 45;
          g = 45;
          b = 50;
        } else if (isRed) {
          r = 228.0 * (1.0 - tireWear);
          g = 32.0 * (1.0 - tireWear);
          b = 36.0 * (1.0 - tireWear);
        } else {
          r = 242.0 * (1.0 - tireWear);
          g = 244.0 * (1.0 - tireWear);
          b = 248.0 * (1.0 - tireWear);
        }

        albedo[idx] = r.round().clamp(0, 255);
        albedo[idx + 1] = g.round().clamp(0, 255);
        albedo[idx + 2] = b.round().clamp(0, 255);
        albedo[idx + 3] = 255;
      }
    }

    _bakeNormalFromHeight(heightField, w, h, normal, strength: 3.0);

    curbAlbedo = Texture2D.fromPixels(
      albedo,
      w,
      h,
      content: TextureContent.color,
    );
    curbNormal = Texture2D.fromPixels(
      normal,
      w,
      h,
      content: TextureContent.normal,
    );
  }

  /// Builds lush multi-tone turf grass albedo and normal textures.
  void _buildGrassTextures() {
    const w = 128;
    const h = 128;
    final albedo = Uint8List(w * h * 4);
    final normal = Uint8List(w * h * 4);
    final heightField = Float32List(w * h);

    final bladeNoise = FastNoiseLite(seed: 404)
      ..noiseType = NoiseType.cellular
      ..frequency = 0.22
      ..fractalType = FractalType.fbm
      ..octaves = 2;

    final patchNoise = FastNoiseLite(seed: 505)
      ..noiseType = NoiseType.openSimplex2
      ..frequency = 0.06;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = (y * w + x) * 4;
        final bVal = bladeNoise.getNoise2(x.toDouble(), y.toDouble());
        final pVal = patchNoise.getNoise2(x.toDouble(), y.toDouble());
        final combined = bVal * 0.6 + pVal * 0.4;
        heightField[y * w + x] = combined;

        // Mow stripes along X
        final mowStripe = math.sin((x / w) * math.pi * 4.0) * 8.0;

        final r = 42.0 + combined * 18.0 + mowStripe * 0.5;
        final g = 128.0 + combined * 28.0 + mowStripe;
        final b = 52.0 + combined * 14.0 + mowStripe * 0.3;

        albedo[idx] = r.round().clamp(0, 255);
        albedo[idx + 1] = g.round().clamp(0, 255);
        albedo[idx + 2] = b.round().clamp(0, 255);
        albedo[idx + 3] = 255;
      }
    }

    _bakeNormalFromHeight(heightField, w, h, normal, strength: 1.8);

    grassAlbedo = Texture2D.fromPixels(
      albedo,
      w,
      h,
      content: TextureContent.color,
    );
    grassNormal = Texture2D.fromPixels(
      normal,
      w,
      h,
      content: TextureContent.normal,
    );
  }

  /// Builds 2x2 diagonal twill carbon-fiber weave albedo + normal map.
  void _buildCarbonTextures() {
    const w = 64;
    const h = 64;
    final albedo = Uint8List(w * h * 4);
    final normal = Uint8List(w * h * 4);
    final heightField = Float32List(w * h);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = (y * w + x) * 4;
        // Diagonal 2x2 twill weave pattern
        final cellX = x % 8;
        final cellY = y % 8;
        final diag = (cellX + cellY) % 8;
        final isWarp = diag < 4;
        final localPos = (diag % 4) / 4.0;
        final arch = math.sin(localPos * math.pi);

        heightField[y * w + x] = arch * (isWarp ? 1.0 : 0.75);

        final shade = isWarp ? (26.0 + arch * 28.0) : (16.0 + arch * 18.0);
        albedo[idx] = shade.round().clamp(0, 255);
        albedo[idx + 1] = (shade + 2.0).round().clamp(0, 255);
        albedo[idx + 2] = (shade + 5.0).round().clamp(0, 255);
        albedo[idx + 3] = 255;
      }
    }

    _bakeNormalFromHeight(heightField, w, h, normal, strength: 2.5);

    carbonAlbedo = Texture2D.fromPixels(
      albedo,
      w,
      h,
      content: TextureContent.color,
    );
    carbonNormal = Texture2D.fromPixels(
      normal,
      w,
      h,
      content: TextureContent.normal,
    );
  }

  /// Builds racing tire tread & grooved normal map.
  void _buildTireTextures() {
    const w = 128;
    const h = 128;
    final albedo = Uint8List(w * h * 4);
    final normal = Uint8List(w * h * 4);
    final heightField = Float32List(w * h);

    for (var y = 0; y < h; y++) {
      final v = y / h;
      for (var x = 0; x < w; x++) {
        final u = x / w;
        final idx = (y * w + x) * 4;

        // 3 circumferential drainage grooves + diagonal V-sipes
        final centerGroove =
            (u > 0.46 && u < 0.54) ||
            (u > 0.24 && u < 0.29) ||
            (u > 0.71 && u < 0.76);
        final sipePhase = ((v * 12.0) + (u - 0.5).abs() * 3.5) % 1.0;
        final isSipe = sipePhase < 0.14 && u > 0.12 && u < 0.88;

        final depth = (centerGroove || isSipe) ? -1.0 : 0.2;
        heightField[y * w + x] = depth;

        final c = (centerGroove || isSipe) ? 14 : 26;
        albedo[idx] = c;
        albedo[idx + 1] = c;
        albedo[idx + 2] = c + 3;
        albedo[idx + 3] = 255;
      }
    }

    _bakeNormalFromHeight(heightField, w, h, normal, strength: 3.2);

    tireAlbedo = Texture2D.fromPixels(
      albedo,
      w,
      h,
      content: TextureContent.color,
    );
    tireNormal = Texture2D.fromPixels(
      normal,
      w,
      h,
      content: TextureContent.normal,
    );
  }

  /// Builds a high-contrast checkered flag & start-line texture.
  Texture2D _buildCheckeredTexture() {
    const w = 256;
    const h = 64;
    final pixels = Uint8List(w * h * 4);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = (y * w + x) * 4;
        final cx = x ~/ 16;
        final cy = y ~/ 16;
        final isWhite = (cx + cy).isEven;
        final c = isWhite ? 245 : 20;
        pixels[idx] = c;
        pixels[idx + 1] = c;
        pixels[idx + 2] = isWhite ? 250 : 24;
        pixels[idx + 3] = 255;
      }
    }
    return Texture2D.fromPixels(pixels, w, h, content: TextureContent.color);
  }

  /// Builds a glowing neon chevron texture for scrolling boost pads.
  ///
  /// In [PlaneGeometry], `v = 0` maps to `-depth/2` (rear) and `v = 1` maps to
  /// `+depth/2` (`+Z`, forward driving direction). Using `v * 3.0 + centerDist`
  /// places the chevron apex (`centerDist = 0`) at a larger `v` (`+Z`) than its
  /// wings (`centerDist = 1`), so arrows point strictly FORWARD down the track!
  Texture2D _buildBoostPadTexture() {
    const w = 128;
    const h = 256;
    final pixels = Uint8List(w * h * 4);

    for (var y = 0; y < h; y++) {
      final v = y / h;
      for (var x = 0; x < w; x++) {
        final u = x / w;
        final idx = (y * w + x) * 4;

        final centerDist = (u - 0.5).abs() * 2.0; // 0 at center, 1 at edge
        // Forward-pointing chevron arrow pattern (+Z is v = 1.0)
        final chevronPhase = (v * 3.0 + centerDist * 0.92) % 1.0;
        final wrapped = chevronPhase < 0 ? chevronPhase + 1.0 : chevronPhase;

        final isArrowCore =
            wrapped > 0.22 && wrapped < 0.62 && centerDist < 0.85;
        final isArrowRim =
            wrapped > 0.16 && wrapped < 0.68 && centerDist < 0.88;
        final isEdgeRail = centerDist > 0.88 && centerDist < 0.96;

        double r = 8, g = 14, b = 28;
        if (isArrowCore) {
          final pulse = math.sin(((wrapped - 0.22) / 0.40) * math.pi);
          // Vibrant forward-pointing gradient: gold/white tip -> electric cyan wings
          r = 45.0 + 210.0 * (1.0 - centerDist * 0.75) * pulse;
          g = 225.0 * pulse + 30.0;
          b = 255.0;
        } else if (isArrowRim) {
          r = 0;
          g = 145;
          b = 240;
        } else if (isEdgeRail) {
          r = 255;
          g = 195;
          b = 35;
        }

        pixels[idx] = r.round().clamp(0, 255);
        pixels[idx + 1] = g.round().clamp(0, 255);
        pixels[idx + 2] = b.round().clamp(0, 255);
        pixels[idx + 3] = 255;
      }
    }

    return Texture2D.fromPixels(pixels, w, h, content: TextureContent.color);
  }

  /// Builds a festive Andean woven diamond & stripe pattern texture for Turbo Llama's poncho.
  Texture2D _buildPonchoTexture() {
    const w = 128;
    const h = 128;
    final pixels = Uint8List(w * h * 4);

    for (var y = 0; y < h; y++) {
      final v = y / h;
      for (var x = 0; x < w; x++) {
        final u = x / w;
        final idx = (y * w + x) * 4;

        // Woven textile micro-rib
        final weave = ((x + y) % 2 == 0) ? 1.04 : 0.94;
        // Repeating horizontal bands & Andean diamond motifs
        final band = (v * 6.0) % 1.0;
        final diamondX = ((u * 12.0) % 1.0 - 0.5).abs() * 2.0;
        final diamondY = ((v * 6.0) % 1.0 - 0.5).abs() * 2.0;
        final isDiamond = (diamondX + diamondY) < 0.68;

        double r, g, b;
        if (band < 0.14 || band > 0.86) {
          // Gold border stripe
          r = 250;
          g = 198;
          b = 28;
        } else if (band > 0.42 && band < 0.58 && isDiamond) {
          // Turquoise Andean diamond center
          r = 24;
          g = 225;
          b = 235;
        } else if (isDiamond) {
          // Warm太阳 orange-gold diamond
          r = 255;
          g = 135;
          b = 25;
        } else {
          // Rich Andean crimson-magenta base cloth
          r = 218;
          g = 26;
          b = 98;
        }

        pixels[idx] = (r * weave).round().clamp(0, 255);
        pixels[idx + 1] = (g * weave).round().clamp(0, 255);
        pixels[idx + 2] = (b * weave).round().clamp(0, 255);
        pixels[idx + 3] = 255;
      }
    }
    return Texture2D.fromPixels(pixels, w, h, content: TextureContent.color);
  }

  /// Builds a soft feather/wool normal map for character plumage & fleece.
  Texture2D _buildPlumageNormalTexture() {
    const w = 64;
    const h = 64;
    final normal = Uint8List(w * h * 4);
    final heightField = Float32List(w * h);
    final fluffNoise = FastNoiseLite(seed: 808)
      ..noiseType = NoiseType.cellular
      ..frequency = 0.28;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final n = fluffNoise.getNoise2(x.toDouble(), y.toDouble());
        final scallop =
            math.sin((x / w) * math.pi * 16.0) *
            math.cos((y / h) * math.pi * 16.0) *
            0.35;
        heightField[y * w + x] = n * 0.65 + scallop;
      }
    }
    _bakeNormalFromHeight(heightField, w, h, normal, strength: 1.9);
    return Texture2D.fromPixels(normal, w, h, content: TextureContent.normal);
  }

  /// Builds a vibrant stadium grandstand spectator crowd texture.
  Texture2D _buildCrowdTexture() {
    const w = 128;
    const h = 64;
    final pixels = Uint8List(w * h * 4);
    final rng = math.Random(777);

    const palette = <List<int>>[
      [235, 55, 60],
      [45, 160, 250],
      [250, 200, 45],
      [60, 215, 110],
      [240, 240, 248],
      [185, 85, 245],
      [255, 125, 40],
    ];

    for (var y = 0; y < h; y++) {
      final isAisle = (y % 8) < 2;
      for (var x = 0; x < w; x++) {
        final idx = (y * w + x) * 4;
        if (isAisle || (x % 32 == 0)) {
          pixels[idx] = 52;
          pixels[idx + 1] = 56;
          pixels[idx + 2] = 66;
          pixels[idx + 3] = 255;
        } else {
          final seatHash = ((x ~/ 3) * 73 + (y ~/ 4) * 37) % palette.length;
          final c = palette[seatHash];
          final jitter = rng.nextInt(24) - 12;
          pixels[idx] = (c[0] + jitter).clamp(0, 255);
          pixels[idx + 1] = (c[1] + jitter).clamp(0, 255);
          pixels[idx + 2] = (c[2] + jitter).clamp(0, 255);
          pixels[idx + 3] = 255;
        }
      }
    }
    return Texture2D.fromPixels(pixels, w, h, content: TextureContent.color);
  }

  /// Builds a soft circular radial glow sprite for exhaust flames & smoke puffs.
  Texture2D _buildParticleGlowTexture() {
    const size = 64;
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      final dy = (y + 0.5) / size * 2.0 - 1.0;
      for (var x = 0; x < size; x++) {
        final dx = (x + 0.5) / size * 2.0 - 1.0;
        final r2 = dx * dx + dy * dy;
        final falloff = r2 >= 1.0 ? 0.0 : math.pow(1.0 - r2, 2.2).toDouble();
        final idx = (y * size + x) * 4;
        final v = (falloff * 255).round().clamp(0, 255);
        pixels[idx] = 255;
        pixels[idx + 1] = 255;
        pixels[idx + 2] = 255;
        pixels[idx + 3] = v;
      }
    }
    return Texture2D.fromPixels(
      pixels,
      size,
      size,
      content: TextureContent.color,
    );
  }

  /// Builds an elongated diamond/streak sprite for drift sparks.
  Texture2D _buildSparkStreakTexture() {
    const size = 64;
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      final dy = ((y + 0.5) / size * 2.0 - 1.0).abs();
      for (var x = 0; x < size; x++) {
        final dx = ((x + 0.5) / size * 2.0 - 1.0).abs();
        // Sharp elongated diamond core
        final d = dx * 2.4 + dy * 0.85;
        final falloff = d >= 1.0 ? 0.0 : math.pow(1.0 - d, 1.8).toDouble();
        final idx = (y * size + x) * 4;
        pixels[idx] = 255;
        pixels[idx + 1] = 255;
        pixels[idx + 2] = 255;
        pixels[idx + 3] = (falloff * 255).round().clamp(0, 255);
      }
    }
    return Texture2D.fromPixels(
      pixels,
      size,
      size,
      content: TextureContent.color,
    );
  }

  static void _bakeNormalFromHeight(
    Float32List heightField,
    int w,
    int h,
    Uint8List outNormal, {
    double strength = 2.0,
  }) {
    for (var y = 0; y < h; y++) {
      final ym = (y - 1 + h) % h;
      final yp = (y + 1) % h;
      for (var x = 0; x < w; x++) {
        final xm = (x - 1 + w) % w;
        final xp = (x + 1) % w;

        final dX =
            (heightField[y * w + xp] - heightField[y * w + xm]) * strength;
        final dY =
            (heightField[yp * w + x] - heightField[ym * w + x]) * strength;

        final n = vm.Vector3(-dX, -dY, 1.0)..normalize();
        final idx = (y * w + x) * 4;
        outNormal[idx] = ((n.x * 0.5 + 0.5) * 255).round().clamp(0, 255);
        outNormal[idx + 1] = ((n.y * 0.5 + 0.5) * 255).round().clamp(0, 255);
        outNormal[idx + 2] = ((n.z * 0.5 + 0.5) * 255).round().clamp(0, 255);
        outNormal[idx + 3] = 255;
      }
    }
  }
}
