// UniOpVV (two-operand vector) ops shared by the x86 and AArch64 backends,
// executed on the host and compared with a Dart reference model.
//
// Each op runs with a distinct destination, dst == src and a memory source
// (on x86 also with SSE2 only, SSE4.1 and the host features). The narrowing
// "Hi" conversions write the high half of the destination and keep its low
// half, so the destination is initialized first. Broadcasts are also checked
// from general purpose registers.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';
import '../support/ujit_run.dart';

/// Reference: result bytes from the source `a` and the initial dst `d`.
typedef _Ref = Uint8List Function(Uint8List a, Uint8List d);

class _Case {
  final UniOpVV op;
  final Uint8List a;
  final _Ref ref;

  /// Number of low bytes compared (scalar ops only define lane 0).
  final int bytes;

  _Case(this.op, this.a, this.ref, [this.bytes = 16]);
}

Uint8List _u8(List<int> v) => Uint8List.fromList(v);
Uint8List _f32s(List<double> v) => Float32List.fromList(v).buffer.asUint8List();
Uint8List _f64s(List<double> v) => Float64List.fromList(v).buffer.asUint8List();
List<double> _asF32(Uint8List b) =>
    Float32List.view(Uint8List.fromList(b).buffer).toList();
List<double> _asF64(Uint8List b) =>
    Float64List.view(Uint8List.fromList(b).buffer).toList();

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

_Ref _lanes(int bytes, bool signed, int Function(int x) f) => (a, _) {
      final d = ByteData.sublistView(a), out = ByteData(16);
      for (var i = 0; i < 16; i += bytes) {
        _wr(out, i, bytes, f(_rd(d, i, bytes, signed)));
      }
      return out.buffer.asUint8List();
    };

/// Widens the lanes of the low (or high) half of the source.
_Ref _widen(int inBytes, bool signed, bool hi) => (a, _) {
      final d = ByteData.sublistView(a), out = ByteData(16);
      final outBytes = inBytes * 2;
      for (var i = 0; i < 16 ~/ outBytes; i++) {
        _wr(out, i * outBytes, outBytes,
            _rd(d, (hi ? 8 : 0) + i * inBytes, inBytes, signed));
      }
      return out.buffer.asUint8List();
    };

/// Repeats the low [bytes] bytes of the source.
_Ref _broadcast(int bytes) =>
    (a, _) => _u8([for (var i = 0; i < 16; i++) a[i % bytes]]);

double _roundEven(double x) {
  final r = x.roundToDouble();
  if ((x - x.truncateToDouble()).abs() == 0.5) {
    return (x / 2).roundToDouble() * 2;
  }
  return r;
}

double _roundHalfAway(double x) {
  final r = (x.abs() + 0.5).floorToDouble();
  return x.isNegative ? -r : r;
}

/// Lane-wise float op; f32 results are rounded to single precision.
_Ref _fp(bool f64, double Function(double x) f) => (a, _) {
      if (f64) return _f64s(_asF64(a).map(f).toList());
      return _f32s(_asF32(a).map(f).toList());
    };

