// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  final size = 1024;

  // === FULL ICON (for legacy launchers) ===
  final image = img.Image(width: size, height: size);

  // Soft blue background
  _fill(image, 0x5B, 0x8D, 0xD9);

  // Round corners
  _roundCorners(image, 220);

  // Draw white fuel pump and arrows
  _drawPumpAndArrows(image, 255, 255, 255);

  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(image));
  print('Generated assets/app_icon.png');

  // === FOREGROUND (for adaptive icons, transparent bg) ===
  final fg = img.Image(width: size, height: size);
  _drawPumpAndArrows(fg, 255, 255, 255);

  File('assets/app_icon_foreground.png').writeAsBytesSync(img.encodePng(fg));
  print('Generated assets/app_icon_foreground.png');
}

void _drawPumpAndArrows(img.Image image, int r, int g, int b) {
  // Fuel pump body — clean rectangle
  _fillRect(image, 360, 260, 600, 640, r, g, b, 255);

  // Pump display/screen — cutout (darker)
  _fillRect(image, 392, 300, 568, 400, r, g, b, 80);

  // Pump base — wider rectangle
  _fillRect(image, 330, 640, 630, 690, r, g, b, 255);

  // Nozzle holder — small rect on right side
  _fillRect(image, 600, 340, 630, 400, r, g, b, 255);

  // Nozzle arm — angled line going right and up
  _drawLine(image, 630, 370, 710, 300, 12, r, g, b, 255);

  // Hose — smooth curve from nozzle holder down
  for (var t = 0.0; t <= 1.0; t += 0.002) {
    final x = 630 + (90 * t);
    final y = 400 + (160 * t) + (40 * sin(t * 3.14));
    _circle(image, x.round(), y.round(), 7, r, g, b, 255);
  }

  // Nozzle tip at end of hose
  _fillRect(image, 700, 565, 750, 580, r, g, b, 255);

  // Up arrow — left side
  _drawArrowUp(image, 210, 320, 55, 200, r, g, b);

  // Down arrow — right side
  _drawArrowDown(image, 820, 400, 55, 200, r, g, b);
}

void _fill(img.Image image, int r, int g, int b) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

void _roundCorners(img.Image image, int radius) {
  final w = image.width;
  final h = image.height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      bool outside = false;
      if (x < radius && y < radius) {
        outside = _dist(x, y, radius, radius) > radius;
      } else if (x >= w - radius && y < radius) {
        outside = _dist(x, y, w - radius - 1, radius) > radius;
      } else if (x < radius && y >= h - radius) {
        outside = _dist(x, y, radius, h - radius - 1) > radius;
      } else if (x >= w - radius && y >= h - radius) {
        outside = _dist(x, y, w - radius - 1, h - radius - 1) > radius;
      }
      if (outside) image.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
}

double _dist(int x, int y, int cx, int cy) {
  final dx = (x - cx).toDouble();
  final dy = (y - cy).toDouble();
  return sqrt(dx * dx + dy * dy);
}

void _fillRect(img.Image image, int x1, int y1, int x2, int y2,
    int r, int g, int b, int a) {
  for (var y = y1; y < y2; y++) {
    for (var x = x1; x < x2; x++) {
      if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
        _blend(image, x, y, r, g, b, a);
      }
    }
  }
}

void _circle(img.Image image, int cx, int cy, int radius,
    int r, int g, int b, int a) {
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      if (dx * dx + dy * dy <= radius * radius) {
        final x = cx + dx, y = cy + dy;
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          _blend(image, x, y, r, g, b, a);
        }
      }
    }
  }
}

void _drawLine(img.Image image, int x1, int y1, int x2, int y2,
    int thickness, int r, int g, int b, int a) {
  final dx = (x2 - x1).toDouble();
  final dy = (y2 - y1).toDouble();
  final steps = sqrt(dx * dx + dy * dy).round() * 2;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    _circle(image, (x1 + dx * t).round(), (y1 + dy * t).round(),
        thickness ~/ 2, r, g, b, a);
  }
}

void _drawArrowUp(img.Image image, int cx, int top, int hw, int h,
    int r, int g, int b) {
  final headH = h * 45 ~/ 100;
  // Arrow head
  for (var y = 0; y < headH; y++) {
    final w = (hw * y / headH).round();
    for (var x = cx - w; x <= cx + w; x++) {
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height) {
        image.setPixelRgba(x, top + y, r, g, b, 255);
      }
    }
  }
  // Shaft
  final sw = hw * 40 ~/ 100;
  for (var y = headH; y < h; y++) {
    for (var x = cx - sw; x <= cx + sw; x++) {
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height) {
        image.setPixelRgba(x, top + y, r, g, b, 255);
      }
    }
  }
}

void _drawArrowDown(img.Image image, int cx, int top, int hw, int h,
    int r, int g, int b) {
  final headH = h * 45 ~/ 100;
  final sw = hw * 40 ~/ 100;
  // Shaft
  for (var y = 0; y < h - headH; y++) {
    for (var x = cx - sw; x <= cx + sw; x++) {
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height) {
        image.setPixelRgba(x, top + y, r, g, b, 255);
      }
    }
  }
  // Arrow head
  for (var y = 0; y < headH; y++) {
    final w = (hw * (1 - y / headH)).round();
    final py = top + h - headH + y;
    for (var x = cx - w; x <= cx + w; x++) {
      if (x >= 0 && x < image.width && py >= 0 && py < image.height) {
        image.setPixelRgba(x, py, r, g, b, 255);
      }
    }
  }
}

void _blend(img.Image image, int x, int y, int r, int g, int b, int a) {
  if (a == 255) {
    image.setPixelRgba(x, y, r, g, b, 255);
    return;
  }
  final p = image.getPixel(x, y);
  final alpha = a / 255;
  final inv = 1 - alpha;
  image.setPixelRgba(x, y,
      (r * alpha + p.r.toInt() * inv).round().clamp(0, 255),
      (g * alpha + p.g.toInt() * inv).round().clamp(0, 255),
      (b * alpha + p.b.toInt() * inv).round().clamp(0, 255),
      (a + p.a.toInt() * inv).round().clamp(0, 255));
}
