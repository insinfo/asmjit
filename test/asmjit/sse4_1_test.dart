/// AsmJit Unit Tests - SSE4.1 Exntensions
///
/// Tests for Extend, Insert/Extract, and Blend instructions.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }

  group('X86Encoder - SSE4.1 Extend', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('pmovzxbw xmm0, xmm1 encodes correctly', () {
      encoder.pmovzxbwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x30, 0xC1]));
    });

    test('pmovzxbd xmm0, xmm1 encodes correctly', () {
      encoder.pmovzxbdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x31, 0xC1]));
    });

    test('pmovzxbq xmm0, xmm1 encodes correctly', () {
      encoder.pmovzxbqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x32, 0xC1]));
    });

    test('pmovzxwd xmm0, xmm1 encodes correctly', () {
      encoder.pmovzxwdXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x33, 0xC1]));
    });

    test('pmovzxwq xmm0, xmm1 encodes correctly', () {
      encoder.pmovzxwqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x34, 0xC1]));
    });

    test('pmovzxdq xmm0, xmm1 encodes correctly', () {
      encoder.pmovzxdqXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x35, 0xC1]));
    });

    test('pmovsxbw xmm0, xmm1 encodes correctly', () {
      encoder.pmovsxbwXmmXmm(xmm0, xmm1);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x20, 0xC1]));
    });
  });

  group('X86Encoder - SSE4.1 Insert/Extract', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('pinsrb xmm0, eax, imm8 encodes correctly', () {
      encoder.pinsrbXmmRegImm8(xmm0, eax, 1);
      // 66 0F 3A 20 C0 01
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x20, 0xC0, 0x01]));
    });

    test('pinsrd xmm0, eax, imm8 encodes correctly', () {
      encoder.pinsrdXmmRegImm8(xmm0, eax, 1);
      // 66 0F 3A 22 C0 01
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x22, 0xC0, 0x01]));
    });

    test('pinsrq xmm0, rax, imm8 encodes correctly', () {
      encoder.pinsrqXmmRegImm8(xmm0, rax, 1);
      // 66 48 0F 3A 22 C0 01
      expect(buffer.bytes, equals([0x66, 0x48, 0x0F, 0x3A, 0x22, 0xC0, 0x01]));
    });

    test('pextrb eax, xmm0, imm8 encodes correctly', () {
      encoder.pextrbRegXmmImm8(eax, xmm0, 1);
      // 66 0F 3A 14 C0 01
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x14, 0xC0, 0x01]));
    });

    test('pextrd eax, xmm0, imm8 encodes correctly', () {
      encoder.pextrdRegXmmImm8(eax, xmm0, 1);
      // 66 0F 3A 16 C0 01
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x16, 0xC0, 0x01]));
    });

    test('pextrq rax, xmm0, imm8 encodes correctly', () {
      encoder.pextrqRegXmmImm8(rax, xmm0, 1);
      // 66 48 0F 3A 16 C0 01
      expect(buffer.bytes, equals([0x66, 0x48, 0x0F, 0x3A, 0x16, 0xC0, 0x01]));
    });
  });

  group('X86Encoder - SSE4.1 Blend', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('pblendw xmm0, xmm1, imm8 encodes correctly', () {
      encoder.pblendwXmmXmmImm8(xmm0, xmm1, 0xAA);
      // 66 0F 3A 0E C1 AA
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x0E, 0xC1, 0xAA]));
    });

    test('pblendvb xmm0, xmm1 encodes correctly', () {
      encoder.pblendvbXmmXmm(xmm0, xmm1);
      // 66 0F 38 10 C1
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x10, 0xC1]));
    });

    test('blendps xmm0, xmm1, imm8 encodes correctly', () {
      encoder.blendpsXmmXmmImm8(xmm0, xmm1, 0x0F);
      // 66 0F 3A 0C C1 0F
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x0C, 0xC1, 0x0F]));
    });
  });
}
