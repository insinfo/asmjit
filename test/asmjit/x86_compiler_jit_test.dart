import 'dart:ffi';
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

typedef SimpleAddFunc = Int32 Function(Int32, Int32);
typedef SimpleAddDart = int Function(int, int);

void main() {
  group('X86Compiler JIT Tests', () {
    test('Simple Add - Register Allocation', () {
      final rt = JitRuntime();
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature = FuncSignature(
          retType: TypeId.int32, args: [TypeId.int32, TypeId.int32]);

      compiler.addFunc(signature);

      final vAdd0 = compiler.newGp32('vAdd0');
      final vAdd1 = compiler.newGp32('vAdd1');

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final arg0Reg = isWindows ? ecx : edi;
      final arg1Reg = isWindows ? edx : esi;

      compiler.mov(vAdd0, arg0Reg);
      compiler.mov(vAdd1, arg1Reg);

      compiler.add(vAdd0, vAdd1);

      compiler.mov(eax, vAdd0);
      compiler.ret();
      compiler.endFunc();

      compiler.finalize();
      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final finalized = code.finalize();
      print(
          "Simple Add Hex Dump:\n${AsmFormatter.hexDump(finalized.textBytes)}");

      final fn = rt.add(code);
      try {
        final add = fn.pointer
            .cast<NativeFunction<SimpleAddFunc>>()
            .asFunction<SimpleAddDart>();
        expect(add(10, 20), equals(30));
        expect(add(-5, 15), equals(10));
      } finally {
        fn.dispose();
        rt.dispose();
      }
    });

    test('Jump and RAGlobal - ensures state resolution works', () {
      final rt = JitRuntime();
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature =
          FuncSignature(retType: TypeId.int32, args: [TypeId.int32]);

      compiler.addFunc(signature);

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final arg0Reg = isWindows ? ecx : edi;

      final vVal = compiler.newGp32('vVal');
      compiler.mov(vVal, arg0Reg);

      final L1 = compiler.newLabel();
      final LEnd = compiler.newLabel();

      compiler.cmp(vVal, Imm(10));
      compiler.jl(L1);

      compiler.add(vVal, Imm(100));
      compiler.jmp(LEnd);

      compiler.bind(L1);
      compiler.sub(vVal, Imm(5));

      compiler.bind(LEnd);
      compiler.mov(eax, vVal);
      compiler.ret();
      compiler.endFunc();

      compiler.finalize();
      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final finalized = code.finalize();
      print(
          "Jump/RAGlobal Hex Dump:\n${AsmFormatter.hexDump(finalized.textBytes)}");

      final fn = rt.add(code);
      try {
        final testFn = fn.pointer
            .cast<NativeFunction<Int32 Function(Int32)>>()
            .asFunction<int Function(int)>();

        expect(testFn(15), equals(115));
        expect(testFn(8), equals(3));
      } finally {
        fn.dispose();
        rt.dispose();
      }
    });
  });
}
