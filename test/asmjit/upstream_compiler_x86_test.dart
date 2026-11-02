// Ports of the x86 compiler tests of upstream asmjit
// (asmjit-testing/tests/asmjit_test_compiler_x86.cpp, `X86Test_*`): each
// test builds the same instructions, virtual registers and control flow as
// upstream `compile()` and checks what upstream `run()` checks.
import 'dart:ffi';
import 'dart:io';

import 'package:asmjit/asmjit.dart' hide calloc;
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import '../support/host.dart';

typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();
typedef _IntNative = Int32 Function();
typedef _IntDart = int Function();
typedef _Int2Native = Int32 Function(Int32, Int32);
typedef _Int2Dart = int Function(int, int);
typedef _Int3Native = Int32 Function(Int32, Int32, Int32);
typedef _Int3Dart = int Function(int, int, int);
typedef _PtrNative = Void Function(Pointer<Int32>);
typedef _PtrDart = void Function(Pointer<Int32>);
typedef _Ptr2Native = Void Function(Pointer<Int32>, Pointer<Int32>);
typedef _Ptr2Dart = void Function(Pointer<Int32>, Pointer<Int32>);
typedef _N1 = Void Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>);
typedef _D1 = void Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>);
typedef _N2 = Void Function(
    Float, Float, Float, Float, Float, Float, Float, Pointer<Float>);
typedef _D2 = void Function(
    double, double, double, double, double, double, double, Pointer<Float>);
typedef _N3 = Void Function(
    Double, Double, Double, Double, Double, Double, Double, Pointer<Double>);
typedef _D3 = void Function(
    double, double, double, double, double, double, double, Pointer<Double>);
typedef _N4 = Void Function(Pointer<Int32>, Pointer<Int32>, Int32, Int32);
typedef _D4 = void Function(Pointer<Int32>, Pointer<Int32>, int, int);
typedef _N5 = Void Function(Int32, Int32, Pointer<Int8>);
typedef _D5 = void Function(int, int, Pointer<Int8>);
typedef _N6 = Void Function(Pointer<Int32>, Int32, Int32, Int32);
typedef _D6 = void Function(Pointer<Int32>, int, int, int);
typedef _N7 = Void Function(Pointer<Utf8>, Pointer<Utf8>, IntPtr);
typedef _D7 = void Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _N8 = Void Function(Pointer<Uint32>, Pointer<Uint32>, IntPtr);
typedef _D8 = void Function(Pointer<Uint32>, Pointer<Uint32>, int);
typedef _N9 = Uint32 Function(Uint8, Uint8, Uint32);
typedef _D9 = int Function(int, int, int);

