// Golden encodings for AArch64 loads/stores, moves involving SP and register
// pairs. Expected words were cross-checked with the LLVM disassembler.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

const _sp = A64Gp(31, 64);

int _word(void Function(A64Assembler a) emit) {
  final code = CodeHolder(env: Environment.aarch64());
  emit(A64Assembler(code));
  final bytes = code.finalize().textBytes;
  expect(bytes.length, 4);
  return ByteData.sublistView(Uint8List.fromList(bytes))
      .getUint32(0, Endian.little);
}

void main() {
  final cases = <String, (void Function(A64Assembler), int)>{
    'mov x0, x1': ((a) => a.mov(x0, x1), 0xAA0103E0),
    'mov x29, sp': ((a) => a.mov(x29, _sp), 0x910003FD),
    'mov sp, x29': ((a) => a.mov(_sp, x29), 0x910003BF),
    'ldr q0, [x1, #16]': ((a) => a.ldrVec(A64Vec(0, 128), x1, 16), 0x3DC00420),
    'ldr d0, [x1, #8]': ((a) => a.ldrVec(A64Vec(0, 64), x1, 8), 0xFD400420),
    'ldr s0, [x1, #4]': ((a) => a.ldrVec(A64Vec(0, 32), x1, 4), 0xBD400420),
    'str q2, [sp, #32]': ((a) => a.strVec(A64Vec(2, 128), _sp, 32), 0x3D800BE2),
    'str d8, [sp, #8]': ((a) => a.strVec(A64Vec(8, 64), _sp, 8), 0xFD0007E8),
    'stp x29, x30, [sp, #16]': ((a) => a.stp(x29, x30, _sp, 16), 0xA9017BFD),
    'ldp x29, x30, [sp, #16]': ((a) => a.ldp(x29, x30, _sp, 16), 0xA9417BFD),
    'ldr x3, [sp, #24]': ((a) => a.ldr(x3, _sp, 24), 0xF9400FE3),
    'str w4, [sp, #12]': ((a) => a.str(A64Gp(4, 32), _sp, 12), 0xB9000FE4),
    'sub sp, sp, #32': ((a) => a.subImm(_sp, _sp, 32), 0xD10083FF),
    'add sp, sp, #32': ((a) => a.addImm(_sp, _sp, 32), 0x910083FF),
    'ldur q0, [x1, #-16]': (
      (a) => a.ldrVecUnscaled(A64Vec(0, 128), x1, -16),
      0x3CDF0020
    ),
    'stur d3, [x2, #7]': (
      (a) => a.strVecUnscaled(A64Vec(3, 64), x2, 7),
      0xFC007043
    ),
    'ldr q5, #+8 (literal)': (
      (a) => a.ldrVecLiteral(A64Vec(5, 128), 8),
      0x9C000045
    ),
    'ldr d5, #-4 (literal)': (
      (a) => a.ldrVecLiteral(A64Vec(5, 64), -4),
      0x5CFFFFE5
    ),
    'stp x29, x30, [sp, #-16]!': (
      (a) => a.stpPre(x29, x30, _sp, -16),
      0xA9BF7BFD
    ),
    'ldp x29, x30, [sp], #16': (
      (a) => a.ldpPost(x29, x30, _sp, 16),
      0xA8C17BFD
    ),
    'ldur x0, [x1, #-8]': ((a) => a.ldur(x0, x1, -8), 0xF85F8020),
    'stur w2, [sp, #3]': ((a) => a.stur(A64Gp(2, 32), _sp, 3), 0xB80033E2),
    'stp x19, x20, [sp, #-32]': (
      (a) => a.stp(A64Gp(19, 64), A64Gp(20, 64), _sp, -32),
      0xA93E53F3
    ),
  };

  group('A64 load/store encoding', () {
    cases.forEach((name, c) {
      test(name, () {
        expect(_word(c.$1).toRadixString(16), c.$2.toRadixString(16));
      });
    });

    test('rejects offsets that cannot be encoded', () {
      expect(() => _word((a) => a.ldrVec(A64Vec(0, 128), x1, 8)),
          throwsArgumentError);
      expect(() => _word((a) => a.ldrVecUnscaled(A64Vec(0, 128), x1, 256)),
          throwsArgumentError);
      expect(() => _word((a) => a.stp(x29, x30, _sp, 4)), throwsArgumentError);
    });
  });
}
