/// AsmJit Unit Tests - SSE/SIMD Instructions
///
/// Tests for SSE instruction encoding.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('X86 SIMD Registers', () {
    test('XMM registers have correct properties', () {
      expect(xmm0.id, equals(0));
      expect(xmm0.size, equals(16));
      expect(xmm0.isExtended, isFalse);

      expect(xmm8.id, equals(8));
      expect(xmm8.isExtended, isTrue);
      expect(xmm8.encoding, equals(0));

      expect(xmm15.id, equals(15));
      expect(xmm15.encoding, equals(7));
    });

    test('YMM registers have correct properties', () {
      expect(ymm0.id, equals(0));
      expect(ymm0.size, equals(32));

      expect(ymm8.isExtended, isTrue);
    });

    test('ZMM registers have correct properties', () {
      expect(zmm0.id, equals(0));
      expect(zmm0.size, equals(64));

      expect(zmm31.id, equals(31));
    });

    test('register conversion works', () {
      expect(xmm0.ymm, equals(ymm0));
      expect(ymm0.xmm, equals(xmm0));
      expect(xmm5.zmm, equals(zmm5));
    });
  });

  group('X86Encoder - SSE Move Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('movaps xmm, xmm encodes correctly', () {
      encoder.movapsXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x0F, 0x28, 0xC1]));
    });

    test('movaps xmm8, xmm0 encodes correctly (with REX)', () {
      encoder.movapsXmmXmm(xmm8, xmm0);
      // REX.R for xmm8
      expect(buffer.bytes, equals([0x44, 0x0F, 0x28, 0xC0]));
    });

    test('movups xmm, xmm encodes correctly', () {
      encoder.movupsXmmXmm(xmm2, xmm3);
      expect(buffer.bytes, equals([0x0F, 0x10, 0xD3]));
    });

    test('movsd xmm, xmm encodes correctly', () {
      encoder.movsdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x10, 0xC1]));
    });

    test('movss xmm, xmm encodes correctly', () {
      encoder.movssXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF3, 0x0F, 0x10, 0xC1]));
    });
  });

  group('X86Encoder - SSE Arithmetic Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('addsd xmm, xmm encodes correctly', () {
      encoder.addsdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x58, 0xC1]));
    });

    test('subsd xmm, xmm encodes correctly', () {
      encoder.subsdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x5C, 0xC1]));
    });

    test('mulsd xmm, xmm encodes correctly', () {
      encoder.mulsdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x59, 0xC1]));
    });

    test('divsd xmm, xmm encodes correctly', () {
      encoder.divsdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x5E, 0xC1]));
    });

    test('sqrtsd xmm, xmm encodes correctly', () {
      encoder.sqrtsdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x51, 0xC1]));
    });

    test('addss xmm, xmm encodes correctly', () {
      encoder.addssXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF3, 0x0F, 0x58, 0xC1]));
    });
  });

  group('X86Encoder - SSE Logical Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('pxor xmm, xmm encodes correctly', () {
      encoder.pxorXmmXmm(xmm0, xmm0);
      // 66 0F EF C0 (pxor xmm0, xmm0)
      expect(buffer.bytes, equals([0x66, 0x0F, 0xEF, 0xC0]));
    });

    test('xorps xmm, xmm encodes correctly', () {
      encoder.xorpsXmmXmm(xmm0, xmm0);
      expect(buffer.bytes, equals([0x0F, 0x57, 0xC0]));
    });

    test('xorpd xmm, xmm encodes correctly', () {
      encoder.xorpdXmmXmm(xmm0, xmm0);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x57, 0xC0]));
    });
  });

  group('X86Encoder - SSE Conversion Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('cvtsi2sd xmm, r64 encodes correctly', () {
      encoder.cvtsi2sdXmmR64(xmm0, rax);
      // F2 REX.W 0F 2A C0
      expect(buffer.bytes, equals([0xF2, 0x48, 0x0F, 0x2A, 0xC0]));
    });

    test('cvttsd2si r64, xmm encodes correctly', () {
      encoder.cvttsd2siR64Xmm(rax, xmm0);
      // F2 REX.W 0F 2C C0
      expect(buffer.bytes, equals([0xF2, 0x48, 0x0F, 0x2C, 0xC0]));
    });

    test('cvtsd2ss xmm, xmm encodes correctly', () {
      encoder.cvtsd2ssXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x5A, 0xC1]));
    });

    test('cvtss2sd xmm, xmm encodes correctly', () {
      encoder.cvtss2sdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0xF3, 0x0F, 0x5A, 0xC1]));
    });
  });

  group('X86Encoder - SSE Comparison Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('comisd xmm, xmm encodes correctly', () {
      encoder.comisdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x2F, 0xC1]));
    });

    test('comiss xmm, xmm encodes correctly', () {
      encoder.comissXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x0F, 0x2F, 0xC1]));
    });

    test('ucomisd xmm, xmm encodes correctly', () {
      encoder.ucomisdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x2E, 0xC1]));
    });
  });

  group('X86Encoder - SSE GP<->XMM Transfer', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('movq xmm, r64 encodes correctly', () {
      encoder.movqXmmR64(xmm0, rax);
      // 66 REX.W 0F 6E C0
      expect(buffer.bytes, equals([0x66, 0x48, 0x0F, 0x6E, 0xC0]));
    });

    test('movq r64, xmm encodes correctly', () {
      encoder.movqR64Xmm(rax, xmm0);
      // 66 REX.W 0F 7E C0
      expect(buffer.bytes, equals([0x66, 0x48, 0x0F, 0x7E, 0xC0]));
    });

    test('movd xmm, r32 encodes correctly', () {
      encoder.movdXmmR32(xmm0, eax);
      // 66 0F 6E C0
      expect(buffer.bytes, equals([0x66, 0x0F, 0x6E, 0xC0]));
    });
  });
}
