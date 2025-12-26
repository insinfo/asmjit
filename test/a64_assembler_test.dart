import 'package:asmjit/src/arm/a64.dart';
import 'package:asmjit/src/arm/a64_assembler.dart';
import 'package:test/test.dart';

void main() {
  group('A64Assembler', () {
    late A64Assembler asm;

    setUp(() {
      asm = A64Assembler.create();
    });

    test('Basic Instructions', () {
      asm.mov(x0, x1);
      asm.addImm(x0, x0, 1);
      asm.ret();

      final bytes = asm.code.text.buffer.bytes;
      expect(bytes.length, equals(12));

      // ORR x0, xzr, x1 (MOV x0, x1) -> sf=1, op=01010100, rm=x1, rn=xzr, rd=x0
      // 0xAA0103E0
      expect(bytes.sublist(0, 4), equals([0xE0, 0x03, 0x01, 0xAA]));
    });

    test('Load/Store', () {
      asm.str(x0, sp, 16);
      asm.ldr(x0, sp, 16);
      asm.ldp(x29, x30, sp, 0);
      asm.strb(w0, sp, 0);
      asm.ldrb(w1, sp, 0);
      asm.strh(w2, sp, 2);
      asm.ldrh(w3, sp, 2);
      asm.ldrsb(x4, sp, 0);
      asm.ldrsh(x5, sp, 2);
      asm.ldrsw(x6, sp, 4);

      final bytes = asm.code.text.buffer.bytes;
      expect(bytes.length, greaterThan(0));
    });

    test('Branches', () {
      final label = asm.newLabel();
      asm.b(label);
      asm.nop();
      asm.bind(label);
      asm.adr(x0, 8); // small PC-rel
      asm.adrp(x1, 0); // page-rel zero
      asm.ret();

      asm.finalize();
      final bytes = asm.code.text.buffer.bytes;
      // B offset=8 (since NOP is 4 bytes + 4 bytes for B itself). imm26=2
      // 0x14000002
      expect(bytes.sublist(0, 4), equals([0x02, 0x00, 0x00, 0x14]));
    });

    test('Floating Point', () {
      asm.fadd(s0, s1, s2);
      asm.fadd(d0, d1, d2);

      final bytes = asm.code.text.buffer.bytes;
      expect(bytes.length, equals(8));
      expect(bytes.sublist(0, 4), equals([0x20, 0x28, 0x22, 0x1E]));
      expect(bytes.sublist(4, 8), equals([0x20, 0x28, 0x62, 0x1E]));
    });
  });
}
