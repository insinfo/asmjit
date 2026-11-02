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
  }, skip: skipUnlessA64Host);
}
