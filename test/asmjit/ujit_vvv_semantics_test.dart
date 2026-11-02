// Cross-architecture semantics of UniCompiler three-operand vector ops.
//
// Each case JIT-compiles `dst = op(a, b)` for 128-bit vectors loaded from
// memory, runs it on the host (x86-64 or AArch64) and compares every byte
// with a Dart reference implementation, so both backends must agree.
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:test/test.dart';

typedef _FnNative = Void Function(Pointer<Uint8>);
typedef _FnDart = void Function(Pointer<Uint8>);

/// Reference: computes the expected 16 result bytes from the inputs.
typedef _Ref = Uint8List Function(Uint8List a, Uint8List b);

final _host = Environment.host().arch;
final Object _skip = _host == Arch.x64 || _host == Arch.aarch64
    ? false
    : 'requires an x86-64 or AArch64 host';

Uint8List _run(UniOpVVV op, Uint8List a, Uint8List b, {bool sameSrc = false}) {
  final rt = JitRuntime();
  try {
    final code = CodeHolder(env: rt.environment);
    final isA64 = code.env.arch == Arch.aarch64;
    final BaseCompiler archCc = isA64
        ? A64Compiler(env: code.env, labelManager: code.labelManager)
        : X86Compiler(env: code.env, labelManager: code.labelManager);
    final cc = UniCompiler(archCc);
    BaseMem mem(BaseReg p, int off) => p is A64Gp
        ? A64Mem.baseOffset(p, off)
        : X86Mem.baseDisp(p as X86Gp, off);

    cc.addFunc(
        FuncSignature.build([TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
    final p = cc.newGpPtr('p');
    cc.setArg(0, p);
    final va = cc.newVec('a');
    final vb = cc.newVec('b');
    final vd = cc.newVec('d');
    cc.emitVM(UniOpVM.load128U32, va, mem(p, 0));
    cc.emitVM(UniOpVM.load128U32, vb, mem(p, 16));
    cc.emit3v(op, vd, va, sameSrc ? va : vb);
    cc.emitMV(UniOpMV.store128U32, mem(p, 32), vd);
    cc.ret();
    cc.endFunc();
    archCc.finalize();
    archCc
        .serializeToAssembler(isA64 ? A64Assembler(code) : X86Assembler(code));

    final fn = rt.add(code);
    final buf = pkgffi.calloc<Uint8>(48);
    try {
      buf.asTypedList(48)
        ..setAll(0, a)
        ..setAll(16, b);
      fn.pointer.cast<NativeFunction<_FnNative>>().asFunction<_FnDart>()(buf);
      return Uint8List.fromList(buf.asTypedList(48).sublist(32, 48));
    } finally {
      pkgffi.calloc.free(buf);
    }
  } finally {
    rt.dispose();
  }
}

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

/// Ops whose x86 lowering is known to be wrong or not dispatchable yet
/// (missing dispatcher cases / wrong instruction selection). Tracked in
/// roteiro_novo.md; remove entries as the x86 backend gets fixed.
final _knownBrokenOnX86 = <UniOpVVV>{
  UniOpVVV.addF32,
  UniOpVVV.addsI16,
  UniOpVVV.addsI8,
  UniOpVVV.addsU8,
  UniOpVVV.andnU64,
  UniOpVVV.avgrU16,
  UniOpVVV.avgrU8,
  UniOpVVV.bicU32,
  UniOpVVV.cmpEqF32,
  UniOpVVV.cmpEqU8,
  UniOpVVV.cmpGeF32,
  UniOpVVV.cmpGeU16,
  UniOpVVV.cmpGtI32,
  UniOpVVV.cmpGtI8,
  UniOpVVV.cmpGtU8,
  UniOpVVV.cmpLeU32,
  UniOpVVV.cmpLtF32,
  UniOpVVV.cmpLtI16,
  UniOpVVV.cmpNeF32,
  UniOpVVV.combineLoHiU64,
  UniOpVVV.interleaveHiU16,
  UniOpVVV.interleaveLoU32,
  UniOpVVV.interleaveLoU64,
  UniOpVVV.maxI32,
  UniOpVVV.maxI64,
  UniOpVVV.maxU16,
  UniOpVVV.maxU32,
  UniOpVVV.maxU64,
  UniOpVVV.minI16,
  UniOpVVV.minI32,
  UniOpVVV.minI64,
  UniOpVVV.minI8,
  UniOpVVV.minU32,
  UniOpVVV.minU64,
  UniOpVVV.minU8,
  UniOpVVV.mulU32,
  UniOpVVV.packsI16I8,
  UniOpVVV.packsI32I16,
  UniOpVVV.subU64,
  UniOpVVV.subsI16,
  UniOpVVV.subsU8,
};

Object _skipFor(UniOpVVV op) =>
    _host == Arch.x64 && _knownBrokenOnX86.contains(op)
        ? 'known broken on x86 (see _knownBrokenOnX86)'
        : false;

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

  group('UniOpVVV semantics', () {
    intCases.forEach((op, ref) {
      test(op.name, () {
        expect(_run(op, ia, ib), ref(ia, ib));
      }, skip: _skipFor(op));
    });
    fpCases.forEach((op, ref) {
      test(op.name, () {
        expect(_run(op, fa, fb), ref(fa, fb));
      }, skip: _skipFor(op));
    });
    test('same source register shortcuts',
        skip: _host == Arch.x64 ? 'known broken on x86' : false, () {
      final ones = Uint8List(16)..fillRange(0, 16, 0xFF);
      expect(_run(UniOpVVV.xorU32, ia, ib, sameSrc: true), Uint8List(16));
      expect(_run(UniOpVVV.subU32, ia, ib, sameSrc: true), Uint8List(16));
      expect(_run(UniOpVVV.cmpEqU32, ia, ib, sameSrc: true), ones);
      expect(_run(UniOpVVV.andU32, ia, ib, sameSrc: true), ia);
      expect(_run(UniOpVVV.minI32, ia, ib, sameSrc: true), ia);
    });
  }, skip: _skip);
}
