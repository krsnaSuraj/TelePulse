import 'dart:io';
import 'dart:math';

import 'package:image/image.dart';

const int render = 2048;
const int outSize = 1024;
const double c = render / 2;

double clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

double smoothstep(double edge0, double edge1, double x) {
  final t = clampD((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double coverage(double dist, double halfWidth, double aa) =>
    1.0 - smoothstep(halfWidth - aa, halfWidth + aa, dist);

const boltRel = [
  (0.10, -0.34),
  (-0.16, 0.06),
  (-0.05, 0.06),
  (-0.10, 0.34),
  (0.16, -0.08),
  (0.05, -0.08),
];

double pointSegDist(
    double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = clampD(t, 0.0, 1.0);
  final qx = ax + t * dx - px;
  final qy = ay + t * dy - py;
  return sqrt(qx * qx + qy * qy);
}

bool pointInPoly(double px, double py, List<Point> pts) {
  var inside = false;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final xi = pts[i].x.toDouble();
    final yi = pts[i].y.toDouble();
    final xj = pts[j].x.toDouble();
    final yj = pts[j].y.toDouble();
    if ((yi > py) != (yj > py) &&
        px < (xj - xi) * (py - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

double polyDist(double px, double py, List<Point> pts) {
  var best = double.infinity;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    final d = pointSegDist(px, py, a.x.toDouble(), a.y.toDouble(),
        b.x.toDouble(), b.y.toDouble());
    if (d < best) best = d;
  }
  return best;
}

double angDiff(double a, double b) {
  var d = (a - b) % (2 * pi);
  if (d > pi) d -= 2 * pi;
  if (d < -pi) d += 2 * pi;
  return d.abs();
}

Image renderEmblem({
  required double scale,
  required bool transparent,
}) {
  final img = Image(width: render, height: render, numChannels: 4);
  final s = render / 1024.0 * scale;
  const aa = 1.6;

  final boltPts = [
    for (final p in boltRel)
      Point(c + p.$1 * 560 * s * 0.9, c + p.$2 * 560 * s * 0.9),
  ];
  var minX = render.toDouble();
  var minY = render.toDouble();
  var maxX = 0.0;
  var maxY = 0.0;
  for (final p in boltPts) {
    minX = min(minX, p.x.toDouble());
    minY = min(minY, p.y.toDouble());
    maxX = max(maxX, p.x.toDouble());
    maxY = max(maxY, p.y.toDouble());
  }
  const boltMargin = 90.0;

  for (var y = 0; y < render; y++) {
    final py = y + 0.5;
    final t = y / (render - 1);
    final bgR = (22 + (9 - 22) * t);
    final bgG = (23 + (10 - 23) * t);
    final bgB = (28 + (12 - 28) * t);
    for (var x = 0; x < render; x++) {
      final px = x + 0.5;
      final dx = px - c;
      final dy = py - c;
      final dist = sqrt(dx * dx + dy * dy);
      final ang = atan2(dy, dx);

      var r = transparent ? 0.0 : bgR;
      var g = transparent ? 0.0 : bgG;
      var b = transparent ? 0.0 : bgB;
      var a = transparent ? 0.0 : 255.0;

      void blend(double sr, double sg, double sb, double sa) {
        if (sa <= 0) return;
        final inv = 1 - sa;
        r = sr * sa + r * inv;
        g = sg * sa + g * inv;
        b = sb * sa + b * inv;
        a = sa + a * inv;
      }

      for (final ring in [300.0 * s, 238.0 * s]) {
        final cov = coverage((dist - ring).abs(), 2.2 * s, aa) *
            (ring > 260 * s ? 0.16 : 0.26);
        blend(232, 163, 61, cov);
      }

      var inWedge = false;
      for (final ring in [300.0 * s, 238.0 * s]) {
        final band = coverage((dist - ring).abs(), 11.0 * s, aa + 2.0 * s);
        if (band <= 0) continue;
        final spread = 54 * pi / 180;
        final dAng = angDiff(ang, 0);
        if (dAng < spread) {
          inWedge = true;
          final edge = smoothstep(spread, spread - 6 * pi / 180, dAng);
          blend(232, 163, 61, band * (0.55 + 0.45 * edge));
        }
      }
      if (inWedge) {
        final tipX = c + 300 * s;
        final dTip =
            sqrt((px - tipX) * (px - tipX) + (py - c) * (py - c));
        final glow = 1.0 - smoothstep(8 * s, 46 * s, dTip);
        blend(232, 163, 61, glow * 0.5);
        final dot = 1.0 - smoothstep(10 * s, 13 * s, dTip);
        blend(255, 205, 120, dot);
      }

      if (px > minX - boltMargin &&
          px < maxX + boltMargin &&
          py > minY - boltMargin &&
          py < maxY + boltMargin) {
        final inside = pointInPoly(px, py, boltPts);
        final edge = polyDist(px, py, boltPts);
        if (inside) {
          blend(232, 163, 61, 1.0);
          blend(255, 220, 150,
              (1.0 - smoothstep(10 * s, 90 * s, edge)) * 0.35);
        } else {
          final glow = (1.0 - smoothstep(0, 48 * s, edge)) * 0.3;
          blend(232, 163, 61, glow);
          final aaEdge = 1.0 - smoothstep(0, aa * 1.4, edge);
          blend(232, 163, 61, aaEdge);
        }
      }

      img.setPixel(
        x,
        y,
        ColorRgba8(r.round().clamp(0, 255), g.round().clamp(0, 255),
            b.round().clamp(0, 255), (a * 255).round().clamp(0, 255)),
      );
    }
  }
  return img;
}

Image downsample(Image src) {
  final dst = Image(width: outSize, height: outSize, numChannels: 4);
  for (var y = 0; y < outSize; y++) {
    for (var x = 0; x < outSize; x++) {
      var r = 0, g = 0, b = 0, a = 0;
      for (var j = 0; j < 2; j++) {
        for (var i = 0; i < 2; i++) {
          final px = src.getPixel(x * 2 + i, y * 2 + j);
          r += px.r.toInt();
          g += px.g.toInt();
          b += px.b.toInt();
          a += px.a.toInt();
        }
      }
      dst.setPixel(x, y,
          ColorRgba8(r ~/ 4, g ~/ 4, b ~/ 4, a ~/ 4));
    }
  }
  return dst;
}

void applyRoundMask(Image img) {
  const radius = 230.0;
  const half = outSize / 2.0;
  for (var y = 0; y < outSize; y++) {
    for (var x = 0; x < outSize; x++) {
      final dx = max((x + 0.5 - half).abs() - (half - radius), 0.0);
      final dy = max((y + 0.5 - half).abs() - (half - radius), 0.0);
      final d = sqrt(dx * dx + dy * dy);
      if (d > radius) {
        final px = img.getPixel(x, y);
        final keep = (1.0 - smoothstep(radius - 1.5, radius + 1.5, d));
        img.setPixel(
            x,
            y,
            ColorRgba8(px.r.toInt(), px.g.toInt(), px.b.toInt(),
                (px.a.toInt() * keep).round()));
      }
    }
  }
}

Future<void> main() async {
  final outDir = Directory('${Directory.current.path}/assets').path;
  final full = downsample(renderEmblem(scale: 1.3, transparent: false));
  applyRoundMask(full);
  await encodePngFile('$outDir/icon.png', full);
  // ignore: avoid_print
  print('wrote icon.png');

  final fg = downsample(renderEmblem(scale: 0.72, transparent: true));
  await encodePngFile('$outDir/icon_fg.png', fg);
  // ignore: avoid_print
  print('wrote icon_fg.png');
  exit(0);
}
