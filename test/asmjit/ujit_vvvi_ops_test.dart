// UniOpVVVI ops shared by the x86 and AArch64 backends, executed on the host
// and compared with a Dart reference model.
//
// Interleaved shuffle immediates are Swizzle4 / Swizzle2 values as in asmjit
// (the low lanes come from src1, the high lanes from src2): all 256 32-bit and
// the 4 64-bit shuffles are checked, plus alignrU128 for every byte count.
// The layouts cover the special paths of the lowerings: dst == src1,
// dst == src2 (AArch64 uses another table), src1 == src2 (a swizzle) and a
// memory src2.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';
import '../support/ujit_run.dart';

class _Case {
  final String name;
  final UniOpVVVI op;
  final int imm;
  final Uint8List Function(Uint8List a, Uint8List b) ref;
  _Case(this.name, this.op, this.imm, this.ref);
}

Uint8List _u8(List<int> v) => Uint8List.fromList(v);

List<int> _lane(Uint8List v, int bytes, int i) =>
    v.sublist(i * bytes, (i + 1) * bytes);

List<_Case> _cases() {
  final out = <_Case>[];
  for (var v = 0; v < 256; v++) {
    final idx = [v & 3, (v >> 2) & 3, (v >> 4) & 3, (v >> 6) & 3];
    final swz = swizzle4(idx[3], idx[2], idx[1], idx[0]).value;
    for (final op in [
      UniOpVVVI.interleaveShuffleU32x4,
      UniOpVVVI.interleaveShuffleF32x4
    ]) {
      out.add(_Case(
          '${op.name} ${idx.join()}',
          op,
          swz,
          (a, b) => _u8([
                ..._lane(a, 4, idx[0]),
                ..._lane(a, 4, idx[1]),
                ..._lane(b, 4, idx[2]),
                ..._lane(b, 4, idx[3]),
              ])));
    }
  }
  for (final (hi, lo) in [(0, 0), (0, 1), (1, 0), (1, 1)]) {
    for (final op in [
      UniOpVVVI.interleaveShuffleU64x2,
      UniOpVVVI.interleaveShuffleF64x2
    ]) {
      out.add(_Case('${op.name} $hi$lo', op, swizzle2(hi, lo).value,
          (a, b) => _u8([..._lane(a, 8, lo), ..._lane(b, 8, hi)])));
    }
  }
  // PALIGNR semantics: (src1:src2) >> (8 * imm), src1 being the high part.
  for (var n = 0; n < 16; n++) {
    out.add(_Case('alignrU128 $n', UniOpVVVI.alignrU128, n,
        (a, b) => _u8([...b, ...a].sublist(n, n + 16))));
  }
  return out;
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

final _featureSets = <String, CpuFeatures?>{
  if (hostIsX64) ...{
    'sse2': null,
    'sse4.1': const CpuFeatures(
        sse: true, sse2: true, sse3: true, ssse3: true, sse41: true),
  },
  'host': hostIsX64 ? CpuInfo.host().features : null,
};

void main() {
  final ia = _u8(List.generate(16, (i) => 0x10 + i));
  final ib = _u8(List.generate(16, (i) => 0xA0 + i));
  final cases = _cases();

  for (final fs in _featureSets.entries) {
    for (final layout in [
      'dst',
      'dst=src1',
      'dst=src2',
      'src1=src2',
      'src2=mem'
    ]) {
      group('UniOpVVVI ${fs.key} $layout', () {
        for (final c in cases) {
          test(c.name, () {
            final r = runUjit((cc, d, a, b, cv, m) {
              switch (layout) {
                case 'dst':
                  cc.emit3vi(c.op, d, a, b, c.imm);
                case 'dst=src1':
                  cc.emit3vi(c.op, a, a, b, c.imm);
                  cc.emit2v(UniOpVV.mov, d, a);
                case 'dst=src2':
                  cc.emit3vi(c.op, b, a, b, c.imm);
                  cc.emit2v(UniOpVV.mov, d, b);
                case 'src1=src2':
                  cc.emit3vi(c.op, d, a, a, c.imm);
                default:
                  cc.emit3vi(c.op, d, a, m, c.imm);
              }
            }, ia, ib, ib, features: fs.value);
            final b = layout == 'src1=src2' ? ia : ib;
            expect(_hex(r), _hex(c.ref(ia, b)));
          });
        }
      }, skip: skipUnlessJitHost);
    }
  }
}