List<_Case> _cases() {
  final ia = _u8([
    0x01, 0x7F, 0x80, 0xFF, 0x10, 0x00, 0xFE, 0x81, //
    0x33, 0xC0, 0x55, 0xAA, 0x00, 0x80, 0xFF, 0x7F,
  ]);
  final i32 =
      Int32List.fromList([7, -3, 16777217, -2147483648]).buffer.asUint8List();
  // Ties, negative values below 1 (sign of a zero result) and non-ties.
  final r32 = _f32s([2.5, -2.5, -0.25, 3.75]);
  final r32b = _f32s([1.5, -1.5, 0.25, -3.75]);
  final r64 = _f64s([2.5, -0.25]);
  final r64b = _f64s([-2.5, 3.75]);
  final f32 = _f32s([2.25, -9.0, 0.5, 1e10]);
  final f64 = _f64s([2.25, -9.0]);
  final pos32 = _f32s([2.0, 9.0, 0.5, 1e10]);
  final pos64 = _f64s([2.0, 0.81]);
  final cvt32 = _f32s([2.5, -3.5, 1234.75, -0.75]);
  final cvt64 = _f64s([2.5, -3.5]);
  final cvt64b = _f64s([1234.75, -0.75]);

  final out = <_Case>[];
  void add(UniOpVV op, List<Uint8List> inputs, _Ref ref, [int bytes = 16]) {
    for (final a in inputs) {
      out.add(_Case(op, a, ref, bytes));
    }
  }

  add(UniOpVV.mov, [ia], (a, _) => a);
  add(UniOpVV.movU64, [ia],
      (a, _) => _u8([...a.sublist(0, 8), ...List.filled(8, 0)]));
  for (final (op, n) in [
    (UniOpVV.broadcastU8Z, 1),
    (UniOpVV.broadcastU16Z, 2),
    (UniOpVV.broadcastU8, 1),
    (UniOpVV.broadcastU16, 2),
    (UniOpVV.broadcastU32, 4),
    (UniOpVV.broadcastU64, 8),
    (UniOpVV.broadcastF32, 4),
    (UniOpVV.broadcastF64, 8),
  ]) {
    add(op, [ia], _broadcast(n));
  }
  for (final op in [
    UniOpVV.broadcastV128U32,
    UniOpVV.broadcastV128U64,
    UniOpVV.broadcastV128F32,
    UniOpVV.broadcastV128F64,
  ]) {
    add(op, [ia], (a, _) => a);
  }

  add(UniOpVV.absI8, [ia], _lanes(1, true, (x) => x.abs()));
  add(UniOpVV.absI16, [ia], _lanes(2, true, (x) => x.abs()));
  add(UniOpVV.absI32, [ia, i32], _lanes(4, true, (x) => x.abs()));
  add(UniOpVV.absI64, [ia], _lanes(8, true, (x) => x.abs()));
  for (final op in [
    UniOpVV.notU32,
    UniOpVV.notU64,
    UniOpVV.notF32,
    UniOpVV.notF64
  ]) {
    add(op, [ia], _lanes(1, false, (x) => ~x));
  }

  add(UniOpVV.cvtI8LoToI16, [ia], _widen(1, true, false));
  add(UniOpVV.cvtI8HiToI16, [ia], _widen(1, true, true));
  add(UniOpVV.cvtU8LoToU16, [ia], _widen(1, false, false));
  add(UniOpVV.cvtU8HiToU16, [ia], _widen(1, false, true));
  add(UniOpVV.cvtI16LoToI32, [ia], _widen(2, true, false));
  add(UniOpVV.cvtI16HiToI32, [ia], _widen(2, true, true));
  add(UniOpVV.cvtU16LoToU32, [ia], _widen(2, false, false));
  add(UniOpVV.cvtU16HiToU32, [ia], _widen(2, false, true));
  add(UniOpVV.cvtI32LoToI64, [ia], _widen(4, true, false));
  add(UniOpVV.cvtI32HiToI64, [ia], _widen(4, true, true));
  add(UniOpVV.cvtU32LoToU64, [ia], _widen(4, false, false));
  add(UniOpVV.cvtU32HiToU64, [ia], _widen(4, false, true));
  add(UniOpVV.cvtI8ToI32, [ia], (a, _) {
    final out = ByteData(16);
    for (var i = 0; i < 4; i++) {
      out.setInt32(i * 4, ByteData.sublistView(a).getInt8(i), Endian.little);
    }
    return out.buffer.asUint8List();
  });
  add(UniOpVV.cvtU8ToU32, [ia], (a, _) {
    final out = ByteData(16);
    for (var i = 0; i < 4; i++) {
      out.setUint32(i * 4, a[i], Endian.little);
    }
    return out.buffer.asUint8List();
  });

  // Float ops on 4 x f32 / 2 x f64; scalar variants only define lane 0.
  void fpOps(String name, double Function(double) f, List<Uint8List> in32,
      List<Uint8List> in64) {
    for (final (suffix, f64, scalar) in [
      ('F32S', false, true),
      ('F64S', true, true),
      ('F32', false, false),
      ('F64', true, false),
    ]) {
      final op = UniOpVV.values.byName('$name$suffix');
      add(op, f64 ? in64 : in32, _fp(f64, f), scalar ? (f64 ? 8 : 4) : 16);
    }
  }

  fpOps('abs', (x) => x.abs(), [f32, r32], [f64, r64]);
  fpOps('neg', (x) => -x, [f32, r32], [f64, r64]);
  fpOps('trunc', (x) => x.truncateToDouble(), [r32, r32b], [r64, r64b]);
  fpOps('floor', (x) => x.floorToDouble(), [r32, r32b], [r64, r64b]);
  fpOps('ceil', (x) => x.ceilToDouble(), [r32, r32b], [r64, r64b]);
  fpOps('roundEven', _roundEven, [r32, r32b], [r64, r64b]);
  fpOps('roundHalfAway', _roundHalfAway, [r32, r32b], [r64, r64b]);
  fpOps('roundHalfUp', (x) => (x + 0.5).floorToDouble(), [r32, r32b],
      [r64, r64b]);
  fpOps('sqrt', math.sqrt, [pos32], [pos64]);
  add(UniOpVV.rcpF32, [f32], _fp(false, (x) => 1 / x));
  add(UniOpVV.rcpF64, [f64], _fp(true, (x) => 1 / x));

  add(
      UniOpVV.cvtI32ToF32,
      [i32],
      (a, _) => _f32s(Int32List.view(Uint8List.fromList(a).buffer)
          .map((x) => x.toDouble())
          .toList()));
  add(
      UniOpVV.cvtTruncF32ToI32,
      [cvt32],
      (a, _) => Int32List.fromList(_asF32(a).map((x) => x.truncate()).toList())
          .buffer
          .asUint8List());
  add(
      UniOpVV.cvtRoundF32ToI32,
      [cvt32],
      (a, _) => Int32List.fromList(
              _asF32(a).map((x) => _roundEven(x).toInt()).toList())
          .buffer
          .asUint8List());
  add(UniOpVV.cvtF32ToF64S, [cvt32], (a, _) => _f64s([_asF32(a)[0]]), 8);
  add(UniOpVV.cvtF64ToF32S, [cvt64], (a, _) => _f32s([_asF64(a)[0]]), 4);
  add(UniOpVV.cvtF32LoToF64, [cvt32], (a, _) => _f64s(_asF32(a).sublist(0, 2)));
  add(UniOpVV.cvtF32HiToF64, [cvt32], (a, _) => _f64s(_asF32(a).sublist(2)));
  add(
      UniOpVV.cvtI32LoToF64,
      [i32],
      (a, _) => _f64s(Int32List.view(Uint8List.fromList(a).buffer)
          .sublist(0, 2)
          .map((x) => x.toDouble())
          .toList()));
  add(
      UniOpVV.cvtI32HiToF64,
      [i32],
      (a, _) => _f64s(Int32List.view(Uint8List.fromList(a).buffer)
          .sublist(2)
          .map((x) => x.toDouble())
          .toList()));

  // Narrowing: Lo writes the low 64 bits and zeroes the rest, Hi writes the
  // high 64 bits and keeps the low 64 bits of the destination.
  Uint8List lo(List<int> v) => _u8([...v, ...List.filled(8, 0)]);
  _Ref hiOf(List<int> Function(Uint8List a) f) =>
      (a, d) => _u8([...d.sublist(0, 8), ...f(a)]);
  List<int> toF32(Uint8List a) => _f32s(_asF64(a));
  List<int> truncI32(Uint8List a) =>
      Int32List.fromList(_asF64(a).map((x) => x.truncate()).toList())
          .buffer
          .asUint8List();
  List<int> roundI32(Uint8List a) =>
      Int32List.fromList(_asF64(a).map((x) => _roundEven(x).toInt()).toList())
          .buffer
          .asUint8List();
  add(UniOpVV.cvtF64ToF32Lo, [cvt64, cvt64b], (a, _) => lo(toF32(a)));
  add(UniOpVV.cvtF64ToF32Hi, [cvt64, cvt64b], hiOf(toF32));
  add(UniOpVV.cvtTruncF64ToI32Lo, [cvt64, cvt64b], (a, _) => lo(truncI32(a)));
  add(UniOpVV.cvtTruncF64ToI32Hi, [cvt64, cvt64b], hiOf(truncI32));
  add(UniOpVV.cvtRoundF64ToI32Lo, [cvt64, cvt64b], (a, _) => lo(roundI32(a)));
  add(UniOpVV.cvtRoundF64ToI32Hi, [cvt64, cvt64b], hiOf(roundI32));
  return out;
}

