// UniOpVVI (vector + immediate) ops shared by the x86 and AArch64 backends,
// executed on the host and compared with a Dart reference model.
//
// Swizzle immediates are Swizzle2 / Swizzle4 values as in asmjit: every one
// of the 256 32-bit and 16-bit swizzles and the 4 64-bit swizzles is checked,
// plus the shifts at their boundary amounts. Each case runs with a distinct
// destination, dst == src and a memory source; on x86 also with SSE2 only,
// SSE4.1 and the host features.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';
import '../support/ujit_run.dart';

typedef _Ref = Uint8List Function(Uint8List a);

class _Case {
  final String name;
  final UniOpVVI op;
  final int imm;
  final _Ref ref;
  _Case(this.name, this.op, this.imm, this.ref);
}

Uint8List _u8(List<int> v) => Uint8List.fromList(v);

/// Lanes of [bytes] bytes of [a] permuted by [idx] (destination lane i takes
/// source lane idx[i]); [base] offsets both (16-bit swizzles per 64 bits).
List<int> _permute(Uint8List a, int bytes, List<int> idx, int base) => [
      for (final i in idx)
        ...a.sublist(base + i * bytes, base + (i + 1) * bytes)
    ];

_Ref _lanes(int bytes, bool signed, int Function(int x) f) => (a) {
      final d = ByteData.sublistView(a);
      final out = ByteData(16);
      for (var i = 0; i < 16; i += bytes) {
        final x = switch (bytes) {
          2 => signed
              ? d.getInt16(i, Endian.little)
              : d.getUint16(i, Endian.little),
          4 => signed
              ? d.getInt32(i, Endian.little)
              : d.getUint32(i, Endian.little),
          _ => d.getInt64(i, Endian.little),
        };
        final v = f(x);
        switch (bytes) {
          case 2:
            out.setUint16(i, v & 0xFFFF, Endian.little);
          case 4:
            out.setUint32(i, v & 0xFFFFFFFF, Endian.little);
          default:
            out.setInt64(i, v, Endian.little);
        }
      }
      return out.buffer.asUint8List();
    };

List<_Case> _cases() {
  final out = <_Case>[];

  for (var v = 0; v < 256; v++) {
    final idx = [v & 3, (v >> 2) & 3, (v >> 4) & 3, (v >> 6) & 3];
    final swz = swizzle4(idx[3], idx[2], idx[1], idx[0]).value;
    final tag = idx.join();
    for (final op in [UniOpVVI.swizzleU32x4, UniOpVVI.swizzleF32x4]) {
      out.add(_Case(
          '${op.name} $tag', op, swz, (a) => _u8(_permute(a, 4, idx, 0))));
    }
    out.add(_Case('swizzleU16x4 $tag', UniOpVVI.swizzleU16x4, swz,
        (a) => _u8([..._permute(a, 2, idx, 0), ..._permute(a, 2, idx, 8)])));
    out.add(_Case('swizzleLoU16x4 $tag', UniOpVVI.swizzleLoU16x4, swz,
        (a) => _u8([..._permute(a, 2, idx, 0), ...a.sublist(8)])));
    out.add(_Case('swizzleHiU16x4 $tag', UniOpVVI.swizzleHiU16x4, swz,
        (a) => _u8([...a.sublist(0, 8), ..._permute(a, 2, idx, 8)])));
  }

  for (final (b, a) in [(0, 0), (0, 1), (1, 0), (1, 1)]) {
    for (final op in [UniOpVVI.swizzleU64x2, UniOpVVI.swizzleF64x2]) {
      out.add(_Case('${op.name} $b$a', op, swizzle2(b, a).value,
          (x) => _u8(_permute(x, 8, [a, b], 0))));
    }
  }

  for (final n in [0, 1, 7, 15]) {
    out.add(_Case(
        'sllU16 $n', UniOpVVI.sllU16, n, _lanes(2, false, (x) => x << n)));
    out.add(_Case(
        'srlU16 $n', UniOpVVI.srlU16, n, _lanes(2, false, (x) => x >> n)));
    out.add(
        _Case('sraI16 $n', UniOpVVI.sraI16, n, _lanes(2, true, (x) => x >> n)));
  }
  for (final n in [0, 1, 17, 31]) {
    out.add(_Case(
        'sllU32 $n', UniOpVVI.sllU32, n, _lanes(4, false, (x) => x << n)));
    out.add(_Case(
        'srlU32 $n', UniOpVVI.srlU32, n, _lanes(4, false, (x) => x >> n)));
    out.add(
        _Case('sraI32 $n', UniOpVVI.sraI32, n, _lanes(4, true, (x) => x >> n)));
  }
  for (final n in [0, 1, 31, 32, 33, 47, 63]) {
    out.add(
        _Case('sllU64 $n', UniOpVVI.sllU64, n, _lanes(8, true, (x) => x << n)));
    out.add(_Case(
        'srlU64 $n', UniOpVVI.srlU64, n, _lanes(8, true, (x) => x >>> n)));
    out.add(
        _Case('sraI64 $n', UniOpVVI.sraI64, n, _lanes(8, true, (x) => x >> n)));
  }
  for (final n in [0, 1, 4, 8, 12, 15]) {
    out.add(_Case('sllbU128 $n', UniOpVVI.sllbU128, n,
        (a) => _u8([...List.filled(n, 0), ...a.sublist(0, 16 - n)])));
    out.add(_Case('srlbU128 $n', UniOpVVI.srlbU128, n,
        (a) => _u8([...a.sublist(n), ...List.filled(n, 0)])));
  }
  return out;
}

String _hex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

final _layouts = <String,
    void Function(UniCompiler, UniOpVVI, int, BaseReg, BaseReg, BaseMem)>{
  'dst': (cc, op, imm, d, a, m) => cc.emit2vi(op, d, a, imm),
  'dst=src': (cc, op, imm, d, a, m) {
    cc.emit2vi(op, a, a, imm);
    cc.emit2v(UniOpVV.mov, d, a);
  },
  'src=mem': (cc, op, imm, d, a, m) => cc.emit2vi(op, d, m, imm),
};

final _featureSets = <String, CpuFeatures?>{
  if (hostIsX64) ...{
    'sse2': null,
    'sse4.1': const CpuFeatures(
        sse: true, sse2: true, sse3: true, ssse3: true, sse41: true),
  },
  'host': hostIsX64 ? CpuInfo.host().features : null,
};

void main() {
  // Distinct, non-symmetric bytes with sign bits set in several lanes.
  final input = _u8([
    0x01, 0x82, 0x13, 0xF4, 0x25, 0x06, 0xB7, 0x48, //
    0x59, 0x6A, 0xFB, 0x0C, 0x9D, 0x2E, 0x3F, 0xC0,
  ]);
  final cases = _cases();

  for (final fs in _featureSets.entries) {
    for (final layout in _layouts.entries) {
      group('UniOpVVI ${fs.key} ${layout.key}', () {
        for (final c in cases) {
          test(c.name, () {
            final r = runUjit(
                (cc, d, a, b, cv, m) => layout.value(cc, c.op, c.imm, d, cv, m),
                input,
                input,
                input,
                features: fs.value);
            expect(_hex(r), _hex(c.ref(input)));
          });
        }
      }, skip: skipUnlessJitHost);
    }
  }
}
