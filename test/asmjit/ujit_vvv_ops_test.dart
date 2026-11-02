// Every UniOpVVV shared by the x86 and AArch64 backends, executed on the host
// and compared with a Dart reference model.
//
// Each op runs with four operand layouts, because the lowerings take
// different paths for them: a distinct destination, dst == src1,
// dst == src2 and a memory src2. On x86 the lowering is also run with SSE2
// only, with SSE4.1 (no SSE4.2, no AVX) and with the host features.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';
import '../support/ujit_run.dart';

typedef _Ref = Uint8List Function(Uint8List a, Uint8List b);

class _Case {
  final UniOpVVV op;
  final Uint8List a, b;
  final _Ref ref;

  /// Number of low bytes compared (scalar float ops only define lane 0).
  final int bytes;

  _Case(this.op, this.a, this.b, this.ref, [this.bytes = 16]);
}

Uint8List _u8(List<int> v) => Uint8List.fromList(v);
Uint8List _f32s(List<double> v) => Float32List.fromList(v).buffer.asUint8List();
Uint8List _f64s(List<double> v) => Float64List.fromList(v).buffer.asUint8List();

int _rd(ByteData d, int i, int bytes, bool signed) => switch (bytes) {
      1 => signed ? d.getInt8(i) : d.getUint8(i),
      2 =>
        signed ? d.getInt16(i, Endian.little) : d.getUint16(i, Endian.little),
      4 =>
        signed ? d.getInt32(i, Endian.little) : d.getUint32(i, Endian.little),
      _ => d.getInt64(i, Endian.little),
    };

void _wr(ByteData d, int i, int bytes, int v) => switch (bytes) {
      1 => d.setUint8(i, v & 0xFF),
      2 => d.setUint16(i, v & 0xFFFF, Endian.little),
      4 => d.setUint32(i, v & 0xFFFFFFFF, Endian.little),
      _ => d.setInt64(i, v, Endian.little),
    };

/// Lane-wise integer op ([signed] lanes of [bytes] bytes; 64-bit lanes are
/// always read as signed Dart ints).
_Ref _lanes(int bytes, bool signed, int Function(int x, int y) f) => (a, b) {
      final out = ByteData(16);
      final da = ByteData.sublistView(a), db = ByteData.sublistView(b);
      for (var i = 0; i < 16; i += bytes) {
        _wr(out, i, bytes,
            f(_rd(da, i, bytes, signed), _rd(db, i, bytes, signed)));
      }
      return out.buffer.asUint8List();
    };

/// Compares 64-bit lanes as unsigned values.
int _cmpU64(int x, int y) =>
    (x ^ 0x8000000000000000).compareTo(y ^ 0x8000000000000000);

