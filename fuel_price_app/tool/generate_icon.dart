// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  final size = 1024;
  final image = img.Image(width: size, height: size);

  // Blue gradient background
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final t = (x + y) / (size * 2);
      final r = (0x15 + (0x0D - 0x15) * t).round().clamp(0, 255);
      final g = (0x65 + (0x47 - 0x65) * t).round().clamp(0, 255);
      final b = (0xC0 + (0xA1 - 0xC0) * t).round().clamp(0, 255);
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Round corners (mask)
  final cornerRadius = 220;
  _roundCorners(image, cornerRadius);

  // Draw fuel pump body (white rounded rect)
  _fillRoundedRect(image, 320, 280, 580, 660, 24, 255, 255, 255, 240);

  // Draw pump display (dark blue)
  _fillRoundedRect(image, 352, 320, 548, 420, 12, 21, 101, 192, 80);

  // Draw pump base
  _fillRoundedRect(image, 300, 660, 600, 700, 12, 255, 255, 255, 220);

  // Draw nozzle arm
  _drawThickLine(image, 580, 380, 700, 310, 14, 255, 255, 255, 220);

  // Draw hose (thick curved line approx)
  for (var t = 0.0; t <= 1.0; t += 0.002) {
    final x = 620 + (80 * t) + (20 * sin(t * 3.14));
    final y = 440 + (180 * t);
    _fillCircle(image, x.round(), y.round(), 8, 255, 255, 255, 200);
  }

  // Draw nozzle tip
  _fillRoundedRect(image, 665, 615, 730, 635, 4, 255, 255, 255, 200);

  // Up arrow (green, left)
  _drawArrowUp(image, 220, 340, 60, 180, 76, 175, 80, 230);

  // Down arrow (red, right)
  _drawArrowDown(image, 800, 420, 60, 180, 239, 83, 80, 230);

  // Save full icon
  final pngBytes = img.encodePng(image);
  File('assets/app_icon.png').writeAsBytesSync(pngBytes);
  print('Generated assets/app_icon.png');

  // Create foreground (same but transparent background for adaptive icon)
  final fg = img.Image(width: size, height: size);

  // Draw everything except background
  _fillRoundedRect(fg, 320, 280, 580, 660, 24, 255, 255, 255, 240);
  _fillRoundedRect(fg, 352, 320, 548, 420, 12, 21, 101, 192, 180);
  _fillRoundedRect(fg, 300, 660, 600, 700, 12, 255, 255, 255, 220);
  _drawThickLine(fg, 580, 380, 700, 310, 14, 255, 255, 255, 220);
  for (var t = 0.0; t <= 1.0; t += 0.002) {
    final x = 620 + (80 * t) + (20 * sin(t * 3.14));
    final y = 440 + (180 * t);
    _fillCircle(fg, x.round(), y.round(), 8, 255, 255, 255, 200);
  }
  _fillRoundedRect(fg, 665, 615, 730, 635, 4, 255, 255, 255, 200);
  _drawArrowUp(fg, 220, 340, 60, 180, 76, 175, 80, 230);
  _drawArrowDown(fg, 800, 420, 60, 180, 239, 83, 80, 230);

  final fgBytes = img.encodePng(fg);
  File('assets/app_icon_foreground.png').writeAsBytesSync(fgBytes);
  print('Generated assets/app_icon_foreground.png');
}

void _roundCorners(img.Image image, int radius) {
  final w = image.width;
  final h = image.height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // Check if pixel is outside rounded corners
      bool outside = false;
      if (x < radius && y < radius) {
        outside = _outsideCircle(x, y, radius, radius, radius);
      } else if (x >= w - radius && y < radius) {
        outside = _outsideCircle(x, y, w - radius - 1, radius, radius);
      } else if (x < radius && y >= h - radius) {
        outside = _outsideCircle(x, y, radius, h - radius - 1, radius);
      } else if (x >= w - radius && y >= h - radius) {
        outside = _outsideCircle(x, y, w - radius - 1, h - radius - 1, radius);
      }
      if (outside) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
}

bool _outsideCircle(int x, int y, int cx, int cy, int r) {
  final dx = x - cx;
  final dy = y - cy;
  return dx * dx + dy * dy > r * r;
}

