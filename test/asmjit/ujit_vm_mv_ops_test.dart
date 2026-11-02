// UniOpVM loads and UniOpMV stores shared by the x86 and AArch64 backends,
// executed on the host and compared with a Dart reference model.
//
// Every 128-bit load (plain, converting, inserting, broadcasting) and store
// (plain, extracting) runs at an aligned and at an unaligned address; on x86
// also with SSE2 only, SSE4.1 and the host features.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';
import '../support/ujit_run.dart';

Uint8List _u8(List<int> v) => Uint8List.fromList(v);

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

List<int> _zeros(int n) => List.filled(n, 0);

/// Widens [count] lanes of [inBytes] bytes from [m] to [outBytes] bytes.
List<int> _widen(
    List<int> m, int inBytes, int outBytes, bool signed, int count) {
  final src = ByteData.sublistView(Uint8List.fromList(m));
  final out = ByteData(16);
  for (var i = 0; i < count; i++) {
    final v = switch (inBytes) {
      1 => signed ? src.getInt8(i) : src.getUint8(i),
      2 => signed
          ? src.getInt16(i * 2, Endian.little)
          : src.getUint16(i * 2, Endian.little),
      _ => signed
          ? src.getInt32(i * 4, Endian.little)
          : src.getUint32(i * 4, Endian.little),
    };
    switch (outBytes) {
      case 2:
        out.setUint16(i * 2, v & 0xFFFF, Endian.little);
      case 4:
        out.setUint32(i * 4, v & 0xFFFFFFFF, Endian.little);
      default:
        out.setInt64(i * 8, v, Endian.little);
    }
  }
  return out.buffer.asUint8List();
}

/// Loads: op -> expected register from the 16 bytes at the address.
Map<UniOpVM, List<int> Function(List<int> m)> _loads() {
  final out = <UniOpVM, List<int> Function(List<int> m)>{
    UniOpVM.load8: (m) => [m[0], ..._zeros(15)],
    UniOpVM.load16U16: (m) => [...m.sublist(0, 2), ..._zeros(14)],
    UniOpVM.load32U32: (m) => [...m.sublist(0, 4), ..._zeros(12)],
    UniOpVM.load32F32: (m) => [...m.sublist(0, 4), ..._zeros(12)],
    UniOpVM.load64U32: (m) => [...m.sublist(0, 8), ..._zeros(8)],
    UniOpVM.load64U64: (m) => [...m.sublist(0, 8), ..._zeros(8)],
    UniOpVM.load64F32: (m) => [...m.sublist(0, 8), ..._zeros(8)],
    UniOpVM.load64F64: (m) => [...m.sublist(0, 8), ..._zeros(8)],
    UniOpVM.loadDup16: (m) => [for (var i = 0; i < 8; i++) ...m.sublist(0, 2)],
    UniOpVM.loadDup32: (m) => [for (var i = 0; i < 4; i++) ...m.sublist(0, 4)],
    UniOpVM.loadDup64: (m) => [for (var i = 0; i < 2; i++) ...m.sublist(0, 8)],
    UniOpVM.loadCvt16U8ToU64: (m) => _widen(m, 1, 8, false, 2),
    UniOpVM.loadCvtNU8ToU64: (m) => _widen(m, 1, 8, false, 2),
  };
  for (final op in [
    UniOpVM.load128U32,
    UniOpVM.load128U64,
    UniOpVM.load128F32,
    UniOpVM.load128F64,
    UniOpVM.loadNU32,
    UniOpVM.loadNU64,
    UniOpVM.loadNF32,
    UniOpVM.loadNF64,
  ]) {
    out[op] = (m) => m.sublist(0, 16);
  }
  // loadCvt{32,64,N}_{I,U}{8,16,32}To{I,U}{16,32,64}: memory size of the
  // 128-bit result, element sizes and signedness.
  for (final (inBits, outBits) in [(8, 16), (8, 32), (16, 32), (32, 64)]) {
    for (final signed in [true, false]) {
      final s = signed ? 'I' : 'U';
      final count = 128 ~/ outBits;
      for (final mem in ['32', '64', 'N']) {
        final name = 'loadCvt$mem$s${inBits}To$s$outBits';
        final op = UniOpVM.values.where((v) => v.name == name).firstOrNull;
        if (op == null) continue;
        // A 32-bit memory operand fills only part of the 128-bit result
        // (the rest is zero) unless it already fills it (8 -> 32 bit).
        final memBytes = mem == 'N' ? count * inBits ~/ 8 : int.parse(mem) ~/ 8;
        if (memBytes * outBits ~/ inBits > 16) continue;
        final lanes = memBytes * 8 ~/ inBits;
        out[op] = (m) => _widen(m, inBits ~/ 8, outBits ~/ 8, signed, lanes);
      }
    }
  }
  return out;
}

