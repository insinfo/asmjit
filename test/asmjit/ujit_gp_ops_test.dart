// General purpose UniCompiler ops (emit_2i, emit_3i, emit_rm, emit_mr,
// emit_m, cmov, select, j_if) shared by the x86 and AArch64 backends,
// executed on the host and compared with a Dart reference model.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:test/test.dart';

import '../support/host.dart';

typedef _FnNative = Int64 Function(Int64, Int64, Pointer<Uint8>);
typedef _FnDart = int Function(int, int, Pointer<Uint8>);

typedef _Body = void Function(
    UniCompiler cc, BaseReg dst, BaseReg a, BaseReg b, BaseMem mem);

/// JIT-compiles `int64 f(a, b, p)`: [body] computes `dst` from `a`, `b`
/// (registers of [bits] bits) and `mem` (the 16 bytes at `p`), and the
/// function returns `dst` (sign extended from [bits]).
int _run(CpuFeatures? features, int bits, _Body body, int a, int b,
    {List<int>? memBytes, List<int>? memOut}) {
  final rt = JitRuntime();
  try {
    final code = CodeHolder(env: rt.environment);
    final isA64 = code.env.arch == Arch.aarch64;
    final BaseCompiler archCc = isA64
        ? A64Compiler(env: code.env, labelManager: code.labelManager)
        : X86Compiler(env: code.env, labelManager: code.labelManager);
    final cc = UniCompiler(archCc, features: features);
    cc.addFunc(FuncSignature.build([TypeId.int64, TypeId.int64, TypeId.intPtr],
        TypeId.int64, CallConvId.cdecl));
    final a64 = cc.newGp64('a'), b64 = cc.newGp64('b');
    final p = cc.newGpPtr('p');
    cc.setArg(0, a64);
    cc.setArg(1, b64);
    cc.setArg(2, p);
    BaseReg narrow(BaseReg r) =>
        bits == 64 ? r : (isA64 ? (r as A64Gp).w : X86Gp.r32(r.id));
    final dst = cc.newGp64('dst');
    final mem = isA64
        ? A64Mem.baseOffset(p as A64Gp, 0)
        : X86Mem.baseDisp(p as X86Gp, 0);
    body(cc, narrow(dst), narrow(a64), narrow(b64), mem);
    if (bits == 32) {
      // Sign extend the 32-bit result for the comparison.
      final r = cc.newGp64('r');
      cc.emitMR(UniOpMR.storeU32, mem, narrow(dst));
      cc.emitRM(UniOpRM.loadI32, r, mem);
      cc.ret([r]);
    } else {
      cc.ret([dst]);
    }
    cc.endFunc();
    archCc.finalize();
    archCc
        .serializeToAssembler(isA64 ? A64Assembler(code) : X86Assembler(code));
    final fn = rt.add(code);
    final buf = pkgffi.calloc<Uint8>(16);
    try {
      if (memBytes != null) buf.asTypedList(16).setAll(0, memBytes);
      final r = fn.pointer
          .cast<NativeFunction<_FnNative>>()
          .asFunction<_FnDart>()(a, b, buf);
      memOut?.setAll(0, buf.asTypedList(16));
      return r;
    } finally {
      pkgffi.calloc.free(buf);
    }
  } finally {
    rt.dispose();
  }
}

int _wrap(int v, int bits) => bits == 64 ? v : v.toSigned(32);
int _u(int v, int bits) => bits == 64 ? v : v.toUnsigned(32);

int _cmpU(int x, int y, int bits) {
  final ux = _u(x, bits), uy = _u(y, bits);
  if (bits == 64) {
    return (ux ^ 0x8000000000000000).compareTo(uy ^ 0x8000000000000000);
  }
  return ux.compareTo(uy);
}

int _divU(int x, int y, int bits) {
  if (bits == 32) return _u(x, 32) ~/ _u(y, 32);
  // Unsigned 64-bit division of Dart's signed ints.
  final bx = BigInt.from(x).toUnsigned(64), by = BigInt.from(y).toUnsigned(64);
  return (bx ~/ by).toSigned(64).toInt();
}

int _modU(int x, int y, int bits) {
  if (bits == 32) return _u(x, 32) % _u(y, 32);
  final bx = BigInt.from(x).toUnsigned(64), by = BigInt.from(y).toUnsigned(64);
  return (bx % by).toSigned(64).toInt();
}

