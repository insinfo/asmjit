// UniOpVVVV ops shared by the x86 and AArch64 backends, executed on the host
// and compared with a Dart reference model.
//
// The products of the float inputs are exact, so fused (FMA) and separate
// multiply + add give the same result. Each op runs with every register
// aliasing of dst and the sources and with memory src2/src3; on x86 also with
// SSE2 only, SSE4.1, AVX without FMA (on AVX2 hosts) and the host features.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';
import '../support/ujit_run.dart';

class _Case {
  final UniOpVVVV op;
  final Uint8List a, b, c;
  final Uint8List Function(Uint8List a, Uint8List b, Uint8List c) ref;
  final int bytes;
  _Case(this.op, this.a, this.b, this.c, this.ref, [this.bytes = 16]);
}

Uint8List _u8(List<int> v) => Uint8List.fromList(v);
Uint8List _f32s(List<double> v) => Float32List.fromList(v).buffer.asUint8List();
Uint8List _f64s(List<double> v) => Float64List.fromList(v).buffer.asUint8List();
List<double> _f32(Uint8List b) =>
    Float32List.view(Uint8List.fromList(b).buffer).toList();
List<double> _f64(Uint8List b) =>
    Float64List.view(Uint8List.fromList(b).buffer).toList();

List<_Case> _cases() {
  final out = <_Case>[];
  final ia = _u8(List.generate(16, (i) => 0x31 * i + 7));
  final ib = _u8(List.generate(16, (i) => 0x5B * i + 0x81));
  final ic = _u8(List.generate(16, (i) => 0x17 * i + 0xF0));
  // Masks with whole-byte 0x00/0xFF values (pblendvb uses the byte MSB, the
  // other lowerings select bits).
  final msk = _u8([for (var i = 0; i < 16; i++) (i * 5) % 3 == 0 ? 0xFF : 0]);
  out.add(_Case(
      UniOpVVVV.blendvU8,
      ia,
      ib,
      msk,
      (a, b, m) =>
          _u8([for (var i = 0; i < 16; i++) m[i] != 0 ? b[i] : a[i]])));

  Uint8List mla(Uint8List a, Uint8List b, Uint8List c, int bytes) {
    final x = ByteData.sublistView(a), y = ByteData.sublistView(b);
    final z = ByteData.sublistView(c), out = ByteData(16);
    for (var i = 0; i < 16; i += bytes) {
      if (bytes == 2) {
        out.setUint16(
            i,
            (x.getUint16(i, Endian.little) * y.getUint16(i, Endian.little) +
                    z.getUint16(i, Endian.little)) &
                0xFFFF,
            Endian.little);
      } else {
        out.setUint32(
            i,
            (x.getUint32(i, Endian.little) * y.getUint32(i, Endian.little) +
                    z.getUint32(i, Endian.little)) &
                0xFFFFFFFF,
            Endian.little);
      }
    }
    return out.buffer.asUint8List();
  }

  out.add(_Case(UniOpVVVV.mAddU16, ia, ib, ic, (a, b, c) => mla(a, b, c, 2)));
  out.add(_Case(UniOpVVVV.mAddU32, ia, ib, ic, (a, b, c) => mla(a, b, c, 4)));

  final fa = _f32s([1.5, -2.0, 3.0, 0.25]);
  final fb = _f32s([2.0, 4.5, -1.0, 8.0]);
  final fc = _f32s([0.5, 1.0, -3.0, 2.0]);
  final da = _f64s([1.5, -2.0]);
  final db = _f64s([2.0, 4.5]);
  final dc = _f64s([0.5, -3.0]);
  for (final (name, f) in [
    ('mAdd', (double a, double b, double c) => a * b + c),
    ('mSub', (double a, double b, double c) => a * b - c),
    ('nmAdd', (double a, double b, double c) => -a * b + c),
    ('nmSub', (double a, double b, double c) => -a * b - c),
  ]) {
    for (final (suffix, f64, scalar) in [
      ('F32S', false, true),
      ('F64S', true, true),
      ('F32', false, false),
      ('F64', true, false),
    ]) {
      final op = UniOpVVVV.values.byName('$name$suffix');
      if (f64) {
        out.add(_Case(op, da, db, dc, (a, b, c) {
          final x = _f64(a), y = _f64(b), z = _f64(c);
          return _f64s([for (var i = 0; i < 2; i++) f(x[i], y[i], z[i])]);
        }, scalar ? 8 : 16));
      } else {
        out.add(_Case(op, fa, fb, fc, (a, b, c) {
          final x = _f32(a), y = _f32(b), z = _f32(c);
          return _f32s([for (var i = 0; i < 4; i++) f(x[i], y[i], z[i])]);
        }, scalar ? 4 : 16));
      }
    }
  }
  return out;
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

final _host = hostIsX64 ? CpuInfo.host().features : null;

final _featureSets = <String, CpuFeatures?>{
  if (hostIsX64) ...{
    'sse2': null,
    'sse4.1': const CpuFeatures(
        sse: true, sse2: true, sse3: true, ssse3: true, sse41: true),
    if (_host!.avx2)
      'avx2-nofma': const CpuFeatures(
          sse: true,
          sse2: true,
          sse3: true,
          ssse3: true,
          sse41: true,
          sse42: true,
          popcnt: true,
          avx: true,
          avx2: true),
  },
  'host': _host,
};

void main() {
  final cases = _cases();

  test('every UniOpVVVV has a case', () {
    final covered = {for (final c in cases) c.op};
    expect(UniOpVVVV.values.where((op) => !covered.contains(op)), isEmpty);
  });

  for (final fs in _featureSets.entries) {
    for (final layout in [
      'dst',
      'dst=src1',
      'dst=src2',
      'dst=src3',
      'src2=mem',
      'src3=mem',
    ]) {
      group('UniOpVVVV ${fs.key} $layout', () {
        for (final c in cases) {
          test(c.op.name, () {
            final r = runUjit((cc, d, a, b, cv, m) {
              switch (layout) {
                case 'dst':
                  cc.emit4v(c.op, d, a, b, cv);
                case 'dst=src1':
                  cc.emit4v(c.op, a, a, b, cv);
                  cc.emit2v(UniOpVV.mov, d, a);
                case 'dst=src2':
                  cc.emit4v(c.op, b, a, b, cv);
                  cc.emit2v(UniOpVV.mov, d, b);
                case 'dst=src3':
                  cc.emit4v(c.op, cv, a, b, cv);
                  cc.emit2v(UniOpVV.mov, d, cv);
                case 'src2=mem':
                  // The memory slot is overwritten with `b` after `c` was
                  // loaded into its register.
                  cc.emitMV(UniOpMV.store128U32, m, b);
                  cc.emit4v(c.op, d, a, m, cv);
                default:
                  cc.emit4v(c.op, d, a, b, m);
              }
            }, c.a, c.b, c.c, features: fs.value);
            final expected = c.ref(c.a, c.b, c.c);
            expect(_hex(r.sublist(0, c.bytes)),
                _hex(expected.sublist(0, c.bytes)));
          });
        }
      }, skip: skipUnlessJitHost);
    }
  }
}