/// Ops that write only the high half of the destination.
const _hiNarrowing = {
  UniOpVV.cvtF64ToF32Hi,
  UniOpVV.cvtTruncF64ToI32Hi,
  UniOpVV.cvtRoundF64ToI32Hi,
};

/// 256-bit broadcasts need 256-bit vectors.
const _wideOnly = {
  UniOpVV.broadcastV256U32,
  UniOpVV.broadcastV256U64,
  UniOpVV.broadcastV256F32,
  UniOpVV.broadcastV256F64,
};

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
  final cases = _cases();
  // Initial destination of the high-half conversions.
  final dInit = _u8(List.generate(16, (i) => 0xA0 + i));

  test('every 128-bit UniOpVV has a case', () {
    final covered = {for (final c in cases) c.op};
    expect(
        UniOpVV.values
            .where((op) => !_wideOnly.contains(op) && !covered.contains(op)),
        isEmpty);
  });

  for (final fs in _featureSets.entries) {
    for (final layout in ['dst', 'dst=src', 'src=mem']) {
      group('UniOpVV ${fs.key} $layout', () {
        for (final c in cases) {
          test('${c.op.name} ${_hex(c.a)}', () {
            final hi = _hiNarrowing.contains(c.op);
            final r = runUjit((cc, d, a, b, cv, m) {
              switch (layout) {
                case 'dst':
                  if (hi) cc.emit2v(UniOpVV.mov, d, b);
                  cc.emit2v(c.op, d, a);
                case 'dst=src':
                  cc.emit2v(c.op, a, a);
                  cc.emit2v(UniOpVV.mov, d, a);
                default:
                  if (hi) cc.emit2v(UniOpVV.mov, d, b);
                  cc.emit2v(c.op, d, m);
              }
            }, c.a, dInit, c.a, features: fs.value);
            final d0 = layout == 'dst=src' ? c.a : dInit;
            expect(_hex(r.sublist(0, c.bytes)),
                _hex(c.ref(c.a, d0).sublist(0, c.bytes)));
          });
        }
      }, skip: skipUnlessJitHost);
    }

    group('UniOpVV ${fs.key} broadcast from GP', () {
      final value = _u8([0x81, 0x92, 0xA3, 0xB4, 0xC5, 0xD6, 0xE7, 0xF8]);
      for (final (op, n, load) in [
        (UniOpVV.broadcastU8Z, 1, UniOpRM.loadU8),
        (UniOpVV.broadcastU16Z, 2, UniOpRM.loadU16),
        (UniOpVV.broadcastU8, 1, UniOpRM.loadU64),
        (UniOpVV.broadcastU16, 2, UniOpRM.loadU64),
        (UniOpVV.broadcastU32, 4, UniOpRM.loadU64),
        (UniOpVV.broadcastU64, 8, UniOpRM.loadU64),
        (UniOpVV.broadcastF32, 4, UniOpRM.loadU64),
        (UniOpVV.broadcastF64, 8, UniOpRM.loadU64),
      ]) {
        test(op.name, () {
          final input = _u8([...value, ...List.filled(8, 0)]);
          final r = runUjit((cc, d, a, b, cv, m) {
            final g = cc.newGp64('g');
            cc.emitRM(load, g, m);
            cc.emit2v(op, d, g);
          }, input, input, input, features: fs.value);
          expect(_hex(r), _hex([for (var i = 0; i < 16; i++) value[i % n]]));
        });
      }
    }, skip: skipUnlessJitHost);
  }

  // 256-bit vectors (AVX2). Most ops work on each 128-bit lane; broadcasts
  // and the lo/hi conversions follow the upstream test references for a
  // 32-byte vector (lo/hi select a half of the whole vector), derived here
  // from the 128-bit references.
  final host = hostIsX64 ? CpuInfo.host().features : null;
  final dInit256 = _u8(List.generate(32, (i) => 0xA0 + i));
  final byOp = <UniOpVV, List<_Case>>{};
  for (final c in cases) {
    (byOp[c.op] ??= []).add(c);
  }
  _Ref refOf(UniOpVV op) => byOp[op]!.first.ref;
  for (final layout in ['dst', 'dst=src', 'src=mem']) {
    group('UniOpVV avx2-256 $layout', () {
      for (final (i, c) in cases.indexed) {
        test('${c.op.name} ${_hex(c.a)}', () {
          final a0 = c.a;
          final a1 =
              _otherInput(c, byOp[c.op]!, i - cases.indexOf(byOp[c.op]!.first));
          final a = _u8([...a0, ...a1]);
          final d0 = dInit256.sublist(0, 16), d1 = dInit256.sublist(16);
          final hi = _hiNarrowing.contains(c.op);
          final r = runUjit((cc, d, va, vb, cv, m) {
            switch (layout) {
              case 'dst':
                if (hi) cc.emit2v(UniOpVV.mov, d, vb);
                cc.emit2v(c.op, d, va);
              case 'dst=src':
                cc.emit2v(c.op, va, va);
                cc.emit2v(UniOpVV.mov, d, va);
              default:
                if (hi) cc.emit2v(UniOpVV.mov, d, vb);
                cc.emit2v(c.op, d, m);
            }
          }, a, dInit256, a, features: host, width: VecWidth.k256);
          final d0Init = layout == 'dst=src' ? a0 : d0;
          final d1Init = layout == 'dst=src' ? a1 : d1;
          final expected = _wideExpected(c, a0, a1, d0Init, d1Init, refOf);
          final n = c.bytes < 16 ? c.bytes : 32;
          expect(_hex(r.sublist(0, n)), _hex(expected.sublist(0, n)));
        });
      }
      for (final op in _wideOnly) {
        test('${op.name} (256-bit)', () {
          final a = _u8(List.generate(32, (i) => i * 7 + 1));
          final r = runUjit((cc, d, va, vb, cv, m) {
            switch (layout) {
              case 'dst':
                cc.emit2v(op, d, va);
              case 'dst=src':
                cc.emit2v(op, va, va);
                cc.emit2v(UniOpVV.mov, d, va);
              default:
                cc.emit2v(op, d, m);
            }
          }, a, dInit256, a, features: host, width: VecWidth.k256);
          expect(_hex(r), _hex(a));
        });
      }
    }, skip: (host?.avx2 ?? false) ? null : 'needs an AVX2 host');
  }
}

