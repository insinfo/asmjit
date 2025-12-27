/// AsmJit Unit Tests - AVX Instructions
///
/// Tests for AVX/AVX2 VEX-encoded instruction encoding.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('X86Encoder - AVX Move Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('vmovaps xmm encodes correctly', () {
      encoder.vmovapsXmmXmm(xmm0, xmm1);
      // VEX.128.0F 28 /r
      // C5 F8 28 C1
      expect(buffer.bytes, equals([0xC5, 0xF8, 0x28, 0xC1]));
    });

    test('vmovaps ymm encodes correctly', () {
      encoder.vmovapsYmmYmm(ymm0, ymm1);
      // VEX.256.0F 28 /r
      // C5 FC 28 C1 (L=1 for 256-bit)
      expect(buffer.bytes, equals([0xC5, 0xFC, 0x28, 0xC1]));
    });

    test('vmovups xmm encodes correctly', () {
      encoder.vmovupsXmmXmm(xmm0, xmm1);
      // C5 F8 10 C1
      expect(buffer.bytes, equals([0xC5, 0xF8, 0x10, 0xC1]));
    });
  });

  group('X86Encoder - AVX Logical', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('vxorps xmm encodes correctly (zero idiom)', () {
      encoder.vxorpsXmmXmmXmm(xmm0, xmm0, xmm0);
      // VEX.128.0F 57 /r
      // C5 F8 57 C0
      expect(buffer.bytes, equals([0xC5, 0xF8, 0x57, 0xC0]));
    });

    test('vxorps ymm encodes correctly', () {
      encoder.vxorpsYmmYmmYmm(ymm0, ymm0, ymm0);
      // VEX.256.0F 57 /r
      // C5 FC 57 C0
      expect(buffer.bytes, equals([0xC5, 0xFC, 0x57, 0xC0]));
    });

    test('vpxor xmm encodes correctly', () {
      encoder.vpxorXmmXmmXmm(xmm0, xmm0, xmm0);
      // VEX.128.66.0F EF /r
      // C5 F9 EF C0
      expect(buffer.bytes, equals([0xC5, 0xF9, 0xEF, 0xC0]));
    });
  });

  group('X86Encoder - AVX Arithmetic', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('vaddsd xmm encodes correctly', () {
      encoder.vaddsdXmmXmmXmm(xmm0, xmm1, xmm2);
      // VEX.LIG.F2.0F 58 /r
      // C5 F3 58 C2 (vvvv=~xmm1=0xE)
      expect(buffer.bytes, equals([0xC5, 0xF3, 0x58, 0xC2]));
    });

    test('vsubsd xmm encodes correctly', () {
      encoder.vsubsdXmmXmmXmm(xmm0, xmm1, xmm2);
      expect(buffer.bytes, equals([0xC5, 0xF3, 0x5C, 0xC2]));
    });

    test('vmulsd xmm encodes correctly', () {
      encoder.vmulsdXmmXmmXmm(xmm0, xmm1, xmm2);
      expect(buffer.bytes, equals([0xC5, 0xF3, 0x59, 0xC2]));
    });

    test('vdivsd xmm encodes correctly', () {
      encoder.vdivsdXmmXmmXmm(xmm0, xmm1, xmm2);
      expect(buffer.bytes, equals([0xC5, 0xF3, 0x5E, 0xC2]));
    });

    test('vaddps ymm encodes correctly', () {
      encoder.vaddpsYmmYmmYmm(ymm0, ymm1, ymm2);
      // VEX.256.0F 58 /r
      // C5 F4 58 C2
      expect(buffer.bytes, equals([0xC5, 0xF4, 0x58, 0xC2]));
    });
  });

  group('X86Encoder - AVX Special', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('vzeroupper encodes correctly', () {
      encoder.vzeroupper();
      // VEX.128.0F 77
      // C5 F8 77
      expect(buffer.bytes, equals([0xC5, 0xF8, 0x77]));
    });

    test('vzeroall encodes correctly', () {
      encoder.vzeroall();
      // VEX.256.0F 77
      // C5 FC 77
      expect(buffer.bytes, equals([0xC5, 0xFC, 0x77]));
    });
  });

  group('X86Encoder - AVX2 Integer', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('vpaddd xmm encodes correctly', () {
      encoder.vpadddXmmXmmXmm(xmm0, xmm1, xmm2);
      // VEX.128.66.0F FE /r
      // C5 F1 FE C2
      expect(buffer.bytes, equals([0xC5, 0xF1, 0xFE, 0xC2]));
    });

    test('vpaddq xmm encodes correctly', () {
      encoder.vpaddqXmmXmmXmm(xmm0, xmm1, xmm2);
      // VEX.128.66.0F D4 /r
      expect(buffer.bytes, equals([0xC5, 0xF1, 0xD4, 0xC2]));
    });

    test('vpmulld xmm encodes correctly', () {
      encoder.vpmulldXmmXmmXmm(xmm0, xmm1, xmm2);
      // VEX.128.66.0F38 40 /r
      // C4 E2 71 40 C2
      expect(buffer.bytes.length, equals(5)); // 3-byte VEX
      expect(buffer.bytes[0], equals(0xC4)); // 3-byte VEX prefix
    });
  });

  group('X86Encoder - FMA Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('vfmadd132sd encodes with 3-byte VEX', () {
      encoder.vfmadd132sdXmmXmmXmm(xmm0, xmm1, xmm2);
      // VEX.DDS.LIG.66.0F38.W1 99 /r
      expect(buffer.bytes.length, equals(5)); // 3-byte VEX + opcode + modrm
      expect(buffer.bytes[0], equals(0xC4)); // 3-byte VEX
      expect(buffer.bytes[3], equals(0x99)); // opcode
    });

    test('vfmadd231sd encodes with 3-byte VEX', () {
      encoder.vfmadd231sdXmmXmmXmm(xmm0, xmm1, xmm2);
      expect(buffer.bytes.length, equals(5));
      expect(buffer.bytes[0], equals(0xC4));
      expect(buffer.bytes[3], equals(0xB9)); // opcode
    });
  });
}
