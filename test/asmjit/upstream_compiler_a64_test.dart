// Ports of the upstream AArch64 compiler tests
// (asmjit-testing/tests/asmjit_test_compiler_a64.cpp), compiled with
// A64Compiler and executed under the JIT on AArch64 hosts.
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import '../support/host.dart';

typedef _N0 = Uint32 Function();
typedef _D0 = int Function();
typedef _N1 = Uint32 Function(Uint32);
typedef _D1 = int Function(int);
typedef _N2 = Uint32 Function(Uint32, Uint32);
typedef _D2 = int Function(int, int);
typedef _N3 = Uint32 Function(Uint32, Uint32, Uint32);
typedef _D3 = int Function(int, int, int);
typedef _N4 = Uint32 Function(Uint32, Uint32, Uint32, Uint32);
typedef _D4 = int Function(int, int, int, int);
typedef _N5 = Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D5 = int Function(int, int, int, int, int);
typedef _N6 = Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D6 = int Function(int, int, int, int, int, int);
typedef _N7 = Uint32 Function(
    Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D7 = int Function(int, int, int, int, int, int, int);
typedef _N8 = Uint32 Function(
    Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D8 = int Function(int, int, int, int, int, int, int, int);
typedef _N9 = Uint32 Function(
    Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D9 = int Function(int, int, int, int, int, int, int, int, int);
typedef _N10 = Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Uint32,
    Uint32, Uint32, Uint32, Uint32);
typedef _D10 = int Function(int, int, int, int, int, int, int, int, int, int);
typedef _N11 = Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Uint32,
    Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D11 = int Function(
    int, int, int, int, int, int, int, int, int, int, int);
typedef _N12 = Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Uint32,
    Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D12 = int Function(
    int, int, int, int, int, int, int, int, int, int, int, int);
typedef _N13 = Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Uint32,
    Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D13 = int Function(
    int, int, int, int, int, int, int, int, int, int, int, int, int);
typedef _N14 = Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Uint32,
    Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D14 = int Function(
    int, int, int, int, int, int, int, int, int, int, int, int, int, int);
typedef _N15 = Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Uint32,
    Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _D15 = int Function(
    int, int, int, int, int, int, int, int, int, int, int, int, int, int, int);
typedef _N16 = Uint32 Function(
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32);
typedef _D16 = int Function(int, int, int, int, int, int, int, int, int, int,
    int, int, int, int, int, int);

typedef _VoidPtr3Native = Void Function(Pointer, Pointer, Pointer);
typedef _VoidPtr3Dart = void Function(Pointer, Pointer, Pointer);
typedef _IntNative = Int32 Function();
typedef _IntDart = int Function();
typedef _BranchNative = Void Function(Pointer<Uint8>, IntPtr);
typedef _BranchDart = void Function(Pointer<Uint8>, int);
typedef _FloatOpNative = Float Function(Float, Float, Uint32);
typedef _FloatOpDart = double Function(double, double, int);

typedef _U32x2Native = Uint32 Function(Uint32, Uint32);
typedef _U32x2Dart = int Function(int, int);
typedef _F64x2Native = Double Function(Double, Double);
typedef _F64x2Dart = double Function(double, double);

/// `called_fn` of A64Test_Invoke1.
int _subU32(int x, int y) => (x - y) & 0xFFFFFFFF;

/// `called_fn` of A64Test_Invoke2/3.
double _subF64(double x, double y) => x - y;

/// Calls the `uint32_t f(uint32_t...)` at [p] with the arguments 1..[n].
int _callGpArgs(Pointer<Void> p, int n) => switch (n) {
      0 => p.cast<NativeFunction<_N0>>().asFunction<_D0>()(),
      1 => p.cast<NativeFunction<_N1>>().asFunction<_D1>()(1),
      2 => p.cast<NativeFunction<_N2>>().asFunction<_D2>()(1, 2),
      3 => p.cast<NativeFunction<_N3>>().asFunction<_D3>()(1, 2, 3),
      4 => p.cast<NativeFunction<_N4>>().asFunction<_D4>()(1, 2, 3, 4),
      5 => p.cast<NativeFunction<_N5>>().asFunction<_D5>()(1, 2, 3, 4, 5),
      6 => p.cast<NativeFunction<_N6>>().asFunction<_D6>()(1, 2, 3, 4, 5, 6),
      7 => p.cast<NativeFunction<_N7>>().asFunction<_D7>()(1, 2, 3, 4, 5, 6, 7),
      8 =>
        p.cast<NativeFunction<_N8>>().asFunction<_D8>()(1, 2, 3, 4, 5, 6, 7, 8),
      9 => p.cast<NativeFunction<_N9>>().asFunction<_D9>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9),
      10 => p.cast<NativeFunction<_N10>>().asFunction<_D10>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
      11 => p.cast<NativeFunction<_N11>>().asFunction<_D11>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11),
      12 => p.cast<NativeFunction<_N12>>().asFunction<_D12>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12),
      13 => p.cast<NativeFunction<_N13>>().asFunction<_D13>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13),
      14 => p.cast<NativeFunction<_N14>>().asFunction<_D14>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14),
      15 => p.cast<NativeFunction<_N15>>().asFunction<_D15>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
      16 => p.cast<NativeFunction<_N16>>().asFunction<_D16>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16),
      _ => throw ArgumentError(n),
    };