int _sat(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

int _mask(bool c) => c ? -1 : 0;

/// Integer compare/min/max ops, derived from the op name.
_Ref? _intCmpMinMax(UniOpVVV op) {
  final m =
      RegExp(r'^(cmpEq|cmpGt|cmpGe|cmpLt|cmpLe|min|max)([IU])(8|16|32|64)$')
          .firstMatch(op.name);
  if (m == null) return null;
  final kind = m.group(1)!;
  final signed = m.group(2) == 'I';
  final bytes = int.parse(m.group(3)!) ~/ 8;
  int cmp(int x, int y) =>
      bytes == 8 && !signed ? _cmpU64(x, y) : x.compareTo(y);
  return _lanes(bytes, signed, (x, y) {
    final c = cmp(x, y);
    return switch (kind) {
      'cmpEq' => _mask(c == 0),
      'cmpGt' => _mask(c > 0),
      'cmpGe' => _mask(c >= 0),
      'cmpLt' => _mask(c < 0),
      'cmpLe' => _mask(c <= 0),
      'min' => c <= 0 ? x : y,
      _ => c >= 0 ? x : y,
    };
  });
}

/// Float ops of [op] (F32/F64 vector and F32S/F64S scalar).
({bool f64, bool scalar, Object Function(double x, double y) f})? _fpOp(
    UniOpVVV op) {
  final m = RegExp(r'^(add|sub|mul|div|min|max|mod|cmpEq|cmpNe|cmpGt|cmpGe|'
          r'cmpLt|cmpLe|cmpOrd|cmpUnord)F(32|64)(S?)$')
      .firstMatch(op.name);
  if (m == null) return null;
  final f64 = m.group(2) == '64';
  double r(double v) => f64 ? v : (Float32List(1)..[0] = v)[0];
  bool nan(double x, double y) => x.isNaN || y.isNaN;
  final Object Function(double x, double y) f = switch (m.group(1)!) {
    'add' => (x, y) => r(x + y),
    'sub' => (x, y) => r(x - y),
    'mul' => (x, y) => r(x * y),
    'div' => (x, y) => r(x / y),
    'min' => (x, y) => math.min(x, y),
    'max' => (x, y) => math.max(x, y),
    'mod' => (x, y) => r(x - r(r(x / y).truncateToDouble() * y)),
    'cmpEq' => (x, y) => x == y,
    'cmpNe' => (x, y) => x != y,
    'cmpGt' => (x, y) => x > y,
    'cmpGe' => (x, y) => x >= y,
    'cmpLt' => (x, y) => x < y,
    'cmpLe' => (x, y) => x <= y,
    'cmpOrd' => (x, y) => !nan(x, y),
    _ => (x, y) => nan(x, y),
  };
  return (f64: f64, scalar: m.group(3) == 'S', f: f);
}

_Ref _fpRef(bool f64, Object Function(double x, double y) f) => (a, b) {
      final out = ByteData(16);
      final da = ByteData.sublistView(a), db = ByteData.sublistView(b);
      final n = f64 ? 8 : 4;
      for (var i = 0; i < 16; i += n) {
        final x = f64
            ? da.getFloat64(i, Endian.little)
            : da.getFloat32(i, Endian.little);
        final y = f64
            ? db.getFloat64(i, Endian.little)
            : db.getFloat32(i, Endian.little);
        final v = f(x, y);
        if (v is bool) {
          _wr(out, i, n, _mask(v));
        } else if (f64) {
          out.setFloat64(i, v as double, Endian.little);
        } else {
          out.setFloat32(i, v as double, Endian.little);
        }
      }
      return out.buffer.asUint8List();
    };

/// Interleaves the low or high halves of [a] and [b] in [bytes]-byte lanes.
_Ref _interleave(int bytes, bool hi) => (a, b) {
      final base = hi ? 8 : 0;
      return _u8([
        for (var i = 0; i < 8; i += bytes) ...[
          ...a.sublist(base + i, base + i + bytes),
          ...b.sublist(base + i, base + i + bytes),
        ],
      ]);
    };

/// Signed pack of [inBytes]-byte lanes of a (low half) and b (high half).
_Ref _pack(int inBytes, int lo, int hi) => (a, b) {
      final outBytes = inBytes ~/ 2;
      final out = ByteData(16);
      final n = 16 ~/ inBytes;
      for (var i = 0; i < 2 * n; i++) {
        final src = ByteData.sublistView(i < n ? a : b);
        final v = _rd(src, (i % n) * inBytes, inBytes, true);
        _wr(out, i * outBytes, outBytes, _sat(v, lo, hi));
      }
      return out.buffer.asUint8List();
    };

/// Every UniOpVVV shared by both backends (the AArch64-only widening ops
/// follow `swizzlevU8` in the enum).
final _commonOps = UniOpVVV.values.sublist(0, UniOpVVV.swizzlevU8.index + 1);

List<_Case> _cases() {
  // Integer inputs exercise signedness, saturation and overflow; `ic`
  // equals `ia` in the low 64 bits so every compare sees equal lanes too.
  final ia = _u8([
    0x01, 0x7F, 0x80, 0xFF, 0x10, 0x00, 0xFE, 0x81, //
    0x33, 0xC0, 0x55, 0xAA, 0x00, 0x80, 0xFF, 0x7F,
  ]);
  final ib = _u8([
    0x02, 0x01, 0x80, 0x01, 0xF0, 0x00, 0x03, 0x7F, //
    0x33, 0x40, 0xAA, 0x55, 0x01, 0x7F, 0xFF, 0x80,
  ]);
  final ic = _u8([...ia.sublist(0, 8), ...ib.sublist(8)]);

  final fa = _f32s([1.5, -2.0, 8.0, 0.25]), fb = _f32s([0.5, -2.0, -4.0, 4.0]);
  final da = _f64s([1.5, -7.5]), db = _f64s([0.5, 2.0]);
  final ma = _f32s([7.5, -7.5, 10.0, 5.25]), mb = _f32s([2.0, 2.0, 3.0, 1.5]);
  final dma = _f64s([7.5, -7.5]), dmb = _f64s([2.0, 2.0]);
  final ca = _f32s([1.0, double.nan, 3.0, -1.0]);
  final cb = _f32s([2.0, 1.0, 3.0, double.nan]);
  final dca1 = _f64s([1.0, double.nan]), dcb1 = _f64s([2.0, 1.0]);
  final dca2 = _f64s([3.0, -1.0]), dcb2 = _f64s([3.0, double.nan]);

  final out = <_Case>[];
  for (final op in _commonOps) {
    final cmm = _intCmpMinMax(op);
    if (cmm != null) {
      out.add(_Case(op, ia, ib, cmm));
      out.add(_Case(op, ia, ic, cmm));
      out.add(_Case(op, ib, ia, cmm));
      continue;
    }

    final fp = _fpOp(op);
    if (fp != null) {
      final ref = _fpRef(fp.f64, fp.f);
      final bytes = fp.scalar ? (fp.f64 ? 8 : 4) : 16;
      final name = op.name;
      if (name.startsWith('cmp')) {
        if (fp.f64) {
          out.add(_Case(op, dca1, dcb1, ref, bytes));
          out.add(_Case(op, dca2, dcb2, ref, bytes));
          out.add(_Case(op, dcb1, dca1, ref, bytes));
        } else {
          out.add(_Case(op, ca, cb, ref, bytes));
          out.add(_Case(op, cb, ca, ref, bytes));
        }
      } else if (name.startsWith('mod')) {
        out.add(fp.f64
            ? _Case(op, dma, dmb, ref, bytes)
            : _Case(op, ma, mb, ref, bytes));
      } else {
        out.add(fp.f64
            ? _Case(op, da, db, ref, bytes)
            : _Case(op, fa, fb, ref, bytes));
      }
      continue;
    }

    final _Ref? ref = switch (op) {
      UniOpVVV.andU32 ||
      UniOpVVV.andU64 ||
      UniOpVVV.andF32 ||
      UniOpVVV.andF64 =>
        _lanes(1, false, (x, y) => x & y),
      UniOpVVV.orU32 ||
      UniOpVVV.orU64 ||
      UniOpVVV.orF32 ||
      UniOpVVV.orF64 =>
        _lanes(1, false, (x, y) => x | y),
      UniOpVVV.xorU32 ||
      UniOpVVV.xorU64 ||
      UniOpVVV.xorF32 ||
      UniOpVVV.xorF64 =>
        _lanes(1, false, (x, y) => x ^ y),
      UniOpVVV.andnU32 ||
      UniOpVVV.andnU64 ||
      UniOpVVV.andnF32 ||
      UniOpVVV.andnF64 =>
        _lanes(1, false, (x, y) => ~x & y),
      UniOpVVV.bicU32 ||
      UniOpVVV.bicU64 ||
      UniOpVVV.bicF32 ||
      UniOpVVV.bicF64 =>
        _lanes(1, false, (x, y) => x & ~y),
      UniOpVVV.avgrU8 => _lanes(1, false, (x, y) => (x + y + 1) >> 1),
      UniOpVVV.avgrU16 => _lanes(2, false, (x, y) => (x + y + 1) >> 1),
      UniOpVVV.addU8 => _lanes(1, false, (x, y) => x + y),
      UniOpVVV.addU16 => _lanes(2, false, (x, y) => x + y),
      UniOpVVV.addU32 => _lanes(4, false, (x, y) => x + y),
      UniOpVVV.addU64 => _lanes(8, true, (x, y) => x + y),
      UniOpVVV.subU8 => _lanes(1, false, (x, y) => x - y),
      UniOpVVV.subU16 => _lanes(2, false, (x, y) => x - y),
      UniOpVVV.subU32 => _lanes(4, false, (x, y) => x - y),
      UniOpVVV.subU64 => _lanes(8, true, (x, y) => x - y),
      UniOpVVV.addsI8 => _lanes(1, true, (x, y) => _sat(x + y, -128, 127)),
      UniOpVVV.addsU8 => _lanes(1, false, (x, y) => _sat(x + y, 0, 255)),
      UniOpVVV.addsI16 => _lanes(2, true, (x, y) => _sat(x + y, -32768, 32767)),
      UniOpVVV.addsU16 => _lanes(2, false, (x, y) => _sat(x + y, 0, 65535)),
      UniOpVVV.subsI8 => _lanes(1, true, (x, y) => _sat(x - y, -128, 127)),
      UniOpVVV.subsU8 => _lanes(1, false, (x, y) => _sat(x - y, 0, 255)),
      UniOpVVV.subsI16 => _lanes(2, true, (x, y) => _sat(x - y, -32768, 32767)),
      UniOpVVV.subsU16 => _lanes(2, false, (x, y) => _sat(x - y, 0, 65535)),
      UniOpVVV.mulU16 => _lanes(2, false, (x, y) => x * y),
      UniOpVVV.mulU32 => _lanes(4, false, (x, y) => x * y),
      UniOpVVV.mulU64 => _lanes(8, true, (x, y) => x * y),
      UniOpVVV.mulhI16 => _lanes(2, true, (x, y) => (x * y) >> 16),
      UniOpVVV.mulhU16 => _lanes(2, false, (x, y) => (x * y) >> 16),
      UniOpVVV.mulU64LoU32 => _lanes(8, true, (x, y) => x * (y & 0xFFFFFFFF)),
      UniOpVVV.mHAddI16I32 => (a, b) {
          final out = ByteData(16);
          final x = ByteData.sublistView(a), y = ByteData.sublistView(b);
          for (var i = 0; i < 16; i += 4) {
            final v =
                x.getInt16(i, Endian.little) * y.getInt16(i, Endian.little) +
                    x.getInt16(i + 2, Endian.little) *
                        y.getInt16(i + 2, Endian.little);
            out.setInt32(i, v.toSigned(32), Endian.little);
          }
          return out.buffer.asUint8List();
        },
      UniOpVVV.interleaveLoU8 => _interleave(1, false),
      UniOpVVV.interleaveHiU8 => _interleave(1, true),
      UniOpVVV.interleaveLoU16 => _interleave(2, false),
      UniOpVVV.interleaveHiU16 => _interleave(2, true),
      UniOpVVV.interleaveLoU32 ||
      UniOpVVV.interleaveLoF32 =>
        _interleave(4, false),
      UniOpVVV.interleaveHiU32 ||
      UniOpVVV.interleaveHiF32 =>
        _interleave(4, true),
      UniOpVVV.interleaveLoU64 ||
      UniOpVVV.interleaveLoF64 =>
        _interleave(8, false),
      UniOpVVV.interleaveHiU64 ||
      UniOpVVV.interleaveHiF64 =>
        _interleave(8, true),
      UniOpVVV.packsI16I8 => _pack(2, -128, 127),
      UniOpVVV.packsI16U8 => _pack(2, 0, 255),
      UniOpVVV.packsI32I16 => _pack(4, -32768, 32767),
      UniOpVVV.packsI32U16 => _pack(4, 0, 65535),
      UniOpVVV.combineLoHiU64 || UniOpVVV.combineLoHiF64 => (a, b) =>
          _u8([...b.sublist(8), ...a.sublist(0, 8)]),
      UniOpVVV.combineHiLoU64 || UniOpVVV.combineHiLoF64 => (a, b) =>
          _u8([...b.sublist(0, 8), ...a.sublist(8)]),
      UniOpVVV.hAddF64 => (a, b) {
          final x = Float64List.view(a.buffer, a.offsetInBytes, 2);
          final y = Float64List.view(b.buffer, b.offsetInBytes, 2);
          return _f64s([x[0] + x[1], y[0] + y[1]]);
        },
      // Indices are kept in [0, 16): the result of other indices differs
      // between pshufb, TBL and the SSE2 emulation.
      UniOpVVV.swizzlevU8 => (a, b) => _u8([for (final i in b) a[i]]),
      _ => null,
    };
    if (ref == null) continue;

    if (op == UniOpVVV.swizzlevU8) {
      final idx = _u8([3, 15, 0, 7, 7, 1, 14, 2, 9, 8, 13, 4, 12, 5, 11, 6]);
      out.add(_Case(op, ia, idx, ref));
    } else if (op == UniOpVVV.hAddF64 || op.name.endsWith('F64')) {
      out.add(_Case(op, da, db, ref));
    } else {
      out.add(_Case(op, ia, ib, ref));
      out.add(_Case(op, ib, ia, ref));
    }
  }
  return out;
}

String _hex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

/// Operand layouts: how `op(a, b)` is emitted and its result moved to dst.
final _layouts = <String,
    void Function(
        UniCompiler, UniOpVVV, BaseReg, BaseReg, BaseReg, BaseReg, BaseMem)>{
  'dst': (cc, op, d, a, b, c, m) => cc.emit3v(op, d, a, b),
  'dst=src1': (cc, op, d, a, b, c, m) {
    cc.emit3v(op, a, a, b);
    cc.emit2v(UniOpVV.mov, d, a);
  },
  'dst=src2': (cc, op, d, a, b, c, m) {
    cc.emit3v(op, b, a, b);
    cc.emit2v(UniOpVV.mov, d, b);
  },
  'src2=mem': (cc, op, d, a, b, c, m) => cc.emit3v(op, d, a, m),
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
  final cases = _cases();

  test('every shared UniOpVVV has a case', () {
    final covered = {for (final c in cases) c.op};
    expect(_commonOps.where((op) => !covered.contains(op)), isEmpty);
  });

  for (final fs in _featureSets.entries) {
    for (final layout in _layouts.entries) {
      group('UniOpVVV ${fs.key} ${layout.key}', () {
        for (final c in cases) {
          final name = '${c.op.name} ${_hex(c.a)} ${_hex(c.b)}';
          test(name, () {
            final r = runUjit(
                (cc, d, a, b, cv, m) => layout.value(cc, c.op, d, a, b, cv, m),
                c.a,
                c.b,
                c.b,
                features: fs.value);
            expect(_hex(r.sublist(0, c.bytes)),
                _hex(c.ref(c.a, c.b).sublist(0, c.bytes)));
          });
        }
      }, skip: skipUnlessJitHost);
    }
  }

  // 256-bit vectors (AVX2): UniCompiler ops work on each 128-bit lane, so the
  // expected result is the reference of each lane. The lanes get different
  // data: A = a|b and B = b|a (for swizzlevU8 B = b|b: B holds the indices,
  // which the reference requires to be in range).
  final host = hostIsX64 ? CpuInfo.host().features : null;
  for (final layout in _layouts.entries) {
    group('UniOpVVV avx2-256 ${layout.key}', () {
      for (final c in cases) {
        final name = '${c.op.name} ${_hex(c.a)} ${_hex(c.b)}';
        test(name, () {
          final hi = c.op == UniOpVVV.swizzlevU8 ? c.b : c.a;
          final a = Uint8List.fromList([...c.a, ...c.b]);
          final b = Uint8List.fromList([...c.b, ...hi]);
          final r = runUjit(
              (cc, d, va, vb, vc, m) =>
                  layout.value(cc, c.op, d, va, vb, vc, m),
              a,
              b,
              b,
              features: host,
              width: VecWidth.k256);
          final expected = [...c.ref(c.a, c.b), ...c.ref(c.b, hi)];
          if (c.bytes < 16) {
            expect(_hex(r.sublist(0, c.bytes)),
                _hex(Uint8List.fromList(expected.sublist(0, c.bytes))));
          } else {
            expect(_hex(r), _hex(Uint8List.fromList(expected)));
          }
        });
      }
    }, skip: host == null || !host.avx2 ? 'needs an AVX2 host' : null);
  }
}
