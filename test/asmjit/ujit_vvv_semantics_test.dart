// Cross-architecture semantics of UniCompiler three-operand vector ops.
//
// Each case JIT-compiles `dst = op(a, b)` for 128-bit vectors loaded from
// memory, runs it on the host (x86-64 or AArch64) and compares every byte
// with a Dart reference implementation, so both backends must agree.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/ujit_run.dart';

/// Reference: computes the expected 16 result bytes from the inputs.
typedef _Ref = Uint8List Function(Uint8List a, Uint8List b);

final _host = Environment.host().arch;
final Object _skip = _host == Arch.x64 || _host == Arch.aarch64
    ? false
    : 'requires an x86-64 or AArch64 host';

Uint8List _run(UniOpVVV op, Uint8List a, Uint8List b,
        {bool sameSrc = false, CpuFeatures? features}) =>
    _runEmit((cc, d, x, y) => cc.emit3v(op, d, x, sameSrc ? x : y), a, b,
        features: features);

/// Memory operand of the `c` input slot (offset 32 of the argument buffer),
/// used as scratch by memory-load cases.
BaseMem _scratch(UniCompiler cc) => _scratchMem!;
BaseMem? _scratchMem;

/// JIT-compiles `emit(cc, dst, a, b)` on 128-bit vectors and runs it.
Uint8List _runEmit(
        void Function(UniCompiler cc, BaseReg d, BaseReg a, BaseReg b) emit,
        Uint8List a,
        Uint8List b,
        {CpuFeatures? features}) =>
    _runEmit3((cc, d, x, y, z) => emit(cc, d, x, y), a, b, Uint8List(16),
        features: features);

/// Like [_runEmit] with a third input vector `c`.
Uint8List _runEmit3(
        void Function(
                UniCompiler cc, BaseReg d, BaseReg a, BaseReg b, BaseReg c)
            emit,
        Uint8List a,
        Uint8List b,
        Uint8List c,
        {CpuFeatures? features}) =>
    runUjit((cc, d, x, y, z, m) {
      _scratchMem = m;
      emit(cc, d, x, y, z);
    }, a, b, c, features: features);

// --- reference helpers -------------------------------------------------------

/// Lane-wise integer op on lanes of [bytes] bytes ([signed] lanes).
_Ref _lanes(int bytes, bool signed, int Function(int x, int y) f) {
  return (a, b) {
    final out = ByteData(16);
    final da = ByteData.sublistView(a), db = ByteData.sublistView(b);
    for (int i = 0; i < 16; i += bytes) {
      int rd(ByteData d) => switch (bytes) {
            1 => signed ? d.getInt8(i) : d.getUint8(i),
            2 => signed
                ? d.getInt16(i, Endian.little)
                : d.getUint16(i, Endian.little),
            4 => signed
                ? d.getInt32(i, Endian.little)
                : d.getUint32(i, Endian.little),
            _ => d.getInt64(i, Endian.little),
          };
      final r = f(rd(da), rd(db));
      switch (bytes) {
        case 1:
          out.setUint8(i, r & 0xFF);
        case 2:
          out.setUint16(i, r & 0xFFFF, Endian.little);
        case 4:
          out.setUint32(i, r & 0xFFFFFFFF, Endian.little);
        default:
          out.setInt64(i, r, Endian.little);
      }
    }
    return out.buffer.asUint8List();
  };
}

/// Unsigned 64-bit compare helper (Dart ints are signed 64-bit).
int _cmpU64(int x, int y) =>
    (x ^ 0x8000000000000000).compareTo(y ^ 0x8000000000000000);