/// Input of the high 128-bit lane: another input of the same op, else a
/// value of the same domain (floats doubled, integers byte-reversed).
Uint8List _otherInput(_Case c, List<_Case> sameOp, int indexInOp) {
  if (sameOp.length > 1) return sameOp[(indexInOp + 1) % sameOp.length].a;
  final name = c.op.name;
  final isFloat = name.contains('F32') || name.contains('F64');
  if (!isFloat) return _u8(c.a.reversed.toList());
  final f64 = name.endsWith('F64') ||
      name.endsWith('F64S') ||
      name.startsWith('cvtF64') ||
      name.startsWith('cvtTruncF64') ||
      name.startsWith('cvtRoundF64');
  return f64
      ? _f64s(_asF64(c.a).map((x) => x * 2).toList())
      : _f32s(_asF32(c.a).map((x) => x * 2).toList());
}

const _widenLoHi = {
  UniOpVV.cvtI8LoToI16: UniOpVV.cvtI8HiToI16,
  UniOpVV.cvtU8LoToU16: UniOpVV.cvtU8HiToU16,
  UniOpVV.cvtI16LoToI32: UniOpVV.cvtI16HiToI32,
  UniOpVV.cvtU16LoToU32: UniOpVV.cvtU16HiToU32,
  UniOpVV.cvtI32LoToI64: UniOpVV.cvtI32HiToI64,
  UniOpVV.cvtU32LoToU64: UniOpVV.cvtU32HiToU64,
  UniOpVV.cvtF32LoToF64: UniOpVV.cvtF32HiToF64,
  UniOpVV.cvtI32LoToF64: UniOpVV.cvtI32HiToF64,
};

