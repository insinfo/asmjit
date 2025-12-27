import 'package:test/test.dart';
import 'package:asmjit/blend2d.dart';

void main() {
  group('BLRgba', () {
    test('constructs with components', () {
      const color = BLRgba(1.0, 0.5, 0.25, 0.75);
      expect(color.r, 1.0);
      expect(color.g, 0.5);
      expect(color.b, 0.25);
      expect(color.a, 0.75);
    });

    test('converts to BLRgba32', () {
      const color = BLRgba(1.0, 0.5, 0.0, 1.0);
      final rgba32 = color.toRgba32();
      expect(rgba32.r, 255);
      expect(rgba32.g, closeTo(127, 1)); // 0.5 * 255
      expect(rgba32.b, 0);
      expect(rgba32.a, 255);
    });

    test('premultiplies alpha', () {
      const color = BLRgba(1.0, 1.0, 1.0, 0.5);
      final premul = color.premultiplied();
      expect(premul.r, 0.5);
      expect(premul.g, 0.5);
      expect(premul.b, 0.5);
      expect(premul.a, 0.5);
    });
  });

  group('BLRgba32', () {
    test('constructs from components', () {
      final color = BLRgba32(255, 128, 64, 200);
      expect(color.r, 255);
      expect(color.g, 128);
      expect(color.b, 64);
      expect(color.a, 200);
    });

    test('constructs from ARGB value', () {
      final color = BLRgba32.fromValue(0xFFFF8040); // Opaque orange
      expect(color.r, 255);
      expect(color.g, 128);
      expect(color.b, 64);
      expect(color.a, 255);
    });

    test('premultiplies alpha', () {
      final color = BLRgba32(255, 255, 255, 128); // 50% white
      final premul = color.premultiplied();
      expect(premul.a, 128);
      expect(premul.r, closeTo(128, 1));
      expect(premul.g, closeTo(128, 1));
      expect(premul.b, closeTo(128, 1));
    });

    test('named colors work', () {
      expect(BLColors.red.r, 255);
      expect(BLColors.red.g, 0);
      expect(BLColors.red.b, 0);
      expect(BLColors.red.a, 255);

      expect(BLColors.transparent.a, 0);
    });
  });

  group('BLFormat', () {
    test('returns correct depth', () {
      expect(BLFormat.prgb32.depth, 4);
      expect(BLFormat.xrgb32.depth, 4);
      expect(BLFormat.a8.depth, 1);
      expect(BLFormat.none.depth, 0);
    });

    test('reports alpha correctly', () {
      expect(BLFormat.prgb32.hasAlpha, true);
      expect(BLFormat.xrgb32.hasAlpha, false);
      expect(BLFormat.a8.hasAlpha, true);
    });

    test('reports premultiplication correctly', () {
      expect(BLFormat.prgb32.isPremultiplied, true);
      expect(BLFormat.xrgb32.isPremultiplied, false);
      expect(BLFormat.a8.isPremultiplied, false);
    });
  });

  group('BLImage', () {
    test('creates empty image', () {
      final img = BLImage.empty();
      expect(img.isEmpty, true);
      expect(img.width, 0);
      expect(img.height, 0);
    });

    test('creates image with dimensions', () {
      final img = BLImage.create(100, 100, BLFormat.prgb32);
      expect(img.isEmpty, false);
      expect(img.width, 100);
      expect(img.height, 100);
      expect(img.format, BLFormat.prgb32);
      expect(img.stride, 400); // 100 * 4 bytes
      img.dispose();
    });

    test('clears image to zero', () {
      final img = BLImage.create(10, 10, BLFormat.prgb32);
      img.clear();
      final pixel = img.getPixel(5, 5);
      expect(pixel?.value, 0x00000000);
      img.dispose();
    });

    test('fills image with color', () {
      final img = BLImage.create(10, 10, BLFormat.prgb32);
      img.fillAll(BLColors.red);

      final pixel = img.getPixel(5, 5);
      expect(pixel?.r, 255);
      expect(pixel?.g, 0);
      expect(pixel?.b, 0);
      expect(pixel?.a, 255);
      img.dispose();
    });

    test('sets and gets individual pixels', () {
      final img = BLImage.create(10, 10, BLFormat.prgb32);

      final blue = BLRgba32(0, 0, 255, 255);
      img.setPixel(3, 3, blue);

      final pixel = img.getPixel(3, 3);
      expect(pixel?.b, 255);
      expect(pixel?.r, 0);
      expect(pixel?.g, 0);
      img.dispose();
    });

    test('handles A8 format', () {
      final img = BLImage.create(10, 10, BLFormat.a8);
      expect(img.stride, 10); // 10 * 1 byte

      img.setPixel(2, 2, BLRgba32(0, 0, 0, 128));
      final pixel = img.getPixel(2, 2);
      expect(pixel?.a, 128);
      img.dispose();
    });

    test('disposes correctly', () {
      final img = BLImage.create(100, 100, BLFormat.prgb32);
      expect(img.data, isNotNull);

      img.dispose();
      expect(img.data, isNull);
      expect(img.isEmpty, true);
    });
  });
}
