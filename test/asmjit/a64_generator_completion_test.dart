import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('A64 Generator Completion', () {
    test('FP Scalar instructions', () {
      final env = Environment.aarch64();
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);

      asm.fneg(s0, s1);
      asm.fabs(d0, d1);
      asm.fsqrt(s2, s3);
      asm.fcmp(d0, d1);
      asm.fcsel(s0, s1, s2, A64Cond.eq);
      asm.fmax(s0, s1, s2);
      asm.fmin(d0, d1, d2);
      asm.fmaxnm(s0, s1, s2);
      asm.fminnm(d0, d1, d2);

      final bytes = asm.finalize().textBytes;
      expect(bytes.length, equals(9 * 4));
    });

    test('NEON Integer Misc instructions', () {
      final env = Environment.aarch64();
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);

      asm.neg(v0.s, v1.s);
      asm.abs(v0.d, v1.d); // ABS usually vectors
      asm.mvn(v0.q, v1.q);
      asm.cls(v0.s, v1.s);
      asm.clz(v0.s, v1.s);
      asm.cnt(v0.b, v1.b);
      asm.rev64(v0.s, v1.s);
      asm.rev32(v0.h, v1.h);
      asm.rev16(v0.b, v1.b);

      final bytes = asm.finalize().textBytes;
      expect(bytes.length, equals(9 * 4));
    });

    test('NEON Logic instructions', () {
      final env = Environment.aarch64();
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);

      asm.bic(v0.s, v1.s, v2.s);
      asm.orn(v0.s, v1.s, v2.s);
      asm.bsl(v0.s, v1.s, v2.s);
      asm.bit(v0.s, v1.s, v2.s);
      asm.bif(v0.s, v1.s, v2.s);

      final bytes = asm.finalize().textBytes;
      expect(bytes.length, equals(5 * 4));
    });

    test('NEON FP Vector instructions', () {
      final env = Environment.aarch64();
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);

      asm.fmaxVec(v0.s, v1.s, v2.s);
      asm.fminVec(v0.d, v1.d, v2.d);
      asm.fmaxnmVec(v0.s, v1.s, v2.s);
      asm.fminnmVec(v0.d, v1.d, v2.d);
      asm.faddp(v0.s, v1.s, v2.s);

      final bytes = asm.finalize().textBytes;
      expect(bytes.length, equals(5 * 4));
    });

    test('Vector Moves', () {
      final env = Environment.aarch64();
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);

      asm.dup(v0.s, v1.s, 0);
      asm.dup(v0.b, v1.b, 7);
      asm.ins(v0.s, 0, v1.s, 1);
      asm.umov(x0, v0.b, 0);
      asm.smov(x0.w, v0.b, 0);

      final bytes = asm.finalize().textBytes;
      expect(bytes.length, equals(5 * 4));
    });
  });
}
