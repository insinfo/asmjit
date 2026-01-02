import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('A64 Binary Verification', () {
    late CodeHolder code;
    late A64Assembler a;

    setUp(() {
      code = CodeHolder(env: Environment(arch: Arch.aarch64));
      a = A64Assembler(code);
    });

    void verifyBytes(List<int> expected) {
      final bytes = code.text.buffer.bytes.toList();
      expect(bytes, equals(expected), reason: 'Bytes mismatch');
      code.reset();
    }

    test('LD1R', () {
      // ld1r v0.s4, [x0]
      // Little Endian: 00 08 C0 4D
      a.ld1r(v0.s4, x0);
      verifyBytes([0x00, 0x08, 0xC0, 0x4D]);

      // ld1r v1.h8, [x1]
      // Little Endian: 21 04 C0 4D
      a.ld1r(v1.h8, x1);
      verifyBytes([0x21, 0x04, 0xC0, 0x4D]);
    });

    test('Permutations (TBL, ZIP, UZP, TRN)', () {
      // TBL v0.b16, {v1.b16}, v2.b16
      // LE: 20 00 02 4E
      a.tbl(v0.b16, v1.b16, v2.b16);
      verifyBytes([0x20, 0x00, 0x02, 0x4E]);

      // ZIP1 v0.b16, v1.b16, v2.b16
      // LE: 20 38 02 4E
      a.zip1(v0.b16, v1.b16, v2.b16);
      verifyBytes([0x20, 0x38, 0x02, 0x4E]);

      // ZIP2
      // LE: 20 78 02 4E
      a.zip2(v0.b16, v1.b16, v2.b16);
      verifyBytes([0x20, 0x78, 0x02, 0x4E]);

      // UZP1
      // LE: 20 18 02 4E
      a.uzp1(v0.b16, v1.b16, v2.b16);
      verifyBytes([0x20, 0x18, 0x02, 0x4E]);

      // TRN1
      // LE: 20 28 02 4E
      a.trn1(v0.b16, v1.b16, v2.b16);
      verifyBytes([0x20, 0x28, 0x02, 0x4E]);
    });
  });
}