int _rot(int x, int n, int bits, bool left) {
  final ux = _u(x, bits);
  n %= bits;
  if (n == 0) return x;
  final mask = bits == 64 ? -1 : 0xFFFFFFFF;
  final r = left
      ? ((ux << n) | (ux >>> (bits - n))) & mask
      : ((ux >>> n) | (ux << (bits - n))) & mask;
  return r;
}

/// Reference of emit_3i on [bits]-bit registers.
int _ref3(UniOpRRR op, int x, int y, int bits) {
  final r = switch (op) {
    UniOpRRR.and => x & y,
    UniOpRRR.or => x | y,
    UniOpRRR.xor => x ^ y,
    UniOpRRR.bic => x & ~y,
    UniOpRRR.add => x + y,
    UniOpRRR.sub => x - y,
    UniOpRRR.mul => x * y,
    UniOpRRR.uDiv => _divU(x, y, bits),
    UniOpRRR.uMod => _modU(x, y, bits),
    UniOpRRR.sMin => _wrap(x, bits) < _wrap(y, bits) ? x : y,
    UniOpRRR.sMax => _wrap(x, bits) > _wrap(y, bits) ? x : y,
    UniOpRRR.uMin => _cmpU(x, y, bits) < 0 ? x : y,
    UniOpRRR.uMax => _cmpU(x, y, bits) > 0 ? x : y,
    UniOpRRR.sll => _u(x, bits) << (y % bits),
    UniOpRRR.srl => _u(x, bits) >>> (y % bits),
    UniOpRRR.sra => _wrap(x, bits) >> (y % bits),
    UniOpRRR.rol => _rot(x, y, bits, true),
    UniOpRRR.ror => _rot(x, y, bits, false),
    // Clamps a signed value to [0, b] (b >= 0).
    UniOpRRR.sBound =>
      _wrap(x, bits) < 0 ? 0 : (_wrap(x, bits) > _wrap(y, bits) ? y : x),
  };
  return _wrap(r, bits);
}

int _clz(int x, int bits) {
  final ux = _u(x, bits);
  for (var i = bits - 1; i >= 0; i--) {
    if ((ux >>> i) & 1 != 0) return bits - 1 - i;
  }
  return bits;
}

int _ctz(int x, int bits) {
  for (var i = 0; i < bits; i++) {
    if ((x >>> i) & 1 != 0) return i;
  }
  return bits;
}

int _bswap(int x, int bits) {
  var r = 0;
  for (var i = 0; i < bits ~/ 8; i++) {
    r = (r << 8) | ((x >>> (8 * i)) & 0xFF);
  }
  return r;
}

/// Reference of emit_2i on [bits]-bit registers.
int _ref2(UniOpRR op, int x, int bits) {
  final r = switch (op) {
    UniOpRR.abs => _wrap(x, bits).abs(),
    UniOpRR.neg => -x,
    UniOpRR.not => ~x,
    UniOpRR.bSwap => _bswap(x, bits),
    UniOpRR.clz => _clz(x, bits),
    UniOpRR.ctz => _ctz(x, bits),
    // x ^ (x >> (bits - 1)) (arithmetic): flips all bits of negative values.
    UniOpRR.reflect => x ^ (_wrap(x, bits) >> (bits - 1)),
    UniOpRR.mov => x,
  };
  return _wrap(r, bits);
}

final _values = <(int, int)>[
  (7, 3),
  (-5, 2),
  (100, -7),
  (0x7FFFFFF0, 0x13),
  (-0x80000000, 5),
  (0x123456789AB, 9),
  (-2, -3),
  (12, 12),
];

const _immediates = [
  0,
  1,
  2,
  3,
  5,
  9,
  7,
  16,
  127,
  128,
  1000,
  -1,
  -128,
  0x12345,
  0x5000,
];

/// x86: the SSE2 baseline (no BMI/BMI2/LZCNT/MOVBE) and the host features.
final _featureSets = <String, CpuFeatures?>{
  if (hostIsX64) 'baseline': null,
  'host': hostIsX64 ? CpuInfo.host().features : null,
};

void main() {
  for (final fs in _featureSets.entries) {
    group(fs.key, () => _suite(fs.value));
  }
}

