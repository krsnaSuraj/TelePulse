import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  const size = 1024;
  final canvas = img.Image(width: size, height: size);

  final bgDark = img.ColorRgba8(26, 26, 46, 255);
  final bgCircle = img.ColorRgba8(30, 39, 73, 255);
  final blue = img.ColorRgba8(42, 171, 238, 255);
  final white = img.ColorRgba8(255, 255, 255, 255);
  final grey = img.ColorRgba8(180, 190, 210, 255);

  _fillRect(canvas, 0, 0, size, size, bgDark);
  _fillCircle(canvas, 512, 512, 480, bgCircle);
  _drawRing(canvas, 512, 512, 470, 5, blue, 100);

  _drawSignalArc(canvas, 512, 512, 300, 8, blue, 40);
  _drawSignalArc(canvas, 512, 512, 350, 7, blue, 35);
  _drawSignalArc(canvas, 512, 512, 400, 6, blue, 30);

  _drawPaperPlane(canvas, 512, 512, white, grey);

  final png = img.encodePng(canvas);
  File('assets\\icon.png').writeAsBytesSync(png);
  print('Icon generated: assets/icon.png (${png.length} bytes)');
}

void _fillRect(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
  for (int y = y1; y < y2; y++) {
    for (int x = x1; x < x2; x++) {
      if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
        image.setPixel(x, y, color);
      }
    }
  }
}

void _fillCircle(img.Image image, int cx, int cy, int r, img.Color color) {
  final r2 = r * r;
  for (int y = cy - r; y <= cy + r; y++) {
    for (int x = cx - r; x <= cx + r; x++) {
      if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
        final dx = x - cx;
        final dy = y - cy;
        if (dx * dx + dy * dy <= r2) {
          image.setPixel(x, y, color);
        }
      }
    }
  }
}

void _drawRing(img.Image image, int cx, int cy, int r, int thickness, img.Color color, int alpha) {
  final c = img.ColorRgba8(color.r.toInt(), color.g.toInt(), color.b.toInt(), alpha);
  for (int y = cy - r - thickness; y <= cy + r + thickness; y++) {
    for (int x = cx - r - thickness; x <= cx + r + thickness; x++) {
      if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
        final dist = math.sqrt(((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble());
        if (dist >= r && dist <= r + thickness) {
          image.setPixel(x, y, c);
        }
      }
    }
  }
}

void _drawSignalArc(img.Image image, int cx, int cy, int r, int thickness, img.Color color, int alpha) {
  final c = img.ColorRgba8(color.r.toInt(), color.g.toInt(), color.b.toInt(), alpha);
  for (int y = cy - r - thickness; y <= cy + r + thickness; y++) {
    for (int x = cx - r - thickness; x <= cx + r + thickness; x++) {
      if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
        final dist = math.sqrt(((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble());
        if (dist >= r && dist <= r + thickness) {
          final angle = math.atan2((y - cy).toDouble(), (x - cx).toDouble()) * 180 / math.pi;
          if (angle >= 5 && angle <= 85) {
            image.setPixel(x, y, c);
          }
        }
      }
    }
  }
}

void _drawPaperPlane(img.Image image, int cx, int cy, img.Color mainColor, img.Color foldColor) {
  // Paper plane pointing upper-right, ~400px wide
  // 4 vertices defining the plane shape
  // Rotated -35 degrees to point upper-right

  final angle = -35 * math.pi / 180;
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);

  // Paper plane vertices (Telegram-inspired shape) - BIGGER size
  // Tip points right, wings spread up/down, tail to the left
  final rawVerts = [
    (220.0, 0.0),     // tip (right)
    (-130.0, -200.0), // upper wing
    (-220.0, 0.0),    // tail (left)
    (-130.0, 200.0),  // lower wing
  ];

  final rotated = rawVerts.map((v) {
    final rx = v.$1 * cosA - v.$2 * sinA;
    final ry = v.$1 * sinA + v.$2 * cosA;
    return (cx + rx, cy + ry);
  }).toList();

  // Fill the main body (quad = 2 triangles)
  _fillTriangleScanline(image, rotated[0], rotated[1], rotated[2], mainColor);
  _fillTriangleScanline(image, rotated[0], rotated[2], rotated[3], mainColor);

  // Draw fold line from tip to tail (subtle grey line for paper fold effect)
  _drawLine(image, rotated[0], rotated[2], foldColor, 5);
}

void _fillTriangleScanline(img.Image image, (double, double) v0, (double, double) v1, (double, double) v2, img.Color color) {
  // Sort vertices by Y coordinate
  var verts = [v0, v1, v2];
  verts.sort((a, b) => a.$2.compareTo(b.$2));

  final topY = verts[0].$2;
  final midY = verts[1].$2;
  final botY = verts[2].$2;

  final topX = verts[0].$1;
  final midX = verts[1].$1;
  final botX = verts[2].$1;

  // Scan from top to bottom
  final startY = topY.ceil().clamp(0, image.height - 1);
  final endY = botY.floor().clamp(0, image.height - 1);

  for (int y = startY; y <= endY; y++) {
    double xLeft, xRight;

    if (y <= midY) {
      // Upper half: interpolate between top and mid, top and bot
      xLeft = _lerpX(topX, topY, midX, midY, y.toDouble());
      xRight = _lerpX(topX, topY, botX, botY, y.toDouble());
    } else {
      // Lower half: interpolate between mid and bot, top and bot
      xLeft = _lerpX(midX, midY, botX, botY, y.toDouble());
      xRight = _lerpX(topX, topY, botX, botY, y.toDouble());
    }

    if (xLeft > xRight) {
      final tmp = xLeft;
      xLeft = xRight;
      xRight = tmp;
    }

    final sx = xLeft.floor().clamp(0, image.width - 1);
    final ex = xRight.ceil().clamp(0, image.width - 1);

    for (int x = sx; x <= ex; x++) {
      image.setPixel(x, y, color);
    }
  }
}

double _lerpX(double x1, double y1, double x2, double y2, double y) {
  if ((y2 - y1).abs() < 0.001) return (x1 + x2) / 2;
  final t = (y - y1) / (y2 - y1);
  return x1 + t * (x2 - x1);
}

void _drawLine(img.Image image, (double, double) start, (double, double) end, img.Color color, int thickness) {
  final dx = end.$1 - start.$1;
  final dy = end.$2 - start.$2;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length == 0) return;

  final steps = (length * 2).ceil();
  final half = thickness ~/ 2;

  for (int i = 0; i <= steps; i++) {
    final t = i / steps;
    final x = (start.$1 + t * dx).round();
    final y = (start.$2 + t * dy).round();

    for (int oy = -half; oy <= half; oy++) {
      for (int ox = -half; ox <= half; ox++) {
        final px = x + ox;
        final py = y + oy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, color);
        }
      }
    }
  }
}
