/// Tests for AArch64 UJIT operations
///
/// Tests widening multiply, packing, and conversion operations.

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('A64 UJIT Operations', () {
    late CodeHolder code;
    late A64Assembler a;

    setUp(() {
      code = CodeHolder();
      a = A64Assembler(code);
    });

    group('Widening Multiply', () {
      test('SMULL - signed multiply long (low)', () {
        final v0 = A64Vec(0, 128);
        final v1 = A64Vec(1, 64);
        final v2 = A64Vec(2, 64);

        a.smull(v0, v1, v2);

        final result = code.text.buffer.bytes;
        expect(result.length, greaterThan(0));
      });

      test('UMULL - unsigned multiply long (low)', () {
        final v0 = A64Vec(0, 128);
        final v1 = A64Vec(1, 64);
        final v2 = A64Vec(2, 64);

        a.umull(v0, v1, v2);

        final result = code.text.buffer.bytes;
        expect(result.length, greaterThan(0));
      });
    });

    group('Packing (Narrowing)', () {
      test('SQXTN - saturating narrow', () {
        final v0 = A64Vec(0, 64);
        final v1 = A64Vec(1, 128);

        a.sqxtn(v0, v1);

        final result = code.text.buffer.bytes;
        expect(result.length, greaterThan(0));
      });

      test('XTN - extract narrow', () {
        final v0 = A64Vec(0, 64);
        final v1 = A64Vec(1, 128);

        a.xtn(v0, v1);

        final result = code.text.buffer.bytes;
        expect(result.length, greaterThan(0));
      });
    });

    group('Conversion Operations', () {
      test('SCVTF - signed integer to float', () {
        final v0 = A64Vec(0, 128);
        final v1 = A64Vec(1, 128);

        a.scvtf(v0, v1);

        final result = code.text.buffer.bytes;
        expect(result.length, greaterThan(0));
      });

      test('FCVTZS - float to signed integer (truncate)', () {
        final v0 = A64Vec(0, 128);
        final v1 = A64Vec(1, 128);

        a.fcvtzs(v0, v1);

        final result = code.text.buffer.bytes;
        expect(result.length, greaterThan(0));
      });
    });
  });
}