void main() {
  late JitRuntime rt;
  setUp(() => rt = JitRuntime());
  tearDown(() => rt.dispose());

  Pointer<Void> compile(void Function(A64Compiler cc) body) {
    final code = CodeHolder(env: rt.environment);
    final cc = A64Compiler(env: code.env, labelManager: code.labelManager);
    body(cc);
    cc.finalize();
    cc.serializeToAssembler(A64Assembler(code));
    return rt.add(code).pointer;
  }

  group('A64Test', () {
    for (var argCount = 0; argCount <= 16; argCount++) {
      for (final preserveFp in [true, false]) {
        test('GpArgs {NumArgs=$argCount PreserveFP=${preserveFp ? 'Y' : 'N'}}',
            () {
          final fn = compile((cc) {
            final func = cc.addFunc(FuncSignature.build(
                List.filled(argCount, TypeId.int32),
                TypeId.int32,
                CallConvId.cdecl));
            if (preserveFp) func.frame.setPreservedFP();

            A64Gp sum;
            if (argCount > 0) {
              sum = cc.newGp32('i0');
              cc.setArg(0, sum);
              for (var i = 1; i < argCount; i++) {
                final iReg = cc.newGp32('i$i');
                cc
                  ..setArg(i, iReg)
                  ..inst(A64InstId.kAdd, [sum, sum, iReg]);
              }
            } else {
              sum = cc.newGp32('i');
              cc.mov(sum, Imm(0));
            }
            cc
              ..ret([sum])
              ..endFunc();
          });
          expect(_callGpArgs(fn, argCount), argCount * (argCount + 1) ~/ 2);
        });
      }
    }

    test('Simd1', () {
      final fn = compile((cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr, TypeId.intPtr],
            TypeId.void_,
            CallConvId.cdecl));
        final dst = cc.newGpPtr('dst');
        final src1 = cc.newGpPtr('src1');
        final src2 = cc.newGpPtr('src2');
        cc
          ..setArg(0, dst)
          ..setArg(1, src1)
          ..setArg(2, src2);

        final v1 = cc.newVecQ('vec1');
        final v2 = cc.newVecQ('vec2');
        final v3 = cc.newVecQ('vec3');
        cc
          ..inst(A64InstId.kLdr, [v2, A64Mem.base(src1)])
          ..inst(A64InstId.kLdr, [v3, A64Mem.base(src2)])
          ..inst(A64InstId.kAdd, [
            A64Vec(v1.id, 128, A64Layout.b16),
            A64Vec(v2.id, 128, A64Layout.b16),
            A64Vec(v3.id, 128, A64Layout.b16),
          ])
          ..inst(A64InstId.kStr, [v1, A64Mem.base(dst)])
          ..endFunc();
      });
      using((arena) {
        final dst = arena<Uint32>(4);
        final a = arena<Uint32>(4);
        final b = arena<Uint32>(4);
        for (final (i, (x, y))
            in [(0, 99), (1, 17), (2, 33), (255, 1)].indexed) {
          a[i] = x;
          b[i] = y;
        }
        fn.cast<NativeFunction<_VoidPtr3Native>>().asFunction<_VoidPtr3Dart>()(
            dst, a, b);
        // A byte add, so uint8_t(255 + 1) == 0.
        expect([for (var i = 0; i < 4; i++) dst[i]], [99, 18, 35, 0]);
      });
    });

    for (var regCount = 2; regCount < 64; regCount++) {
      test('GpRegs {NumRegs=$regCount}', () {
        final fn = compile((cc) {
          cc.addFunc(FuncSignature.build([], TypeId.int32, CallConvId.cdecl));
          final regs = [
            for (var i = 0; i < regCount; i++) cc.newGp32('reg$i'),
          ];
          for (final (i, r) in regs.indexed) {
            cc.mov(r, Imm(i + 1));
          }
          final sum = cc.newGp32('sum');
          cc.mov(sum, Imm(0));
          for (final r in regs) {
            cc.inst(A64InstId.kAdd, [sum, sum, r]);
          }
          cc
            ..ret([sum])
            ..endFunc();
        });
        expect(fn.cast<NativeFunction<_IntNative>>().asFunction<_IntDart>()(),
            (regCount | 1) * ((regCount + 1) ~/ 2));
      });
    }

    test('Adr', () {
      final fn = compile((cc) {
        cc.addFunc(FuncSignature.build([], TypeId.int32, CallConvId.cdecl));
        final addr = cc.newGpPtr('addr');
        final val = cc.newGpPtr('val');
        final lTable = cc.newLabel();
        cc
          ..inst(A64InstId.kAdr, [addr, LabelOp(lTable)])
          ..inst(A64InstId.kLdrsw, [val, A64Mem.baseOffset(addr, 8)])
          ..ret([val])
          ..endFunc();
        cc
          ..bind(lTable)
          ..embedData([
            for (var i = 1; i <= 5; i++) ...[i, 0, 0, 0]
          ]);
      });
      expect(fn.cast<NativeFunction<_IntNative>>().asFunction<_IntDart>()(), 3);
    });

    test('Branch1', () {
      final fn = compile((cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.uintPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        final count = cc.newGpPtr('count');
        final i = cc.newGpPtr('i');
        final l = cc.newLabel();
        cc
          ..setArg(0, p)
          ..setArg(1, count)
          ..mov(i, Imm(0))
          ..bind(l)
          ..inst(A64InstId.kStrb, [i.w, A64Mem.baseIndex(p, i)])
          ..inst(A64InstId.kAdd, [i, i, Imm(1)])
          ..inst(A64InstId.kCmp, [i, count])
          ..inst(A64InstId.kB_cond, [A64CondOp(A64Cond.ne), LabelOp(l)],
              type: NodeType.jump)
          ..endFunc();
      });
      using((arena) {
        final array = arena<Uint8>(16);
        fn.cast<NativeFunction<_BranchNative>>().asFunction<_BranchDart>()(
            array, 16);
        expect([for (var i = 0; i < 16; i++) array[i]],
            [for (var i = 0; i < 16; i++) i]);
      });
    });

    test('Invoke1', () {
      final fn = compile((cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.uint32, TypeId.uint32], TypeId.uint32, CallConvId.cdecl));
        final x = cc.newGp32('x');
        final y = cc.newGp32('y');
        final r = cc.newGp32('r');
        final f = cc.newGpPtr('fn');
        cc
          ..setArg(0, x)
          ..setArg(1, y)
          ..mov(f, Imm(Pointer.fromFunction<_U32x2Native>(_subU32, 0).address));
        cc.invoke(
            f,
            FuncSignature.build([TypeId.uint32, TypeId.uint32], TypeId.uint32,
                CallConvId.cdecl))
          ..setArg(0, x)
          ..setArg(1, y)
          ..setRet(0, r);
        cc
          ..ret([r])
          ..endFunc();
      });
      expect(
          fn.cast<NativeFunction<_U32x2Native>>().asFunction<_U32x2Dart>()(
              49, 7),
          42);
    });

    for (final (name, swap) in [('Invoke2', false), ('Invoke3', true)]) {
      test(name, () {
        final fn = compile((cc) {
          final sig = FuncSignature.build([TypeId.float64, TypeId.float64],
              TypeId.float64, CallConvId.cdecl);
          cc.addFunc(sig);
          final x = cc.newVecD('x');
          final y = cc.newVecD('y');
          final r = cc.newVecD('r');
          final f = cc.newGpPtr('fn');
          cc
            ..setArg(0, x)
            ..setArg(1, y)
            ..mov(f,
                Imm(Pointer.fromFunction<_F64x2Native>(_subF64, 0.0).address));
          cc.invoke(f, sig)
            ..setArg(0, swap ? y : x)
            ..setArg(1, swap ? x : y)
            ..setRet(0, r);
          cc
            ..ret([r])
            ..endFunc();
        });
        final f =
            fn.cast<NativeFunction<_F64x2Native>>().asFunction<_F64x2Dart>();
        expect(f(49, 7), swap ? _subF64(7, 49) : _subF64(49, 7));
      });
    }

    for (final annotated in [false, true]) {
      test('JumpTable {${annotated ? 'Annotated' : 'Unknown Target'}}', () {
        final fn = compile((cc) {
          cc.addFunc(FuncSignature.build(
              [TypeId.float32, TypeId.float32, TypeId.uint32],
              TypeId.float32,
              CallConvId.cdecl));
          final a = cc.newVecS('a');
          final b = cc.newVecS('b');
          final op = cc.newGp32('op');
          final target = cc.newGpPtr('target');
          final offset = cc.newGpPtr('offset');

          final lEnd = cc.newLabel();
          final lTable = cc.newLabel();
          final lAdd = cc.newLabel();
          final lSub = cc.newLabel();
          final lMul = cc.newLabel();
          final lDiv = cc.newLabel();

          cc
            ..setArg(0, a)
            ..setArg(1, b)
            ..setArg(2, op)
            ..inst(A64InstId.kAdr, [target, LabelOp(lTable)])
            ..inst(A64InstId.kLdrsw, [
              offset,
              A64Mem.baseIndex(target, op,
                  shift: 2, extend: A64Shift.sxtw.encoding)
            ])
            ..inst(A64InstId.kAdd, [target, target, offset]);

          if (annotated) {
            final annotation = cc.newJumpAnnotation()
              ..addLabel(lAdd)
              ..addLabel(lSub)
              ..addLabel(lMul)
              ..addLabel(lDiv);
            cc.br(target, annotation);
          } else {
            cc.br(target);
          }

          cc
            ..bind(lAdd)
            ..fadd(a, a, b)
            ..inst(A64InstId.kB, [LabelOp(lEnd)], type: NodeType.jump)
            ..bind(lSub)
            ..fsub(a, a, b)
            ..inst(A64InstId.kB, [LabelOp(lEnd)], type: NodeType.jump)
            ..bind(lMul)
            ..fmul(a, a, b)
            ..inst(A64InstId.kB, [LabelOp(lEnd)], type: NodeType.jump)
            ..bind(lDiv)
            ..fdiv(a, a, b)
            ..bind(lEnd)
            ..ret([a])
            ..endFunc();

          cc.bind(lTable);
          for (final l in [lAdd, lSub, lMul, lDiv]) {
            cc.embedLabelDelta(l, lTable, 4);
          }
        });
        final f = fn
            .cast<NativeFunction<_FloatOpNative>>()
            .asFunction<_FloatOpDart>();
        expect([f(33, 14, 0), f(33, 14, 1), f(10, 6, 2), f(80, 8, 3)],
            [47.0, 19.0, 60.0, 10.0]);
      });
    }
  }, skip: skipUnlessA64Host);
}
