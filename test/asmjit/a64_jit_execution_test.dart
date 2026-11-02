// Executes JIT-compiled AArch64 code on AArch64 hosts (macOS / Linux arm64).
//
// Guards the runtime path that x86 hosts never exercise: MAP_JIT allocation on
// Apple Silicon and instruction cache maintenance after writing code.
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:test/test.dart';

import '../support/host.dart';

typedef _BinNative = Int64 Function(Int64, Int64);
typedef _BinDart = int Function(int, int);
typedef _UnNative = Int64 Function(Int64);
typedef _UnDart = int Function(int);
typedef _PtrNative = Void Function(Pointer<Int64>);
typedef _PtrDart = void Function(Pointer<Int64>);
typedef _PtrVoidNative = Void Function(Pointer<Void>);
typedef _PtrVoidDart = void Function(Pointer<Void>);

void main() {
  group('A64 JIT execution', () {
    late JitRuntime rt;

    setUp(() => rt = JitRuntime());
    tearDown(() => rt.dispose());

    test('add x0, x0, x1', () {
      final code = CodeHolder(env: rt.environment);
      final a = A64Assembler(code);
      a.add(x0, x0, x1);
      a.ret();

      final fn = rt.add(code);
      final f =
          fn.pointer.cast<NativeFunction<_BinNative>>().asFunction<_BinDart>();
      expect(f(40, 2), 42);
      expect(f(-5, 3), -2);
    });

    test('loop with labels (sum 1..n)', () {
      final code = CodeHolder(env: rt.environment);
      final a = A64Assembler(code);
      final loop = code.newLabel();
      final done = code.newLabel();

      a.movz(x1, 0);
      a.cbz(x0, done);
      a.bind(loop);
      a.add(x1, x1, x0);
      a.subsImm(x0, x0, 1);
      a.bCond(A64Cond.ne, loop);
      a.bind(done);
      a.mov(x0, x1);
      a.ret();

      final fn = rt.add(code);
      final f =
          fn.pointer.cast<NativeFunction<_UnNative>>().asFunction<_UnDart>();
      expect(f(0), 0);
      expect(f(10), 55);
      expect(f(1000), 500500);
    });

    test('load/store through pointer argument', () {
      final code = CodeHolder(env: rt.environment);
      final a = A64Assembler(code);
      // p[1] = p[0] + p[1]
      a.ldr(x1, x0, 0);
      a.ldr(x2, x0, 8);
      a.add(x1, x1, x2);
      a.str(x1, x0, 8);
      a.ret();

      final fn = rt.add(code);
      final f =
          fn.pointer.cast<NativeFunction<_PtrNative>>().asFunction<_PtrDart>();
      final p = pkgffi.calloc<Int64>(2);
      try {
        p[0] = 1000;
        p[1] = 234;
        f(p);
        expect(p[0], 1000);
        expect(p[1], 1234);
      } finally {
        pkgffi.calloc.free(p);
      }
    });

    test('UniCompiler + register allocation (a * b + a)', () {
      final code = CodeHolder(env: rt.environment);
      final compiler =
          A64Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.build(
          [TypeId.int64, TypeId.int64], TypeId.int64, CallConvId.cdecl));
      final a = cc.newGp64('a');
      final b = cc.newGp64('b');
      cc.setArg(0, a);
      cc.setArg(1, b);
      final t = cc.newGp64('t');
      cc.emitRRR(UniOpRRR.mul, t, a, b);
      cc.emitRRR(UniOpRRR.add, t, t, a);
      cc.ret([t]);
      cc.endFunc();
      cc.finalize();
      compiler.serializeToAssembler(A64Assembler(code));

      final fn = rt.add(code);
      final f =
          fn.pointer.cast<NativeFunction<_BinNative>>().asFunction<_BinDart>();
      expect(f(6, 7), 48);
      expect(f(-3, 5), -18);
    });

    JitFunction compileUni(void Function(UniCompiler cc) body) {
      final code = CodeHolder(env: rt.environment);
      final compiler =
          A64Compiler(env: code.env, labelManager: code.labelManager);
      body(UniCompiler(compiler));
      compiler.finalize();
      compiler.serializeToAssembler(A64Assembler(code));
      return rt.add(code);
    }

    test('register pressure: spills and callee-saved registers', () {
      // Keeps 40 values alive at once (more than the 28 allocatable GP
      // registers), forcing spills and the use of x19-x28, which the prolog
      // must preserve for the caller (the Dart VM).
      const n = 40;
      final fn = compileUni((cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr], TypeId.int64, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        cc.setArg(0, p);
        final vals = [
          for (int i = 0; i < n; i++) cc.newGp64('v$i'),
        ];
        for (int i = 0; i < n; i++) {
          cc.emitRM(
              UniOpRM.loadU64, vals[i], A64Mem.baseOffset(p as A64Gp, i * 8));
        }
        // sum = v0*1 + v1*2 + ... (all values live until consumed)
        final sum = cc.newGp64('sum');
        cc.emitRRR(UniOpRRR.add, sum, vals[0], vals[0]);
        cc.emitRRR(UniOpRRR.sub, sum, sum, vals[0]);
        for (int i = 1; i < n; i++) {
          for (int k = 0; k <= i; k++) {
            cc.emitRRR(UniOpRRR.add, sum, sum, vals[i]);
          }
        }
        cc.ret([sum]);
        cc.endFunc();
      });

      final f = fn.pointer
          .cast<NativeFunction<Int64 Function(Pointer<Int64>)>>()
          .asFunction<int Function(Pointer<Int64>)>();
      final buf = pkgffi.calloc<Int64>(n);
      try {
        int expected = 0;
        for (int i = 0; i < n; i++) {
          buf[i] = 1000 + i * 7;
          expected += buf[i] * (i + 1);
        }
        for (int r = 0; r < 3; r++) {
          expect(f(buf), expected);
        }
      } finally {
        pkgffi.calloc.free(buf);
      }
    });

    test('loop with conditional branch (sum 1..n)', () {
      final fn = compileUni((cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.int64], TypeId.int64, CallConvId.cdecl));
        final i = cc.newGp64('i');
        cc.setArg(0, i);
        final sum = cc.newGp64('sum');
        final loop = cc.newLabel();
        final done = cc.newLabel();
        cc.emitRRR(UniOpRRR.sub, sum, i, i); // sum = 0
        cc.emitJIf(
            done, UniCondition(UniOpCond.compare, CondCode.kEqual, i, Imm(0)));
        cc.bind(loop);
        cc.emitRRR(UniOpRRR.add, sum, sum, i);
        cc.emitRRI(UniOpRRR.sub, i, i, 1);
        cc.emitJIf(loop,
            UniCondition(UniOpCond.compare, CondCode.kNotEqual, i, Imm(0)));
        cc.bind(done);
        cc.ret([sum]);
        cc.endFunc();
      });

      final f =
          fn.pointer.cast<NativeFunction<_UnNative>>().asFunction<_UnDart>();
      expect(f(0), 0);
      expect(f(1), 1);
      expect(f(10), 55);
      expect(f(100000), 5000050000);
    });

    test('vector load/add/store (f32x4)', () {
      final fn = compileUni((cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p') as A64Gp;
        cc.setArg(0, p);
        final a = cc.newVec('a');
        final b = cc.newVec('b');
        cc.emitVM(UniOpVM.load128F32, a, A64Mem.baseOffset(p, 0));
        cc.emitVM(UniOpVM.load128F32, b, A64Mem.baseOffset(p, 16));
        cc.emit3v(UniOpVVV.addF32, a, a, b);
        cc.emitMV(UniOpMV.store128F32, A64Mem.baseOffset(p, 32), a);
        cc.ret();
        cc.endFunc();
      });

      final f = fn.pointer
          .cast<NativeFunction<_PtrVoidNative>>()
          .asFunction<_PtrVoidDart>();
      final buf = pkgffi.calloc<Float>(16);
      try {
        for (int k = 0; k < 4; k++) {
          buf[k] = k + 0.5;
          buf[4 + k] = 10.0 * (k + 1);
        }
        for (int k = 8; k < 16; k++) {
          buf[k] = -1;
        }
        f(buf.cast());
        for (int k = 0; k < 4; k++) {
          expect(buf[8 + k], closeTo(k + 0.5 + 10.0 * (k + 1), 1e-6));
        }
        for (int k = 12; k < 16; k++) {
          expect(buf[k], -1, reason: 'store must write exactly 16 bytes');
        }
      } finally {
        pkgffi.calloc.free(buf);
      }
    });
  }, skip: skipUnlessA64Host);
}