/// Narrowing "Lo" op of each "Hi" op.
const _narrowHiToLo = {
  UniOpVV.cvtF64ToF32Hi: UniOpVV.cvtF64ToF32Lo,
  UniOpVV.cvtTruncF64ToI32Hi: UniOpVV.cvtTruncF64ToI32Lo,
  UniOpVV.cvtRoundF64ToI32Hi: UniOpVV.cvtRoundF64ToI32Lo,
};

/// Expected 32 bytes of [c] at 256 bits for the lane inputs [a0] / [a1] and
/// the initial destination lanes [d0] / [d1].
Uint8List _wideExpected(_Case c, Uint8List a0, Uint8List a1, Uint8List d0,
    Uint8List d1, _Ref Function(UniOpVV) refOf) {
  final op = c.op;
  final zero = Uint8List(16);
  Uint8List cat(List<int> x, List<int> y) => _u8([...x, ...y]);

  if (op == UniOpVV.movU64) return cat(c.ref(a0, d0), zero);
  if (op.name.startsWith('broadcastV128')) return cat(a0, a0);
  if (op.name.startsWith('broadcast')) {
    return cat(c.ref(a0, d0), c.ref(a0, d0));
  }
  final hiOfLo = _widenLoHi[op];
  if (hiOfLo != null) return cat(c.ref(a0, d0), refOf(hiOfLo)(a0, d0));
  final loOfHi = _widenLoHi.entries.where((e) => e.value == op).firstOrNull;
  if (loOfHi != null) return cat(refOf(loOfHi.key)(a1, d1), c.ref(a1, d1));
  if (op == UniOpVV.cvtI8ToI32 || op == UniOpVV.cvtU8ToU32) {
    return cat(
        c.ref(a0, d0), c.ref(_u8([...a0.sublist(4), ...zero.sublist(12)]), d0));
  }
  // Narrowing: all four results go to the low (Lo) or high (Hi) 128 bits.
  if (op == UniOpVV.cvtF64ToF32Lo ||
      op == UniOpVV.cvtTruncF64ToI32Lo ||
      op == UniOpVV.cvtRoundF64ToI32Lo) {
    return cat(
        [...c.ref(a0, d0).sublist(0, 8), ...c.ref(a1, d1).sublist(0, 8)], zero);
  }
  final lo = _narrowHiToLo[op];
  if (lo != null) {
    return cat(d0, [
      ...refOf(lo)(a0, d0).sublist(0, 8),
      ...refOf(lo)(a1, d1).sublist(0, 8),
    ]);
  }
  // Element-wise (and scalar) ops: each lane.
  return cat(c.ref(a0, d0), c.ref(a1, d1));
}
