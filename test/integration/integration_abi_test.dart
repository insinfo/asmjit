import 'dart:ffi';
import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';
import 'package:ffi/ffi.dart' as pkgffi;

// Helper to run JIT code
void runJitTest(
    void Function(JitRuntime runtime, UniCompiler cc) generator,
    void Function(JitFunction fn) verifier) {
  final runtime = JitRuntime();
  final code = CodeHolder(env: runtime.environment);
  
  // Setup compiler
  BaseCompiler archCompiler;
  if (code.env.arch == Arch.x64) {
    archCompiler = X86Compiler(env: code.env, labelManager: code.labelManager);
  } else if (code.env.arch == Arch.aarch64) {
    archCompiler = A64Compiler(env: code.env, labelManager: code.labelManager);
  } else {
    throw UnsupportedError('Unsupported architecture');
  }
  
  final cc = UniCompiler(archCompiler);
  
  generator(runtime, cc);
  
  archCompiler.finalize();
  
  if (code.env.arch == Arch.x64) {
    final assembler = X86Assembler(code);
    archCompiler.serializeToAssembler(assembler);
  } else {
    final assembler = A64Assembler(code);
    archCompiler.serializeToAssembler(assembler);
  }
  
  final fn = runtime.add(code);
  try {
    verifier(fn);
  } finally {
    // runtime.release(fn); // Not implemented yet in Dart binding
  }
}

