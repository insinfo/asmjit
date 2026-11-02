// Golden encodings for AArch64 Advanced SIMD instructions (three same,
// three different, permute, MOVI). Expected words were cross-checked with the
// LLVM disassembler.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

A64Vec v(int id, A64Layout l) => A64Vec(id, 128, l);
A64Vec vv(int id, A64Layout l, [int bits = 128]) => A64Vec(id, bits, l);

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
    'fcmeq s0, s1, s2': (
      (a) => a.fcmeq(A64Vec(0, 32), A64Vec(1, 32), A64Vec(2, 32)),
      0x5E22E420
    ),
    'fcmeq d3, d4, d5': (
      (a) => a.fcmeq(A64Vec(3, 64), A64Vec(4, 64), A64Vec(5, 64)),
      0x5E65E483
    ),
    'fcmge s0, s1, s2': (
      (a) => a.fcmge(A64Vec(0, 32), A64Vec(1, 32), A64Vec(2, 32)),
      0x7E22E420
    ),
    'fcmge d3, d4, d5': (
      (a) => a.fcmge(A64Vec(3, 64), A64Vec(4, 64), A64Vec(5, 64)),
      0x7E65E483
    ),
    'fcmgt s0, s1, s2': (
      (a) => a.fcmgt(A64Vec(0, 32), A64Vec(1, 32), A64Vec(2, 32)),
      0x7EA2E420
    ),
    'fcmgt d3, d4, d5': (
      (a) => a.fcmgt(A64Vec(3, 64), A64Vec(4, 64), A64Vec(5, 64)),
      0x7EE5E483
    ),
    'fmax d1, d2, d3': (
      (a) => a.fmax(A64Vec(1, 64), A64Vec(2, 64), A64Vec(3, 64)),
      0x1E634841
    ),
    'fmin s1, s2, s3': (
      (a) => a.fmin(A64Vec(1, 32), A64Vec(2, 32), A64Vec(3, 32)),
      0x1E235841
    ),
    'fmaxnm d1, d2, d3': (
      (a) => a.fmaxnm(A64Vec(1, 64), A64Vec(2, 64), A64Vec(3, 64)),
      0x1E636841
    ),
    'fminnm s1, s2, s3': (
      (a) => a.fminnm(A64Vec(1, 32), A64Vec(2, 32), A64Vec(3, 32)),
      0x1E237841
    ),
    'uaddlp v1.2d, v2.4s': ((a) => a.uaddlp(v(1, d2), v(2, s4)), 0x6EA02841),
    'uaddlp v1.4s, v2.8h': ((a) => a.uaddlp(v(1, s4), v(2, h8)), 0x6E602841),
    'uaddlp v1.8h, v2.16b': ((a) => a.uaddlp(v(1, h8), v(2, b16)), 0x6E202841),
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
    'shl v1.4s, v0.4s, #16': (
      (a) => a.shlVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4), 16),
      0x4F305401
    ),
    'shl v1.16b, v0.16b, #7': (
      (a) => a.shlVec(vv(1, A64Layout.b16), vv(0, A64Layout.b16), 7),
      0x4F0F5401
    ),
    'shl v1.2d, v0.2d, #63': (
      (a) => a.shlVec(vv(1, A64Layout.d2), vv(0, A64Layout.d2), 63),
      0x4F7F5401
    ),
    'sli v1.4s, v0.4s, #12': (
      (a) => a.sliVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4), 12),
      0x6F2C5401
    ),
    'ushr v1.4s, v0.4s, #20': (
      (a) => a.ushrVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4), 20),
      0x6F2C0401
    ),
    'ushr v1.8h, v0.8h, #16': (
      (a) => a.ushrVec(vv(1, A64Layout.h8), vv(0, A64Layout.h8), 16),
      0x6F100401
    ),
    'sshr v1.2s, v0.2s, #1': (
      (a) => a.sshrVec(vv(1, A64Layout.s2, 64), vv(0, A64Layout.s2, 64), 1),
      0x0F3F0401
    ),
    'sri v1.4s, v0.4s, #25': (
      (a) => a.sriVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4), 25),
      0x6F274401
    ),
    'usra v1.2d, v0.2d, #32': (
      (a) => a.usraVec(vv(1, A64Layout.d2), vv(0, A64Layout.d2), 32),
      0x6F601401
    ),
    'ssra v1.8h, v0.8h, #3': (
      (a) => a.ssraVec(vv(1, A64Layout.h8), vv(0, A64Layout.h8), 3),
      0x4F1D1401
    ),
    'shrn v1.4h, v0.4s, #16': (
      (a) => a.shrnVec(vv(1, A64Layout.h4, 64), vv(0, A64Layout.s4), 16),
      0x0F108401
    ),
    'shrn2 v1.8h, v0.4s, #16': (
      (a) => a.shrnVec(vv(1, A64Layout.h8), vv(0, A64Layout.s4), 16),
      0x4F108401
    ),
    'ushll v1.8h, v0.8b, #0': (
      (a) => a.ushllVec(vv(1, A64Layout.h8), vv(0, A64Layout.b8, 64), 0),
      0x2F08A401
    ),
    'ushll2 v1.4s, v0.8h, #2': (
      (a) => a.ushllVec(vv(1, A64Layout.s4), vv(0, A64Layout.h8), 2),
      0x6F12A401
    ),
    'sshll v1.2d, v0.2s, #0': (
      (a) => a.sshllVec(vv(1, A64Layout.d2), vv(0, A64Layout.s2, 64), 0),
      0x0F20A401
    ),
    'mov v1.s[2], v0.s[1]': (
      (a) => a.ins(vv(1, A64Layout.s4), 2, vv(0, A64Layout.s4), 1),
      0x6E142401
    ),
    'mov v3.d[1], v4.d[0]': (
      (a) => a.ins(vv(3, A64Layout.d2), 1, vv(4, A64Layout.d2), 0),
      0x6E180483
    ),
    'mov v3.b[15], v4.b[3]': (
      (a) => a.ins(vv(3, A64Layout.b16), 15, vv(4, A64Layout.b16), 3),
      0x6E1F1C83
    ),
    'urshr v1.4s, v0.4s, #8': (
      (a) => a.urshrVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4), 8),
      0x6F382401
    ),
    'ursra v1.8h, v0.8h, #4': (
      (a) => a.ursraVec(vv(1, A64Layout.h8), vv(0, A64Layout.h8), 4),
      0x6F1C3401
    ),
    'rshrn v1.8b, v0.8h, #8': (
      (a) => a.rshrnVec(vv(1, A64Layout.b8, 64), vv(0, A64Layout.h8), 8),
      0x0F088C01
    ),
    'rshrn2 v1.16b, v0.8h, #8': (
      (a) => a.rshrnVec(vv(1, A64Layout.b16), vv(0, A64Layout.h8), 8),
      0x4F088C01
    ),
    'abs v1.4s, v0.4s': (
      (a) => a.abs(vv(1, A64Layout.s4), vv(0, A64Layout.s4)),
      0x4EA0B801
    ),
    'abs v1.2d, v0.2d': (
      (a) => a.abs(vv(1, A64Layout.d2), vv(0, A64Layout.d2)),
      0x4EE0B801
    ),
    'abs v1.8b, v0.8b': (
      (a) => a.abs(vv(1, A64Layout.b8, 64), vv(0, A64Layout.b8, 64)),
      0x0E20B801
    ),
    'mvn v1.16b, v0.16b': (
      (a) => a.mvnVec(vv(1, A64Layout.b16), vv(0, A64Layout.b16)),
      0x6E205801
    ),
    'mvn v1.8b, v0.8b': (
      (a) => a.mvnVec(vv(1, A64Layout.b8, 64), vv(0, A64Layout.b8, 64)),
      0x2E205801
    ),
    'fabs v1.4s, v0.4s': (
      (a) => a.fabsVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4)),
      0x4EA0F801
    ),
    'fneg v1.2d, v0.2d': (
      (a) => a.fnegVec(vv(1, A64Layout.d2), vv(0, A64Layout.d2)),
      0x6EE0F801
    ),
    'fsqrt v1.4s, v0.4s': (
      (a) => a.fsqrtVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4)),
      0x6EA1F801
    ),
    'frintn v1.4s, v0.4s': (
      (a) => a.frintnVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4)),
      0x4E218801
    ),
    'frintm v1.2d, v0.2d': (
      (a) => a.frintmVec(vv(1, A64Layout.d2), vv(0, A64Layout.d2)),
      0x4E619801
    ),
    'frintp v1.4s, v0.4s': (
      (a) => a.frintpVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4)),
      0x4EA18801
    ),
    'frintz v1.2s, v0.2s': (
      (a) => a.frintzVec(vv(1, A64Layout.s2, 64), vv(0, A64Layout.s2, 64)),
      0x0EA19801
    ),
    'frinta v1.2d, v0.2d': (
      (a) => a.frintaVec(vv(1, A64Layout.d2), vv(0, A64Layout.d2)),
      0x6E618801
    ),
    'scvtf v1.4s, v0.4s': (
      (a) => a.scvtfVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4)),
      0x4E21D801
    ),
    'ucvtf v1.2d, v0.2d': (
      (a) => a.ucvtfVec(vv(1, A64Layout.d2), vv(0, A64Layout.d2)),
      0x6E61D801
    ),
    'fcvtzs v1.4s, v0.4s': (
      (a) => a.fcvtzsVec(vv(1, A64Layout.s4), vv(0, A64Layout.s4)),
      0x4EA1B801
    ),
    'fcvtns v1.2d, v0.2d': (
      (a) => a.fcvtnsVec(vv(1, A64Layout.d2), vv(0, A64Layout.d2)),
      0x4E61A801
    ),
    'fcvtl v1.2d, v0.2s': (
      (a) => a.fcvtlVec(vv(1, A64Layout.d2), vv(0, A64Layout.s2, 64)),
      0x0E617801
    ),
    'fcvtl2 v1.2d, v0.4s': (
      (a) => a.fcvtlVec(vv(1, A64Layout.d2), vv(0, A64Layout.s4)),
      0x4E617801
    ),
    'fcvtn v1.2s, v0.2d': (
      (a) => a.fcvtnVec(vv(1, A64Layout.s2, 64), vv(0, A64Layout.d2)),
      0x0E616801
    ),
    'fcvtn2 v1.4s, v0.2d': (
      (a) => a.fcvtnVec(vv(1, A64Layout.s4), vv(0, A64Layout.d2)),
      0x4E616801
    ),
    'fabs s1, s0': ((a) => a.fabs(A64Vec(1, 32), A64Vec(0, 32)), 0x1E20C001),
    'fneg d1, d0': ((a) => a.fneg(A64Vec(1, 64), A64Vec(0, 64)), 0x1E614001),
    'fsqrt s1, s0': ((a) => a.fsqrt(A64Vec(1, 32), A64Vec(0, 32)), 0x1E21C001),
    'fsqrt d1, d0': ((a) => a.fsqrt(A64Vec(1, 64), A64Vec(0, 64)), 0x1E61C001),
    'frintn s1, s0': (
      (a) => a.frintnS(A64Vec(1, 32), A64Vec(0, 32)),
      0x1E244001
    ),
    'frintp d1, d0': (
      (a) => a.frintpS(A64Vec(1, 64), A64Vec(0, 64)),
      0x1E64C001
    ),
    'frintm s1, s0': (
      (a) => a.frintmS(A64Vec(1, 32), A64Vec(0, 32)),
      0x1E254001
    ),
    'frintz d1, d0': (
      (a) => a.frintzS(A64Vec(1, 64), A64Vec(0, 64)),
      0x1E65C001
    ),
    'frinta s1, s0': (
      (a) => a.frintaS(A64Vec(1, 32), A64Vec(0, 32)),
      0x1E264001
    ),
    'fcvt d1, s0': ((a) => a.fcvt(A64Vec(1, 64), A64Vec(0, 32)), 0x1E22C001),
    'fcvt s1, d0': ((a) => a.fcvt(A64Vec(1, 32), A64Vec(0, 64)), 0x1E624001),
    'dup v1.4s, v0.s[2]': (
      (a) => a.dup(vv(1, A64Layout.s4), vv(0, A64Layout.s4), 2),
      0x4E140401
    ),
    'dup v1.16b, v0.b[5]': (
      (a) => a.dup(vv(1, A64Layout.b16), vv(0, A64Layout.b16), 5),
      0x4E0B0401
    ),
    'dup v1.2d, v0.d[1]': (
      (a) => a.dup(vv(1, A64Layout.d2), vv(0, A64Layout.d2), 1),
      0x4E180401
    ),
    'dup v1.8h, v0.h[7]': (
      (a) => a.dup(vv(1, A64Layout.h8), vv(0, A64Layout.h8), 7),
      0x4E1E0401
    ),
    'dup v1.4s, w2': (
      (a) => a.dupGp(vv(1, A64Layout.s4), A64Gp(2, 32)),
      0x4E040C41
    ),
    'dup v1.16b, w2': (
      (a) => a.dupGp(vv(1, A64Layout.b16), A64Gp(2, 32)),
      0x4E010C41
    ),
    'dup v1.8h, w3': (
      (a) => a.dupGp(vv(1, A64Layout.h8), A64Gp(3, 32)),
      0x4E020C61
    ),
    'dup v1.2d, x4': (
      (a) => a.dupGp(vv(1, A64Layout.d2), A64Gp(4, 64)),
      0x4E080C81
    ),
    'dup v1.2s, w5': (
      (a) => a.dupGp(vv(1, A64Layout.s2, 64), A64Gp(5, 32)),
      0x0E040CA1
    ),
    'fmla v1.4s, v2.4s, v3.4s': (
      (a) => a.fmlaVec(
          vv(1, A64Layout.s4), vv(2, A64Layout.s4), vv(3, A64Layout.s4)),
      0x4E23CC41
    ),
    'fmla v1.2d, v2.2d, v3.2d': (
      (a) => a.fmlaVec(
          vv(1, A64Layout.d2), vv(2, A64Layout.d2), vv(3, A64Layout.d2)),
      0x4E63CC41
    ),
    'fmls v1.4s, v2.4s, v3.4s': (
      (a) => a.fmlsVec(
          vv(1, A64Layout.s4), vv(2, A64Layout.s4), vv(3, A64Layout.s4)),
      0x4EA3CC41
    ),
    'mla v1.8h, v2.8h, v3.8h': (
      (a) => a.mlaVec(
          vv(1, A64Layout.h8), vv(2, A64Layout.h8), vv(3, A64Layout.h8)),
      0x4E639441
    ),
    'mla v1.4s, v2.4s, v3.4s': (
      (a) => a.mlaVec(
          vv(1, A64Layout.s4), vv(2, A64Layout.s4), vv(3, A64Layout.s4)),
      0x4EA39441
    ),
    'mls v1.16b, v2.16b, v3.16b': (
      (a) => a.mlsVec(
          vv(1, A64Layout.b16), vv(2, A64Layout.b16), vv(3, A64Layout.b16)),
      0x6E239441
    ),
  };

  group('A64 Advanced SIMD encoding', () {
    cases.forEach((name, c) {
      test(name, () {
        expect(_word(c.$1).toRadixString(16), c.$2.toRadixString(16));
      });
    });
  });
}
