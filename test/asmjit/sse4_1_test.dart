/// AsmJit Unit Tests - SSE4.1 Exntensions
///
/// Tests for Extend, Insert/Extract, and Blend instructions.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }

  group('x86 emit - SSE4.1 Extend', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('pmovzxbw xmm0, xmm1 encodes correctly', () {
      encoder.emit(X86InstId.kPmovzxbw, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x30, 0xC1]));
    });

    test('pmovzxbd xmm0, xmm1 encodes correctly', () {
      encoder.emit(X86InstId.kPmovzxbd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x31, 0xC1]));
    });

    test('pmovzxbq xmm0, xmm1 encodes correctly', () {
      encoder.emit(X86InstId.kPmovzxbq, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x32, 0xC1]));
    });

    test('pmovzxwd xmm0, xmm1 encodes correctly', () {
      encoder.emit(X86InstId.kPmovzxwd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x33, 0xC1]));
    });

    test('pmovzxwq xmm0, xmm1 encodes correctly', () {
      encoder.emit(X86InstId.kPmovzxwq, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x34, 0xC1]));
    });

    test('pmovzxdq xmm0, xmm1 encodes correctly', () {
      encoder.emit(X86InstId.kPmovzxdq, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x35, 0xC1]));
    });

    test('pmovsxbw xmm0, xmm1 encodes correctly', () {
      encoder.emit(X86InstId.kPmovsxbw, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x20, 0xC1]));
    });
  });

  group('x86 emit - SSE4.1 Insert/Extract', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('pinsrb xmm0, eax, imm8 encodes correctly', () {
      encoder.emit(X86InstId.kPinsrb, [xmm0, eax, 1]);
      // 66 0F 3A 20 C0 01
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x20, 0xC0, 0x01]));
    });

    test('pinsrd xmm0, eax, imm8 encodes correctly', () {
      encoder.emit(X86InstId.kPinsrd, [xmm0, eax, 1]);
      // 66 0F 3A 22 C0 01
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x22, 0xC0, 0x01]));
    });

    test('pinsrq xmm0, rax, imm8 encodes correctly', () {
      encoder.emit(X86InstId.kPinsrq, [xmm0, rax, 1]);
      // 66 48 0F 3A 22 C0 01
      expect(buffer.bytes, equals([0x66, 0x48, 0x0F, 0x3A, 0x22, 0xC0, 0x01]));
    });

    test('pextrb eax, xmm0, imm8 encodes correctly', () {
      encoder.emit(X86InstId.kPextrb, [eax, xmm0, 1]);
      // 66 0F 3A 14 C0 01
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x14, 0xC0, 0x01]));
    });

    test('pextrd eax, xmm0, imm8 encodes correctly', () {
      encoder.emit(X86InstId.kPextrd, [eax, xmm0, 1]);
      // 66 0F 3A 16 C0 01
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x16, 0xC0, 0x01]));
    });

    test('pextrq rax, xmm0, imm8 encodes correctly', () {
      encoder.emit(X86InstId.kPextrq, [rax, xmm0, 1]);
      // 66 48 0F 3A 16 C0 01
      expect(buffer.bytes, equals([0x66, 0x48, 0x0F, 0x3A, 0x16, 0xC0, 0x01]));
    });
  });

  group('x86 emit - SSE4.1 Blend', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('pblendw xmm0, xmm1, imm8 encodes correctly', () {
      encoder.emit(X86InstId.kPblendw, [xmm0, xmm1, 0xAA]);
      // 66 0F 3A 0E C1 AA
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x0E, 0xC1, 0xAA]));
    });

    test('pblendvb xmm0, xmm1 encodes correctly', () {
      encoder.emit(X86InstId.kPblendvb, [xmm0, xmm1]);
      // 66 0F 38 10 C1
      expect(buffer.bytes, equals([0x66, 0x0F, 0x38, 0x10, 0xC1]));
    });

    test('blendps xmm0, xmm1, imm8 encodes correctly', () {
      encoder.emit(X86InstId.kBlendps, [xmm0, xmm1, 0x0F]);
      // 66 0F 3A 0C C1 0F
      expect(buffer.bytes, equals([0x66, 0x0F, 0x3A, 0x0C, 0xC1, 0x0F]));
    });
  });
}