void main() {
  group('Integration ABI Tests', () {
    test('Function Arguments - 4 Integers (Registers)', () {
      runJitTest((runtime, cc) {
        // int sum4(int a, int b, int c, int d)
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr, TypeId.intPtr, TypeId.intPtr],
            TypeId.intPtr,
            CallConvId.x64Windows)); // Use host convention

        final a = cc.newGpPtr('a');
        final b = cc.newGpPtr('b');
        final c = cc.newGpPtr('c');
        final d = cc.newGpPtr('d');

        cc.setArg(0, a);
        cc.setArg(1, b);
        cc.setArg(2, c);
        cc.setArg(3, d);

        final sum = cc.newGpPtr('sum');
        cc.emitRRI(UniOpRRR.add, sum, a, 0); // mov sum, a
        cc.emitRRR(UniOpRRR.add, sum, sum, b);
        cc.emitRRR(UniOpRRR.add, sum, sum, c);
        cc.emitRRR(UniOpRRR.add, sum, sum, d);

        cc.ret([sum]);
        cc.endFunc();
      }, (fn) {
        final func = fn.pointer.cast<NativeFunction<IntPtr Function(IntPtr, IntPtr, IntPtr, IntPtr)>>().asFunction<int Function(int, int, int, int)>();
        expect(func(10, 20, 30, 40), equals(100));
        expect(func(1, 1, 1, 1), equals(4));
        expect(func(-1, -1, -1, -1), equals(-4));
      });
    });

    // TODO: Investigate why mixed int/float arguments are not passed correctly in tests
    test('Function Arguments - Mixed Int/Float', () {
      runJitTest((runtime, cc) {
        // double calc(double a, int b, double c)
        // return a + b + c
        cc.addFunc(FuncSignature.build(
            [TypeId.float64, TypeId.intPtr, TypeId.float64],
            TypeId.float64,
            CallConvId.x64Windows));

        final a = cc.newVec('a'); // double
        final b = cc.newGpPtr('b'); // int
        final c = cc.newVec('c'); // double

        cc.setArg(0, a);
        cc.setArg(1, b);
        cc.setArg(2, c);

        final tmp = cc.newVec('tmp');
        final bDouble = cc.newVec('bDouble');

        // Convert int b to double
        cc.emitCV(UniOpCV.cvtI2D, bDouble, b); // cvtsi2sd

        cc.emit3v(UniOpVVV.addF64S, tmp, a, bDouble);
        cc.emit3v(UniOpVVV.addF64S, tmp, tmp, c);

        cc.ret([tmp]);
        cc.endFunc();
      }, (fn) {
        final func = fn.pointer.cast<NativeFunction<Double Function(Double, IntPtr, Double)>>().asFunction<double Function(double, int, double)>();
        expect(func(10.5, 20, 30.5), closeTo(61.0, 0.001));
      });
    });
    
    test('Function Arguments - Pointer Access (Context)', () {
      // Simulates the ChaCha20 context access pattern that crashed
      runJitTest((runtime, cc) {
        // void updateCtx(int* ctx, int val)
        // ctx[0] = val
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr],
            TypeId.void_,
            CallConvId.x64Windows));

        final ctx = cc.newGpPtr('ctx');
        final val = cc.newGpPtr('val');

        cc.setArg(0, ctx);
        cc.setArg(1, val);

        // Store val to [ctx]
        cc.emitMR(UniOpMR.storeU32, _mem(cc, ctx, 0), val);
        
        // Store val+1 to [ctx + 4]
        cc.emitRRI(UniOpRRR.add, val, val, 1);
        cc.emitMR(UniOpMR.storeU32, _mem(cc, ctx, 4), val);

        cc.ret();
        cc.endFunc();
      }, (fn) {
        final func = fn.pointer.cast<NativeFunction<Void Function(Pointer<Int32>, IntPtr)>>().asFunction<void Function(Pointer<Int32>, int)>();
        final mem = pkgffi.calloc<Int32>(2);
        try {
          func(mem, 42);
          expect(mem[0], equals(42));
          expect(mem[1], equals(43));
        } finally {
          pkgffi.calloc.free(mem);
        }
      });
    });

    test('Function Arguments - Mixed Int/Float com spill de XMM', () {
      runJitTest((runtime, cc) {
        // double calc(double a, int b, double c) com muitos temporários em XMM
        cc.addFunc(FuncSignature.build(
            [TypeId.float64, TypeId.intPtr, TypeId.float64],
            TypeId.float64,
            CallConvId.x64Windows));

        final a = cc.newVec('a');
        final b = cc.newGpPtr('b');
        final c = cc.newVec('c');

        cc.setArg(0, a);
        cc.setArg(1, b);
        cc.setArg(2, c);

        final bDouble = cc.newVec('bDouble');
        cc.emitCV(UniOpCV.cvtI2D, bDouble, b);

        final tmp = cc.newVec('tmp');
        cc.emit3v(UniOpVVV.addF64S, tmp, a, c); // tmp = a+c

        // Cria vários temporários para forçar spill de XMM em Win64
        const tempCount = 12;
        final temps = <BaseReg>[];
        for (int i = 0; i < tempCount; i++) {
          final t = cc.newVec('t$i');
          temps.add(t);
          cc.emit3v(UniOpVVV.addF64S, t, a, c); // t = a+c
        }

        for (final t in temps) {
          cc.emit3v(UniOpVVV.addF64S, tmp, tmp, t);
        }

        cc.emit3v(UniOpVVV.addF64S, tmp, tmp, bDouble);

        cc.ret([tmp]);
        cc.endFunc();
      }, (fn) {
        final func = fn.pointer
            .cast<NativeFunction<Double Function(Double, IntPtr, Double)>>()
            .asFunction<double Function(double, int, double)>();

        const a = 1.5;
        const c = 2.5;
        const b = 3;
        const tempCount = 12;
        final expected = (a + c) * (tempCount + 1) + b;

        expect(func(a, b, c), closeTo(expected, 0.0001));
      });
    });
  });
}

// Helper for memory operand creation in tests
UniMem _mem(UniCompiler cc, BaseReg base, int disp) {
  if (cc.isX86Family) {
    return UniMem(X86Mem.baseDisp(base as X86Gp, disp));
  } else {
    // A64 not fully supported in this helper yet for tests
    throw UnimplementedError();
  }
}
