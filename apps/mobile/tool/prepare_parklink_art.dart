import 'dart:io';
import 'package:image/image.dart' as image;

void main() {
  final source = image.decodePng(
    File('assets/images/parklink_logo.png').readAsBytesSync(),
  )!;
  final transparent = image.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final p = source.getPixel(x, y);
      final alpha =
          ([p.r, p.g, p.b].reduce((a, b) => a > b ? a : b).toInt() - 8).clamp(
            0,
            255,
          );
      if (alpha > 0) {
        transparent.setPixelRgba(
          x,
          y,
          (p.r * 255 / alpha).round().clamp(0, 255),
          (p.g * 255 / alpha).round().clamp(0, 255),
          (p.b * 255 / alpha).round().clamp(0, 255),
          alpha,
        );
      }
    }
  }
  final logo = image.copyCrop(
    transparent,
    x: 55,
    y: 128,
    width: 620,
    height: 106,
  );
  File(
    'assets/images/parklink_logo_transparent.png',
  ).writeAsBytesSync(image.encodePng(logo));
  final icon = image.Image(width: 1024, height: 1024, numChannels: 3);
  image.fill(icon, color: image.ColorRgb8(0, 218, 203));
  final car = image.copyResize(
    image.copyCrop(source, x: 60, y: 132, width: 176, height: 98),
    width: 710,
    interpolation: image.Interpolation.cubic,
  );
  for (var y = 0; y < car.height; y++) {
    for (var x = 0; x < car.width; x++) {
      final p = car.getPixel(x, y);
      final coverage = ((p.g - 8) / 210).clamp(0.0, 1.0);
      icon.setPixelRgb(
        x + 157,
        y + (1024 - car.height) ~/ 2,
        0,
        (218 * (1 - coverage)).round(),
        (203 * (1 - coverage)).round(),
      );
    }
  }
  File('assets/images/app_icon.png').writeAsBytesSync(image.encodePng(icon));
}
