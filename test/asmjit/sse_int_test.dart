/// AsmJit Unit Tests - SSE Integer Arithmetic
///
/// Tests for SSE2/SSE4.1 Packed Integer Arithmetic instructions.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }

  group('X86Encoder - SSE2 Integer Arithmetic', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    // PADD
    test('paddb xmm0, xmm1 encodes correctly', () {
      encoder.paddbXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xFC, 0xC1]));
    });

    test('paddw xmm0, xmm1 encodes correctly', () {
      encoder.paddwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xFD, 0xC1]));
    });

    test('paddd xmm0, xmm1 encodes correctly', () {
      encoder.padddXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xFE, 0xC1]));
    });

    test('paddq xmm0, xmm1 encodes correctly', () {
      encoder.paddqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xD4, 0xC1]));
    });

    // PSUB
    test('psubb xmm0, xmm1 encodes correctly', () {
      encoder.psubbXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xF8, 0xC1]));
    });

    test('psubw xmm0, xmm1 encodes correctly', () {
      encoder.psubwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xF9, 0xC1]));
    });

    test('psubd xmm0, xmm1 encodes correctly', () {
      encoder.psubdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xFA, 0xC1]));
    });

    test('psubq xmm0, xmm1 encodes correctly', () {
      encoder.psubqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xFB, 0xC1]));
    });

    // PMUL
    test('pmullw xmm0, xmm1 encodes correctly', () {
      encoder.pmullwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xD5, 0xC1]));
    });

    test('pmulld xmm0, xmm1 encodes correctly', () {
      encoder.pmulldXmmXmm(xmm0, xmm1);
      // 66 0F 38 40 /r
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x40, 0xC1]));
    });

    test('pmulhw xmm0, xmm1 encodes correctly', () {
      encoder.pmulhwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xE5, 0xC1]));
    });

    test('pmulhuw xmm0, xmm1 encodes correctly', () {
      encoder.pmulhuwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xE4, 0xC1]));
    });

    test('pmaddwd xmm0, xmm1 encodes correctly', () {
      encoder.pmaddwdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xF5, 0xC1]));
    });

    // Memory operands
    test('paddb xmm0, [rax] encodes correctly', () {
      final mem = ptr(rax);
      encoder.paddbXmmMem(xmm0, mem);
      // 66 0F FC /r (00)
      expect(buffer.bytes, equals([0x66, 0x0F, 0xFC, 0x00]));
    });
  });

  group('X86Encoder - SSE Integer Compare', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    // PCMPEQ
    test('pcmpeqb xmm0, xmm1 encodes correctly', () {
      encoder.pcmpeqbXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x74, 0xC1]));
    });

    test('pcmpeqw xmm0, xmm1 encodes correctly', () {
      encoder.pcmpeqwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x75, 0xC1]));
    });

    test('pcmpeqd xmm0, xmm1 encodes correctly', () {
      encoder.pcmpeqdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x76, 0xC1]));
    });

    test('pcmpeqq xmm0, xmm1 encodes correctly', () {
      encoder.pcmpeqqXmmXmm(xmm0, xmm1);
      // 66 0F 38 29 C1
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x29, 0xC1]));
    });

    // PCMPGT
    test('pcmpgtb xmm0, xmm1 encodes correctly', () {
      encoder.pcmpgtbXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x64, 0xC1]));
    });

    test('pcmpgtw xmm0, xmm1 encodes correctly', () {
      encoder.pcmpgtwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x65, 0xC1]));
    });

    test('pcmpgtd xmm0, xmm1 encodes correctly', () {
      encoder.pcmpgtdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x66, 0xC1]));
    });

    test('pcmpgtq xmm0, xmm1 encodes correctly', () {
      // 66 0F 38 37 C1
      encoder.pcmpgtqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x37, 0xC1]));
    });
  });

  group('X86Encoder - SSE Min/Max', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    // PMIN/PMAX unsigned
    test('pminub xmm0, xmm1 encodes correctly', () {
      encoder.pminubXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xDA, 0xC1]));
    });

    test('pmaxub xmm0, xmm1 encodes correctly', () {
      encoder.pmaxubXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xDE, 0xC1]));
    });

    test('pminud xmm0, xmm1 encodes correctly', () {
      encoder.pminudXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x3B, 0xC1]));
    });

    test('pmaxud xmm0, xmm1 encodes correctly', () {
      encoder.pmaxudXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x3F, 0xC1]));
    });

    // PMIN/PMAX signed
    test('pminsw xmm0, xmm1 encodes correctly', () {
      encoder.pminswXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xEA, 0xC1]));
    });

    test('pmaxsw xmm0, xmm1 encodes correctly', () {
      encoder.pmaxswXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xEE, 0xC1]));
    });

    test('pminsd xmm0, xmm1 encodes correctly', () {
      encoder.pminsdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x39, 0xC1]));
    });

    test('pmaxsd xmm0, xmm1 encodes correctly', () {
      encoder.pmaxsdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x3D, 0xC1]));
    });
  });

  group('X86Encoder - SSE Shifts', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    // Logical Left
    test('psllw xmm0, xmm1 encodes correctly', () {
      encoder.psllwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xF1, 0xC1]));
    });

    test('psllw xmm0, imm8 encodes correctly', () {
      encoder.psllwXmmImm8(xmm0, 16);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x71, 0xF0, 0x10]));
    });

    test('pslld xmm0, xmm1 encodes correctly', () {
      encoder.pslldXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xF2, 0xC1]));
    });

    test('psllq xmm0, xmm1 encodes correctly', () {
      encoder.psllqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xF3, 0xC1]));
    });

    test('psllq xmm0, imm8 encodes correctly', () {
      encoder.psllqXmmImm8(xmm0, 16);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x73, 0xF0, 0x10]));
    });

    // Logical Right
    test('psrlw xmm0, xmm1 encodes correctly', () {
      encoder.psrlwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xD1, 0xC1]));
    });

    test('psrlw xmm0, imm8 encodes correctly', () {
      encoder.psrlwXmmImm8(xmm0, 16);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x71, 0xD0, 0x10]));
    });

    test('psrld xmm0, xmm1 encodes correctly', () {
      encoder.psrldXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xD2, 0xC1]));
    });

    test('psrlq xmm0, xmm1 encodes correctly', () {
      encoder.psrlqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xD3, 0xC1]));
    });

    // Arithmetic Right
    test('psraw xmm0, xmm1 encodes correctly', () {
      encoder.psrawXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xE1, 0xC1]));
    });

    test('psraw xmm0, imm8 encodes correctly', () {
      encoder.psrawXmmImm8(xmm0, 16);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x71, 0xE0, 0x10]));
    });

    test('psrad xmm0, xmm1 encodes correctly', () {
      encoder.psradXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xE2, 0xC1]));
    });

    test('psrad xmm0, imm8 encodes correctly', () {
      encoder.psradXmmImm8(xmm0, 16);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x72, 0xE0, 0x10]));
    });

    // Byte Shifts
    test('pslldq xmm0, imm8 encodes correctly', () {
      encoder.pslldqXmmImm8(xmm0, 16);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x73, 0xF8, 0x10]));
    });

    test('psrldq xmm0, imm8 encodes correctly', () {
      encoder.psrldqXmmImm8(xmm0, 16);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x73, 0xD8, 0x10]));
    });
  });

  group('X86Encoder - SSE Logic', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('pand xmm0, xmm1 encodes correctly', () {
      encoder.pandXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xDB, 0xC1]));
    });

    test('pandn xmm0, xmm1 encodes correctly', () {
      encoder.pandnXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0xDF, 0xC1]));
    });
  });

  group('X86Encoder - SSE Pack/Unpack', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('packsswb xmm0, xmm1 encodes correctly', () {
      encoder.packsswbXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x63, 0xC1]));
    });

    test('packuswb xmm0, xmm1 encodes correctly', () {
      encoder.packuswbXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x67, 0xC1]));
    });

    test('punpcklbw xmm0, xmm1 encodes correctly', () {
      encoder.punpcklbwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x60, 0xC1]));
    });

    test('punpckldq xmm0, xmm1 encodes correctly', () {
      encoder.punpckldqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x62, 0xC1]));
    });

    test('punpcklqdq xmm0, xmm1 encodes correctly', () {
      encoder.punpcklqdqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x6C, 0xC1]));
    });
  });

  group('X86Encoder - SSE Shuffle', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('pshufd xmm0, xmm1, imm8 encodes correctly', () {
      encoder.pshufdXmmXmmImm8(xmm0, xmm1, 0x1B);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x70, 0xC1, 0x1B]));
    });

    test('pshufd xmm0, [rax], imm8 encodes correctly', () {
      final mem = ptr(rax);
      encoder.pshufdXmmMemImm8(xmm0, mem, 0x1B);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x70, 0x00, 0x1B]));
    });

    test('pshufb xmm0, xmm1 encodes correctly', () {
      encoder.pshufbXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x00, 0xC1]));
    });

    test('pshuflw xmm0, xmm1, imm8 encodes correctly', () {
      encoder.pshuflwXmmXmmImm8(xmm0, xmm1, 0x1B);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x70, 0xC1, 0x1B]));
    });

    test('pshufhw xmm0, xmm1, imm8 encodes correctly', () {
      encoder.pshufhwXmmXmmImm8(xmm0, xmm1, 0x1B);
      expect(buffer.bytes, equals([0xF3, 0x0F, 0x70, 0xC1, 0x1B]));
    });

    test('palignr xmm0, xmm1, imm8 encodes correctly', () {
      encoder.palignrXmmXmmImm8(xmm0, xmm1, 4);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x0F, 0xC1, 0x04]));
    });
  });
}
