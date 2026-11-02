// Ports of the function call tests of upstream asmjit
// (asmjit-testing/tests/asmjit_test_compiler_x86.cpp, `X86Test_FuncCall*`
// and `X86Test_MiscMultiFunc`): each test builds the same instructions,
// virtual registers and calls (`invoke()`) as upstream `compile()` and checks
// what upstream `run()` checks.
//
// The C++ functions upstream calls are Dart callbacks here
// (`Pointer.fromFunction`), or libc for memcpy/memcmp. The variadic callees
// of FuncCallVarArg1/2 are fixed-signature Dart callbacks: on SysV and Win64
// a variadic caller passes the leading integer/double arguments in the same
// registers (and stack slots) a non-variadic callee reads them from.
import 'dart:ffi';
import 'dart:io';

import 'package:asmjit/asmjit.dart' hide calloc;
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import '../support/host.dart';

typedef _I3N = Int32 Function(Int32, Int32, Int32);
typedef _I3D = int Function(int, int, int);
typedef _I2N = Int32 Function(Int32, Int32);
typedef _I2D = int Function(int, int);
typedef _I1N = Int32 Function(Int32);
typedef _I1D = int Function(int);
typedef _I0N = Int32 Function();
typedef _I0D = int Function();
typedef _I10N = Int32 Function(
    Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32);
typedef _P10N = Int32 Function(IntPtr, IntPtr, IntPtr, IntPtr, IntPtr, IntPtr,
    IntPtr, IntPtr, IntPtr, IntPtr);