/// Stores: op -> number of bytes written from the low end of the register.
const _stores = <UniOpMV, int>{
  UniOpMV.store8: 1,
  UniOpMV.store16U16: 2,
  UniOpMV.store32U32: 4,
  UniOpMV.store32F32: 4,
  UniOpMV.store64U32: 8,
  UniOpMV.store64U64: 8,
  UniOpMV.store64F32: 8,
  UniOpMV.store64F64: 8,
  UniOpMV.store128U32: 16,
  UniOpMV.store128U64: 16,
  UniOpMV.store128F32: 16,
  UniOpMV.store128F64: 16,
  UniOpMV.storeNU32: 16,
  UniOpMV.storeNU64: 16,
  UniOpMV.storeNF32: 16,
  UniOpMV.storeNF64: 16,
};

final _featureSets = <String, CpuFeatures?>{
  if (hostIsX64) ...{
    'sse2': null,
    'sse4.1': const CpuFeatures(
        sse: true, sse2: true, sse3: true, ssse3: true, sse41: true),
  },
  'host': hostIsX64 ? CpuInfo.host().features : null,
};

BaseMem _offset(BaseMem m, int n) => m is X86Mem
    ? m.withDisplacement(m.displacement + n)
    : A64Mem.baseOffset((m as A64Mem).base as A64Gp, m.offset + n);

void main() {
  // `a` is the register input, `b` the bytes at the address (slot `c` and
  // the following bytes for the unaligned cases).
  final a = _u8(List.generate(16, (i) => 0xC0 + i));
  final mem = _u8([
    0x81, 0x7F, 0x02, 0xFE, 0x13, 0xE4, 0x75, 0x96, //
    0xA7, 0x58, 0x39, 0xCA, 0x1B, 0x8C, 0x6D, 0x4E,
  ]);
  final loads = _loads();

  for (final fs in _featureSets.entries) {
    group('UniOpVM ${fs.key}', () {
      loads.forEach((op, ref) {
        for (final off in [0, 3]) {
          test('${op.name} +$off', () {
            // The slot `c` holds `mem`; the unaligned cases read past it into
            // the output slot, which is written only at the end.
            final buf = Uint8List(32)..setAll(0, mem);
            final r = runUjit((cc, d, x, y, z, m) {
              cc.emitVM(op, d, _offset(m, off));
            }, a, a, buf.sublist(0, 16), features: fs.value);
            final window = [...mem, ..._zeros(16)].sublist(off, off + 16);
            // Bytes past `mem` are the zeroed output slot.
            expect(_hex(r), _hex(ref(window)));
          });
        }
      });
      test('load128 aligned', () {
        final r = runUjit((cc, d, x, y, z, m) {
          cc.emitVM(UniOpVM.load128U32, d, m, alignment: Alignment.byte16);
        }, a, a, mem, features: fs.value);
        expect(_hex(r), _hex(mem));
      });
    }, skip: skipUnlessJitHost);

    group('UniOpMV ${fs.key}', () {
      _stores.forEach((op, n) {
        for (final off in [0, 3]) {
          test('${op.name} +$off', () {
            final r = runUjit((cc, d, x, y, z, m) {
              cc.emitMV(op, _offset(m, off), x);
              cc.emitVM(UniOpVM.load128U32, d, m);
            }, a, a, mem, features: fs.value);
            final expected = Uint8List.fromList(mem);
            final end = off + n > 16 ? 16 : off + n;
            expected.setRange(off, end, a.sublist(0, end - off));
            expect(_hex(r), _hex(expected));
          });
        }
      });
      test('store128 aligned', () {
        final r = runUjit((cc, d, x, y, z, m) {
          cc.emitMV(UniOpMV.store128U32, m, x, alignment: Alignment.byte16);
          cc.emitVM(UniOpVM.load128U32, d, m);
        }, a, a, mem, features: fs.value);
        expect(_hex(r), _hex(a));
      });
    }, skip: skipUnlessJitHost);
  }
}
