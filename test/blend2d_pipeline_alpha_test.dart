import 'package:test/test.dart';
import 'package:asmjit/src/blend2d/core/image.dart';
import 'package:asmjit/src/blend2d/core/context.dart';
import 'package:asmjit/src/blend2d/core/format.dart';
import 'package:asmjit/src/blend2d/core/rgba.dart';
import 'package:asmjit/src/blend2d/geometry/types.dart';
import 'package:asmjit/src/asmjit/runtime/cpuinfo.dart';

void main() {
  CpuInfo.host();

  group('JIT Pipeline Global Alpha', () {
    late BLImage dst;
    late BLContext ctx;

    setUp(() {
      dst = BLImage.create(10, 10, BLFormat.prgb32);
      ctx = BLContext(dst);
    });

    tearDown(() {
      ctx.dispose();
      dst.dispose();
    });

    test('Alpha 0.0 (No Op)', () {
      dst.fillAll(BLRgba32(0, 0, 0, 0)); // Clear
      ctx.globalAlpha = 0.0;
      ctx.fillStyle = BLRgba32(255, 0, 0, 255);
      ctx.fillRect(BLRectI(0, 0, 10, 10));

      expect(dst.getPixel(0, 0)!.value, 0, reason: 'Should not draw anything');
    });

    test('Alpha 1.0 (Full Opacity)', () {
      dst.fillAll(BLRgba32(0, 0, 0, 0));
      ctx.globalAlpha = 1.0;
      ctx.fillStyle = BLRgba32(255, 0, 0, 255);
      ctx.fillRect(BLRectI(0, 0, 10, 10));

      final p = dst.getPixel(0, 0)!;
      expect(p.r, 255);
      expect(p.a, 255);
    });

    test('Alpha 0.5 over White (Blend)', () {
      // Dst: White opaque
      dst.fillAll(BLRgba32(255, 255, 255, 255));

      // Src: Red, Global Alpha 0.5 -> Effective Src: (128, 0, 0, 128)
      ctx.globalAlpha = 0.5;
      ctx.fillStyle = BLRgba32(255, 0, 0, 255);
      ctx.fillRect(BLRectI(0, 0, 10, 10));

      // Result = Src + Dst * (1 - Sa)
      // Approx:
      // R = 127 + 255 * 0.5 = 254
      // G = 0 + 255 * 0.5 = 127
      // B = 0 + 255 * 0.5 = 127
      // A = 127 + 255 * 0.5 = 254

      final p = dst.getPixel(0, 0)!;
      // Allow +/- 2 margin for integer rounding
      expect(p.r, closeTo(254, 2));
      expect(p.g, closeTo(127, 2));
      expect(p.b, closeTo(127, 2));
      expect(p.a, closeTo(254, 2));
    });
  });
}
