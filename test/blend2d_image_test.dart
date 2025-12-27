import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:asmjit/src/blend2d/core/image.dart';
import 'package:asmjit/src/blend2d/core/format.dart';
import 'package:asmjit/src/blend2d/core/rgba.dart';

void main() {
  group('BLImage', () {
    test('create empty', () {
      final img = BLImage.empty();
      expect(img.width, 0);
      expect(img.height, 0);
      expect(img.format, BLFormat.none);
      expect(img.data, isNull);
      expect(img.pixels, isNull);
    });

    test('create PRGB32', () {
      final img = BLImage.create(100, 50, BLFormat.prgb32);
      expect(img.width, 100);
      expect(img.height, 50);
      expect(img.format, BLFormat.prgb32);
      expect(img.stride, 100 * 4);
      expect(img.data, isNotNull);
      expect(img.pixels!.length, 100 * 50 * 4);

      img.dispose();
      expect(img.data, isNull);
    });

    test('create fromBytes', () {
      final bytes = Uint8List(10 * 10 * 4);
      bytes.fillRange(0, bytes.length, 255);

      final img = BLImage.fromBytes(bytes, 10, 10, BLFormat.prgb32);
      expect(img.width, 10);
      expect(img.height, 10);
      expect(img.getPixel(0, 0)!.value, 0xFFFFFFFF);

      img.dispose();
    });

    test('get/set pixel PRGB32', () {
      final img = BLImage.create(10, 10, BLFormat.prgb32);
      final red = BLRgba32(255, 0, 0, 255);

      img.setPixel(0, 0, red);
      final p = img.getPixel(0, 0)!;
      expect(p.r, 255);
      expect(p.g, 0);
      expect(p.b, 0);
      expect(p.a, 255);

      // Premultiplied alpha check
      final semiRed = BLRgba32(255, 0, 0, 128);
      img.setPixel(1, 1, semiRed);
      final p2 = img.getPixel(1, 1)!;
      // Stored premultiplied: R=128, G=0, B=0, A=128
      // But getPixel returns raw value from memory which is premultiplied
      // The getter uses BLRgba32.fromValue(ptr.value)
      // So checks should be against premultiplied values
      expect(p2.r, 128);
      expect(p2.a, 128);

      img.dispose();
    });

    test('fillAll', () {
      final img = BLImage.create(10, 10, BLFormat.prgb32);
      final blue = BLRgba32(0, 0, 255, 255);
      img.fillAll(blue);

      expect(img.getPixel(0, 0)!.b, 255);
      expect(img.getPixel(9, 9)!.b, 255);

      img.dispose();
    });
  });
}