int _sat(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

_Ref _f32(double Function(double x, double y) f) => (a, b) {
      final fa = Float32List.view(a.buffer, a.offsetInBytes, 4);
      final fb = Float32List.view(b.buffer, b.offsetInBytes, 4);
      final r = Float32List(4);
      for (int i = 0; i < 4; i++) {
        r[i] = f(fa[i], fb[i]);
      }
      return r.buffer.asUint8List();
    };

_Ref _f32Mask(bool Function(double x, double y) f) => (a, b) {
      final fa = Float32List.view(a.buffer, a.offsetInBytes, 4);
      final fb = Float32List.view(b.buffer, b.offsetInBytes, 4);
      final r = Uint32List(4);
      for (int i = 0; i < 4; i++) {
        r[i] = f(fa[i], fb[i]) ? 0xFFFFFFFF : 0;
      }
      return r.buffer.asUint8List();
    };

int _mask(bool c, int bytes) =>
    c ? (bytes == 8 ? -1 : (1 << (bytes * 8)) - 1) : 0;

Uint8List _bytes(List<int> v) => Uint8List.fromList(v);

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// x86 lowering variants: SSE2 baseline (no features) and the host CPU.
final _featureSets = <String, CpuFeatures?>{
  'baseline': null,
  if (_host == Arch.x64) 'host': CpuInfo.host().features,
};

void main() {
  // Inputs chosen to exercise signedness, saturation and overflow.
  final ia = _bytes([
    0x01, 0x7F, 0x80, 0xFF, 0x10, 0x00, 0xFE, 0x81, //
    0x33, 0xC0, 0x55, 0xAA, 0x00, 0x80, 0xFF, 0x7F,
  ]);
  final ib = _bytes([
    0x02, 0x01, 0x80, 0x01, 0xF0, 0x00, 0x03, 0x7F, //
    0x33, 0x40, 0xAA, 0x55, 0x01, 0x7F, 0xFF, 0x80,
  ]);
  final fa = Float32List.fromList([1.5, -2.0, 8.0, 0.25]).buffer.asUint8List();
  final fb = Float32List.fromList([0.5, -2.0, -4.0, 4.0]).buffer.asUint8List();

  final intCases = <UniOpVVV, _Ref>{
    UniOpVVV.addU8: _lanes(1, false, (x, y) => x + y),
    UniOpVVV.addU16: _lanes(2, false, (x, y) => x + y),
    UniOpVVV.addU32: _lanes(4, false, (x, y) => x + y),
    UniOpVVV.addU64: _lanes(8, true, (x, y) => x + y),
    UniOpVVV.subU8: _lanes(1, false, (x, y) => x - y),
    UniOpVVV.subU32: _lanes(4, false, (x, y) => x - y),
    UniOpVVV.subU64: _lanes(8, true, (x, y) => x - y),
    UniOpVVV.addsI8: _lanes(1, true, (x, y) => _sat(x + y, -128, 127)),
    UniOpVVV.addsU8: _lanes(1, false, (x, y) => _sat(x + y, 0, 255)),
    UniOpVVV.addsI16: _lanes(2, true, (x, y) => _sat(x + y, -32768, 32767)),
    UniOpVVV.subsU8: _lanes(1, false, (x, y) => _sat(x - y, 0, 255)),
    UniOpVVV.subsI16: _lanes(2, true, (x, y) => _sat(x - y, -32768, 32767)),
    UniOpVVV.mulU16: _lanes(2, false, (x, y) => x * y),
    UniOpVVV.mulU32: _lanes(4, false, (x, y) => x * y),
    UniOpVVV.minI8: _lanes(1, true, math.min),
    UniOpVVV.minU8: _lanes(1, false, math.min),
    UniOpVVV.minI16: _lanes(2, true, math.min),
    UniOpVVV.maxU16: _lanes(2, false, math.max),
    UniOpVVV.minI32: _lanes(4, true, math.min),
    UniOpVVV.maxI32: _lanes(4, true, math.max),
    UniOpVVV.minU32: _lanes(4, false, math.min),
    UniOpVVV.maxU32: _lanes(4, false, math.max),
    UniOpVVV.minI64: _lanes(8, true, math.min),
    UniOpVVV.maxI64: _lanes(8, true, math.max),
    UniOpVVV.minU64: _lanes(8, true, (x, y) => _cmpU64(x, y) <= 0 ? x : y),
    UniOpVVV.maxU64: _lanes(8, true, (x, y) => _cmpU64(x, y) >= 0 ? x : y),
    UniOpVVV.cmpEqU8: _lanes(1, false, (x, y) => _mask(x == y, 1)),
    UniOpVVV.cmpEqU32: _lanes(4, false, (x, y) => _mask(x == y, 4)),
    UniOpVVV.cmpGtI8: _lanes(1, true, (x, y) => _mask(x > y, 1)),
    UniOpVVV.cmpGtU8: _lanes(1, false, (x, y) => _mask(x > y, 1)),
    UniOpVVV.cmpGtI32: _lanes(4, true, (x, y) => _mask(x > y, 4)),
    UniOpVVV.cmpGeU16: _lanes(2, false, (x, y) => _mask(x >= y, 2)),
    UniOpVVV.cmpLtI16: _lanes(2, true, (x, y) => _mask(x < y, 2)),
    UniOpVVV.cmpLeU32: _lanes(4, false, (x, y) => _mask(x <= y, 4)),
    UniOpVVV.andU32: _lanes(1, false, (x, y) => x & y),
    UniOpVVV.orU64: _lanes(1, false, (x, y) => x | y),
    UniOpVVV.xorU32: _lanes(1, false, (x, y) => x ^ y),
    UniOpVVV.andnU64: _lanes(1, false, (x, y) => ~x & y),
    UniOpVVV.bicU32: _lanes(1, false, (x, y) => x & ~y),
    UniOpVVV.avgrU8: _lanes(1, false, (x, y) => (x + y + 1) >> 1),
    UniOpVVV.avgrU16: _lanes(2, false, (x, y) => (x + y + 1) >> 1),
    UniOpVVV.interleaveLoU32: (a, b) => _bytes([
          ...a.sublist(0, 4), ...b.sublist(0, 4), //
          ...a.sublist(4, 8), ...b.sublist(4, 8),
        ]),
    UniOpVVV.interleaveHiU16: (a, b) => _bytes([
          for (int i = 8; i < 16; i += 2) ...[a[i], a[i + 1], b[i], b[i + 1]],
        ]),
    UniOpVVV.interleaveLoU64: (a, b) =>
        _bytes([...a.sublist(0, 8), ...b.sublist(0, 8)]),
    UniOpVVV.combineLoHiU64: (a, b) =>
        _bytes([...b.sublist(8, 16), ...a.sublist(0, 8)]),
    UniOpVVV.packsI32I16: (a, b) {
      final out = ByteData(16);
      for (int i = 0; i < 8; i++) {
        final src = i < 4 ? a : b;
        final v =
            ByteData.sublistView(src).getInt32((i % 4) * 4, Endian.little);
        out.setInt16(i * 2, _sat(v, -32768, 32767), Endian.little);
      }
      return out.buffer.asUint8List();
    },
    UniOpVVV.packsI16I8: (a, b) {
      final out = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        final src = i < 8 ? a : b;
        final v =
            ByteData.sublistView(src).getInt16((i % 8) * 2, Endian.little);
        out[i] = _sat(v, -128, 127) & 0xFF;
      }
      return out;
    },
  };

  final fpCases = <UniOpVVV, _Ref>{
    UniOpVVV.addF32: _f32((x, y) => x + y),
    UniOpVVV.subF32: _f32((x, y) => x - y),
    UniOpVVV.mulF32: _f32((x, y) => x * y),
    UniOpVVV.divF32: _f32((x, y) => x / y),
    UniOpVVV.minF32: _f32(math.min),
    UniOpVVV.maxF32: _f32(math.max),
    UniOpVVV.cmpEqF32: _f32Mask((x, y) => x == y),
    UniOpVVV.cmpNeF32: _f32Mask((x, y) => x != y),
    UniOpVVV.cmpLtF32: _f32Mask((x, y) => x < y),
    UniOpVVV.cmpGeF32: _f32Mask((x, y) => x >= y),
  };

  // emit2vi cases: (op, imm, reference on `a`).
  final vviCases = <String, (UniOpVVI, int, Uint8List Function(Uint8List))>{
    'sllU32 #7': (
      UniOpVVI.sllU32,
      7,
      (a) => _lanes(4, false, (x, _) => x << 7)(a, a)
    ),
    'srlU32 #9': (
      UniOpVVI.srlU32,
      9,
      (a) => _lanes(4, false, (x, _) => x >> 9)(a, a)
    ),
    'sraI32 #3': (
      UniOpVVI.sraI32,
      3,
      (a) => _lanes(4, true, (x, _) => x >> 3)(a, a)
    ),
    'sllU16 #4': (
      UniOpVVI.sllU16,
      4,
      (a) => _lanes(2, false, (x, _) => x << 4)(a, a)
    ),
    'srlU64 #12': (
      UniOpVVI.srlU64,
      12,
      (a) => _bytes([
            for (final lane in [0, 8])
              ...(ByteData(8)
                    ..setUint64(
                        0,
                        ByteData.sublistView(a)
                                .getUint64(lane, Endian.little) >>>
                            12,
                        Endian.little))
                  .buffer
                  .asUint8List()
          ])
    ),
    'sllbU128 #3': (
      UniOpVVI.sllbU128,
      3,
      (a) => _bytes([0, 0, 0, ...a.sublist(0, 13)])
    ),
    'srlbU128 #5': (
      UniOpVVI.srlbU128,
      5,
      (a) => _bytes([...a.sublist(5), 0, 0, 0, 0, 0])
    ),
    'swizzleU32x4 [2,0,3,1]': (
      UniOpVVI.swizzleU32x4,
      swizzle4(1, 3, 0, 2).value,
      (a) => _bytes([
            ...a.sublist(8, 12),
            ...a.sublist(0, 4),
            ...a.sublist(12, 16),
            ...a.sublist(4, 8)
          ])
    ),
    'swizzleU32x4 rotate 1': (
      UniOpVVI.swizzleU32x4,
      swizzle4(0, 3, 2, 1).value,
      (a) => _bytes([...a.sublist(4), ...a.sublist(0, 4)])
    ),
    'swizzleU64x2 swap': (
      UniOpVVI.swizzleU64x2,
      swizzle2(0, 1).value,
      (a) => _bytes([...a.sublist(8), ...a.sublist(0, 8)])
    ),
  };

  // emit2v cases: (op, input, reference, bytes compared from the low end).
  Uint8List f32s(List<double> v) =>
      Float32List.fromList(v).buffer.asUint8List();
  Uint8List f64s(List<double> v) =>
      Float64List.fromList(v).buffer.asUint8List();
  Uint8List i32s(List<int> v) => Int32List.fromList(v).buffer.asUint8List();
  List<double> rf32(Uint8List b) =>
      Float32List.view(b.buffer, b.offsetInBytes, 4);
  final fin = f32s([1.5, -2.5, 3.75, -0.25]);
  final fin64 = f64s([2.5, -7.25]);
  final vvCases =
      <String, (UniOpVV, Uint8List, Uint8List Function(Uint8List), int)>{
    'absI8': (
      UniOpVV.absI8,
      ia,
      (a) => _lanes(1, true, (x, _) => x.abs())(a, a),
      16
    ),
    'absI16': (
      UniOpVV.absI16,
      ia,
      (a) => _lanes(2, true, (x, _) => x.abs())(a, a),
      16
    ),
    'absI32': (
      UniOpVV.absI32,
      ia,
      (a) => _lanes(4, true, (x, _) => x.abs())(a, a),
      16
    ),
    'notU32': (
      UniOpVV.notU32,
      ia,
      (a) => _lanes(1, false, (x, _) => ~x)(a, a),
      16
    ),
    'broadcastU8': (
      UniOpVV.broadcastU8,
      ia,
      (a) => Uint8List(16)..fillRange(0, 16, a[0]),
      16
    ),
    'broadcastU16': (
      UniOpVV.broadcastU16,
      ia,
      (a) => _bytes([for (int i = 0; i < 8; i++) ...a.sublist(0, 2)]),
      16
    ),
    'broadcastU32': (
      UniOpVV.broadcastU32,
      ia,
      (a) => _bytes([for (int i = 0; i < 4; i++) ...a.sublist(0, 4)]),
      16
    ),
    'broadcastU64': (
      UniOpVV.broadcastU64,
      ia,
      (a) => _bytes([...a.sublist(0, 8), ...a.sublist(0, 8)]),
      16
    ),
    'cvtU8LoToU16': (
      UniOpVV.cvtU8LoToU16,
      ia,
      (a) => _bytes([
            for (int i = 0; i < 8; i++) ...[a[i], 0]
          ]),
      16
    ),
    'cvtI8LoToI16': (
      UniOpVV.cvtI8LoToI16,
      ia,
      (a) => _bytes([
            for (int i = 0; i < 8; i++) ...[a[i], a[i] >= 0x80 ? 0xFF : 0]
          ]),
      16
    ),
    'cvtI16HiToI32': (
      UniOpVV.cvtI16HiToI32,
      ia,
      (a) {
        final o = ByteData(16), d = ByteData.sublistView(a);
        for (int i = 0; i < 4; i++) {
          o.setInt32(
              i * 4, d.getInt16(8 + i * 2, Endian.little), Endian.little);
        }
        return o.buffer.asUint8List();
      },
      16
    ),
    'cvtU32LoToU64': (
      UniOpVV.cvtU32LoToU64,
      ia,
      (a) => _bytes(
          [...a.sublist(0, 4), 0, 0, 0, 0, ...a.sublist(4, 8), 0, 0, 0, 0]),
      16
    ),
    'cvtU8ToU32': (
      UniOpVV.cvtU8ToU32,
      ia,
      (a) => _bytes([
            for (int i = 0; i < 4; i++) ...[a[i], 0, 0, 0]
          ]),
      16
    ),
    'movU64': (
      UniOpVV.movU64,
      ia,
      (a) => _bytes([...a.sublist(0, 8), ...List.filled(8, 0)]),
      16
    ),
    'absF32': (
      UniOpVV.absF32,
      fin,
      (a) => f32s([for (final x in rf32(a)) x.abs()]),
      16
    ),
    'negF32': (
      UniOpVV.negF32,
      fin,
      (a) => f32s([for (final x in rf32(a)) -x]),
      16
    ),
    'sqrtF32': (
      UniOpVV.sqrtF32,
      f32s([4, 9, 2.25, 16]),
      (a) => f32s([2, 3, 1.5, 4]),
      16
    ),
    'floorF32': (
      UniOpVV.floorF32,
      fin,
      (a) => f32s([for (final x in rf32(a)) x.floorToDouble()]),
      16
    ),
    'ceilF32': (
      UniOpVV.ceilF32,
      fin,
      (a) => f32s([for (final x in rf32(a)) x.ceilToDouble()]),
      16
    ),
    'truncF32': (
      UniOpVV.truncF32,
      fin,
      (a) => f32s([for (final x in rf32(a)) x.truncateToDouble()]),
      16
    ),
    'roundEvenF32': (
      UniOpVV.roundEvenF32,
      f32s([0.5, 1.5, 2.5, -2.5]),
      (a) => f32s([0, 2, 2, -2]),
      16
    ),
    'cvtI32ToF32': (
      UniOpVV.cvtI32ToF32,
      i32s([1, -2, 100000, -7]),
      (a) => f32s([1, -2, 100000, -7]),
      16
    ),
    'cvtTruncF32ToI32': (
      UniOpVV.cvtTruncF32ToI32,
      fin,
      (a) => i32s([1, -2, 3, 0]),
      16
    ),
    'cvtRoundF32ToI32': (
      UniOpVV.cvtRoundF32ToI32,
      f32s([1.5, -2.5, 3.75, -0.25]),
      (a) => i32s([2, -2, 4, 0]),
      16
    ),
    'cvtF32LoToF64': (UniOpVV.cvtF32LoToF64, fin, (a) => f64s([1.5, -2.5]), 16),
    'cvtF64ToF32Lo': (
      UniOpVV.cvtF64ToF32Lo,
      fin64,
      (a) => f32s([2.5, -7.25, 0, 0]),
      8
    ),
    'sqrtF64S (low lane)': (
      UniOpVV.sqrtF64S,
      f64s([6.25, 1]),
      (a) => f64s([2.5, 0]),
      8
    ),
    'floorF64': (
      UniOpVV.floorF64,
      f64s([-2.5, 7.75]),
      (a) => f64s([-3, 7]),
      16
    ),
    'ceilF64': (UniOpVV.ceilF64, f64s([-2.5, 7.25]), (a) => f64s([-2, 8]), 16),
    'truncF64': (
      UniOpVV.truncF64,
      f64s([-2.75, 7.75]),
      (a) => f64s([-2, 7]),
      16
    ),
    'roundEvenF64': (
      UniOpVV.roundEvenF64,
      f64s([2.5, -3.5]),
      (a) => f64s([2, -4]),
      16
    ),
    'truncF32S (low lane)': (
      UniOpVV.truncF32S,
      f32s([-7.75, 0, 0, 0]),
      (a) => f32s([-7, 0, 0, 0]),
      4
    ),
    'truncF64S (low lane)': (
      UniOpVV.truncF64S,
      f64s([9.5, 0]),
      (a) => f64s([9, 0]),
      8
    ),
    'floorF32S (low lane)': (
      UniOpVV.floorF32S,
      f32s([-1.25, 0, 0, 0]),
      (a) => f32s([-2, 0, 0, 0]),
      4
    ),
    'roundHalfUpF32': (
      UniOpVV.roundHalfUpF32,
      f32s([2.5, -2.5, 1.4, -1.6]),
      (a) => f32s([3, -2, 1, -2]),
      16
    ),
    'roundHalfUpF64': (
      UniOpVV.roundHalfUpF64,
      f64s([0.5, -3.5]),
      (a) => f64s([1, -3]),
      16
    ),
    'rcpF32': (
      UniOpVV.rcpF32,
      f32s([2, 4, 0.5, -8]),
      (a) => f32s([0.5, 0.25, 2, -0.125]),
      16
    ),
    'rcpF64': (UniOpVV.rcpF64, f64s([4, -0.25]), (a) => f64s([0.25, -4]), 16),
    'absF32S (low lane)': (
      UniOpVV.absF32S,
      fin,
      (a) => f32s([1.5, 0, 0, 0]),
      4
    ),
  };

  Uint8List w32(Uint8List v, int i) => v.sublist(i * 4, i * 4 + 4);
  Uint8List w64(Uint8List v, int i) => v.sublist(i * 8, i * 8 + 8);
  final fa4 = Float32List.fromList([1.5, -2.0, 4.0, 0.5]).buffer.asUint8List();
  final fb4 = Float32List.fromList([2.0, 3.0, -0.25, 8.0]).buffer.asUint8List();
  final fc4 = Float32List.fromList([0.5, 1.0, 2.0, -3.0]).buffer.asUint8List();
  final da2 = Float64List.fromList([1.5, -2.0]).buffer.asUint8List();
  final db2 = Float64List.fromList([4.0, 0.25]).buffer.asUint8List();
  final dc2 = Float64List.fromList([-1.0, 3.0]).buffer.asUint8List();
  final mask = _bytes([for (int i = 0; i < 16; i++) i % 3 == 0 ? 0xFF : 0x00]);
  List<double> f4(Uint8List b) =>
      Float32List.view(b.buffer, b.offsetInBytes, 4);
  List<double> f2(Uint8List b) =>
      Float64List.view(b.buffer, b.offsetInBytes, 2);

  // emit3vi / emit4v cases: (emit, a, b, c, reference).
  final vvvCases = <String,
      (
    void Function(UniCompiler, BaseReg, BaseReg, BaseReg, BaseReg),
    Uint8List,
    Uint8List,
    Uint8List,
    Uint8List Function(Uint8List, Uint8List, Uint8List)
  )>{
    'interleaveShuffleU32x4 [1,3 | 0,2]': (
      (cc, d, a, b, c) => cc.emit3vi(UniOpVVVI.interleaveShuffleU32x4, d, a, b,
          1 | (3 << 2) | (0 << 4) | (2 << 6)),
      ia,
      ib,
      ia,
      (a, b, c) =>
          _bytes([...w32(a, 1), ...w32(a, 3), ...w32(b, 0), ...w32(b, 2)])
    ),
    'interleaveShuffleF32x4 [0,0 | 3,1]': (
      (cc, d, a, b, c) => cc.emit3vi(UniOpVVVI.interleaveShuffleF32x4, d, a, b,
          0 | (0 << 2) | (3 << 4) | (1 << 6)),
      ia,
      ib,
      ia,
      (a, b, c) =>
          _bytes([...w32(a, 0), ...w32(a, 0), ...w32(b, 3), ...w32(b, 1)])
    ),
    'interleaveShuffleU64x2 [1 | 0]': (
      (cc, d, a, b, c) =>
          cc.emit3vi(UniOpVVVI.interleaveShuffleU64x2, d, a, b, 1),
      ia,
      ib,
      ia,
      (a, b, c) => _bytes([...w64(a, 1), ...w64(b, 0)])
    ),
    'blendvU8 (mask ? b : a)': (
      (cc, d, a, b, c) => cc.emit4v(UniOpVVVV.blendvU8, d, a, b, c),
      ia,
      ib,
      mask,
      (a, b, m) =>
          _bytes([for (int i = 0; i < 16; i++) m[i] != 0 ? b[i] : a[i]])
    ),
    'mAddU16 (a * b + c)': (
      (cc, d, a, b, c) => cc.emit4v(UniOpVVVV.mAddU16, d, a, b, c),
      ia,
      ib,
      ia,
      (a, b, c) => _lanes(2, false, (x, y) => x * y)(a, b)
          .let((ab) => _lanes(2, false, (x, y) => x + y)(ab, c))
    ),
    'mAddU32 (a * b + c)': (
      (cc, d, a, b, c) => cc.emit4v(UniOpVVVV.mAddU32, d, a, b, c),
      ia,
      ib,
      ib,
      (a, b, c) => _lanes(4, false, (x, y) => x * y)(a, b)
          .let((ab) => _lanes(4, false, (x, y) => x + y)(ab, c))
    ),
    'mAddF32 (a * b + c)': (
      (cc, d, a, b, c) => cc.emit4v(UniOpVVVV.mAddF32, d, a, b, c),
      fa4,
      fb4,
      fc4,
      (a, b, c) => Float32List.fromList(
              [for (int i = 0; i < 4; i++) f4(a)[i] * f4(b)[i] + f4(c)[i]])
          .buffer
          .asUint8List()
    ),
    'mSubF32 (a * b - c)': (
      (cc, d, a, b, c) => cc.emit4v(UniOpVVVV.mSubF32, d, a, b, c),
      fa4,
      fb4,
      fc4,
      (a, b, c) => Float32List.fromList(
              [for (int i = 0; i < 4; i++) f4(a)[i] * f4(b)[i] - f4(c)[i]])
          .buffer
          .asUint8List()
    ),
    'mAddF64 (a * b + c)': (
      (cc, d, a, b, c) => cc.emit4v(UniOpVVVV.mAddF64, d, a, b, c),
      da2,
      db2,
      dc2,
      (a, b, c) => Float64List.fromList(
              [for (int i = 0; i < 2; i++) f2(a)[i] * f2(b)[i] + f2(c)[i]])
          .buffer
          .asUint8List()
    ),
  };

  // emitVM load-and-convert cases: (op, reference on the 16 source bytes).
  Uint8List widen(Uint8List src, int count, int from, int to, bool signed) {
    final o = ByteData(16), d = ByteData.sublistView(src);
    for (int i = 0; i < count; i++) {
      final v = switch (from) {
        1 => signed ? d.getInt8(i) : d.getUint8(i),
        2 => signed
            ? d.getInt16(i * 2, Endian.little)
            : d.getUint16(i * 2, Endian.little),
        _ => signed
            ? d.getInt32(i * 4, Endian.little)
            : d.getUint32(i * 4, Endian.little),
      };
      switch (to) {
        case 2:
          o.setUint16(i * 2, v & 0xFFFF, Endian.little);
        case 4:
          o.setUint32(i * 4, v & 0xFFFFFFFF, Endian.little);
        default:
          o.setInt64(i * 8, v, Endian.little);
      }
    }
    return o.buffer.asUint8List();
  }

  final vmCases = <UniOpVM, Uint8List Function(Uint8List)>{
    UniOpVM.loadCvt32U8ToU32: (a) => widen(a, 4, 1, 4, false),
    UniOpVM.loadCvt32I8ToI32: (a) => widen(a, 4, 1, 4, true),
    UniOpVM.loadCvt32U8ToU16: (a) => widen(a, 4, 1, 2, false),
    UniOpVM.loadCvt64U8ToU16: (a) => widen(a, 8, 1, 2, false),
    UniOpVM.loadCvt64I8ToI16: (a) => widen(a, 8, 1, 2, true),
    UniOpVM.loadCvt64U16ToU32: (a) => widen(a, 4, 2, 4, false),
    UniOpVM.loadCvt64I16ToI32: (a) => widen(a, 4, 2, 4, true),
    UniOpVM.loadCvt64U32ToU64: (a) => widen(a, 2, 4, 8, false),
    UniOpVM.loadCvt64I32ToI64: (a) => widen(a, 2, 4, 8, true),
    UniOpVM.loadCvtNU8ToU16: (a) => widen(a, 8, 1, 2, false),
    UniOpVM.loadCvt16U8ToU64: (a) => widen(a, 2, 1, 8, false),
  };

  // loadInsert: (op, idx, element bytes); dst starts as `ib`, memory = `ia`.
  final insertCases = <String, (UniOpVM, int, int)>{
    'loadInsertU8 [5]': (UniOpVM.loadInsertU8, 5, 1),
    'loadInsertU16 [3]': (UniOpVM.loadInsertU16, 3, 2),
    'loadInsertU32 [2]': (UniOpVM.loadInsertU32, 2, 4),
    'loadInsertF32 [1]': (UniOpVM.loadInsertF32, 1, 4),
    'loadInsertU64 [1]': (UniOpVM.loadInsertU64, 1, 8),
    'loadInsertF64 [0]': (UniOpVM.loadInsertF64, 0, 8),
    'loadInsertF32x2 [1]': (UniOpVM.loadInsertF32x2, 1, 8),
  };
  // storeExtract: (op, idx, element bytes); memory starts as `ib`, src = `ia`.
  final extractCases = <String, (UniOpMV, int, int)>{
    'storeExtractU16 [6]': (UniOpMV.storeExtractU16, 6, 2),
    'storeExtractU32 [3]': (UniOpMV.storeExtractU32, 3, 4),
    'storeExtractU64 [1]': (UniOpMV.storeExtractU64, 1, 8),
  };

  for (final fs in _featureSets.entries) {
    group('UniOpVVV semantics (${fs.key})', () {
      final f = fs.value;
      intCases.forEach((op, ref) {
        test(op.name, () {
          expect(_run(op, ia, ib, features: f), ref(ia, ib));
        });
      });
      fpCases.forEach((op, ref) {
        test(op.name, () {
          expect(_run(op, fa, fb, features: f), ref(fa, fb));
        });
      });
      vviCases.forEach((name, c) {
        test(name, () {
          expect(
              _runEmit((cc, d, x, y) => cc.emit2vi(c.$1, d, x, c.$2), ia, ib,
                  features: f),
              c.$3(ia));
        });
      });
      test('alignrU128 (palignr semantics: src1 high, src2 low)', () {
        expect(
            _runEmit(
                (cc, d, x, y) => cc.emit3vi(UniOpVVVI.alignrU128, d, x, y, 4),
                ia,
                ib,
                features: f),
            _bytes([...ib.sublist(4), ...ia.sublist(0, 4)]));
      });
      vvCases.forEach((name, c) {
        test(name, () {
          final r = _runEmit((cc, d, x, y) => cc.emit2v(c.$1, d, x), c.$2, c.$2,
              features: f);
          expect(r.sublist(0, c.$4), c.$3(c.$2).sublist(0, c.$4));
        });
      });
      vvvCases.forEach((name, c) {
        test(name, () {
          expect(_runEmit3(c.$1, c.$2, c.$3, c.$4, features: f),
              c.$5(c.$2, c.$3, c.$4));
        });
      });
      vmCases.forEach((op, ref) {
        test(op.name, () {
          // Loads from memory (the 16 bytes of `ia`) and converts.
          final r = _runEmit3((cc, d, x, y, z) {
            final p = cc;
            p.emitMV(UniOpMV.store128U32, _scratch(cc), x); // spill a to mem
            p.emitVM(op, d, _scratch(cc));
          }, ia, ib, ib, features: f);
          expect(r, ref(ia));
        });
      });
      insertCases.forEach((name, c) {
        test(name, () {
          final (op, idx, size) = c;
          final r = _runEmit3((cc, d, x, y, z) {
            cc.emitMV(UniOpMV.store128U32, _scratch(cc), x); // memory = a
            cc.emit2v(UniOpVV.mov, d, y); // dst = b
            cc.emitVM(op, d, _scratch(cc), idx: idx);
          }, ia, ib, ib, features: f);
          final expected = Uint8List.fromList(ib)
            ..setRange(idx * size, idx * size + size, ia);
          expect(r, expected);
        });
      });
      extractCases.forEach((name, c) {
        test(name, () {
          final (op, idx, size) = c;
          // memory = c (= b); store lane idx of a; read the memory back.
          final r = _runEmit3((cc, d, x, y, z) {
            cc.emitMV(op, _scratch(cc), x, idx: idx);
            cc.emitVM(UniOpVM.load128U32, d, _scratch(cc));
          }, ia, ib, ib, features: f);
          final expected = Uint8List.fromList(ib)
            ..setRange(0, size, ia.sublist(idx * size, idx * size + size));
          expect(r, expected);
        });
      });
      test('same source register shortcuts', () {
        final ones = Uint8List(16)..fillRange(0, 16, 0xFF);
        Uint8List same(UniOpVVV op) =>
            _run(op, ia, ib, sameSrc: true, features: f);
        expect(same(UniOpVVV.xorU32), Uint8List(16));
        expect(same(UniOpVVV.subU32), Uint8List(16));
        expect(same(UniOpVVV.cmpEqU32), ones);
        expect(same(UniOpVVV.andU32), ia);
        expect(same(UniOpVVV.minI32), ia);
      });
    }, skip: _skip);
  }
}
