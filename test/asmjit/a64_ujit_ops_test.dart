/// Tests for AArch64 UJIT operations
///
/// Tests byte shifts, widening multiply, packing, and comparison operations.

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('A64 UJIT Operations', () {
    late CodeHolder code;
    late A64Assembler a;

    setUp(() {
      code = CodeHolder();
      code.init(Environment.host());
      a = A64Assembler(code);
    });

    group('Byte Shifts', () {
      test('sllbU128 - shift left by 4 bytes', () {
        // Test left shift whole vector by bytes
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        // EXT implementation: EOR v0, v0, v0 (zero), then EXT v0, v0, v1, #12
        a.eor(v0, v0, v0);
        a.ext(v0, v0, v1, 12); // 16 - 4 = 12

        expect(code.finalize(), equals(AsmJitError.ok));
        final bytes = code.text.buffer.bytes.toList();
        expect(bytes.length, greaterThan(0));
      });

      test('srlbU128 - shift right by 8 bytes', () {
        // Test right shift whole vector by bytes
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        // EXT implementation: EOR v0, v0, v0 (zero), then EXT v0, v1, v0, #8
        a.eor(v0, v0, v0);
        a.ext(v0, v1, v0, 8);

        expect(code.finalize(), equals(AsmJitError.ok));
        final bytes = code.text.buffer.bytes.toList();
        expect(bytes.length, greaterThan(0));
      });
    });

    group('Comparison Operations', () {
      test('CMEQ - compare equal', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.cmeq(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
        final bytes = code.text.buffer.bytes.toList();
        expect(bytes.length, greaterThan(0));
      });

      test('CMGT - compare greater than (signed)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.cmgt(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('CMHI - compare greater than (unsigned)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.cmhi(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('CMGE - compare greater or equal (signed)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.cmge(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('CMHS - compare greater or equal (unsigned)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.cmhs(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });
    });

    group('Widening Multiply', () {
      test('SMULL - signed multiply long (low)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.smull(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
        final bytes = code.text.buffer.bytes.toList();
        expect(bytes.length, greaterThan(0));
      });

      test('UMULL - unsigned multiply long (low)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.umull(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('SMULL2 - signed multiply long (high)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.smull2(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('UMULL2 - unsigned multiply long (high)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.umull2(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });
    });

    group('Multiply-Accumulate Widening', () {
      test('SMLAL - signed multiply-accumulate long (low)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.smlal(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('UMLAL - unsigned multiply-accumulate long (low)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.umlal(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('SMLAL2 - signed multiply-accumulate long (high)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.smlal2(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('UMLAL2 - unsigned multiply-accumulate long (high)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.umlal2(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });
    });

    group('Saturating Operations', () {
      test('SQADD - saturating add (signed)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.sqadd(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('UQADD - saturating add (unsigned)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.uqadd(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('SQSUB - saturating sub (signed)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.sqsub(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('UQSUB - saturating sub (unsigned)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.uqsub(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('URHADD - unsigned rounded halving add (average)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);
        final v2 = A64Vec.v128(2);

        a.urhadd(v0, v1, v2);

        expect(code.finalize(), equals(AsmJitError.ok));
      });
    });

    group('Packing (Narrowing)', () {
      test('SQXTN - saturating narrow', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.sqxtn(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
        final bytes = code.text.buffer.bytes.toList();
        expect(bytes.length, greaterThan(0));
      });

      test('XTN - extract narrow', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.xtn(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
      });
    });

    group('Unary Operations', () {
      test('FNEG - floating point negate', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.fneg(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('FABS - floating point absolute', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.fabs(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('FSQRT - floating point square root', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.fsqrt(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('ABS - integer absolute', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.abs(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('MVN - bitwise NOT', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.mvn(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
      });
    });

    group('Conversion Operations', () {
      test('SCVTF - signed integer to float', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.scvtf(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('FCVTZS - float to signed integer (truncate)', () {
        final v0 = A64Vec.v128(0);
        final v1 = A64Vec.v128(1);

        a.fcvtzs(v0, v1);

        expect(code.finalize(), equals(AsmJitError.ok));
      });

      test('FCVT - float precision convert', () {
        final s0 = A64Vec.s(0);
        final d1 = A64Vec.d(1);

        a.fcvt(d1, s0);

        expect(code.finalize(), equals(AsmJitError.ok));
      });
    });
  });
}
