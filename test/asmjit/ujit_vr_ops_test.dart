// Runtime semantics of UniCompiler.emit2vs() ([UniOpVR]: GP <-> vector
// moves, element insertion/extraction and int/float conversions), on x86
// with SSE2 only, SSE4.1 and the host features, and on AArch64.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';
import '../support/ujit_run.dart';

final _featureSets = <String, CpuFeatures?>{
  if (hostIsX64) ...{
    'sse2': null,
    'sse4.1': const CpuFeatures(
        sse: true, sse2: true, sse3: true, ssse3: true, sse41: true),
  },
  'host': hostIsX64 ? CpuInfo.host().features : null,
};

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

/// 16 distinct bytes.
final _a = _bytes(List.generate(16, (i) => 0x10 + i * 0x11 & 0xFF));
final _b = _bytes(List.generate(16, (i) => 0xF0 - i));

/// Little-endian bytes of [v] ([n] bytes).
List<int> _le(int v, int n) =>
    [for (var i = 0; i < n; i++) (v >> (8 * i)) & 0xFF];

int _read(List<int> b, int at, int n) {
  var v = 0;
  for (var i = n - 1; i >= 0; i--) {
    v = (v << 8) | b[at + i];
  }
  return v;
}

Uint8List _f32(double v) => Uint8List.view((Float32List(4)..[0] = v).buffer);
Uint8List _f64(double v) => Uint8List.view((Float64List(2)..[0] = v).buffer);

void main() {
  for (final fs in _featureSets.entries) {
    group('UniOpVR ${fs.key}', () {
      for (final (op, n) in [
        (UniOpVR.extractU8, 1),
        (UniOpVR.extractU16, 2),
        (UniOpVR.extractU32, 4),
        (UniOpVR.extractU64, 8),
      ]) {
        for (var idx = 0; idx < 16 ~/ n; idx++) {
          test('${op.name}[$idx]', () {
            final r = runUjit((cc, d, a, b, c, m) {
              final g = cc.newGp64('g');
              cc
                ..emit2vs(op, g, a, idx)
                ..emit2vs(UniOpVR.movU64, d, g);
            }, _a, _b, _b, features: fs.value);
            expect(_read(r, 0, 8), _read(_a, idx * n, n));
          });
        }
      }

      for (final (op, n) in [
        (UniOpVR.insertU8, 1),
        (UniOpVR.insertU16, 2),
        (UniOpVR.insertU32, 4),
        (UniOpVR.insertU64, 8),
      ]) {
        for (var idx = 0; idx < 16 ~/ n; idx++) {
          test('${op.name}[$idx]', () {
            final value =
                _bytes(_le(0x8877665544332211, 8) + List.filled(8, 0));
            final r = runUjit((cc, d, a, b, c, m) {
              final g = cc.newGp64('g');
              cc
                ..emitRM(UniOpRM.loadU64, g, m)
                ..emit2v(UniOpVV.mov, d, b)
                ..emit2vs(op, d, g, idx);
            }, _a, _b, value, features: fs.value);
            final expected = Uint8List.fromList(_b)
              ..setRange(idx * n, idx * n + n, value);
            expect(r, expected);
          });
        }
      }

      for (final (op, n) in [
        (UniOpVR.movU32, 4),
        (UniOpVR.movU64, 8),
      ]) {
        test('${op.name} vec -> gp -> vec', () {
          final r = runUjit((cc, d, a, b, c, m) {
            final g = cc.newGp64('g');
            cc
              ..emit2vs(op, g, a)
              ..emit2vs(op, d, g);
          }, _a, _b, _b, features: fs.value);
          // The GP -> vector move clears the rest of the vector.
          expect(r, [..._a.sublist(0, n), ...List.filled(16 - n, 0)]);
        });
      }

      for (final bits in [32, 64]) {
        test('mov gp$bits -> vec -> gp$bits', () {
          final r = runUjit((cc, d, a, b, c, m) {
            final g = bits == 32 ? cc.newGp32('g') : cc.newGp64('g');
            final h = bits == 32 ? cc.newGp32('h') : cc.newGp64('h');
            final v = cc.newVec('v');
            cc
              ..emitRM(bits == 32 ? UniOpRM.loadU32 : UniOpRM.loadU64, g, m)
              ..emit2vs(UniOpVR.mov, v, g)
              ..emit2vs(UniOpVR.mov, h, v)
              ..emit2vs(bits == 32 ? UniOpVR.movU32 : UniOpVR.movU64, d, h);
          }, _a, _b, _a, features: fs.value);
          expect(r, [
            ..._a.sublist(0, bits ~/ 8),
            ...List.filled(16 - bits ~/ 8, 0),
          ]);
        });
      }

      for (final (op, bits, value) in [
        (UniOpVR.cvtIntToF32, 32, -123456),
        (UniOpVR.cvtIntToF64, 64, -123456789012),
      ]) {
        test(op.name, () {
          final r = runUjit((cc, d, a, b, c, m) {
            final g = cc.newGp64('g');
            cc
              ..emitRM(UniOpRM.loadU64, g, m)
              ..emit2vs(op, d, g);
          }, _a, _b, _bytes(_le(value, 8) + List.filled(8, 0)),
              features: fs.value);
          final expected =
              bits == 32 ? _f32(value.toDouble()) : _f64(value.toDouble());
          expect(r.sublist(0, bits ~/ 8), expected.sublist(0, bits ~/ 8));
        });
      }

      for (final (op, double v, int expected) in [
        (UniOpVR.cvtTruncF32ToInt, -3.75, -3),
        (UniOpVR.cvtRoundF32ToInt, 2.5, 2),
        (UniOpVR.cvtRoundF32ToInt, -3.75, -4),
        (UniOpVR.cvtTruncF64ToInt, 123456789.875, 123456789),
        (UniOpVR.cvtRoundF64ToInt, 3.5, 4),
      ]) {
        test('${op.name}($v)', () {
          final f32 =
              op == UniOpVR.cvtTruncF32ToInt || op == UniOpVR.cvtRoundF32ToInt;
          final input = Uint8List(16)..setAll(0, f32 ? _f32(v) : _f64(v));
          final r = runUjit((cc, d, a, b, c, m) {
            final g = cc.newGp64('g');
            cc
              ..emit2vs(op, g, a)
              ..emit2vs(UniOpVR.movU64, d, g);
          }, input, _b, _b, features: fs.value);
          expect(_read(r, 0, 8).toSigned(64), expected);
        });
      }
    }, skip: skipUnlessJitHost);
  }
}