void _suite(CpuFeatures? features) {
  final opsNeedingPositiveB = {UniOpRRR.uDiv, UniOpRRR.uMod};
  final shiftOps = {
    UniOpRRR.sll,
    UniOpRRR.srl,
    UniOpRRR.sra,
    UniOpRRR.rol,
    UniOpRRR.ror
  };

  for (final bits in [32, 64]) {
    group('emit_3i $bits-bit', () {
      for (final op in UniOpRRR.values) {
        for (final (x0, y0) in _values) {
          var y = y0;
          if (opsNeedingPositiveB.contains(op) && y <= 0) y = 3;
          if (shiftOps.contains(op)) y = y.abs() % bits;
          if (op == UniOpRRR.sBound) y = y.abs();
          final x = _wrap(x0, bits);
          final expected = _ref3(op, x, _wrap(y, bits), bits);
          for (final layout in ['rrr', 'dst=a', 'dst=b', 'mem', 'dst=a mem']) {
            test('${op.name} $layout $x $y', () {
              final mem = ByteData(16)..setInt64(0, y, Endian.little);
              final r = _run(features, bits, (cc, d, a, b, m) {
                switch (layout) {
                  case 'rrr':
                    cc.emit3i(op, d, a, b);
                  case 'dst=a':
                    cc.emit3i(op, a, a, b);
                    cc.emitMov(d, a);
                  case 'dst=b':
                    cc.emit3i(op, b, a, b);
                    cc.emitMov(d, b);
                  case 'mem':
                    cc.emit3i(op, d, a, m);
                  default:
                    cc.emit3i(op, a, a, m);
                    cc.emitMov(d, a);
                }
              }, x, y, memBytes: mem.buffer.asUint8List());
              expect(r, expected);
            });
          }
        }
        for (final imm0 in _immediates) {
          var imm = imm0;
          if (opsNeedingPositiveB.contains(op) && imm <= 0) continue;
          if (shiftOps.contains(op)) imm = imm.abs() % bits;
          if (op == UniOpRRR.sBound && imm < 0) continue;
          for (final (x0, _) in _values.take(5)) {
            final x = _wrap(x0, bits);
            final expected = _ref3(op, x, imm, bits);
            for (final layout in ['imm', 'dst=a imm']) {
              test('${op.name} $layout $x $imm', () {
                final r = _run(features, bits, (cc, d, a, b, m) {
                  if (layout == 'imm') {
                    cc.emit3i(op, d, a, Imm(imm));
                  } else {
                    cc.emit3i(op, a, a, Imm(imm));
                    cc.emitMov(d, a);
                  }
                }, x, 0);
                expect(r, expected);
              });
            }
          }
        }
      }
    }, skip: skipUnlessJitHost);

    group('emit_2i $bits-bit', () {
      for (final op in UniOpRR.values) {
        for (final (x0, _) in _values) {
          final x = _wrap(x0, bits);
          if ((op == UniOpRR.clz || op == UniOpRR.ctz) && x == 0) continue;
          final expected = _ref2(op, x, bits);
          for (final layout in ['rr', 'dst=src', 'mem']) {
            test('${op.name} $layout $x', () {
              final mem = ByteData(16)..setInt64(0, x, Endian.little);
              final r = _run(features, bits, (cc, d, a, b, m) {
                switch (layout) {
                  case 'rr':
                    cc.emit2i(op, d, a);
                  case 'dst=src':
                    cc.emit2i(op, a, a);
                    cc.emitMov(d, a);
                  default:
                    cc.emit2i(op, d, m);
                }
              }, x, 0, memBytes: mem.buffer.asUint8List());
              expect(r, expected);
            });
          }
        }
      }
    }, skip: skipUnlessJitHost);
  }

  group('emit_rm / emit_mr / emit_m', () {
    final bytes = [0x81, 0x92, 0xA3, 0xB4, 0xC5, 0xD6, 0xE7, 0xF8];
    final mem = [...bytes, ...List.filled(8, 0)];
    final d = ByteData.sublistView(Uint8List.fromList(mem));
    final loads = <UniOpRM, (int, int)>{
      UniOpRM.loadReg: (64, d.getInt64(0, Endian.little)),
      UniOpRM.loadI8: (64, d.getInt8(0)),
      UniOpRM.loadU8: (64, d.getUint8(0)),
      UniOpRM.loadI16: (64, d.getInt16(0, Endian.little)),
      UniOpRM.loadU16: (64, d.getUint16(0, Endian.little)),
      UniOpRM.loadI32: (64, d.getInt32(0, Endian.little)),
      UniOpRM.loadU32: (64, d.getUint32(0, Endian.little)),
      UniOpRM.loadI64: (64, d.getInt64(0, Endian.little)),
      UniOpRM.loadU64: (64, d.getInt64(0, Endian.little)),
    };
    loads.forEach((op, e) {
      test(op.name, () {
        final r = _run(
            features, e.$1, (cc, dst, a, b, m) => cc.emitRM(op, dst, m), 0, 0,
            memBytes: mem);
        expect(r, e.$2);
      });
    });
    for (final (op, base, expected) in [
      (UniOpRM.loadMergeU8, 0x1122334455667700, 0x1122334455667781),
      (UniOpRM.loadShiftU8, 0x0000001122334455, 0x0000112233445581),
      (UniOpRM.loadMergeU16, 0x1122334455660000, 0x1122334455669281),
      (UniOpRM.loadShiftU16, 0x0000001122334455, 0x0011223344559281),
    ]) {
      test(op.name, () {
        final r = _run(features, 64, (cc, dst, a, b, m) {
          cc.emitMov(dst, a);
          cc.emitRM(op, dst, m);
        }, base, 0, memBytes: mem);
        expect(r, expected);
      });
    }

    final value = 0x0102030405060708;
    for (final (op, n, add) in [
      (UniOpMR.storeReg, 8, false),
      (UniOpMR.storeU8, 1, false),
      (UniOpMR.storeU16, 2, false),
      (UniOpMR.storeU32, 4, false),
      (UniOpMR.storeU64, 8, false),
      (UniOpMR.addReg, 8, true),
      (UniOpMR.addU8, 1, true),
      (UniOpMR.addU16, 2, true),
      (UniOpMR.addU32, 4, true),
      (UniOpMR.addU64, 8, true),
    ]) {
      test(op.name, () {
        final out = List.filled(16, 0);
        _run(features, 64, (cc, dst, a, b, m) {
          cc.emitMR(op, m, a);
          cc.emitMov(dst, a);
        }, value, 0, memBytes: mem, memOut: out);
        final before = ByteData.sublistView(Uint8List.fromList(mem));
        final expected = Uint8List.fromList(mem);
        final ev = ByteData.sublistView(expected);
        final cur = n == 8
            ? before.getInt64(0, Endian.little)
            : n == 4
                ? before.getUint32(0, Endian.little)
                : n == 2
                    ? before.getUint16(0, Endian.little)
                    : before.getUint8(0);
        final v = add ? cur + value : value;
        switch (n) {
          case 1:
            ev.setUint8(0, v & 0xFF);
          case 2:
            ev.setUint16(0, v & 0xFFFF, Endian.little);
          case 4:
            ev.setUint32(0, v & 0xFFFFFFFF, Endian.little);
          default:
            ev.setInt64(0, v, Endian.little);
        }
        expect(out, expected);
      });
    }

    for (final (op, n) in [
      (UniOpM.storeZeroReg, 8),
      (UniOpM.storeZeroU8, 1),
      (UniOpM.storeZeroU16, 2),
      (UniOpM.storeZeroU32, 4),
      (UniOpM.storeZeroU64, 8),
    ]) {
      test(op.name, () {
        final out = List.filled(16, 0);
        _run(features, 64, (cc, dst, a, b, m) {
          cc.emitM(op, m);
          cc.emitMov(dst, a);
        }, 0, 0, memBytes: mem, memOut: out);
        expect(out, [...List.filled(n, 0), ...mem.sublist(n)]);
      });
    }
  }, skip: skipUnlessJitHost);

  group('conditions', () {
    // (condition factory, reference) on (a, b); conditions that modify `a`
    // (assign*) are checked through the flags only.
    final conds = <String,
        (UniCondition Function(Operand a, Operand b), bool Function(int, int))>{
      'cmp eq': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kEqual, a, b),
        (x, y) => x == y
      ),
      'cmp ne': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kNotEqual, a, b),
        (x, y) => x != y
      ),
      'cmp lt': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kSignedLT, a, b),
        (x, y) => x < y
      ),
      'cmp ge': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kSignedGE, a, b),
        (x, y) => x >= y
      ),
      'cmp gt': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kSignedGT, a, b),
        (x, y) => x > y
      ),
      'cmp le': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kSignedLE, a, b),
        (x, y) => x <= y
      ),
      'cmp ult': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kUnsignedLT, a, b),
        (x, y) => _cmpU(x, y, 64) < 0
      ),
      'cmp uge': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kUnsignedGE, a, b),
        (x, y) => _cmpU(x, y, 64) >= 0
      ),
      'cmp ugt': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kUnsignedGT, a, b),
        (x, y) => _cmpU(x, y, 64) > 0
      ),
      'cmp ule': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kUnsignedLE, a, b),
        (x, y) => _cmpU(x, y, 64) <= 0
      ),
      'test z': (
        (a, b) => UniCondition(UniOpCond.test, CondCode.kZero, a, b),
        (x, y) => x & y == 0
      ),
      'test nz': (
        (a, b) => UniCondition(UniOpCond.test, CondCode.kNotZero, a, b),
        (x, y) => x & y != 0
      ),
      'and z': (
        (a, b) => UniCondition(UniOpCond.assignAnd, CondCode.kZero, a, b),
        (x, y) => x & y == 0
      ),
      'or nz': (
        (a, b) => UniCondition(UniOpCond.assignOr, CondCode.kNotZero, a, b),
        (x, y) => x | y != 0
      ),
      'xor z': (
        (a, b) => UniCondition(UniOpCond.assignXor, CondCode.kZero, a, b),
        (x, y) => x ^ y == 0
      ),
      'add z': (
        (a, b) => UniCondition(UniOpCond.assignAdd, CondCode.kZero, a, b),
        (x, y) => x + y == 0
      ),
      'sub z': (
        (a, b) => UniCondition(UniOpCond.assignSub, CondCode.kZero, a, b),
        (x, y) => x - y == 0
      ),
    };
    final pairs = [
      (3, 3),
      (3, 5),
      (5, 3),
      (-1, 1),
      (1, -1),
      (0, 0),
      (-4, 4),
      (6, 2)
    ];
    conds.forEach((name, c) {
      for (final (x, y) in pairs) {
        test('select $name $x $y', () {
          final r = _run(features, 64, (cc, d, a, b, m) {
            final t = cc.newGp64('t'), f = cc.newGp64('f');
            cc.emitMov(t, Imm(111));
            cc.emitMov(f, Imm(222));
            cc.emitSelect(d, t, f, c.$1(a, b));
          }, x, y);
          expect(r, c.$2(x, y) ? 111 : 222);
        });
        test('cmov $name $x $y', () {
          final r = _run(features, 64, (cc, d, a, b, m) {
            final t = cc.newGp64('t');
            cc.emitMov(t, Imm(111));
            cc.emitMov(d, Imm(222));
            cc.emitCmov(d, t, c.$1(a, b));
          }, x, y);
          expect(r, c.$2(x, y) ? 111 : 222);
        });
        test('jIf $name $x $y', () {
          final r = _run(features, 64, (cc, d, a, b, m) {
            final l = cc.newLabel();
            cc.emitMov(d, Imm(111));
            cc.emitJIf(l, c.$1(a, b));
            cc.emitMov(d, Imm(222));
            cc.bind(l);
          }, x, y);
          expect(r, c.$2(x, y) ? 111 : 222);
        });
      }
    });
    // Conditions with an immediate (or a register) `b` that the backends
    // lower specially: bit tests, shifts, compares with encodable and
    // non-encodable immediates and XOR with -1.
    final immConds = <String,
        (
      UniCondition Function(Operand a, Operand b),
      Operand,
      bool Function(int)
    )>{
      'cmp eq 0': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kEqual, a, b),
        Imm(0),
        (x) => x == 0
      ),
      'cmp ne 0': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kNotEqual, a, b),
        Imm(0),
        (x) => x != 0
      ),
      'cmp lt 5': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kSignedLT, a, b),
        Imm(5),
        (x) => x < 5
      ),
      'cmp ult 0x5000': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kUnsignedLT, a, b),
        Imm(0x5000),
        (x) => _cmpU(x, 0x5000, 64) < 0
      ),
      'cmp gt -3': (
        (a, b) => UniCondition(UniOpCond.compare, CondCode.kSignedGT, a, b),
        Imm(-3),
        (x) => x > -3
      ),
      'test nz 0x10': (
        (a, b) => UniCondition(UniOpCond.test, CondCode.kNotZero, a, b),
        Imm(0x10),
        (x) => x & 0x10 != 0
      ),
      'test z 0x12345': (
        (a, b) => UniCondition(UniOpCond.test, CondCode.kZero, a, b),
        Imm(0x12345),
        (x) => x & 0x12345 == 0
      ),
      'and nz 0xFF': (
        (a, b) => UniCondition(UniOpCond.assignAnd, CondCode.kNotZero, a, b),
        Imm(0xFF),
        (x) => x & 0xFF != 0
      ),
      'xor z -1': (
        (a, b) => UniCondition(UniOpCond.assignXor, CondCode.kZero, a, b),
        Imm(-1),
        (x) => x == -1
      ),
      'shr z 4': (
        (a, b) => UniCondition(UniOpCond.assignShr, CondCode.kZero, a, b),
        Imm(4),
        (x) => x >>> 4 == 0
      ),
      for (final bit in [0, 3, 40, 63]) ...{
        'bt z $bit': (
          (a, b) => UniCondition(UniOpCond.bitTest, CondCode.kBTZero, a, b),
          Imm(bit),
          (x) => (x >>> bit) & 1 == 0
        ),
        'bt nz $bit': (
          (a, b) => UniCondition(UniOpCond.bitTest, CondCode.kBTNotZero, a, b),
          Imm(bit),
          (x) => (x >>> bit) & 1 != 0
        ),
      },
    };
    final immValues = [0, 1, 8, 0x10, 0xF0, -1, 1 << 40, 0x5000, -3, 0x12345];
    immConds.forEach((name, c) {
      for (final x in immValues) {
        test('select $name $x', () {
          final r = _run(features, 64, (cc, d, a, b, m) {
            final t = cc.newGp64('t'), f = cc.newGp64('f');
            cc.emitMov(t, Imm(111));
            cc.emitMov(f, Imm(222));
            cc.emitSelect(d, t, f, c.$1(a, c.$2));
          }, x, 0);
          expect(r, c.$3(x) ? 111 : 222);
        });
        test('jIf $name $x', () {
          final r = _run(features, 64, (cc, d, a, b, m) {
            final l = cc.newLabel();
            cc.emitMov(d, Imm(111));
            cc.emitJIf(l, c.$1(a, c.$2));
            cc.emitMov(d, Imm(222));
            cc.bind(l);
          }, x, 0);
          expect(r, c.$3(x) ? 111 : 222);
        });
      }
    });

    // Bit test and shift with the bit index / shift count in a register.
    for (final x in immValues) {
      for (final n in [0, 3, 40, 63]) {
        test('bt nz reg $x $n', () {
          final r = _run(features, 64, (cc, d, a, b, m) {
            final l = cc.newLabel();
            cc.emitMov(d, Imm(111));
            cc.emitJIf(
                l, UniCondition(UniOpCond.bitTest, CondCode.kBTNotZero, a, b));
            cc.emitMov(d, Imm(222));
            cc.bind(l);
          }, x, n);
          expect(r, (x >>> n) & 1 != 0 ? 111 : 222);
        });
        test('shr nz reg $x $n', () {
          final r = _run(features, 64, (cc, d, a, b, m) {
            final l = cc.newLabel();
            cc.emitMov(d, Imm(111));
            cc.emitJIf(
                l, UniCondition(UniOpCond.assignShr, CondCode.kNotZero, a, b));
            cc.emitMov(d, Imm(222));
            cc.bind(l);
          }, x, n);
          expect(r, x >>> n != 0 ? 111 : 222);
        });
      }
    }

    test('select with immediates', () {
      for (final (x, y) in pairs) {
        final r = _run(features, 64, (cc, d, a, b, m) {
          cc.emitSelect(d, Imm(7), Imm(-9),
              UniCondition(UniOpCond.compare, CondCode.kSignedLT, a, b));
        }, x, y);
        expect(r, x < y ? 7 : -9, reason: '$x $y');
      }
    });
  }, skip: skipUnlessJitHost);
}
