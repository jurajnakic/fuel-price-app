// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

/// Generates a clean, minimal app icon:
/// - Soft blue rounded square background
/// - Stylized fuel drop shape (white)
/// - Small up/down arrows integrated into the drop
void main() {
  final size = 1024;

  // === FULL ICON ===
  final image = img.Image(width: size, height: size);
  _fill(image, 0x4A, 0x80, 0xC8); // pleasant blue
  _roundCorners(image, 230);
  _drawDesign(image);
  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(image));
  print('Generated assets/app_icon.png');

  // === FOREGROUND (transparent bg) ===
  final fg = img.Image(width: size, height: size);
  _drawDesign(fg);
  File('assets/app_icon_foreground.png').writeAsBytesSync(img.encodePng(fg));
  print('Generated assets/app_icon_foreground.png');
}

void _drawDesign(img.Image image) {
  final cx = 512, cy = 512;

  // Large fuel drop — teardrop shape, white
  _drawDrop(image, cx, cy - 20, 200, 320, 255, 255, 255, 255);

  // Up arrow (green) — left of center, small
  _drawSmallArrow(image, cx - 280, cy - 60, true, 0x4C, 0xAF, 0x50);

  // Down arrow (red) — left of center, below up arrow
  _drawSmallArrow(image, cx - 280, cy + 100, false, 0xEF, 0x53, 0x50);
}

/// Draw a teardrop/fuel-drop shape
void _drawDrop(img.Image image, int cx, int cy, int radiusX, int radiusY,
    int r, int g, int b, int a) {
  // Bottom circle part
  final circleR = radiusX;
  final circleCy = cy + radiusY - circleR;

  for (var y = cy - radiusY; y <= circleCy + circleR; y++) {
    for (var x = cx - radiusX - 10; x <= cx + radiusX + 10; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

      bool inside = false;

      if (y >= circleCy) {
        // Circle part (bottom)
        final dx = (x - cx).toDouble();
        final dy = (y - circleCy).toDouble();
        inside = (dx * dx + dy * dy) <= circleR * circleR;
      } else {
        // Tapered top part — triangle tapering to point
        final progress = (y - (cy - radiusY)) / (circleCy - (cy - radiusY));
        final halfWidth = radiusX * progress;
        inside = (x - cx).abs() <= halfWidth;
      }

      if (inside) _blend(image, x, y, r, g, b, a);
    }
  }
}

/// Draw a compact arrow (up or down)
void _drawSmallArrow(img.Image image, int cx, int cy, bool up,
    int r, int g, int b) {
  final hw = 42; // half-width of arrow head
  final h = 130; // total height
  final headH = (h * 0.45).round();
  final shaftW = (hw * 0.38).round();

  if (up) {
    // Head (triangle pointing up)
    for (var y = 0; y < headH; y++) {
      final w = (hw * y / headH).round();
      for (var x = cx - w; x <= cx + w; x++) {
        if (x >= 0 && x < image.width && (cy + y) >= 0 && (cy + y) < image.height) {
          image.setPixelRgba(x, cy + y, r, g, b, 255);
        }
      }
    }
    // Shaft
    for (var y = headH; y < h; y++) {
      for (var x = cx - shaftW; x <= cx + shaftW; x++) {
        if (x >= 0 && x < image.width && (cy + y) >= 0 && (cy + y) < image.height) {
          image.setPixelRgba(x, cy + y, r, g, b, 255);
        }
      }
    }
  } else {
    // Shaft first
    for (var y = 0; y < h - headH; y++) {
      for (var x = cx - shaftW; x <= cx + shaftW; x++) {
        if (x >= 0 && x < image.width && (cy + y) >= 0 && (cy + y) < image.height) {
          image.setPixelRgba(x, cy + y, r, g, b, 255);
        }
      }
    }
    // Head (triangle pointing down)
    for (var y = 0; y < headH; y++) {
      final w = (hw * (1 - y / headH)).round();
      final py = cy + h - headH + y;
      for (var x = cx - w; x <= cx + w; x++) {
        if (x >= 0 && x < image.width && py >= 0 && py < image.height) {
          image.setPixelRgba(x, py, r, g, b, 255);
        }
      }
    }
  }
}

void _fill(img.Image image, int r, int g, int b) {
  for (var y = 0; y < image.height; y++)
    for (var x = 0; x < image.width; x++)
      image.setPixelRgba(x, y, r, g, b, 255);
}

void _roundCorners(img.Image image, int radius) {
  final w = image.width, h = image.height;
  for (var y = 0; y < h; y++)
    for (var x = 0; x < w; x++) {
      bool out = false;
      if (x < radius && y < radius) out = _d(x, y, radius, radius) > radius;
      else if (x >= w - radius && y < radius) out = _d(x, y, w - radius - 1, radius) > radius;
      else if (x < radius && y >= h - radius) out = _d(x, y, radius, h - radius - 1) > radius;
      else if (x >= w - radius && y >= h - radius) out = _d(x, y, w - radius - 1, h - radius - 1) > radius;
      if (out) image.setPixelRgba(x, y, 0, 0, 0, 0);
    }
}

double _d(int x, int y, int cx, int cy) =>
    sqrt(((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble());

void _blend(img.Image image, int x, int y, int r, int g, int b, int a) {
  if (a == 255) { image.setPixelRgba(x, y, r, g, b, 255); return; }
  final p = image.getPixel(x, y);
  final al = a / 255, inv = 1 - al;
  image.setPixelRgba(x, y,
    (r * al + p.r.toInt() * inv).round().clamp(0, 255),
    (g * al + p.g.toInt() * inv).round().clamp(0, 255),
    (b * al + p.b.toInt() * inv).round().clamp(0, 255),
    (a + p.a.toInt() * inv).round().clamp(0, 255));
}