typedef _Ref4N = Int32 Function(
    Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _Ref4D = int Function(
    Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _F2N = Float Function(Float, Float);
typedef _F2D = double Function(double, double);
typedef _D2N = Double Function(Double, Double);
typedef _D2D = double Function(double, double);
typedef _D1N = Double Function(Double);

int _base1Fn(int a, int b, int c) => (a + b) * c;
int _stdFn(int a, int b, int c) => (a + b) * c;
int _fastFn(int a) => a * a;
int _manyArgsFn(
        int a, int b, int c, int d, int e, int f, int g, int h, int i, int j) =>
    ((a * b * c * d * e) + (f * g * h * i * j)).toSigned(32);
int _ptrArgsFn(
        int a, int b, int c, int d, int e, int f, int g, int h, int i, int j) =>
    a + b + c + d + e + f + g + h + i + j;
int _refArgsFn(
    Pointer<Int32> a, Pointer<Int32> b, Pointer<Int32> c, Pointer<Int32> d) {
  a.value += a.value;
  b.value += b.value;
  c.value += c.value;
  d.value += d.value;
  return a.value + b.value + c.value + d.value;
}

double _floatMulFn(double a, double b) => a * b;
double _doubleMulFn(double a, double b) => a * b;
int _addFn(int x, int y) => x + y;
int _mulFn(int x, int y) => x * y;
int _multipleFn(Pointer<Int32> pInt, int index) => pInt[index];
int _varArgIntFn(int n, int a, int b, int c, int d) => a + b + c + d;
double _varArgDoubleFn(int n, double a, double b, double c, double d) =>
    a + b + c + d;
void _dummyFn(int a, int b) {}
double _squareFn(double a) => a * a;
double _misc4Fn() => 3.14;
void _voidFn() {}
int _incFn(int x) => (x + 1) & 0xFFFFFFFF;

void main() {
  late JitRuntime rt;
  setUp(() => rt = JitRuntime());
  tearDown(() => rt.dispose());

  final isWin64 = hostIsX64 && Platform.isWindows;

  Pointer<Void> compile(void Function(X86Compiler cc) body) {
    final code = CodeHolder(env: rt.environment);
    final cc = X86Compiler(env: code.env, labelManager: code.labelManager);
    body(cc);
    cc.finalize();
    cc.serializeToAssembler(X86Assembler(code));
    return rt.add(code).pointer;
  }

  Pointer<Void> assemble(void Function(X86Assembler a) body) {
    final code = CodeHolder(env: rt.environment);
    body(X86Assembler(code));
    return rt.add(code).pointer;
  }

  Imm fnImm(Pointer<NativeFunction> p) => Imm(p.address);

  test('FuncCallBase1', () {
    final p = compile((cc) {
      final v0 = cc.newGp32('v0');
      final v1 = cc.newGp32('v1');
      final v2 = cc.newGp32('v2');
      final sig = FuncSignature.build(
          [TypeId.int32, TypeId.int32, TypeId.int32], TypeId.int32);
      final funcNode = cc.addFunc(sig);
      funcNode.setArg(0, 0, v0);
      funcNode.setArg(1, 0, v1);
      funcNode.setArg(2, 0, v2);

      // Just do something.
      cc
        ..shl(v0, Imm(1))
        ..shl(v1, Imm(1))
        ..shl(v2, Imm(1));

      // Call a function.
      final invokeNode =
          cc.invoke(fnImm(Pointer.fromFunction<_I3N>(_base1Fn, 0)), sig);
      invokeNode
        ..setArg(0, v2)
        ..setArg(1, v1)
        ..setArg(2, v0)
        ..setRet(0, v0);
      cc
        ..ret([v0])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_I3N>>().asFunction<_I3D>()(3, 2, 1), 36);
  }, skip: skipUnlessX64Host);

  test('FuncCallBase2', () {
    const kTokenSize = 32;
    final token = '-+:|abcdefghijklmnopqrstuvwxyz|'.toNativeUtf8();
    addTearDown(() => calloc.free(token));
    final memcpy = libc.lookup<NativeFunction<Void Function()>>('memcpy');
    final memcmp = libc.lookup<NativeFunction<Void Function()>>('memcmp');
    final p = compile((cc) {
      cc.addFunc(FuncSignature.build([], TypeId.int32));

      final s1 = cc.newStack(kTokenSize, 32);
      final s2 = cc.newStack(kTokenSize, 32);
      final p1 = cc.newGpPtr('p1');
      final p2 = cc.newGpPtr('p2');
      final ret = cc.newGp32('ret');
      final lExit = cc.newLabel();

      cc
        ..lea(p1, s1)
        ..lea(p2, s2);

      // Try to corrupt the stack if wrongly allocated.
      final memcpySig = FuncSignature.build(
          [TypeId.intPtr, TypeId.intPtr, TypeId.uintPtr], TypeId.intPtr);
      cc.invoke(fnImm(memcpy), memcpySig)
        ..setArg(0, p1)
        ..setArg(1, Imm(token.address))
        ..setArg(2, Imm(kTokenSize))
        ..setRet(0, p1);
      cc.invoke(fnImm(memcpy), memcpySig)
        ..setArg(0, p2)
        ..setArg(1, Imm(token.address))
        ..setArg(2, Imm(kTokenSize))
        ..setRet(0, p2);
      cc.invoke(
          fnImm(memcmp),
          FuncSignature.build(
              [TypeId.intPtr, TypeId.intPtr, TypeId.uintPtr], TypeId.int32))
        ..setArg(0, p1)
        ..setArg(1, p2)
        ..setArg(2, Imm(kTokenSize))
        ..setRet(0, ret);

      // This should be 0 on success, however, if both `p1` and `p2` were
      // allocated in the same address this check will still pass.
      cc
        ..cmp(ret, Imm(0))
        ..jnz(lExit)
        // Checks whether `p1` and `p2` are different (must be).
        ..xor_(ret, ret)
        ..cmp(p1, p2)
        ..setz(ret.as8)
        ..bind(lExit)
        ..ret([ret])
        ..endFunc();
    });
    // Must be zero, stack addresses must be different.
    expect(p.cast<NativeFunction<_I0N>>().asFunction<_I0D>()(), 0);
  }, skip: skipUnlessX64Host);

  test('FuncCallStd', () {
    final p = compile((cc) {
      final x = cc.newGp32('x');
      final y = cc.newGp32('y');
      final z = cc.newGp32('z');
      final funcNode = cc.addFunc(FuncSignature.build(
          [TypeId.int32, TypeId.int32, TypeId.int32], TypeId.int32));
      funcNode.setArg(0, 0, x);
      funcNode.setArg(1, 0, y);
      funcNode.setArg(2, 0, z);
      // STDCALL is the default calling convention on x86-64.
      cc.invoke(
          fnImm(Pointer.fromFunction<_I3N>(_stdFn, 0)),
          FuncSignature.build([TypeId.int32, TypeId.int32, TypeId.int32],
              TypeId.int32, CallConvId.stdCall))
        ..setArg(0, x)
        ..setArg(1, y)
        ..setArg(2, z)
        ..setRet(0, x);
      cc
        ..ret([x])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_I3N>>().asFunction<_I3D>()(1, 42, 3),
        _stdFn(1, 42, 3));
  }, skip: skipUnlessX64Host);

  test('FuncCallFast', () {
    final p = compile((cc) {
      final v = cc.newGp32('var');
      final funcNode =
          cc.addFunc(FuncSignature.build([TypeId.int32], TypeId.int32));
      funcNode.setArg(0, 0, v);
      final sig = FuncSignature.build(
          [TypeId.int32], TypeId.int32, CallConvId.fastCall);
      final fn = fnImm(Pointer.fromFunction<_I1N>(_fastFn, 0));
      cc.invoke(fn, sig)
        ..setArg(0, v)
        ..setRet(0, v);
      cc.invoke(fn, sig)
        ..setArg(0, v)
        ..setRet(0, v);
      cc
        ..ret([v])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_I1N>>().asFunction<_I1D>()(9),
        (9 * 9) * (9 * 9));
  }, skip: skipUnlessX64Host);

  // Upstream adds the vectorcall variant only when built by MSVC.
  test('FuncCallSIMD {VectorCall=N}', () {
    // `__m128i called_fn_cdecl(__m128i a, __m128i b)`: written with the
    // assembler for the host ABI (Win64 passes __m128i by reference).
    final calledFn = assemble((a) {
      if (isWin64) {
        a
          ..emit(X86InstId.kMovdqu, [xmm0, X86Mem.base(rcx)])
          ..emit(X86InstId.kMovdqu, [xmm1, X86Mem.base(rdx)]);
      }
      a
        ..emit(X86InstId.kPaddb, [xmm0, xmm1])
        ..emit(X86InstId.kRet, []);
    });
    final p = compile((cc) {
      final funcNode = cc.addFunc(FuncSignature.build(
          [TypeId.intPtr, TypeId.intPtr, TypeId.intPtr], TypeId.void_));
      final resultPtr = cc.newGpPtr('result_ptr');
      final aPtr = cc.newGpPtr('a_ptr');
      final bPtr = cc.newGpPtr('b_ptr');
      final pFn = cc.newGpPtr('p_fn');
      final xmmA = cc.newXmm('xmm_a');
      final xmmB = cc.newXmm('xmm_b');
      funcNode.setArg(0, 0, resultPtr);
      funcNode.setArg(1, 0, aPtr);
      funcNode.setArg(2, 0, bPtr);

      cc
        ..mov(pFn, Imm(calledFn.address))
        ..movdqu(xmmA, X86Mem.base(aPtr))
        ..movdqu(xmmB, X86Mem.base(bPtr));
      cc.invoke(pFn,
          FuncSignature.build([TypeId.int32x4, TypeId.int32x4], TypeId.int32x4))
        ..setArg(0, xmmA)
        ..setArg(1, xmmB)
        ..setRet(0, xmmA);
      cc
        ..movdqu(X86Mem.base(resultPtr), xmmA)
        ..endFunc();
    });
    final data = calloc<Uint8>(48);
    try {
      for (var i = 0; i < 16; i++) {
        data[i] = i;
        data[16 + i] = 15 - i;
      }
      p
          .cast<
              NativeFunction<
                  Void Function(
                      Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>>()
          .asFunction<
              void Function(Pointer<Uint8>, Pointer<Uint8>,
                  Pointer<Uint8>)>()(data + 32, data, data + 16);
      expect([for (var i = 0; i < 16; i++) data[32 + i]], List.filled(16, 15));
    } finally {
      calloc.free(data);
    }
  }, skip: skipUnlessX64Host);

  test('FuncCallLight', () {
    final p = compile((cc) {
      final f1Signature =
          FuncSignature.build(List.filled(5, TypeId.intPtr), TypeId.void_);
      final f2Signature = FuncSignature.build([TypeId.int32x4, TypeId.int32x4],
          TypeId.int32x4, CallConvId.lightCall2);

      final f1Node = cc.newFunc(f1Signature);
      final f2Node = cc.newFunc(f2Signature);

      {
        final aPtr = cc.newGpPtr('a_ptr');
        final bPtr = cc.newGpPtr('b_ptr');
        final cPtr = cc.newGpPtr('c_ptr');
        final dPtr = cc.newGpPtr('d_ptr');
        final pOut = cc.newGpPtr('p_out');

        final xmmA = cc.newXmm('xmm_a');
        final xmmB = cc.newXmm('xmm_b');
        final xmmC = cc.newXmm('xmm_c');
        final xmmD = cc.newXmm('xmm_d');

        cc.addFuncNode(f1Node);
        f1Node.setArg(0, 0, aPtr);
        f1Node.setArg(1, 0, bPtr);
        f1Node.setArg(2, 0, cPtr);
        f1Node.setArg(3, 0, dPtr);
        f1Node.setArg(4, 0, pOut);

        cc
          ..movups(xmmA, X86Mem.base(aPtr))
          ..movups(xmmB, X86Mem.base(bPtr))
          ..movups(xmmC, X86Mem.base(cPtr))
          ..movups(xmmD, X86Mem.base(dPtr));

        final xmmX = cc.newXmm('xmm_x');
        final xmmY = cc.newXmm('xmm_y');

        cc.invoke(LabelOp(f2Node.label), f2Signature)
          ..setArg(0, xmmA)
          ..setArg(1, xmmB)
          ..setRet(0, xmmX);
        cc.invoke(LabelOp(f2Node.label), f2Signature)
          ..setArg(0, xmmC)
          ..setArg(1, xmmD)
          ..setRet(0, xmmY);
        cc
          ..pmullw(xmmX, xmmY)
          ..movups(X86Mem.base(pOut), xmmX)
          ..endFunc();
      }

      {
        final xmmA = cc.newXmm('xmm_a');
        final xmmB = cc.newXmm('xmm_b');

        cc.addFuncNode(f2Node);
        f2Node.setArg(0, 0, xmmA);
        f2Node.setArg(1, 0, xmmB);
        cc
          ..paddw(xmmA, xmmB)
          ..ret([xmmA])
          ..endFunc();
      }
    });
    final m = calloc<Int16>(40);
    try {
      const a = [0, 1, 2, 3, 4, 5, 6, 7];
      const b = [7, 6, 5, 4, 3, 2, 1, 0];
      const c = [1, 3, 9, 7, 5, 4, 2, 1];
      const d = [2, 0, -6, -4, -2, -1, 1, 2];
      for (var i = 0; i < 8; i++) {
        m[i] = a[i];
        m[8 + i] = b[i];
        m[16 + i] = c[i];
        m[24 + i] = d[i];
      }
      p
          .cast<
              NativeFunction<
                  Void Function(Pointer<Int16>, Pointer<Int16>, Pointer<Int16>,
                      Pointer<Int16>, Pointer<Int16>)>>()
          .asFunction<
              void Function(
                  Pointer<Int16>,
                  Pointer<Int16>,
                  Pointer<Int16>,
                  Pointer<Int16>,
                  Pointer<Int16>)>()(m, m + 8, m + 16, m + 24, m + 32);
      expect([for (var i = 0; i < 8; i++) m[32 + i]], List.filled(8, 7 * 3));
    } finally {
      calloc.free(m);
    }
  }, skip: skipUnlessX64Host);

  test('FuncCallManyArgs', () {
    final p = compile((cc) {
      cc.addFunc(FuncSignature.build([], TypeId.int32));

      // Prepare.
      final names = [
        'va',
        'vb',
        'vc',
        'vd',
        've',
        'vf',
        'vg',
        'vh',
        'vi',
        'vj'
      ];
      const values = [
        0x03,
        0x12,
        0xA0,
        0x0B,
        0x2F,
        0x02,
        0x0C,
        0x12,
        0x18,
        0x1E
      ];
      final v = [for (final n in names) cc.newGp32(n)];
      for (var i = 0; i < 10; i++) {
        cc.mov(v[i], Imm(values[i]));
      }

      // Function call.
      final invokeNode = cc.invoke(
          fnImm(Pointer.fromFunction<_I10N>(_manyArgsFn, 0)),
          FuncSignature.build(List.filled(10, TypeId.int32), TypeId.int32));
      for (var i = 0; i < 10; i++) {
        invokeNode.setArg(i, v[i]);
      }
      invokeNode.setRet(0, v[0]);
      cc
        ..ret([v[0]])
        ..endFunc();
    });
    expect(
        p.cast<NativeFunction<_I0N>>().asFunction<_I0D>()(),
        _manyArgsFn(
            0x03, 0x12, 0xA0, 0x0B, 0x2F, 0x02, 0x0C, 0x12, 0x18, 0x1E));
  }, skip: skipUnlessX64Host);

  test('FuncCallDuplicateArgs', () {
    final p = compile((cc) {
      cc.addFunc(FuncSignature.build([], TypeId.int32));

      // Prepare.
      final a = cc.newGp32('a');
      cc.mov(a, Imm(3));

      // Call function.
      final invokeNode = cc.invoke(
          fnImm(Pointer.fromFunction<_I10N>(_manyArgsFn, 0)),
          FuncSignature.build(List.filled(10, TypeId.int32), TypeId.int32));
      for (var i = 0; i < 10; i++) {
        invokeNode.setArg(i, a);
      }
      invokeNode.setRet(0, a);
      cc
        ..ret([a])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_I0N>>().asFunction<_I0D>()(),
        _manyArgsFn(3, 3, 3, 3, 3, 3, 3, 3, 3, 3));
  }, skip: skipUnlessX64Host);

  test('FuncCallImmArgs', () {
    final p = compile((cc) {
      cc.addFunc(FuncSignature.build([], TypeId.int32));

      // Prepare.
      final rv = cc.newGp32('rv');

      // Call function.
      final invokeNode = cc.invoke(
          fnImm(Pointer.fromFunction<_I10N>(_manyArgsFn, 0)),
          FuncSignature.build(List.filled(10, TypeId.int32), TypeId.int32));
      const values = [
        0x03,
        0x12,
        0xA0,
        0x0B,
        0x2F,
        0x02,
        0x0C,
        0x12,
        0x18,
        0x1E
      ];
      for (var i = 0; i < 10; i++) {
        invokeNode.setArg(i, Imm(values[i]));
      }
      invokeNode.setRet(0, rv);
      cc
        ..ret([rv])
        ..endFunc();
    });
    expect(
        p.cast<NativeFunction<_I0N>>().asFunction<_I0D>()(),
        _manyArgsFn(
            0x03, 0x12, 0xA0, 0x0B, 0x2F, 0x02, 0x0C, 0x12, 0x18, 0x1E));
  }, skip: skipUnlessX64Host);

  test('FuncCallPtrArgs', () {
    final p = compile((cc) {
      cc.addFunc(FuncSignature.build([], TypeId.int32));

      // Prepare.
      final rv = cc.newGp32('rv');

      // Call function.
      final invokeNode = cc.invoke(
          fnImm(Pointer.fromFunction<_P10N>(_ptrArgsFn, 0)),
          FuncSignature.build(List.filled(10, TypeId.intPtr), TypeId.int32));
      for (var i = 0; i < 10; i++) {
        invokeNode.setArg(i, Imm(i + 1));
      }
      invokeNode.setRet(0, rv);
      cc
        ..ret([rv])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_I0N>>().asFunction<_I0D>()(), 55);
  }, skip: skipUnlessX64Host);

  test('FuncCallRefArgs', () {
    final p = compile((cc) {
      // `int&` arguments are pointers.
      final funcNode = cc.addFunc(
          FuncSignature.build(List.filled(4, TypeId.intPtr), TypeId.int32));

      // Prepare.
      final arg1 = cc.newGp32();
      final arg2 = cc.newGp32();
      final arg3 = cc.newGp32();
      final arg4 = cc.newGp32();
      final rv = cc.newGp32('rv');

      funcNode.setArg(0, 0, arg1);
      funcNode.setArg(1, 0, arg2);
      funcNode.setArg(2, 0, arg3);
      funcNode.setArg(3, 0, arg4);

      // Call function.
      cc.invoke(fnImm(Pointer.fromFunction<_Ref4N>(_refArgsFn, 0)),
          FuncSignature.build(List.filled(4, TypeId.intPtr), TypeId.int32))
        ..setArg(0, arg1)
        ..setArg(1, arg2)
        ..setArg(2, arg3)
        ..setArg(3, arg4)
        ..setRet(0, rv);
      cc
        ..ret([rv])
        ..endFunc();
    });
    final m = calloc<Int32>(4);
    try {
      for (var i = 0; i < 4; i++) {
        m[i] = i + 1;
      }
      final r = p.cast<NativeFunction<_Ref4N>>().asFunction<_Ref4D>()(
          m, m + 1, m + 2, m + 3);
      expect([r, m[0], m[1], m[2], m[3]], [20, 2, 4, 6, 8]);
    } finally {
      calloc.free(m);
    }
  }, skip: skipUnlessX64Host);

  test('FuncCallFloatAsXmmRet', () {
    final p = compile((cc) {
      final funcNode = cc.addFunc(FuncSignature.build(
          [TypeId.float32, TypeId.float32], TypeId.float32));
      final a = cc.newXmmSs('a');
      final b = cc.newXmmSs('b');
      final ret = cc.newXmmSs('ret');
      funcNode.setArg(0, 0, a);
      funcNode.setArg(1, 0, b);

      // Call function.
      cc.invoke(fnImm(Pointer.fromFunction<_F2N>(_floatMulFn, 0.0)),
          FuncSignature.build([TypeId.float32, TypeId.float32], TypeId.float32))
        ..setArg(0, a)
        ..setArg(1, b)
        ..setRet(0, ret);
      cc
        ..ret([ret])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_F2N>>().asFunction<_F2D>()(15.5, 2.0), 31.0);
  }, skip: skipUnlessX64Host);

  test('FuncCallDoubleAsXmmRet', () {
    final p = compile((cc) {
      final funcNode = cc.addFunc(FuncSignature.build(
          [TypeId.float64, TypeId.float64], TypeId.float64));
      final a = cc.newXmmSd('a');
      final b = cc.newXmmSd('b');
      final ret = cc.newXmmSd('ret');
      funcNode.setArg(0, 0, a);
      funcNode.setArg(1, 0, b);
      cc.invoke(fnImm(Pointer.fromFunction<_D2N>(_doubleMulFn, 0.0)),
          FuncSignature.build([TypeId.float64, TypeId.float64], TypeId.float64))
        ..setArg(0, a)
        ..setArg(1, b)
        ..setRet(0, ret);
      cc
        ..ret([ret])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_D2N>>().asFunction<_D2D>()(15.5, 2.0), 31.0);
  }, skip: skipUnlessX64Host);

  test('FuncCallConditional', () {
    final p = compile((cc) {
      final x = cc.newGp32('x');
      final y = cc.newGp32('y');
      final op = cc.newGp32('op');

      final funcNode = cc.addFunc(FuncSignature.build(
          [TypeId.int32, TypeId.int32, TypeId.int32], TypeId.int32));
      funcNode.setArg(0, 0, x);
      funcNode.setArg(1, 0, y);
      funcNode.setArg(2, 0, op);

      final opAdd = cc.newLabel();
      final opMul = cc.newLabel();

      cc
        ..cmp(op, Imm(0))
        ..jz(opAdd)
        ..cmp(op, Imm(1))
        ..jz(opMul);

      var result = cc.newGp32('result_0');
      cc
        ..mov(result, Imm(0))
        ..ret([result])
        ..bind(opAdd);

      final sig =
          FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.int32);
      result = cc.newGp32('result_1');
      cc.invoke(fnImm(Pointer.fromFunction<_I2N>(_addFn, 0)), sig)
        ..setArg(0, x)
        ..setArg(1, y)
        ..setRet(0, result);
      cc
        ..ret([result])
        ..bind(opMul);

      result = cc.newGp32('result_2');
      cc.invoke(fnImm(Pointer.fromFunction<_I2N>(_mulFn, 0)), sig)
        ..setArg(0, x)
        ..setArg(1, y)
        ..setRet(0, result);
      cc
        ..ret([result])
        ..endFunc();
    });
    final f = p.cast<NativeFunction<_I3N>>().asFunction<_I3D>();
    expect([f(4, 8, 0), f(4, 8, 1)], [_addFn(4, 8), _mulFn(4, 8)]);
  }, skip: skipUnlessX64Host);

  test('FuncCallMultiple', () {
    final p = compile((cc) {
      final buf = cc.newGpPtr('buf');
      final acc0 = cc.newGp32('acc0');
      final acc1 = cc.newGp32('acc1');

      final funcNode =
          cc.addFunc(FuncSignature.build([TypeId.intPtr], TypeId.int32));
      funcNode.setArg(0, 0, buf);

      cc
        ..mov(acc0, Imm(0))
        ..mov(acc1, Imm(0));

      final fn = fnImm(
          Pointer.fromFunction<Int32 Function(Pointer<Int32>, Int32)>(
              _multipleFn, 0));
      final sig = FuncSignature.build(
          [TypeId.intPtr, TypeId.int32], TypeId.int32, CallConvId.fastCall);
      for (var i = 0; i < 4; i++) {
        final ret = cc.newGp32('ret');
        final ptr = cc.newGpPtr('ptr');
        final idx = cc.newGp32('idx');

        cc
          ..mov(ptr, buf)
          ..mov(idx, Imm(i));
        cc.invoke(fn, sig)
          ..setArg(0, ptr)
          ..setArg(1, idx)
          ..setRet(0, ret);
        cc
          ..add(acc0, ret)
          ..mov(ptr, buf)
          ..mov(idx, Imm(i));
        cc.invoke(fn, sig)
          ..setArg(0, ptr)
          ..setArg(1, idx)
          ..setRet(0, ret);
        cc.sub(acc1, ret);
      }

      cc
        ..add(acc0, acc1)
        ..ret([acc0])
        ..endFunc();
    });
    final m = calloc<Int32>(4);
    try {
      for (final (i, v) in [127, 87, 23, 17].indexed) {
        m[i] = v;
      }
      expect(
          p
              .cast<NativeFunction<Int32 Function(Pointer<Int32>)>>()
              .asFunction<int Function(Pointer<Int32>)>()(m),
          0);
    } finally {
      calloc.free(m);
    }
  }, skip: skipUnlessX64Host);

  test('FuncCallRecursive', () {
    final p = compile((cc) {
      final val = cc.newGp32('val');
      final skip = cc.newLabel();

      final funcNode =
          cc.addFunc(FuncSignature.build([TypeId.int32], TypeId.int32));
      funcNode.setArg(0, 0, val);

      cc
        ..cmp(val, Imm(1))
        ..jle(skip);

      final tmp = cc.newGp32('tmp');
      cc
        ..mov(tmp, val)
        ..dec(tmp);

      cc.invoke(LabelOp(funcNode.label),
          FuncSignature.build([TypeId.int32], TypeId.int32))
        ..setArg(0, tmp)
        ..setRet(0, tmp);
      cc
        ..mul(cc.newGp32(), val, tmp)
        ..bind(skip)
        ..ret([val])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_I1N>>().asFunction<_I1D>()(5),
        1 * 2 * 3 * 4 * 5);
  }, skip: skipUnlessX64Host);

  test('FuncCallVarArg1', () {
    final p = compile((cc) {
      final funcNode = cc.addFunc(
          FuncSignature.build(List.filled(4, TypeId.int32), TypeId.int32));
      final a0 = cc.newGp32('a0');
      final a1 = cc.newGp32('a1');
      final a2 = cc.newGp32('a2');
      final a3 = cc.newGp32('a3');

      funcNode.setArg(0, 0, a0);
      funcNode.setArg(1, 0, a1);
      funcNode.setArg(2, 0, a2);
      funcNode.setArg(3, 0, a3);

      // We call `int func(size_t, ...)`
      //   - The `va_index` must be 1 (first argument after size_t).
      //   - The full signature of varargs (int, int, int, int) must follow.
      final sig = FuncSignature.build(
          [TypeId.uintPtr, ...List.filled(4, TypeId.int32)], TypeId.int32)
        ..setVaIndex(1);
      cc.invoke(
          fnImm(Pointer.fromFunction<
              Int32 Function(
                  IntPtr, Int32, Int32, Int32, Int32)>(_varArgIntFn, 0)),
          sig)
        ..setArg(0, Imm(4))
        ..setArg(1, a0)
        ..setArg(2, a1)
        ..setArg(3, a2)
        ..setArg(4, a3)
        ..setRet(0, a0);
      cc
        ..ret([a0])
        ..endFunc();
    });
    expect(
        p
            .cast<NativeFunction<Int32 Function(Int32, Int32, Int32, Int32)>>()
            .asFunction<int Function(int, int, int, int)>()(1, 2, 3, 4),
        1 + 2 + 3 + 4);
  }, skip: skipUnlessX64Host);

  test('FuncCallVarArg2', () {
    final p = compile((cc) {
      final funcNode = cc.addFunc(
          FuncSignature.build(List.filled(4, TypeId.float64), TypeId.float64));
      final a0 = cc.newXmmSd('a0');
      final a1 = cc.newXmmSd('a1');
      final a2 = cc.newXmmSd('a2');
      final a3 = cc.newXmmSd('a3');

      funcNode.setArg(0, 0, a0);
      funcNode.setArg(1, 0, a1);
      funcNode.setArg(2, 0, a2);
      funcNode.setArg(3, 0, a3);

      // We call `double func(size_t, ...)`
      //   - The `va_index` must be 1 (first argument after size_t).
      //   - The full signature of varargs (double, double, double, double)
      //     must follow.
      final sig = FuncSignature.build(
          [TypeId.uintPtr, ...List.filled(4, TypeId.float64)], TypeId.float64)
        ..setVaIndex(1);
      cc.invoke(
          fnImm(Pointer.fromFunction<
                  Double Function(IntPtr, Double, Double, Double, Double)>(
              _varArgDoubleFn, 0.0)),
          sig)
        ..setArg(0, Imm(4))
        ..setArg(1, a0)
        ..setArg(2, a1)
        ..setArg(3, a2)
        ..setArg(4, a3)
        ..setRet(0, a0);
      cc
        ..ret([a0])
        ..endFunc();
    });
    expect(
        p
                .cast<
                    NativeFunction<
                        Double Function(Double, Double, Double, Double)>>()
                .asFunction<double Function(double, double, double, double)>()(
            1, 2, 3, 4),
        1.0 + 2.0 + 3.0 + 4.0);
  }, skip: skipUnlessX64Host);

  test('FuncCallInt64Arg', () {
    final p = compile((cc) {
      final funcNode =
          cc.addFunc(FuncSignature.build([TypeId.uint64], TypeId.uint64));
      // 64-bit mode (upstream also has a 32-bit variant with a register
      // pair).
      final reg = cc.newGp64();
      funcNode.setArg(0, 0, reg);
      cc
        ..add(reg, Imm(1))
        ..ret([reg])
        ..endFunc();
    });
    expect(
        p
            .cast<NativeFunction<Uint64 Function(Uint64)>>()
            .asFunction<int Function(int)>()(0xFFFFFFFF),
        0x100000000);
  }, skip: skipUnlessX64Host);

  test('FuncCallMisc1', () {
    final p = compile((cc) {
      final funcNode = cc.addFunc(
          FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.int32));
      final a = cc.newGp32('a');
      final b = cc.newGp32('b');
      final r = cc.newGp32('r');
      funcNode.setArg(0, 0, a);
      funcNode.setArg(1, 0, b);
      cc.invoke(
          fnImm(Pointer.fromFunction<Void Function(Int32, Int32)>(_dummyFn)),
          FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.void_))
        ..setArg(0, a)
        ..setArg(1, b);
      cc
        ..lea(r, X86Mem(base: a, index: b))
        ..ret([r])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_I2N>>().asFunction<_I2D>()(44, 199), 243);
  }, skip: skipUnlessX64Host);

  test('FuncCallMisc2', () {
    final p = compile((cc) {
      final funcNode =
          cc.addFunc(FuncSignature.build([TypeId.intPtr], TypeId.float64));
      final ptr = cc.newGpPtr('p');
      final arg = cc.newXmmSd('arg');
      final ret = cc.newXmmSd('ret');
      funcNode.setArg(0, 0, ptr);
      cc.movsd(arg, X86Mem.base(ptr));
      cc.invoke(fnImm(Pointer.fromFunction<_D1N>(_squareFn, 0.0)),
          FuncSignature.build([TypeId.float64], TypeId.float64))
        ..setArg(0, arg)
        ..setRet(0, ret);
      cc
        ..ret([ret])
        ..endFunc();
    });
    final m = calloc<Double>()..value = 2;
    try {
      expect(
          p
              .cast<NativeFunction<Double Function(Pointer<Double>)>>()
              .asFunction<double Function(Pointer<Double>)>()(m),
          _squareFn(2));
    } finally {
      calloc.free(m);
    }
  }, skip: skipUnlessX64Host);

  test('FuncCallMisc3', () {
    final p = compile((cc) {
      final funcNode =
          cc.addFunc(FuncSignature.build([TypeId.intPtr], TypeId.float64));
      final ptr = cc.newGpPtr('p');
      final arg = cc.newXmmSd('arg');
      final ret = cc.newXmmSd('ret');
      funcNode.setArg(0, 0, ptr);
      cc.movsd(arg, X86Mem.base(ptr));
      cc.invoke(fnImm(Pointer.fromFunction<_D1N>(_squareFn, 0.0)),
          FuncSignature.build([TypeId.float64], TypeId.float64))
        ..setArg(0, arg)
        ..setRet(0, ret);
      cc
        ..xorps(arg, arg)
        ..subsd(arg, ret)
        ..ret([arg])
        ..endFunc();
    });
    final m = calloc<Double>()..value = 2;
    try {
      expect(
          p
              .cast<NativeFunction<Double Function(Pointer<Double>)>>()
              .asFunction<double Function(Pointer<Double>)>()(m),
          -_squareFn(2));
    } finally {
      calloc.free(m);
    }
  }, skip: skipUnlessX64Host);

  test('FuncCallMisc4', () {
    final p = compile((cc) {
      final funcSignature = FuncSignature()
        ..setCallConvId(CallConvId.cdecl)
        ..setRet(TypeId.float64);
      cc.addFunc(funcSignature);

      final invokeSignature = FuncSignature()
        ..setCallConvId(CallConvId.cdecl)
        ..setRet(TypeId.float64);
      final invokeNode = cc.invoke(
          fnImm(Pointer.fromFunction<Double Function()>(_misc4Fn, 0.0)),
          invokeSignature);
      final ret = cc.newXmmSd('ret');
      invokeNode.setRet(0, ret);
      cc
        ..ret([ret])
        ..endFunc();
    });
    expect(
        p
            .cast<NativeFunction<Double Function()>>()
            .asFunction<double Function()>()(),
        3.14);
  }, skip: skipUnlessX64Host);

  // The register allocator should clobber the register used by the `call`
  // itself.
  test('FuncCallMisc5', () {
    final p = compile((cc) {
      cc.addFunc(FuncSignature.build([], TypeId.int32));

      final pFn = cc.newGpPtr('p_fn');
      final vars = List<X86Gp?>.filled(16, null);
      const regCount = 16;

      cc.mov(pFn, fnImm(Pointer.fromFunction<Void Function()>(_voidFn)));

      for (var i = 0; i < regCount; i++) {
        if (i == X86RegId.rbp.index || i == X86RegId.rsp.index) continue;
        vars[i] = cc.newGp32('%$i');
        cc.mov(vars[i]!, Imm(1));
      }

      cc.invoke(pFn, FuncSignature.build([], TypeId.void_));

      for (var i = 1; i < regCount; i++) {
        if (vars[i] != null) cc.add(vars[0]!, vars[i]!);
      }
      cc
        ..ret([vars[0]!])
        ..endFunc();
    });
    expect(p.cast<NativeFunction<_I0N>>().asFunction<_I0D>()(), 14);
  }, skip: skipUnlessX64Host);

  test('FuncCallMisc6', () {
    final p = compile((cc) {
      final funcNode =
          cc.addFunc(FuncSignature.build([TypeId.uint32], TypeId.uint32));

      const kCount = 16;

      final argVal = cc.newGp32('arg_val');
      final retVal = cc.newGp32('ret_val');

      funcNode.setArg(0, 0, argVal);
      cc.add(argVal, Imm(1));

      final v = [for (var i = 0; i < kCount; i++) cc.newGp32('v$i')];

      cc.invoke(fnImm(Pointer.fromFunction<Uint32 Function(Uint32)>(_incFn, 0)),
          FuncSignature.build([TypeId.uint32], TypeId.uint32))
        ..setArg(0, argVal)
        ..setRet(0, retVal);

      for (var i = 0; i < kCount; i++) {
        cc.mov(v[i], Imm(i + 1));
      }
      for (var i = 0; i < kCount; i++) {
        cc.add(argVal, v[i]);
      }

      cc
        ..add(retVal, argVal)
        ..ret([retVal])
        ..endFunc();
    });
    expect(
        p
            .cast<NativeFunction<Uint32 Function(Uint32)>>()
            .asFunction<int Function(int)>()(111),
        111 + 112 + 2 + (1 + 16) * 8);
  }, skip: skipUnlessX64Host);

  // Upstream adds this test only when the host has AVX2.
  test('FuncCallAVXClobber', () {
    final p = compile((cc) {
      final mainFunc = cc.addFunc(
          FuncSignature.build(List.filled(3, TypeId.intPtr), TypeId.void_));
      mainFunc.frame
        ..setAvxEnabled()
        ..setAvxCleanup();

      // We need a Windows calling convention to test this properly also on
      // a non-Windows machine.
      final helperFunc = cc.newFunc(FuncSignature.build(
          [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.x64Windows));
      helperFunc.frame
        ..setAvxEnabled()
        ..setAvxCleanup();

      {
        final dPtr = cc.newGpPtr('d_ptr');
        final aPtr = cc.newGpPtr('a_ptr');
        final bPtr = cc.newGpPtr('b_ptr');
        final tPtr = cc.newGpPtr('t_ptr');
        final acc = <X86Ymm>[];
        final stack = cc.newStack(32, 1, 'stack');

        mainFunc.setArg(0, 0, dPtr);
        mainFunc.setArg(1, 0, aPtr);
        mainFunc.setArg(2, 0, bPtr);

        cc.lea(tPtr, stack);
        for (var i = 0; i < 8; i++) {
          acc.add(cc.newYmm('acc$i'));
          cc.inst(X86InstId.kVmovdqu, [acc[i], X86Mem.base(aPtr)]);
        }

        cc.invoke(
            LabelOp(helperFunc.label),
            FuncSignature.build([TypeId.intPtr, TypeId.intPtr], TypeId.void_,
                CallConvId.x64Windows))
          ..setArg(0, tPtr)
          ..setArg(1, bPtr);

        for (var i = 1; i < 8; i++) {
          cc.inst(X86InstId.kVpaddd, [acc[0], acc[0], acc[i]]);
        }

        cc
          ..inst(X86InstId.kVpaddd, [acc[0], acc[0], X86Mem.base(tPtr)])
          ..inst(X86InstId.kVmovdqu, [X86Mem.base(dPtr), acc[0]])
          ..endFunc();
      }

      {
        cc.addFuncNode(helperFunc);

        final dPtr = cc.newGpPtr('d_ptr');
        final aPtr = cc.newGpPtr('a_ptr');

        helperFunc.setArg(0, 0, dPtr);
        helperFunc.setArg(1, 0, aPtr);

        final tmp = cc.newGpPtr('tmp');
        final acc = cc.newYmm('acc');

        cc
          ..mov(tmp, Imm(1))
          ..inst(X86InstId.kVmovd, [X86Xmm(acc.id), tmp])
          ..inst(X86InstId.kVpbroadcastd, [acc, X86Xmm(acc.id)])
          ..inst(X86InstId.kVpaddd, [acc, acc, X86Mem.base(aPtr)])
          ..inst(X86InstId.kVmovdqu, [X86Mem.base(dPtr), acc])
          ..endFunc();
      }
    });
    const aData = [1, 2, 3, 4, 5, 6, 7, 8];
    const bData = [6, 3, 5, 9, 1, 8, 7, 2];
    final m = calloc<Uint32>(24);
    try {
      for (var i = 0; i < 8; i++) {
        m[8 + i] = aData[i];
        m[16 + i] = bData[i];
      }
      p
          .cast<
              NativeFunction<
                  Void Function(
                      Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>)>>()
          .asFunction<
              void Function(Pointer<Uint32>, Pointer<Uint32>,
                  Pointer<Uint32>)>()(m, m + 8, m + 16);
      expect([for (var i = 0; i < 8; i++) m[i]],
          [for (var i = 0; i < 8; i++) aData[i] * 8 + bData[i] + 1]);
    } finally {
      calloc.free(m);
    }
  },
      skip: !hostIsX64
          ? skipUnlessX64Host
          : CpuInfo.host().features.avx2
              ? false
              : 'requires AVX2 (as upstream)');

  test('MiscMultiFunc', () {
    final p = compile((cc) {
      final sig =
          FuncSignature.build([TypeId.int32, TypeId.int32], TypeId.int32);
      final f1Node = cc.newFunc(sig);
      final f2Node = cc.newFunc(sig);

      {
        final a = cc.newGp32('a');
        final b = cc.newGp32('b');

        cc.addFuncNode(f1Node);
        f1Node.setArg(0, 0, a);
        f1Node.setArg(1, 0, b);

        cc.invoke(LabelOp(f2Node.label), sig)
          ..setArg(0, a)
          ..setArg(1, b)
          ..setRet(0, a);
        cc
          ..ret([a])
          ..endFunc();
      }

      {
        final a = cc.newGp32('a');
        final b = cc.newGp32('b');

        cc.addFuncNode(f2Node);
        f2Node.setArg(0, 0, a);
        f2Node.setArg(1, 0, b);

        cc
          ..add(a, b)
          ..ret([a])
          ..endFunc();
      }
    });
    expect(p.cast<NativeFunction<_I2N>>().asFunction<_I2D>()(56, 22), 56 + 22);
  }, skip: skipUnlessX64Host);
}