void _fillRoundedRect(img.Image image, int x1, int y1, int x2, int y2, int radius,
    int r, int g, int b, int a) {
  for (var y = y1; y < y2; y++) {
    for (var x = x1; x < x2; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      // Simple rounded corner check
      bool inside = true;
      if (x < x1 + radius && y < y1 + radius) {
        inside = !_outsideCircle(x, y, x1 + radius, y1 + radius, radius);
      } else if (x >= x2 - radius && y < y1 + radius) {
        inside = !_outsideCircle(x, y, x2 - radius - 1, y1 + radius, radius);
      } else if (x < x1 + radius && y >= y2 - radius) {
        inside = !_outsideCircle(x, y, x1 + radius, y2 - radius - 1, radius);
      } else if (x >= x2 - radius && y >= y2 - radius) {
        inside = !_outsideCircle(x, y, x2 - radius - 1, y2 - radius - 1, radius);
      }
      if (inside) {
        _blendPixel(image, x, y, r, g, b, a);
      }
    }
  }
}

void _fillCircle(img.Image image, int cx, int cy, int radius, int r, int g, int b, int a) {
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      if (dx * dx + dy * dy <= radius * radius) {
        final x = cx + dx;
        final y = cy + dy;
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          _blendPixel(image, x, y, r, g, b, a);
        }
      }
    }
  }
}

void _drawThickLine(img.Image image, int x1, int y1, int x2, int y2, int thickness,
    int r, int g, int b, int a) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  final len = sqrt(dx * dx + dy * dy);
  final steps = len.round() * 2;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final x = (x1 + dx * t).round();
    final y = (y1 + dy * t).round();
    _fillCircle(image, x, y, thickness ~/ 2, r, g, b, a);
  }
}

void _drawArrowUp(img.Image image, int cx, int top, int halfWidth, int height,
    int r, int g, int b, int a) {
  // Arrow head (triangle pointing up)
  final headHeight = height ~/ 2;
  for (var y = 0; y < headHeight; y++) {
    final progress = y / headHeight;
    final width = (halfWidth * progress).round();
    for (var x = cx - width; x <= cx + width; x++) {
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height) {
        _blendPixel(image, x, top + y, r, g, b, a);
      }
    }
  }
  // Arrow shaft
  final shaftWidth = halfWidth ~/ 2;
  for (var y = headHeight; y < height; y++) {
    for (var x = cx - shaftWidth; x <= cx + shaftWidth; x++) {
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height) {
        _blendPixel(image, x, top + y, r, g, b, a);
      }
    }
  }
}

void _drawArrowDown(img.Image image, int cx, int top, int halfWidth, int height,
    int r, int g, int b, int a) {
  // Arrow shaft
  final headHeight = height ~/ 2;
  final shaftWidth = halfWidth ~/ 2;
  for (var y = 0; y < headHeight; y++) {
    for (var x = cx - shaftWidth; x <= cx + shaftWidth; x++) {
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height) {
        _blendPixel(image, x, top + y, r, g, b, a);
      }
    }
  }
  // Arrow head (triangle pointing down)
  for (var y = 0; y < headHeight; y++) {
    final progress = 1 - (y / headHeight);
    final width = (halfWidth * progress).round();
    for (var x = cx - width; x <= cx + width; x++) {
      final py = top + headHeight + y;
      if (x >= 0 && x < image.width && py >= 0 && py < image.height) {
        _blendPixel(image, x, py, r, g, b, a);
      }
    }
  }
}

void _blendPixel(img.Image image, int x, int y, int r, int g, int b, int a) {
  final existing = image.getPixel(x, y);
  final er = existing.r.toInt();
  final eg = existing.g.toInt();
  final eb = existing.b.toInt();
  final ea = existing.a.toInt();

  final alpha = a / 255;
  final invAlpha = 1 - alpha;

  final nr = (r * alpha + er * invAlpha).round().clamp(0, 255);
  final ng = (g * alpha + eg * invAlpha).round().clamp(0, 255);
  final nb = (b * alpha + eb * invAlpha).round().clamp(0, 255);
  final na = (a + ea * invAlpha).round().clamp(0, 255);

  image.setPixelRgba(x, y, nr, ng, nb, na);
}