/// Calls the AlignBase function [p] with the arguments 1..[n].
int _callAlignBase(Pointer<Void> p, int n) {
  switch (n) {
    case 0:
      return p
          .cast<NativeFunction<Uint32 Function()>>()
          .asFunction<int Function()>()();
    case 1:
      return p
          .cast<NativeFunction<Uint32 Function(Uint32)>>()
          .asFunction<int Function(int)>()(1);
    case 2:
      return p
          .cast<NativeFunction<Uint32 Function(Uint32, Uint32)>>()
          .asFunction<int Function(int, int)>()(1, 2);
    case 3:
      return p
          .cast<NativeFunction<Uint32 Function(Uint32, Uint32, Uint32)>>()
          .asFunction<int Function(int, int, int)>()(1, 2, 3);
    case 4:
      return p
          .cast<
              NativeFunction<Uint32 Function(Uint32, Uint32, Uint32, Uint32)>>()
          .asFunction<int Function(int, int, int, int)>()(1, 2, 3, 4);
    case 5:
      return p
          .cast<
              NativeFunction<
                  Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32)>>()
          .asFunction<int Function(int, int, int, int, int)>()(1, 2, 3, 4, 5);
    case 6:
      return p
              .cast<
                  NativeFunction<
                      Uint32 Function(
                          Uint32, Uint32, Uint32, Uint32, Uint32, Uint32)>>()
              .asFunction<int Function(int, int, int, int, int, int)>()(
          1, 2, 3, 4, 5, 6);
    case 7:
      return p
              .cast<
                  NativeFunction<
                      Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32,
                          Uint32, Uint32)>>()
              .asFunction<int Function(int, int, int, int, int, int, int)>()(
          1, 2, 3, 4, 5, 6, 7);
    case 8:
      return p
              .cast<
                  NativeFunction<
                      Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32,
                          Uint32, Uint32, Uint32)>>()
              .asFunction<
                  int Function(int, int, int, int, int, int, int, int)>()(
          1, 2, 3, 4, 5, 6, 7, 8);
    case 9:
      return p
              .cast<
                  NativeFunction<
                      Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32,
                          Uint32, Uint32, Uint32, Uint32)>>()
              .asFunction<
                  int Function(int, int, int, int, int, int, int, int, int)>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9);
    case 10:
      return p
          .cast<
              NativeFunction<
                  Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32,
                      Uint32, Uint32, Uint32, Uint32, Uint32)>>()
          .asFunction<
              int Function(int, int, int, int, int, int, int, int, int,
                  int)>()(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
    case 11:
      return p
          .cast<
              NativeFunction<
                  Uint32 Function(Uint32, Uint32, Uint32, Uint32, Uint32,
                      Uint32, Uint32, Uint32, Uint32, Uint32, Uint32)>>()
          .asFunction<
              int Function(int, int, int, int, int, int, int, int, int, int,
                  int)>()(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
    case 12:
      return p
          .cast<
              NativeFunction<
                  Uint32 Function(
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
                      Uint32)>>()
          .asFunction<
              int Function(int, int, int, int, int, int, int, int, int, int,
                  int, int)>()(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);
    case 13:
      return p
          .cast<
              NativeFunction<
                  Uint32 Function(
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
                      Uint32)>>()
          .asFunction<
              int Function(int, int, int, int, int, int, int, int, int, int,
                  int, int, int)>()(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13);
    case 14:
      return p
          .cast<
              NativeFunction<
                  Uint32 Function(
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
                      Uint32)>>()
          .asFunction<
              int Function(
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int)>()(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14);
    case 15:
      return p
          .cast<
              NativeFunction<
                  Uint32 Function(
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
                      Uint32)>>()
          .asFunction<
              int Function(
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int,
                  int)>()(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);
    case 16:
      return p
              .cast<
                  NativeFunction<
                      Uint32 Function(
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
                          Uint32)>>()
              .asFunction<
                  int Function(int, int, int, int, int, int, int, int, int, int,
                      int, int, int, int, int, int)>()(
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  }
  throw ArgumentError.value(n);
}

/// `x86::shuffle_imm(a, b, c, d)`.
int _shuffleImm(int a, int b, int c, int d) =>
    (a << 6) | (b << 4) | (c << 2) | d;

/// Port of `generate_sse_alpha_blend_internal()`
/// (asmjit-testing/tests/asmjit_test_misc.h).
void _generateSseAlphaBlendInternal(X86Compiler cc, X86Gp dst, X86Gp src,
    X86Gp n, X86Gp gp0, List<X86Xmm> simd) {
  final i = n;
  final j = gp0;

  final vzero = simd[0];
  final v0080 = simd[1];
  final v0101 = simd[2];

  final lSmallLoop = cc.newLabel();
  final lSmallEnd = cc.newLabel();
  final lLargeLoop = cc.newLabel();
  final lLargeEnd = cc.newLabel();
  final lDone = cc.newLabel();

  void e(int id, List<Operand> ops) => cc.inst(id, ops);

  // Load SIMD Constants.
  cc
    ..xorps(vzero, vzero)
    ..mov(gp0.as32, Imm(0x00800080))
    ..movd(v0080, gp0.as32)
    ..mov(gp0.as32, Imm(0x01010101))
    ..movd(v0101, gp0.as32);
  e(X86InstId.kPshufd, [v0080, v0080, Imm(_shuffleImm(0, 0, 0, 0))]);
  e(X86InstId.kPshufd, [v0101, v0101, Imm(_shuffleImm(0, 0, 0, 0))]);

  // How many pixels have to be processed to make the loop aligned.
  cc
    ..xor_(j, j)
    ..sub(j, dst)
    ..and_(j, Imm(15))
    ..shr(j, Imm(2))
    ..jz(lSmallEnd)
    ..cmp(j, i);
  e(X86InstId.kCmovnle, [j, i]); // j = min(i, j)
  cc.sub(i, j); // i -= j

  // Small loop.
  cc.bind(lSmallLoop);
  {
    final x0 = simd[3];
    final y0 = simd[4];
    final a0 = simd[5];

    cc
      ..movd(y0, X86Mem.base(src))
      ..movd(x0, X86Mem.base(dst));

    e(X86InstId.kPcmpeqb, [a0, a0]);
    cc.pxor(a0, y0);
    e(X86InstId.kPsrlw, [a0, Imm(8)]);
    e(X86InstId.kPunpcklbw, [x0, vzero]);

    e(X86InstId.kPshuflw, [a0, a0, Imm(_shuffleImm(1, 1, 1, 1))]);
    e(X86InstId.kPunpcklbw, [y0, vzero]);

    cc.pmullw(x0, a0);
    e(X86InstId.kPaddsw, [x0, v0080]);
    e(X86InstId.kPmulhuw, [x0, v0101]);

    cc.paddw(x0, y0);
    e(X86InstId.kPackuswb, [x0, x0]);

    cc
      ..movd(X86Mem.base(dst), x0)
      ..add(dst, Imm(4))
      ..add(src, Imm(4))
      ..dec(j)
      ..jnz(lSmallLoop);
  }

  // Second section, prepare for an aligned loop.
  cc
    ..bind(lSmallEnd)
    ..test(i, i)
    ..mov(j, i)
    ..jz(lDone)
    ..and_(j, Imm(3))
    ..shr(i, Imm(2))
    ..jz(lLargeEnd);

  // Aligned loop.
  cc.bind(lLargeLoop);
  {
    final x0 = simd[3];
    final x1 = simd[4];
    final y0 = simd[5];
    final a0 = simd[6];
    final a1 = simd[7];

    cc
      ..movups(y0, X86Mem.base(src))
      ..movaps(x0, X86Mem.base(dst));

    e(X86InstId.kPcmpeqb, [a0, a0]);
    cc
      ..xorps(a0, y0)
      ..movaps(x1, x0);

    e(X86InstId.kPsrlw, [a0, Imm(8)]);
    e(X86InstId.kPunpcklbw, [x0, vzero]);

    cc.movaps(a1, a0);
    e(X86InstId.kPunpcklwd, [a0, a0]);

    e(X86InstId.kPunpckhbw, [x1, vzero]);
    e(X86InstId.kPunpckhwd, [a1, a1]);

    e(X86InstId.kPshufd, [a0, a0, Imm(_shuffleImm(3, 3, 1, 1))]);
    e(X86InstId.kPshufd, [a1, a1, Imm(_shuffleImm(3, 3, 1, 1))]);

    cc
      ..pmullw(x0, a0)
      ..pmullw(x1, a1);

    e(X86InstId.kPaddsw, [x0, v0080]);
    e(X86InstId.kPaddsw, [x1, v0080]);

    e(X86InstId.kPmulhuw, [x0, v0101]);
    e(X86InstId.kPmulhuw, [x1, v0101]);

    cc.add(src, Imm(16));
    e(X86InstId.kPackuswb, [x0, x1]);

    cc
      ..paddw(x0, y0)
      ..movaps(X86Mem.base(dst), x0)
      ..add(dst, Imm(16))
      ..dec(i)
      ..jnz(lLargeLoop);
  }

  cc
    ..bind(lLargeEnd)
    ..test(j, j)
    ..jnz(lSmallLoop)
    ..bind(lDone);
}

/// Port of `generate_sse_alpha_blend()` for a compiler.
void _generateSseAlphaBlend(X86Compiler cc) {
  final dst = cc.newGpPtr('dst');
  final src = cc.newGpPtr('src');
  final i = cc.newGpPtr('i');
  final j = cc.newGpPtr('j');
  final v = [for (var k = 0; k < 8; k++) cc.newXmm('v$k')];

  final funcNode = cc.addFunc(FuncSignature.build(
      [TypeId.intPtr, TypeId.intPtr, TypeId.uintPtr], TypeId.void_));
  funcNode.setArg(0, 0, dst);
  funcNode.setArg(1, 0, src);
  funcNode.setArg(2, 0, i);
  _generateSseAlphaBlendInternal(cc, dst, src, i, j, v);
  cc.endFunc();
}

/// `X86Test_AlphaBlend::blend_src_over()`.
int _blendSrcOver(int d, int s) {
  final saInv = (~s & 0xFFFFFFFF) >> 24;

  var d20 = d & 0x00FF00FF;
  var d31 = (d >> 8) & 0x00FF00FF;

  d20 = (d20 * saInv) & 0xFFFFFFFF;
  d31 = (d31 * saInv) & 0xFFFFFFFF;

  d20 = (((d20 + ((d20 >> 8) & 0x00FF00FF) + 0x00800080) & 0xFF00FF00) >> 8);
  d31 = ((d31 + ((d31 >> 8) & 0x00FF00FF) + 0x00800080) & 0xFF00FF00);

  return (d20 + d31 + s) & 0xFFFFFFFF;
}

final bool _hasAvx512f = hostIsX64 && CpuInfo.host().features.avx512f;

void main() {
  late JitRuntime rt;
  setUp(() => rt = JitRuntime());
  tearDown(() => rt.dispose());

  Pointer<Void> compile(void Function(X86Compiler cc) body) {
    final code = CodeHolder(env: rt.environment);
    final cc = X86Compiler(env: code.env, labelManager: code.labelManager);
    body(cc);
    cc.finalize();
    cc.serializeToAssembler(X86Assembler(code));
    return rt.add(code).pointer;
  }

  group('Base', () {
    test('NoCode', () {
      final p = compile((cc) {
        cc.addFunc(FuncSignature.build([]));
        cc.endFunc();
      });
      p.cast<NativeFunction<_VoidNative>>().asFunction<_VoidDart>()();
    }, skip: skipUnlessX64Host);

    test('NoAlign', () {
      final p = compile((cc) {
        cc.addFunc(FuncSignature.build([]));
        cc.align(AlignMode.code, 0);
        cc.align(AlignMode.code, 1);
        cc.endFunc();
      });
      p.cast<NativeFunction<_VoidNative>>().asFunction<_VoidDart>()();
    }, skip: skipUnlessX64Host);

    test('IndirectBranchProtection', () {
      final p = compile((cc) {
        final func = cc.addFunc(FuncSignature.build([]));
        func.addAttributes(FuncAttributes.kIndirectBranchProtection);
        cc.endFunc();
      });
      p.cast<NativeFunction<_VoidNative>>().asFunction<_VoidDart>()();
    }, skip: skipUnlessX64Host);
  });

  group('AlignBase', () {
    for (var argCount = 0; argCount <= 16; argCount++) {
      for (final alignment in [16, 32]) {
        for (final preserveFp in [true, false]) {
          test(
              'AlignBase {NumArgs=$argCount Alignment=$alignment '
              'PreserveFP=${preserveFp ? 'Y' : 'N'}}', () {
            final p = compile((cc) {
              final funcNode = cc.addFunc(FuncSignature.build(
                  List.filled(argCount, TypeId.int32), TypeId.int32));
              if (preserveFp) funcNode.frame.setPreservedFP();

              final gpVar = cc.newGpPtr('gp_var');
              X86Gp? gpSum;
              final stack = cc.newStack(alignment, alignment);

              // Do a sum of arguments to verify a possible relocation when
              // misaligned.
              for (var i = 0; i < argCount; i++) {
                final gpArg = cc.newGp32('gp_arg$i');
                funcNode.setArg(i, 0, gpArg);
                if (i == 0) {
                  gpSum = gpArg;
                } else {
                  cc.add(gpSum!, gpArg);
                }
              }

              // Check alignment of the stack (has to be 16).
              cc
                ..lea(gpVar, stack)
                ..and_(gpVar, Imm(alignment - 1));

              // Add a sum of all arguments to check if they are correct.
              if (argCount != 0) cc.or_(gpVar.as32, gpSum!);

              cc
                ..ret([gpVar])
                ..endFunc();
            });
            final result = _callAlignBase(p, argCount);
            final expected = argCount * (argCount + 1) ~/ 2;
            expect([result >> 28, result & 0x0FFFFFFF],
                [expected >> 28, expected & 0x0FFFFFFF]);
          }, skip: skipUnlessX64Host);
        }
      }
    }
  });

  group('Jump', () {
    test('JumpMerge', () {
      final p = compile((cc) {
        final l0 = cc.newLabel();
        final l1 = cc.newLabel();
        final l2 = cc.newLabel();
        final lEnd = cc.newLabel();

        final dst = cc.newGpPtr('dst');
        final val = cc.newGp32('val');

        final funcNode = cc.addFunc(
            FuncSignature.build([TypeId.intPtr, TypeId.int32], TypeId.void_));
        funcNode.setArg(0, 0, dst);
        funcNode.setArg(1, 0, val);

        cc
          ..cmp(val, Imm(0))
          ..je(l2)
          ..cmp(val, Imm(1))
          ..je(l1)
          ..cmp(val, Imm(2))
          ..je(l0)
          ..mov(X86Mem.base(dst, size: 4), val)
          ..jmp(lEnd)
          // On purpose. This tests whether the CFG constructs a single
          // basic-block from multiple labels next to each other.
          ..bind(l0)
          ..bind(l1)
          ..bind(l2)
          ..mov(X86Mem.base(dst, size: 4), Imm(0))
          ..bind(lEnd)
          ..endFunc();
      });
      final f = p
          .cast<NativeFunction<Void Function(Pointer<Int32>, Int32)>>()
          .asFunction<void Function(Pointer<Int32>, int)>();
      final arr = calloc<Int32>(5);
      try {
        for (var i = 0; i < 5; i++) {
          arr[i] = -1;
        }
        for (var i = 0; i < 5; i++) {
          f(arr + i, i);
        }
        expect([for (var i = 0; i < 5; i++) arr[i]], [0, 0, 0, 3, 4]);
      } finally {
        calloc.free(arr);
      }
    }, skip: skipUnlessX64Host);

    test('JumpCross', () {
      final p = compile((cc) {
        cc.addFunc(FuncSignature.build([]));
        final l1 = cc.newLabel();
        final l2 = cc.newLabel();
        final l3 = cc.newLabel();
        cc
          ..jmp(l2)
          ..bind(l1)
          ..jmp(l3)
          ..bind(l2)
          ..jmp(l1)
          ..bind(l3)
          ..endFunc();
      });
      p.cast<NativeFunction<_VoidNative>>().asFunction<_VoidDart>()();
    }, skip: skipUnlessX64Host);

    test('JumpMany', () {
      final p = compile((cc) {
        cc.addFunc(FuncSignature.build([], TypeId.int32));
        for (var i = 0; i < 1000; i++) {
          final l = cc.newLabel();
          cc
            ..jmp(l)
            ..bind(l);
        }
        final ret = cc.newGp32('ret');
        cc
          ..xor_(ret, ret)
          ..ret([ret])
          ..endFunc();
      });
      expect(p.cast<NativeFunction<_IntNative>>().asFunction<_IntDart>()(), 0);
    }, skip: skipUnlessX64Host);

    test('JumpUnreachable1', () {
      final p = compile((cc) {
        cc.addFunc(FuncSignature.build([]));
        final l1 = cc.newLabel();
        final l2 = cc.newLabel();
        final l3 = cc.newLabel();
        final l4 = cc.newLabel();
        final l5 = cc.newLabel();
        final l6 = cc.newLabel();
        final l7 = cc.newLabel();

        final v0 = cc.newGp32('v0');
        final v1 = cc.newGp32('v1');

        cc
          ..bind(l2)
          ..bind(l3)
          ..jmp(l1)
          ..bind(l5)
          ..mov(v0, Imm(0))
          ..bind(l6)
          ..jmp(l3)
          ..mov(v1, Imm(1))
          ..jmp(l1)
          ..bind(l4)
          ..jmp(l2)
          ..bind(l7)
          ..add(v0, v1)
          ..align(AlignMode.code, 16)
          ..bind(l1)
          ..ret()
          ..endFunc();
      });
      p.cast<NativeFunction<_VoidNative>>().asFunction<_VoidDart>()();
    }, skip: skipUnlessX64Host);

    test('JumpUnreachable2', () {
      final p = compile((cc) {
        cc.addFunc(FuncSignature.build([]));
        final l1 = cc.newLabel();
        final l2 = cc.newLabel();
        final v0 = cc.newGp32('v0');
        final v1 = cc.newGp32('v1');
        cc
          ..jmp(l1)
          ..bind(l2)
          ..mov(v0, Imm(1))
          ..mov(v1, Imm(2))
          ..cmp(v0, v1)
          ..jz(l2)
          ..jmp(l1)
          ..bind(l1)
          ..ret()
          ..endFunc();
      });
      p.cast<NativeFunction<_VoidNative>>().asFunction<_VoidDart>()();
    }, skip: skipUnlessX64Host);
  });

  group('Alloc', () {
    test('AllocBase', () {
      final p = compile((cc) {
        cc.addFunc(FuncSignature.build([], TypeId.int32));
        final v0 = cc.newGp32('v0');
        final v1 = cc.newGp32('v1');
        final v2 = cc.newGp32('v2');
        final v3 = cc.newGp32('v3');
        final v4 = cc.newGp32('v4');
        cc
          ..xor_(v0, v0)
          ..mov(v1, Imm(1))
          ..mov(v2, Imm(2))
          ..mov(v3, Imm(3))
          ..mov(v4, Imm(4))
          ..add(v0, v1)
          ..add(v0, v2)
          ..add(v0, v3)
          ..add(v0, v4)
          ..ret([v0])
          ..endFunc();
      });
      expect(p.cast<NativeFunction<_IntNative>>().asFunction<_IntDart>()(),
          1 + 2 + 3 + 4);
    }, skip: skipUnlessX64Host);

    test('AllocMany1', () {
      const kCount = 8;
      final p = compile((cc) {
        final a0 = cc.newGpPtr('a0');
        final a1 = cc.newGpPtr('a1');
        final funcNode = cc.addFunc(
            FuncSignature.build([TypeId.intPtr, TypeId.intPtr], TypeId.void_));
        funcNode.setArg(0, 0, a0);
        funcNode.setArg(1, 0, a1);

        // Create some variables.
        final t = cc.newGp32('t');
        final x = [for (var i = 0; i < kCount; i++) cc.newGp32('x$i')];

        // Setup variables (use mov with reg/imm to se if register allocator
        // works).
        for (var i = 0; i < kCount; i++) {
          cc.mov(x[i], Imm(i + 1));
        }
        // Make sum (addition).
        cc.xor_(t, t);
        for (var i = 0; i < kCount; i++) {
          cc.add(t, x[i]);
        }
        // Store result to a given pointer in first argument.
        cc.mov(X86Mem.base(a0, size: 4), t);
        // Clear t.
        cc.xor_(t, t);
        // Make sum (subtraction).
        for (var i = 0; i < kCount; i++) {
          cc.sub(t, x[i]);
        }
        // Store result to a given pointer in second argument.
        cc.mov(X86Mem.base(a1, size: 4), t);
        cc.endFunc();
      });
      final buf = calloc<Int32>(2);
      try {
        p.cast<NativeFunction<_Ptr2Native>>().asFunction<_Ptr2Dart>()(
            buf, buf + 1);
        expect([buf[0], buf[1]], [36, -36]);
      } finally {
        calloc.free(buf);
      }
    }, skip: skipUnlessX64Host);

    test('AllocMany2', () {
      final p = compile((cc) {
        final a = cc.newGpPtr('a');
        final funcNode =
            cc.addFunc(FuncSignature.build([TypeId.intPtr], TypeId.void_));
        funcNode.setArg(0, 0, a);

        final v = [for (var i = 0; i < 32; i++) cc.newGp32('v$i')];
        for (var i = 0; i < 32; i++) {
          cc.xor_(v[i], v[i]);
        }

        final x = cc.newGp32('x');
        final l = cc.newLabel();

        cc
          ..mov(x, Imm(32))
          ..bind(l);
        for (var i = 0; i < 32; i++) {
          cc.add(v[i], Imm(i));
        }
        cc
          ..dec(x)
          ..jnz(l);
        for (var i = 0; i < 32; i++) {
          cc.mov(X86Mem.baseDisp(a, i * 4, size: 4), v[i]);
        }
        cc.endFunc();
      });
      final buf = calloc<Int32>(32);
      try {
        p.cast<NativeFunction<_PtrNative>>().asFunction<_PtrDart>()(buf);
        expect([for (var i = 0; i < 32; i++) buf[i]],
            [for (var i = 0; i < 32; i++) i * 32]);
      } finally {
        calloc.free(buf);
      }
    }, skip: skipUnlessX64Host);

    test('AllocInt8', () {
      final p = compile((cc) {
        final x = cc.newGp8('x');
        final y = cc.newGp32('y');
        final funcNode =
            cc.addFunc(FuncSignature.build([TypeId.int8], TypeId.int32));
        funcNode.setArg(0, 0, x);
        cc
          ..movsx(y, x)
          ..ret([y])
          ..endFunc();
      });
      final f = p
          .cast<NativeFunction<Int32 Function(Int8)>>()
          .asFunction<int Function(int)>();
      expect(f(-13), -13);
    }, skip: skipUnlessX64Host);

    test('AllocUnhandledArg', () {
      final p = compile((cc) {
        final x = cc.newGp32('x');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.int32, TypeId.int32, TypeId.int32], TypeId.int32));
        funcNode.setArg(2, 0, x);
        cc
          ..ret([x])
          ..endFunc();
      });
      expect(
          p.cast<NativeFunction<_Int3Native>>().asFunction<_Int3Dart>()(
              42, 155, 199),
          199);
    }, skip: skipUnlessX64Host);

    test('AllocArgsIntPtr', () {
      final p = compile((cc) {
        final funcNode = cc.addFunc(
            FuncSignature.build(List.filled(8, TypeId.intPtr), TypeId.void_));
        final v = <X86Gp>[];
        for (var i = 0; i < 8; i++) {
          v.add(cc.newGpPtr('var$i'));
          funcNode.setArg(i, 0, v[i]);
        }
        for (var i = 0; i < 8; i++) {
          cc.add(v[i], Imm(i + 1));
        }
        // Move some data into buffer provided by arguments so we can verify
        // if it really works without looking into assembler output.
        for (var i = 0; i < 8; i++) {
          cc.add(X86Mem.base(v[i], size: 1), Imm(i + 1));
        }
        cc.endFunc();
      });
      final buf = calloc<Uint8>(9);
      try {
        p.cast<NativeFunction<_N1>>().asFunction<_D1>()(
            buf, buf, buf, buf, buf, buf, buf, buf);
        expect(
            [for (var i = 0; i < 9; i++) buf[i]], [0, 1, 2, 3, 4, 5, 6, 7, 8]);
      } finally {
        calloc.free(buf);
      }
    }, skip: skipUnlessX64Host);

    test('AllocArgsFloat', () {
      final p = compile((cc) {
        final funcNode = cc.addFunc(FuncSignature.build(
            [...List.filled(7, TypeId.float32), TypeId.intPtr], TypeId.void_));
        final ptr = cc.newGpPtr('p');
        final xv = <X86Xmm>[];
        for (var i = 0; i < 7; i++) {
          xv.add(cc.newXmmSs('xv$i'));
          funcNode.setArg(i, 0, xv[i]);
        }
        funcNode.setArg(7, 0, ptr);
        for (var i = 1; i < 7; i++) {
          cc.addss(xv[0], xv[i]);
        }
        cc
          ..movss(X86Mem.base(ptr), xv[0])
          ..endFunc();
      });
      final out = calloc<Float>();
      try {
        p.cast<NativeFunction<_N2>>().asFunction<_D2>()(
            1, 2, 3, 4, 5, 6, 7, out);
        expect(out.value, 1.0 + 2.0 + 3.0 + 4.0 + 5.0 + 6.0 + 7.0);
      } finally {
        calloc.free(out);
      }
    }, skip: skipUnlessX64Host);

    test('AllocArgsDouble', () {
      final p = compile((cc) {
        final funcNode = cc.addFunc(FuncSignature.build(
            [...List.filled(7, TypeId.float64), TypeId.intPtr], TypeId.void_));
        final ptr = cc.newGpPtr('p');
        final xv = <X86Xmm>[];
        for (var i = 0; i < 7; i++) {
          xv.add(cc.newXmmSd('xv$i'));
          funcNode.setArg(i, 0, xv[i]);
        }
        funcNode.setArg(7, 0, ptr);
        for (var i = 1; i < 7; i++) {
          cc.addsd(xv[0], xv[i]);
        }
        cc
          ..movsd(X86Mem.base(ptr), xv[0])
          ..endFunc();
      });
      final out = calloc<Double>();
      try {
        p.cast<NativeFunction<_N3>>().asFunction<_D3>()(
            1, 2, 3, 4, 5, 6, 7, out);
        expect(out.value, 1.0 + 2.0 + 3.0 + 4.0 + 5.0 + 6.0 + 7.0);
      } finally {
        calloc.free(out);
      }
    }, skip: skipUnlessX64Host);

    test('AllocArgsVec', () {
      final p = compile((cc) {
        final a = cc.newXmm('xmm_a');
        final b = cc.newXmm('xmm_b');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.int32x4, TypeId.int32x4], TypeId.int32x4));
        funcNode.setArg(0, 0, a);
        funcNode.setArg(1, 0, b);
        cc
          ..paddb(a, b)
          ..ret([a])
          ..endFunc();
      });
      // `__m128i (*)(__m128i, __m128i)` cannot be called through dart:ffi
      // (no vector types), so a SysV caller written with the assembler loads
      // the vectors from memory, calls it and stores the result.
      final code = CodeHolder(env: rt.environment);
      X86Assembler(code)
        ..emit(X86InstId.kPush, [rbx])
        ..emit(X86InstId.kMov, [rbx, rdx])
        ..emit(X86InstId.kMovdqu, [xmm0, X86Mem.base(rdi)])
        ..emit(X86InstId.kMovdqu, [xmm1, X86Mem.base(rsi)])
        ..emit(X86InstId.kMov, [rax, Imm(p.address)])
        ..emit(X86InstId.kCall, [rax])
        ..emit(X86InstId.kMovdqu, [X86Mem.base(rbx), xmm0])
        ..emit(X86InstId.kPop, [rbx])
        ..emit(X86InstId.kRet, []);
      final caller = rt.add(code).pointer;
      final data = calloc<Uint8>(48);
      try {
        for (var i = 0; i < 16; i++) {
          data[i] = i;
          data[16 + i] = 15 - i;
        }
        caller
            .cast<
                NativeFunction<
                    Void Function(
                        Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>>()
            .asFunction<
                void Function(Pointer<Uint8>, Pointer<Uint8>,
                    Pointer<Uint8>)>()(data, data + 16, data + 32);
        expect(
            [for (var i = 0; i < 16; i++) data[32 + i]], List.filled(16, 15));
      } finally {
        calloc.free(data);
      }
      // Not supported on Windows (upstream does not add it there).
    },
        skip: hostIsX64 && Platform.isWindows
            ? 'vector arguments are not supported by the Win64 ABI'
            : skipUnlessX64Host);

    test('AllocRetFloat1', () {
      final p = compile((cc) {
        final x = cc.newXmmSs('x');
        final funcNode =
            cc.addFunc(FuncSignature.build([TypeId.float32], TypeId.float32));
        funcNode.setArg(0, 0, x);
        cc
          ..ret([x])
          ..endFunc();
      });
      final f = p
          .cast<NativeFunction<Float Function(Float)>>()
          .asFunction<double Function(double)>();
      expect(f(42), 42.0);
    }, skip: skipUnlessX64Host);

    test('AllocRetFloat2', () {
      final p = compile((cc) {
        final x = cc.newXmmSs('x');
        final y = cc.newXmmSs('y');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.float32, TypeId.float32], TypeId.float32));
        funcNode.setArg(0, 0, x);
        funcNode.setArg(1, 0, y);
        cc
          ..addss(x, y)
          ..ret([x])
          ..endFunc();
      });
      final f = p
          .cast<NativeFunction<Float Function(Float, Float)>>()
          .asFunction<double Function(double, double)>();
      expect(f(1, 2), 1.0 + 2.0);
    }, skip: skipUnlessX64Host);

    test('AllocRetDouble1', () {
      final p = compile((cc) {
        final x = cc.newXmmSd('x');
        final funcNode =
            cc.addFunc(FuncSignature.build([TypeId.float64], TypeId.float64));
        funcNode.setArg(0, 0, x);
        cc
          ..ret([x])
          ..endFunc();
      });
      final f = p
          .cast<NativeFunction<Double Function(Double)>>()
          .asFunction<double Function(double)>();
      expect(f(42), 42.0);
    }, skip: skipUnlessX64Host);

    test('AllocRetDouble2', () {
      final p = compile((cc) {
        final x = cc.newXmmSd('x');
        final y = cc.newXmmSd('y');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.float64, TypeId.float64], TypeId.float64));
        funcNode.setArg(0, 0, x);
        funcNode.setArg(1, 0, y);
        cc
          ..addsd(x, y)
          ..ret([x])
          ..endFunc();
      });
      final f = p
          .cast<NativeFunction<Double Function(Double, Double)>>()
          .asFunction<double Function(double, double)>();
      expect(f(1, 2), 1.0 + 2.0);
    }, skip: skipUnlessX64Host);

    test('AllocStack', () {
      const kSize = 256;
      final p = compile((cc) {
        cc.addFunc(FuncSignature.build([], TypeId.int32));
        final stack = cc.newStack(kSize, 1).withSize(1);
        final i = cc.newGpPtr('i');
        final a = cc.newGp32('a');
        final b = cc.newGp32('b');
        final l1 = cc.newLabel();
        final l2 = cc.newLabel();

        // Fill stack by sequence [0, 1, 2, 3 ... 255].
        cc.xor_(i, i);
        final stackWithIndex = X86Mem(
            base: stack.base,
            index: i,
            displacement: stack.displacement,
            size: stack.size);
        cc
          ..bind(l1)
          ..mov(stackWithIndex, i.as8)
          ..inc(i)
          ..cmp(i, Imm(255))
          ..jle(l1)
          // Sum sequence in stack.
          ..xor_(i, i)
          ..xor_(a, a)
          ..bind(l2)
          ..movzx(b, stackWithIndex)
          ..add(a, b)
          ..inc(i)
          ..cmp(i, Imm(255))
          ..jle(l2)
          ..ret([a])
          ..endFunc();
      });
      expect(
          p.cast<NativeFunction<_IntNative>>().asFunction<_IntDart>()(), 32640);
    }, skip: skipUnlessX64Host);
  });

  group('Instructions', () {
    test('Imul1', () {
      final p = compile((cc) {
        final dstHi = cc.newGpPtr('dst_hi');
        final dstLo = cc.newGpPtr('dst_lo');
        final vHi = cc.newGp32('v_hi');
        final vLo = cc.newGp32('v_lo');
        final src = cc.newGp32('src');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr, TypeId.int32, TypeId.int32],
            TypeId.void_));
        funcNode.setArg(0, 0, dstHi);
        funcNode.setArg(1, 0, dstLo);
        funcNode.setArg(2, 0, vLo);
        funcNode.setArg(3, 0, src);
        cc
          ..imul(vHi, vLo, src)
          ..mov(X86Mem.base(dstHi, size: 4), vHi)
          ..mov(X86Mem.base(dstLo, size: 4), vLo)
          ..endFunc();
      });
      final buf = calloc<Int32>(2);
      try {
        p.cast<NativeFunction<_N4>>().asFunction<_D4>()(buf, buf + 1, 4, 4);
        expect([buf[0], buf[1]], [0, 16]);
      } finally {
        calloc.free(buf);
      }
    }, skip: skipUnlessX64Host);

    test('Imul2', () {
      final p = compile((cc) {
        final dst = cc.newGpPtr('dst');
        final src = cc.newGpPtr('src');
        final funcNode = cc.addFunc(
            FuncSignature.build([TypeId.intPtr, TypeId.intPtr], TypeId.void_));
        funcNode.setArg(0, 0, dst);
        funcNode.setArg(1, 0, src);
        for (var i = 0; i < 4; i++) {
          final x = cc.newGp32('x');
          final y = cc.newGp32('y');
          final hi = cc.newGp32('hi');
          cc
            ..mov(x, X86Mem.baseDisp(src, 0, size: 4))
            ..mov(y, X86Mem.baseDisp(src, 4, size: 4))
            ..imul(hi, x, y)
            ..add(X86Mem.baseDisp(dst, 0, size: 4), hi)
            ..add(X86Mem.baseDisp(dst, 4, size: 4), x);
        }
        cc.endFunc();
      });
      final dst = calloc<Int32>(2);
      final src = calloc<Int32>(2);
      try {
        src[0] = 4;
        src[1] = 9;
        p.cast<NativeFunction<_Ptr2Native>>().asFunction<_Ptr2Dart>()(dst, src);
        expect([dst[0], dst[1]], [0, (4 * 9) * 4]);
      } finally {
        calloc.free(dst);
        calloc.free(src);
      }
    }, skip: skipUnlessX64Host);

    test('Idiv1', () {
      final p = compile((cc) {
        final a = cc.newGp32('a');
        final b = cc.newGp32('b');
        final dummy = cc.newGp32('dummy');
        final funcNode = cc.addFunc(
            FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.int32));
        funcNode.setArg(0, 0, a);
        funcNode.setArg(1, 0, b);
        cc
          ..xor_(dummy, dummy)
          ..idiv(dummy, a, b)
          ..ret([a])
          ..endFunc();
      });
      expect(
          p.cast<NativeFunction<_Int2Native>>().asFunction<_Int2Dart>()(
              2999, 245),
          2999 ~/ 245);
    }, skip: skipUnlessX64Host);

    test('Setz', () {
      final p = compile((cc) {
        final src0 = cc.newGp32('src0');
        final src1 = cc.newGp32('src1');
        final dst0 = cc.newGpPtr('dst0');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.int32, TypeId.int32, TypeId.intPtr], TypeId.void_));
        funcNode.setArg(0, 0, src0);
        funcNode.setArg(1, 0, src1);
        funcNode.setArg(2, 0, dst0);
        cc
          ..cmp(src0, src1)
          ..setz(X86Mem.base(dst0, size: 1))
          ..endFunc();
      });
      final f = p.cast<NativeFunction<_N5>>().asFunction<_D5>();
      final buf = calloc<Int8>(4);
      try {
        f(0, 0, buf + 0); // We are expecting 1 (0 == 0).
        f(0, 1, buf + 1); // We are expecting 0 (0 != 1).
        f(1, 0, buf + 2); // We are expecting 0 (1 != 0).
        f(1, 1, buf + 3); // We are expecting 1 (1 == 1).
        expect([for (var i = 0; i < 4; i++) buf[i]], [1, 0, 0, 1]);
      } finally {
        calloc.free(buf);
      }
    }, skip: skipUnlessX64Host);

    test('ShlRor', () {
      final p = compile((cc) {
        final dst = cc.newGpPtr('dst');
        final v = cc.newGp32('var');
        final vShlParam = cc.newGp32('v_shl_param');
        final vRorParam = cc.newGp32('v_ror_param');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.int32, TypeId.int32, TypeId.int32],
            TypeId.void_));
        funcNode.setArg(0, 0, dst);
        funcNode.setArg(1, 0, v);
        funcNode.setArg(2, 0, vShlParam);
        funcNode.setArg(3, 0, vRorParam);
        cc
          ..shl(v, vShlParam)
          ..ror(v, vRorParam)
          ..mov(X86Mem.base(dst, size: 4), v)
          ..endFunc();
      });
      final out = calloc<Int32>();
      try {
        p.cast<NativeFunction<_N6>>().asFunction<_D6>()(out, 0xFF, 16, 8);
        expect(out.value, 0x0000FF00);
      } finally {
        calloc.free(out);
      }
    }, skip: skipUnlessX64Host);

    test('GpbLo1', () {
      const kCount = 32;
      final p = compile((cc) {
        final regPtr = cc.newGpPtr('reg_Ptr');
        final sum = cc.newGp32('sum');
        final funcNode =
            cc.addFunc(FuncSignature.build([TypeId.intPtr], TypeId.uint32));
        funcNode.setArg(0, 0, regPtr);
        final x = [for (var i = 0; i < kCount; i++) cc.newGp32('x$i')];

        // Init pseudo-regs with values from our array.
        for (var i = 0; i < kCount; i++) {
          cc.mov(x[i], X86Mem.baseDisp(regPtr, i * 4, size: 4));
        }
        for (var i = 2; i < kCount; i++) {
          // Add and truncate to 8 bit; no purpose, just mess with jit.
          cc
            ..add(x[i], x[i - 1])
            ..movzx(x[i], x[i].as8)
            ..movzx(x[i - 2], x[i - 1].as8)
            ..movzx(x[i - 1], x[i - 2].as8);
        }
        // Sum up all computed values.
        cc.mov(sum, Imm(0));
        for (var i = 0; i < kCount; i++) {
          cc.add(sum, x[i]);
        }
        // Return the sum.
        cc
          ..ret([sum])
          ..endFunc();
      });
      final buf = List.filled(kCount, 1);
      for (var i = 2; i < kCount; i++) {
        buf[i] += buf[i - 1];
        buf[i] = buf[i] & 0xFF;
        buf[i - 2] = buf[i - 1] & 0xFF;
        buf[i - 1] = buf[i - 2] & 0xFF;
      }
      final expectRet = buf.reduce((a, b) => a + b);
      final mem = calloc<Uint32>(kCount);
      try {
        for (var i = 0; i < kCount; i++) {
          mem[i] = 1;
        }
        final f = p
            .cast<NativeFunction<Uint32 Function(Pointer<Uint32>)>>()
            .asFunction<int Function(Pointer<Uint32>)>();
        expect(f(mem), expectRet);
      } finally {
        calloc.free(mem);
      }
    }, skip: skipUnlessX64Host);

    test('GpbLo2', () {
      final p = compile((cc) {
        final v = cc.newGp32('v');
        final funcNode =
            cc.addFunc(FuncSignature.build([TypeId.uint32], TypeId.uint32));
        funcNode.setArg(0, 0, v);
        cc
          ..mov(v.as8, Imm(0xFF))
          ..ret([v])
          ..endFunc();
      });
      final f = p
          .cast<NativeFunction<Uint32 Function(Uint32)>>()
          .asFunction<int Function(int)>();
      expect(f(0x12345678), 0x123456FF);
    }, skip: skipUnlessX64Host);

    test('RepMovsb', () {
      final p = compile((cc) {
        final dst = cc.newGpPtr('dst');
        final src = cc.newGpPtr('src');
        final cnt = cc.newGpPtr('cnt');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr, TypeId.uintPtr], TypeId.void_));
        funcNode.setArg(0, 0, dst);
        funcNode.setArg(1, 0, src);
        funcNode.setArg(2, 0, cnt);
        cc
          ..rep(cnt).movs(X86Mem.base(dst, size: 1), X86Mem.base(src, size: 1))
          ..endFunc();
      });
      final dst = calloc<Uint8>(20).cast<Utf8>();
      final src = 'Hello AsmJit!'.toNativeUtf8();
      try {
        p.cast<NativeFunction<_N7>>().asFunction<_D7>()(
            dst, src, src.length + 1);
        expect(dst.toDartString(), 'Hello AsmJit!');
      } finally {
        calloc.free(dst);
        calloc.free(src);
      }
    }, skip: skipUnlessX64Host);

    test('IfElse1', () {
      final p = compile((cc) {
        final v1 = cc.newGp32('v1');
        final v2 = cc.newGp32('v2');
        final l1 = cc.newLabel();
        final l2 = cc.newLabel();
        final funcNode = cc.addFunc(
            FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.int32));
        funcNode.setArg(0, 0, v1);
        funcNode.setArg(1, 0, v2);
        cc
          ..cmp(v1, v2)
          ..jg(l1)
          ..mov(v1, Imm(1))
          ..jmp(l2)
          ..bind(l1)
          ..mov(v1, Imm(2))
          ..bind(l2)
          ..ret([v1])
          ..endFunc();
      });
      final f = p.cast<NativeFunction<_Int2Native>>().asFunction<_Int2Dart>();
      expect([f(0, 1), f(1, 0)], [1, 2]);
    }, skip: skipUnlessX64Host);

    test('IfElse2', () {
      final p = compile((cc) {
        final v1 = cc.newGp32('v1');
        final v2 = cc.newGp32('v2');
        final l1 = cc.newLabel();
        final l2 = cc.newLabel();
        final l3 = cc.newLabel();
        final l4 = cc.newLabel();
        final funcNode = cc.addFunc(
            FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.int32));
        funcNode.setArg(0, 0, v1);
        funcNode.setArg(1, 0, v2);
        cc
          ..jmp(l1)
          ..bind(l2)
          ..jmp(l4)
          ..bind(l1)
          ..cmp(v1, v2)
          ..jg(l3)
          ..mov(v1, Imm(1))
          ..jmp(l2)
          ..bind(l3)
          ..mov(v1, Imm(2))
          ..jmp(l2)
          ..bind(l4)
          ..ret([v1])
          ..endFunc();
      });
      final f = p.cast<NativeFunction<_Int2Native>>().asFunction<_Int2Dart>();
      expect([f(0, 1), f(1, 0)], [1, 2]);
    }, skip: skipUnlessX64Host);

    test('IfElse3', () {
      final p = compile((cc) {
        final v1 = cc.newGp32('v1');
        final v2 = cc.newGp32('v2');
        final counter = cc.newGp32('counter');
        final l1 = cc.newLabel();
        final lLoop = cc.newLabel();
        final lExit = cc.newLabel();
        final funcNode = cc.addFunc(
            FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.int32));
        funcNode.setArg(0, 0, v1);
        funcNode.setArg(1, 0, v2);
        cc
          ..cmp(v1, v2)
          ..jg(l1)
          ..mov(counter, Imm(0))
          ..bind(lLoop)
          ..mov(v1, counter)
          ..inc(counter)
          ..cmp(counter, Imm(1))
          ..jle(lLoop)
          ..jmp(lExit)
          ..bind(l1)
          ..mov(v1, Imm(2))
          ..bind(lExit)
          ..ret([v1])
          ..endFunc();
      });
      final f = p.cast<NativeFunction<_Int2Native>>().asFunction<_Int2Dart>();
      expect([f(0, 1), f(1, 0)], [1, 2]);
    }, skip: skipUnlessX64Host);

    test('IfElse4', () {
      final p = compile((cc) {
        final v1 = cc.newGp32('v1');
        final v2 = cc.newGp32('v2');
        final counter = cc.newGp32('counter');
        final l1 = cc.newLabel();
        final lLoop1 = cc.newLabel();
        final lLoop2 = cc.newLabel();
        final lExit = cc.newLabel();
        final funcNode = cc.addFunc(
            FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.int32));
        funcNode.setArg(0, 0, v1);
        funcNode.setArg(1, 0, v2);
        cc
          ..mov(counter, Imm(0))
          ..cmp(v1, v2)
          ..jg(l1)
          ..bind(lLoop1)
          ..mov(v1, counter)
          ..inc(counter)
          ..cmp(counter, Imm(1))
          ..jle(lLoop1)
          ..jmp(lExit)
          ..bind(l1)
          ..bind(lLoop2)
          ..mov(v1, counter)
          ..inc(counter)
          ..cmp(counter, Imm(2))
          ..jle(lLoop2)
          ..bind(lExit)
          ..ret([v1])
          ..endFunc();
      });
      final f = p.cast<NativeFunction<_Int2Native>>().asFunction<_Int2Dart>();
      expect([f(0, 1), f(1, 0)], [1, 2]);
    }, skip: skipUnlessX64Host);

    test('Memcpy', () {
      const kCount = 32;
      final p = compile((cc) {
        final dst = cc.newGpPtr('dst');
        final src = cc.newGpPtr('src');
        final cnt = cc.newGpPtr('cnt');
        final lLoop = cc.newLabel(); // Create base labels we use
        final lExit = cc.newLabel(); // in our function.
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr, TypeId.uintPtr], TypeId.void_));
        funcNode.setArg(0, 0, dst);
        funcNode.setArg(1, 0, src);
        funcNode.setArg(2, 0, cnt);
        cc
          ..test(cnt, cnt) // Exit if the size is zero.
          ..jz(lExit)
          ..bind(lLoop); // Bind the loop label here.
        final tmp = cc.newGp32('tmp'); // Copy a single dword (4 bytes).
        cc
          ..mov(tmp, X86Mem.base(src, size: 4))
          ..mov(X86Mem.base(dst, size: 4), tmp)
          ..add(src, Imm(4)) // Increment dst/src pointers.
          ..add(dst, Imm(4))
          ..dec(cnt) // Loop until cnt isn't zero.
          ..jnz(lLoop)
          ..bind(lExit) // Bind the exit label here.
          ..endFunc(); // End of function.
      });
      final dst = calloc<Uint32>(kCount);
      final src = calloc<Uint32>(kCount);
      try {
        for (var i = 0; i < kCount; i++) {
          src[i] = i;
        }
        p.cast<NativeFunction<_N8>>().asFunction<_D8>()(dst, src, kCount);
        expect([for (var i = 0; i < kCount; i++) dst[i]],
            [for (var i = 0; i < kCount; i++) i]);
      } finally {
        calloc.free(dst);
        calloc.free(src);
      }
    }, skip: skipUnlessX64Host);

    test('AlphaBlend', () {
      const kCount = 17;
      final p = compile(_generateSseAlphaBlend);
      const dstConstData = [
        0x00000000,
        0x10101010,
        0x20100804,
        0x30200003,
        0x40204040,
        0x5000004D,
        0x60302E2C,
        0x706F6E6D,
        0x807F4F2F,
        0x90349001,
        0xA0010203,
        0xB03204AB,
        0xC023AFBD,
        0xD0D0D0C0,
        0xE0AABBCC,
        0xFFFFFFFF,
        0xF8F4F2F1
      ];
      const srcConstData = [
        0xE0E0E0E0,
        0xA0008080,
        0x341F1E1A,
        0xFEFEFEFE,
        0x80302010,
        0x49490A0B,
        0x998F7798,
        0x00000000,
        0x01010101,
        0xA0264733,
        0xBAB0B1B9,
        0xFF000000,
        0xDAB0A0C1,
        0xE0BACFDA,
        0x99887766,
        0xFFFFFF80,
        0xEE0A5FEC
      ];
      // Has to be aligned.
      final storage = calloc<Uint32>(2 * (kCount + 3) + 4);
      try {
        final base = (storage.address + 15) & ~15;
        final dstBuffer = Pointer<Uint32>.fromAddress(base);
        final srcBuffer = dstBuffer + (kCount + 3);
        for (var i = 0; i < kCount; i++) {
          dstBuffer[i] = dstConstData[i];
          srcBuffer[i] = srcConstData[i];
        }
        final expBuffer = [
          for (var i = 0; i < kCount; i++)
            _blendSrcOver(dstConstData[i], srcConstData[i])
        ];
        p
            .cast<
                NativeFunction<
                    Void Function(Pointer<Uint32>, Pointer<Uint32>, IntPtr)>>()
            .asFunction<
                void Function(Pointer<Uint32>, Pointer<Uint32>,
                    int)>()(dstBuffer, srcBuffer, kCount);
        expect([for (var i = 0; i < kCount; i++) dstBuffer[i]], expBuffer);
      } finally {
        calloc.free(storage);
      }
    }, skip: skipUnlessX64Host);

    // Upstream adds the AVX-512 tests only when the host has AVX512_F.
    test('AVX512_KK', () {
      final p = compile((cc) {
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr, TypeId.uint32], TypeId.uint32));

        final a = cc.newGpPtr('a');
        final b = cc.newGpPtr('b');
        final pred = cc.newGp32('pred');
        final result = cc.newGp32('result');

        final va = cc.newZmm('va');
        final vb = cc.newZmm('vb');
        final kIn = cc.newKd('k_in');
        final kOut = cc.newKd('k_out');

        funcNode.setArg(0, 0, a);
        funcNode.setArg(1, 0, b);
        funcNode.setArg(2, 0, pred);

        cc
          ..inst(X86InstId.kVmovdqu32, [va, X86Mem.base(a)])
          ..inst(X86InstId.kVmovdqu32, [vb, X86Mem.base(b)])
          ..inst(X86InstId.kKmovd, [kIn, pred])
          ..k(kIn).inst(X86InstId.kVpcmpeqd, [kOut, va, vb])
          ..inst(X86InstId.kKmovd, [result, kOut])
          ..ret([result])
          ..endFunc();
      });
      const srcA = [0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1];
      const srcB = [0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1];
      final m = calloc<Uint32>(32);
      try {
        for (var i = 0; i < 16; i++) {
          m[i] = srcA[i];
          m[16 + i] = srcB[i];
        }
        final ret = p
                .cast<
                    NativeFunction<
                        Uint32 Function(
                            Pointer<Uint32>, Pointer<Uint32>, Uint32)>>()
                .asFunction<
                    int Function(Pointer<Uint32>, Pointer<Uint32>, int)>()(
            m, m + 16, 0xF0F0);
        expect(ret, 0xA040);
      } finally {
        calloc.free(m);
      }
    },
        skip: !hostIsX64
            ? skipUnlessX64Host
            : _hasAvx512f
                ? false
                : 'requires AVX512_F (as upstream)');

    test('AVX512_TernLog', () {
      final p = compile((cc) {
        final funcNode =
            cc.addFunc(FuncSignature.build([TypeId.intPtr], TypeId.void_));
        final outPtr = cc.newGpPtr('out_ptr');
        final vec = cc.newZmm('vec');
        funcNode.setArg(0, 0, outPtr);
        cc
          ..inst(X86InstId.kVpternlogd, [vec, vec, vec, Imm(0xFF)])
          ..inst(X86InstId.kVmovdqu8, [X86Mem.base(outPtr), vec])
          ..endFunc();
      });
      final out = calloc<Uint32>(16);
      try {
        p
            .cast<NativeFunction<Void Function(Pointer<Uint32>)>>()
            .asFunction<void Function(Pointer<Uint32>)>()(out);
        expect(
            [for (var i = 0; i < 16; i++) out[i]], List.filled(16, 0xFFFFFFFF));
      } finally {
        calloc.free(out);
      }
    },
        skip: !hostIsX64
            ? skipUnlessX64Host
            : _hasAvx512f
                ? false
                : 'requires AVX512_F (as upstream)');

    test('ExtraBlock', () {
      final p = compile((cc) {
        final cond = cc.newGp32('cond');
        final ret = cc.newGp32('ret');
        final a = cc.newGp32('a');
        final b = cc.newGp32('b');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.int32, TypeId.int32, TypeId.int32], TypeId.int32));
        funcNode.setArg(0, 0, cond);
        funcNode.setArg(1, 0, a);
        funcNode.setArg(2, 0, b);

        final lRet = cc.newLabel();
        final lExtra = cc.newLabel();

        cc
          ..test(cond, cond)
          ..jnz(lExtra)
          ..mov(ret, a)
          ..add(ret, b)
          ..bind(lRet)
          ..ret([ret]);

        // Emit code sequence at the end of the function.
        final prevCursor = cc.setCursor(funcNode.endNode!.prev);
        cc
          ..bind(lExtra)
          ..mov(ret, a)
          ..sub(ret, b)
          ..jmp(lRet);
        cc.setCursor(prevCursor);

        cc.endFunc();
      });
      final f = p.cast<NativeFunction<_Int3Native>>().asFunction<_Int3Dart>();
      expect([f(0, 4, 5), f(1, 4, 5)], [4 + 5, 4 - 5]);
    }, skip: skipUnlessX64Host);
  });

  group('FuncArgs', () {
    test('FuncArgInt8', () {
      final p = compile((cc) {
        final v0 = cc.newGp32('v0');
        final v1 = cc.newGp32('v1');
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.uint8, TypeId.uint8, TypeId.uint32], TypeId.uint32));
        funcNode.setArg(0, 0, v0);
        funcNode.setArg(1, 0, v1);
        cc
          ..add(v0, v1)
          ..ret([v0])
          ..endFunc();
      });
      final arg = p.address & 0xFFFFFFFF;
      expect(
          p.cast<NativeFunction<_N9>>().asFunction<_D9>()(
              arg & 0xFF, arg & 0xFF, arg),
          (arg & 0xFF) * 2);
    }, skip: skipUnlessX64Host);
  });

  group('Misc', () {
    for (final (name, scope) in [
      ('MiscLocalConstPool', ConstPoolScope.local),
      ('MiscGlobalConstPool', ConstPoolScope.global),
    ]) {
      test(name, () {
        final p = compile((cc) {
          cc.addFunc(FuncSignature.build([], TypeId.int32));
          final v0 = cc.newGp32('v0');
          final v1 = cc.newGp32('v1');
          final c0 = cc.newInt32Const(scope, 200);
          final c1 = cc.newInt32Const(scope, 33);
          cc
            ..mov(v0, c0)
            ..mov(v1, c1)
            ..add(v0, v1)
            ..ret([v0])
            ..endFunc();
        });
        expect(
            p.cast<NativeFunction<_IntNative>>().asFunction<_IntDart>()(), 233);
      }, skip: skipUnlessX64Host);
    }

    // Upstream runs it with setjmp()/longjmp(): `handler()` longjmps back
    // to the caller of the generated function, which dart:ffi cannot do (a
    // Dart callback cannot unwind native frames). The function is compiled
    // and the unfollowed jump checked to be emitted without successors.
    test('MiscUnfollow (compile only)', () {
      final code = CodeHolder(env: x64TestEnv());
      final cc = X86Compiler(env: code.env, labelManager: code.labelManager);
      // NOTE: Fastcall calling convention is the most appropriate here as
      // all arguments are passed via registers and there won't be any stack
      // misalignment in the `handler()`.
      final a = cc.newGp32('a');
      final b = cc.newGpPtr('b');
      final tramp = cc.newLabel();

      final funcNode = cc.addFunc(FuncSignature.build(
          [TypeId.int32, TypeId.intPtr], TypeId.int32, CallConvId.fastCall));
      funcNode.setArg(0, 0, a);
      funcNode.setArg(1, 0, b);

      cc
        ..cmp(a, Imm(0))
        ..jz(tramp)
        ..ret([a])
        ..bind(tramp);
      final jmp = cc.unfollow().jmpIndirect(b);
      cc.endFunc();

      expect(jmp.options & kInstOptionUnfollow, isNot(0));
      cc.finalize();
      cc.serializeToAssembler(X86Assembler(code));
      // `jmp b` was rewritten to a physical register.
      expect((jmp.operands[0] as BaseReg).isPhysical, isTrue);
    });

    test('VecToScalar', () {
      const kVecCount = 64;
      final p = compile((cc) {
        final func =
            cc.addFunc(FuncSignature.build([TypeId.uint32], TypeId.uint32));
        final x = cc.newGp32('x');
        final t = cc.newGp32('t');
        func.setArg(0, 0, x);
        final v = <X86Xmm>[];
        for (var i = 0; i < kVecCount; i++) {
          v.add(cc.newXmm('v$i'));
          if (i != 0) cc.add(x, Imm(1));
          cc.movd(v[i], x);
        }
        cc.xor_(x, x);
        for (var i = 0; i < kVecCount; i++) {
          cc
            ..movd(t, v[i])
            ..add(x, t);
        }
        cc
          ..ret([x])
          ..endFunc();
      });
      final f = p
          .cast<NativeFunction<Uint32 Function(Uint32)>>()
          .asFunction<int Function(int)>();
      expect(f(1), 2080); // 1 + 2 + 3 + ... + 64
    }, skip: skipUnlessX64Host);

    test('MiscMultiRet', () {
      final p = compile((cc) {
        final funcNode = cc.addFunc(FuncSignature.build(
            [TypeId.int32, TypeId.int32, TypeId.int32], TypeId.int32));
        final op = cc.newGp32('op');
        final a = cc.newGp32('a');
        final b = cc.newGp32('b');
        final lZero = cc.newLabel();
        final lAdd = cc.newLabel();
        final lSub = cc.newLabel();
        final lMul = cc.newLabel();
        final lDiv = cc.newLabel();
        funcNode.setArg(0, 0, op);
        funcNode.setArg(1, 0, a);
        funcNode.setArg(2, 0, b);
        cc
          ..cmp(op, Imm(0))
          ..jz(lAdd)
          ..cmp(op, Imm(1))
          ..jz(lSub)
          ..cmp(op, Imm(2))
          ..jz(lMul)
          ..cmp(op, Imm(3))
          ..jz(lDiv)
          ..bind(lZero)
          ..xor_(a, a)
          ..ret([a])
          ..bind(lAdd)
          ..add(a, b)
          ..ret([a])
          ..bind(lSub)
          ..sub(a, b)
          ..ret([a])
          ..bind(lMul)
          ..imul(a, b)
          ..ret([a])
          ..bind(lDiv)
          ..cmp(b, Imm(0))
          ..jz(lZero);
        final zero = cc.newGp32('zero');
        cc
          ..xor_(zero, zero)
          ..idiv(zero, a, b)
          ..ret([a])
          ..endFunc();
      });
      final f = p.cast<NativeFunction<_Int3Native>>().asFunction<_Int3Dart>();
      const a = 44;
      const b = 3;
      expect([f(0, a, b), f(1, a, b), f(2, a, b), f(3, a, b)],
          [a + b, a - b, a * b, a ~/ b]);
    }, skip: skipUnlessX64Host);
  });
}
