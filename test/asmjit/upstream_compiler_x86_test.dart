// Ports of the x86 compiler tests of upstream asmjit
// (asmjit-testing/tests/asmjit_test_compiler_x86.cpp, `X86Test_*`): each
// test builds the same instructions, virtual registers and control flow as
// upstream `compile()` and checks what upstream `run()` checks.
import 'dart:ffi';

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
