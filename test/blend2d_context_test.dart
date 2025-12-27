import 'package:test/test.dart';
import 'package:asmjit/src/blend2d/core/image.dart';
import 'package:asmjit/src/blend2d/core/context.dart';
import 'package:asmjit/src/blend2d/core/format.dart';
import 'package:asmjit/src/blend2d/core/rgba.dart';
import 'package:asmjit/src/blend2d/geometry/types.dart';
import 'package:asmjit/src/asmjit/runtime/cpuinfo.dart';

void main() {
  // Ensure CPU info initialized for JIT
  CpuInfo.host();

  group('BLContext', () {
    test('fillRect solid', () {
      final img = BLImage.create(20, 20, BLFormat.prgb32);
      final ctx = BLContext(img);

      ctx.fillStyle = BLRgba32(255, 0, 0, 255); // Red
      ctx.fillRect(BLRectI(0, 0, 10, 10));

      final p1 = img.getPixel(0, 0)!;
      expect(p1.r, 255, reason: 'Pixel at 0,0 should be Red');
      expect(p1.a, 255);

      final p2 = img.getPixel(15, 15)!;
      expect(p2.value, 0, reason: 'Pixel at 15,15 should be zero');

      ctx.dispose();
      img.dispose();
    });

    test('blitImage', () {
      final dst = BLImage.create(20, 20, BLFormat.prgb32);
      final src = BLImage.create(10, 10, BLFormat.prgb32);
      src.fillAll(BLRgba32(0, 255, 0, 255)); // Green

      final ctx = BLContext(dst);
      ctx.blitImage(5, 5, src);

      final p = dst.getPixel(6, 6)!;
      expect(p.g, 255, reason: 'Pixel at 6,6 should be Green');
      expect(p.a, 255);

      expect(dst.getPixel(0, 0)!.value, 0);

      ctx.dispose();
      src.dispose();
      dst.dispose();
    });

    test('globalAlpha fill', () {
      final img = BLImage.create(10, 10, BLFormat.prgb32);
      final ctx = BLContext(img);

      // 50% opacity
      ctx.globalAlpha = 0.5;
      ctx.fillStyle = BLRgba32(255, 255, 255, 255); // White
      ctx.fillRect(BLRectI(0, 0, 10, 10));

      final p = img.getPixel(5, 5)!;
      // White * 0.5 -> 128
      expect(p.r, closeTo(128, 5));
      expect(p.a, closeTo(128, 5));

      ctx.dispose();
      img.dispose();
    });
  });
}
