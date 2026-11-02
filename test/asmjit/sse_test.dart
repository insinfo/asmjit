/// AsmJit Unit Tests - SSE/SIMD Instructions
///
/// Tests for SSE instruction encoding.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
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

  group('x86 emit - SSE Move Instructions', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('movaps xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kMovaps, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x0F, 0x28, 0xC1]));
    });

    test('movaps xmm8, xmm0 encodes correctly (with REX)', () {
      encoder.emit(X86InstId.kMovaps, [xmm8, xmm0]);
      // REX.R for xmm8
      expect(buffer.bytes, equals([0x44, 0x0F, 0x28, 0xC0]));
    });

    test('movups xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kMovups, [xmm2, xmm3]);
      expect(buffer.bytes, equals([0x0F, 0x10, 0xD3]));
    });

    test('movsd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kMovsd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x10, 0xC1]));
    });

    test('movss xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kMovss, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF3, 0x0F, 0x10, 0xC1]));
    });
  });

  group('x86 emit - SSE Arithmetic Instructions', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('addsd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kAddsd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x58, 0xC1]));
    });

    test('subsd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kSubsd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x5C, 0xC1]));
    });

    test('mulsd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kMulsd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x59, 0xC1]));
    });

    test('divsd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kDivsd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x5E, 0xC1]));
    });

    test('sqrtsd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kSqrtsd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x51, 0xC1]));
    });

    test('addss xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kAddss, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF3, 0x0F, 0x58, 0xC1]));
    });
  });

  group('x86 emit - SSE Logical Instructions', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('pxor xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kPxor, [xmm0, xmm0]);
      // 66 0F EF C0 (pxor xmm0, xmm0)
      expect(buffer.bytes, equals([0x66, 0x0F, 0xEF, 0xC0]));
    });

    test('xorps xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kXorps, [xmm0, xmm0]);
      expect(buffer.bytes, equals([0x0F, 0x57, 0xC0]));
    });

    test('xorpd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kXorpd, [xmm0, xmm0]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x57, 0xC0]));
    });
  });

  group('x86 emit - SSE Conversion Instructions', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('cvtsi2sd xmm, r64 encodes correctly', () {
      encoder.emit(X86InstId.kCvtsi2sd, [xmm0, rax]);
      // F2 REX.W 0F 2A C0
      expect(buffer.bytes, equals([0xF2, 0x48, 0x0F, 0x2A, 0xC0]));
    });

    test('cvttsd2si r64, xmm encodes correctly', () {
      encoder.emit(X86InstId.kCvttsd2si, [rax, xmm0]);
      // F2 REX.W 0F 2C C0
      expect(buffer.bytes, equals([0xF2, 0x48, 0x0F, 0x2C, 0xC0]));
    });

    test('cvtsd2ss xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kCvtsd2ss, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF2, 0x0F, 0x5A, 0xC1]));
    });

    test('cvtss2sd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kCvtss2sd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0xF3, 0x0F, 0x5A, 0xC1]));
    });
  });

  group('x86 emit - SSE Comparison Instructions', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('comisd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kComisd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x2F, 0xC1]));
    });

    test('comiss xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kComiss, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x0F, 0x2F, 0xC1]));
    });

    test('ucomisd xmm, xmm encodes correctly', () {
      encoder.emit(X86InstId.kUcomisd, [xmm0, xmm1]);
      expect(buffer.bytes, equals([0x66, 0x0F, 0x2E, 0xC1]));
    });
  });

  group('x86 emit - SSE GP<->XMM Transfer', () {
    late CodeBuffer buffer;
    late X86Assembler encoder;

    setUp(() {
      final code = CodeHolder(env: Environment.x64SysV());
      buffer = code.text.buffer;
      encoder = X86Assembler(code);
    });

    test('movq xmm, r64 encodes correctly', () {
      encoder.emit(X86InstId.kMovq, [xmm0, rax]);
      // 66 REX.W 0F 6E C0
      expect(buffer.bytes, equals([0x66, 0x48, 0x0F, 0x6E, 0xC0]));
    });

    test('movq r64, xmm encodes correctly', () {
      encoder.emit(X86InstId.kMovq, [rax, xmm0]);
      // 66 REX.W 0F 7E C0
      expect(buffer.bytes, equals([0x66, 0x48, 0x0F, 0x7E, 0xC0]));
    });

    test('movd xmm, r32 encodes correctly', () {
      encoder.emit(X86InstId.kMovd, [xmm0, eax]);
      // 66 0F 6E C0
      expect(buffer.bytes, equals([0x66, 0x0F, 0x6E, 0xC0]));
    });
  });
}
