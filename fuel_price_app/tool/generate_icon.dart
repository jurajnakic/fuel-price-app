// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

/// Icon: fuel nozzle with a dripping drop, all white on blue background
void main() {
  final size = 1024;

  // === FULL ICON ===
  final image = img.Image(width: size, height: size);
  _fill(image, 0x4A, 0x80, 0xC8);
  _roundCorners(image, 230);
  _drawNozzle(image, 255, 255, 255);
  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(image));
  print('Generated assets/app_icon.png');

  // === FOREGROUND ===
  final fg = img.Image(width: size, height: size);
  _drawNozzle(fg, 255, 255, 255);
  File('assets/app_icon_foreground.png').writeAsBytesSync(img.encodePng(fg));
  print('Generated assets/app_icon_foreground.png');
}

void _drawNozzle(img.Image image, int r, int g, int b) {
  // Hose coming from top-left, curving down
  // Hose section — thick curved line from top-left toward center
  for (var t = 0.0; t <= 1.0; t += 0.001) {
    // Bezier-like curve: start top-left, curve to right-center
    final x = 250 + 350 * t;
    final y = 180 + 100 * t - 60 * sin(t * 3.14);
    _filledCircle(image, x.round(), y.round(), 28, r, g, b);
  }

  // Handle grip — vertical thick bar
  _fillRoundRect(image, 540, 150, 620, 360, 16, r, g, b);

  // Handle back curve
  for (var t = 0.0; t <= 1.0; t += 0.001) {
    final x = 620 + 60 * sin(t * 3.14 * 0.5);
    final y = 150 + 210 * t;
    _filledCircle(image, x.round(), y.round(), 20, r, g, b);
  }

  // Nozzle body — angled rectangle going down-left from handle
  for (var t = 0.0; t <= 1.0; t += 0.001) {
    final x = 560 - 120 * t;
    final y = 360 + 280 * t;
    _filledCircle(image, x.round(), y.round(), 30 - (12 * t).round(), r, g, b);
  }

  // Nozzle tip — narrow end
  for (var t = 0.0; t <= 1.0; t += 0.001) {
    final x = 440 - 40 * t;
    final y = 640 + 80 * t;
    _filledCircle(image, x.round(), y.round(), 18 - (6 * t).round(), r, g, b);
  }

  // Trigger — small bar inside handle area
  _fillRect(image, 500, 310, 545, 340, r, g, b);

  // Dripping drop below nozzle tip
  _drawDrop(image, 395, 740, 40, 75, r, g, b);
}

/// Teardrop shape — pointed top, round bottom
void _drawDrop(img.Image image, int cx, int top, int radius, int height,
    int r, int g, int b) {
  final circleY = top + height - radius;

  for (var y = top; y <= circleY + radius; y++) {
    for (var x = cx - radius - 2; x <= cx + radius + 2; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

      bool inside = false;
      if (y >= circleY) {
        // Bottom circle
        final dx = (x - cx).toDouble();
        final dy = (y - circleY).toDouble();
        inside = (dx * dx + dy * dy) <= radius * radius;
      } else {
        // Taper to point
        final progress = (y - top) / (circleY - top);
        inside = (x - cx).abs() <= radius * progress;
      }

      if (inside) image.setPixelRgba(x, y, r, g, b, 255);
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

void _filledCircle(img.Image image, int cx, int cy, int radius, int r, int g, int b) {
  for (var dy = -radius; dy <= radius; dy++)
    for (var dx = -radius; dx <= radius; dx++)
      if (dx * dx + dy * dy <= radius * radius) {
        final x = cx + dx, y = cy + dy;
        if (x >= 0 && x < image.width && y >= 0 && y < image.height)
          image.setPixelRgba(x, y, r, g, b, 255);
      }
}

void _fillRect(img.Image image, int x1, int y1, int x2, int y2, int r, int g, int b) {
  for (var y = y1; y < y2; y++)
    for (var x = x1; x < x2; x++)
      if (x >= 0 && x < image.width && y >= 0 && y < image.height)
        image.setPixelRgba(x, y, r, g, b, 255);
}

void _fillRoundRect(img.Image image, int x1, int y1, int x2, int y2, int rad, int r, int g, int b) {
  for (var y = y1; y < y2; y++)
    for (var x = x1; x < x2; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      bool inside = true;
      if (x < x1 + rad && y < y1 + rad) inside = _d(x, y, x1 + rad, y1 + rad) <= rad;
      else if (x >= x2 - rad && y < y1 + rad) inside = _d(x, y, x2 - rad - 1, y1 + rad) <= rad;
      else if (x < x1 + rad && y >= y2 - rad) inside = _d(x, y, x1 + rad, y2 - rad - 1) <= rad;
      else if (x >= x2 - rad && y >= y2 - rad) inside = _d(x, y, x2 - rad - 1, y2 - rad - 1) <= rad;
      if (inside) image.setPixelRgba(x, y, r, g, b, 255);
    }
}
