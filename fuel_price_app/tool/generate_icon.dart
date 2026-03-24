// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  final size = 1024;

  // === FULL ICON ===
  final image = img.Image(width: size, height: size);
  _fill(image, 0x42, 0x7A, 0xC7); // medium blue
  _roundCorners(image, 220);
  _drawDesign(image);
  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(image));
  print('Generated assets/app_icon.png');

  // === FOREGROUND (transparent bg, for adaptive) ===
  final fg = img.Image(width: size, height: size);
  _drawDesign(fg);
  File('assets/app_icon_foreground.png').writeAsBytesSync(img.encodePng(fg));
  print('Generated assets/app_icon_foreground.png');
}

void _drawDesign(img.Image image) {
  // Fuel pump — centered, clean silhouette
  // Main body
  _fillRoundRect(image, 340, 240, 580, 620, 20, 255, 255, 255, 255);

  // Display window (subtracted look — semi-transparent)
  _fillRoundRect(image, 375, 285, 545, 385, 10, 255, 255, 255, 60);

  // Base plate
  _fillRoundRect(image, 310, 620, 610, 670, 12, 255, 255, 255, 255);

  // Nozzle holder on right
  _fillRect(image, 580, 330, 610, 390, 255, 255, 255, 255);

  // Nozzle arm
  _drawLine(image, 610, 360, 680, 300, 10, 255, 255, 255, 255);

  // Hose curve
  for (var t = 0.0; t <= 1.0; t += 0.002) {
    final x = 610 + (70 * t);
    final y = 390 + (140 * t) + (30 * sin(t * 3.14));
    _circle(image, x.round(), y.round(), 6, 255, 255, 255, 255);
  }

  // Nozzle tip
  _fillRect(image, 660, 535, 710, 550, 255, 255, 255, 255);

  // Both arrows on the LEFT side, one above the other, thin
  // Up arrow (green)
  _drawThinArrowUp(image, 190, 290, 35, 150, 0x4C, 0xAF, 0x50);
  // Down arrow (red)
  _drawThinArrowDown(image, 190, 470, 35, 150, 0xEF, 0x53, 0x50);
}

void _fill(img.Image image, int r, int g, int b) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

void _roundCorners(img.Image image, int radius) {
  final w = image.width, h = image.height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      bool outside = false;
      if (x < radius && y < radius) outside = _dist(x, y, radius, radius) > radius;
      else if (x >= w - radius && y < radius) outside = _dist(x, y, w - radius - 1, radius) > radius;
      else if (x < radius && y >= h - radius) outside = _dist(x, y, radius, h - radius - 1) > radius;
      else if (x >= w - radius && y >= h - radius) outside = _dist(x, y, w - radius - 1, h - radius - 1) > radius;
      if (outside) image.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
}

double _dist(int x, int y, int cx, int cy) =>
    sqrt(((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble());

void _fillRect(img.Image img, int x1, int y1, int x2, int y2, int r, int g, int b, int a) {
  for (var y = y1; y < y2; y++)
    for (var x = x1; x < x2; x++)
      if (x >= 0 && x < img.width && y >= 0 && y < img.height)
        _blend(img, x, y, r, g, b, a);
}

void _fillRoundRect(img.Image image, int x1, int y1, int x2, int y2, int rad,
    int r, int g, int b, int a) {
  for (var y = y1; y < y2; y++) {
    for (var x = x1; x < x2; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      bool inside = true;
      if (x < x1 + rad && y < y1 + rad) inside = _dist(x, y, x1 + rad, y1 + rad) <= rad;
      else if (x >= x2 - rad && y < y1 + rad) inside = _dist(x, y, x2 - rad - 1, y1 + rad) <= rad;
      else if (x < x1 + rad && y >= y2 - rad) inside = _dist(x, y, x1 + rad, y2 - rad - 1) <= rad;
      else if (x >= x2 - rad && y >= y2 - rad) inside = _dist(x, y, x2 - rad - 1, y2 - rad - 1) <= rad;
      if (inside) _blend(image, x, y, r, g, b, a);
    }
  }
}

void _circle(img.Image image, int cx, int cy, int radius, int r, int g, int b, int a) {
  for (var dy = -radius; dy <= radius; dy++)
    for (var dx = -radius; dx <= radius; dx++)
      if (dx * dx + dy * dy <= radius * radius) {
        final x = cx + dx, y = cy + dy;
        if (x >= 0 && x < image.width && y >= 0 && y < image.height)
          _blend(image, x, y, r, g, b, a);
      }
}

void _drawLine(img.Image image, int x1, int y1, int x2, int y2, int t, int r, int g, int b, int a) {
  final dx = (x2 - x1).toDouble(), dy = (y2 - y1).toDouble();
  final steps = sqrt(dx * dx + dy * dy).round() * 2;
  for (var i = 0; i <= steps; i++) {
    final p = i / steps;
    _circle(image, (x1 + dx * p).round(), (y1 + dy * p).round(), t ~/ 2, r, g, b, a);
  }
}

void _drawThinArrowUp(img.Image image, int cx, int top, int hw, int h, int r, int g, int b) {
  final headH = h * 40 ~/ 100;
  final sw = hw * 35 ~/ 100;
  for (var y = 0; y < headH; y++) {
    final w = (hw * y / headH).round();
    for (var x = cx - w; x <= cx + w; x++)
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height)
        image.setPixelRgba(x, top + y, r, g, b, 255);
  }
  for (var y = headH; y < h; y++)
    for (var x = cx - sw; x <= cx + sw; x++)
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height)
        image.setPixelRgba(x, top + y, r, g, b, 255);
}

void _drawThinArrowDown(img.Image image, int cx, int top, int hw, int h, int r, int g, int b) {
  final headH = h * 40 ~/ 100;
  final sw = hw * 35 ~/ 100;
  for (var y = 0; y < h - headH; y++)
    for (var x = cx - sw; x <= cx + sw; x++)
      if (x >= 0 && x < image.width && (top + y) >= 0 && (top + y) < image.height)
        image.setPixelRgba(x, top + y, r, g, b, 255);
  for (var y = 0; y < headH; y++) {
    final w = (hw * (1 - y / headH)).round();
    final py = top + h - headH + y;
    for (var x = cx - w; x <= cx + w; x++)
      if (x >= 0 && x < image.width && py >= 0 && py < image.height)
        image.setPixelRgba(x, py, r, g, b, 255);
  }
}

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
