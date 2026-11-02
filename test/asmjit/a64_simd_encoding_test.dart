// Golden encodings for AArch64 Advanced SIMD instructions (three same,
// three different, permute, MOVI). Expected words were cross-checked with the
// LLVM disassembler.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

A64Vec v(int id, A64Layout l) => A64Vec(id, 128, l);

const s4 = A64Layout.s4, d2 = A64Layout.d2, b16 = A64Layout.b16;
const h8 = A64Layout.h8, s2 = A64Layout.s2, h4 = A64Layout.h4;
const b8 = A64Layout.b8;

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
    'fadd v0.4s, v1.4s, v2.4s': (
      (a) => a.faddVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4E22D420
    ),
    'fsub v0.4s, v1.4s, v2.4s': (
      (a) => a.fsubVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4EA2D420
    ),
    'fmul v0.2d, v1.2d, v2.2d': (
      (a) => a.fmulVec(v(0, d2), v(1, d2), v(2, d2)),
      0x6E62DC20
    ),
    'fdiv v0.4s, v1.4s, v2.4s': (
      (a) => a.fdivVec(v(0, s4), v(1, s4), v(2, s4)),
      0x6E22FC20
    ),
    'fmax v0.4s, v1.4s, v2.4s': (
      (a) => a.fmaxVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4E22F420
    ),
    'fmin v0.2d, v1.2d, v2.2d': (
      (a) => a.fminVec(v(0, d2), v(1, d2), v(2, d2)),
      0x4EE2F420
    ),
    'fmaxnm v0.4s, v1.4s, v2.4s': (
      (a) => a.fmaxnmVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4E22C420
    ),
    'fminnm v0.4s, v1.4s, v2.4s': (
      (a) => a.fminnmVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4EA2C420
    ),
    'fadd v0.2s, v1.2s, v2.2s': (
      (a) => a.faddVec(v(0, s2), v(1, s2), v(2, s2)),
      0x0E22D420
    ),
    'fcmeq v0.4s, v1.4s, v2.4s': (
      (a) => a.fcmeqVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4E22E420
    ),
    'fcmge v0.2d, v1.2d, v2.2d': (
      (a) => a.fcmgeVec(v(0, d2), v(1, d2), v(2, d2)),
      0x6E62E420
    ),
    'fcmgt v0.4s, v1.4s, v2.4s': (
      (a) => a.fcmgtVec(v(0, s4), v(1, s4), v(2, s4)),
      0x6EA2E420
    ),
    'sqadd v0.16b, v1.16b, v2.16b': (
      (a) => a.sqaddVec(v(0, b16), v(1, b16), v(2, b16)),
      0x4E220C20
    ),
    'uqadd v0.8h, v1.8h, v2.8h': (
      (a) => a.uqaddVec(v(0, h8), v(1, h8), v(2, h8)),
      0x6E620C20
    ),
    'sqsub v0.8h, v1.8h, v2.8h': (
      (a) => a.sqsubVec(v(0, h8), v(1, h8), v(2, h8)),
      0x4E622C20
    ),
    'uqsub v0.16b, v1.16b, v2.16b': (
      (a) => a.uqsubVec(v(0, b16), v(1, b16), v(2, b16)),
      0x6E222C20
    ),
    'smax v0.4s, v1.4s, v2.4s': (
      (a) => a.smaxVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4EA26420
    ),
    'umax v0.8h, v1.8h, v2.8h': (
      (a) => a.umaxVec(v(0, h8), v(1, h8), v(2, h8)),
      0x6E626420
    ),
    'smin v0.4s, v1.4s, v2.4s': (
      (a) => a.sminVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4EA26C20
    ),
    'umin v0.16b, v1.16b, v2.16b': (
      (a) => a.uminVec(v(0, b16), v(1, b16), v(2, b16)),
      0x6E226C20
    ),
    'cmeq v0.4s, v1.4s, v2.4s': (
      (a) => a.cmeqVec(v(0, s4), v(1, s4), v(2, s4)),
      0x6EA28C20
    ),
    'cmgt v0.2d, v1.2d, v2.2d': (
      (a) => a.cmgtVec(v(0, d2), v(1, d2), v(2, d2)),
      0x4EE23420
    ),
    'cmhi v0.16b, v1.16b, v2.16b': (
      (a) => a.cmhiVec(v(0, b16), v(1, b16), v(2, b16)),
      0x6E223420
    ),
    'cmge v0.8h, v1.8h, v2.8h': (
      (a) => a.cmgeVec(v(0, h8), v(1, h8), v(2, h8)),
      0x4E623C20
    ),
    'cmhs v0.4s, v1.4s, v2.4s': (
      (a) => a.cmhsVec(v(0, s4), v(1, s4), v(2, s4)),
      0x6EA23C20
    ),
    'cmtst v0.4s, v1.4s, v2.4s': (
      (a) => a.cmtstVec(v(0, s4), v(1, s4), v(2, s4)),
      0x4EA28C20
    ),
    'ushl v0.4s, v1.4s, v2.4s': (
      (a) => a.ushlVec(v(0, s4), v(1, s4), v(2, s4)),
      0x6EA24420
    ),
    'add v0.2s, v1.2s, v2.2s': (
      (a) => a.addVec(v(0, s2), v(1, s2), v(2, s2)),
      0x0EA28420
    ),
    'and v0.8b, v1.8b, v2.8b': (
      (a) => a.andVec(v(0, b8), v(1, b8), v(2, b8)),
      0x0E221C20
    ),
    'zip1 v0.2s, v1.2s, v2.2s': (
      (a) => a.zip1(v(0, s2), v(1, s2), v(2, s2)),
      0x0E823820
    ),
    'uzp2 v0.8h, v1.8h, v2.8h': (
      (a) => a.uzp2(v(0, h8), v(1, h8), v(2, h8)),
      0x4E425820
    ),
    'smull v0.4s, v1.4h, v2.4h': (
      (a) => a.smullVec(v(0, s4), v(1, h4), v(2, h4)),
      0x0E62C020
    ),
    'smull2 v0.4s, v1.8h, v2.8h': (
      (a) => a.smullVec(v(0, s4), v(1, h8), v(2, h8)),
      0x4E62C020
    ),
    'umull v0.2d, v1.2s, v2.2s': (
      (a) => a.umullVec(v(0, d2), v(1, s2), v(2, s2)),
      0x2EA2C020
    ),
    'umlal v0.8h, v1.8b, v2.8b': (
      (a) => a.umlalVec(v(0, h8), v(1, b8), v(2, b8)),
      0x2E228020
    ),
    'smlal2 v0.2d, v1.4s, v2.4s': (
      (a) => a.smlalVec(v(0, d2), v(1, s4), v(2, s4)),
      0x4EA28020
    ),
    'movi v0.16b, #0xff': ((a) => a.moviB(v(0, b16), 0xFF), 0x4F07E7E0),
    'movi v3.8b, #0x5a': ((a) => a.moviB(v(3, b8), 0x5A), 0x0F02E743),
    'sqxtn v0.4h, v1.4s': (
      (a) => a.sqxtn(A64Vec(0, 64, h4), v(1, s4)),
      0x0E614820
    ),
    'sqxtn2 v0.8h, v2.4s': ((a) => a.sqxtn2(v(0, h8), v(2, s4)), 0x4E614840),
    'sqxtn v0.8b, v1.8h': (
      (a) => a.sqxtn(A64Vec(0, 64, b8), v(1, h8)),
      0x0E214820
    ),
    'uqxtn v0.4h, v1.4s': (
      (a) => a.uqxtn(A64Vec(0, 64, h4), v(1, s4)),
      0x2E614820
    ),
    'sqxtun v0.8b, v1.8h': (
      (a) => a.sqxtun(A64Vec(0, 64, b8), v(1, h8)),
      0x2E212820
    ),
    'sqxtun2 v0.8h, v1.4s': ((a) => a.sqxtun2(v(0, h8), v(1, s4)), 0x6E612820),
    'xtn v0.2s, v1.2d': ((a) => a.xtn(A64Vec(0, 64, s2), v(1, d2)), 0x0EA12820),
    'uqxtn2 v0.16b, v1.8h': ((a) => a.uqxtn2(v(0, b16), v(1, h8)), 0x6E214820),
  };

  group('A64 Advanced SIMD encoding', () {
    cases.forEach((name, c) {
      test(name, () {
        expect(_word(c.$1).toRadixString(16), c.$2.toRadixString(16));
      });
    });
  });
}
