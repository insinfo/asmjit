import 'dart:ffi';
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

typedef IntFunc = Int64 Function();
typedef IntDart = int Function();

void main() {
  group('ABI Integration Tests', () {
    late JitRuntime rt;

    setUp(() {
      rt = JitRuntime();
    });

    tearDown(() {
      rt.dispose();
    });

    test('Preserves Callee-Saved Registers (RBX, RSI, RDI, R12-R15)', () {
      // ---------------------------------------------------------
      // 1. Compile the Target Function (The one being tested)
      // ---------------------------------------------------------
      final codeTarget = CodeHolder(env: Environment.host());
      final compiler = X86Compiler(env: codeTarget.env, labelManager: codeTarget.labelManager);
      
      compiler.addFunc(FuncSignature(retType: TypeId.void_, args: []));
      
      // Force usage of many registers to trigger spills and usage of callee-saved regs.
      // We create 16 virtual registers and keep them alive.
      final vRegs = <X86Gp>[];
      for (var i = 0; i < 16; i++) {
        vRegs.add(compiler.newGp64('v$i'));
      }

      // Initialize
      for (var i = 0; i < 16; i++) {
        compiler.mov(vRegs[i], Imm(i + 0x1000));
      }

      // Mutate
      for (var i = 0; i < 16; i++) {
        compiler.add(vRegs[i], Imm(1));
      }

      // Sum (keep alive)
      final sum = compiler.newGp64('sum');
      compiler.mov(sum, Imm(0));
      for (var i = 0; i < 16; i++) {
        compiler.add(sum, vRegs[i]);
      }

      compiler.ret();
      compiler.endFunc();
      
      // Finalize Target
      print('Finalizing Target...');
      compiler.finalize();
      
      // Serialize to Assembler to generate bytes in CodeHolder
      print('Serializing Target...');
      final assembler = X86Assembler(codeTarget);
      compiler.serializeToAssembler(assembler);
      
      print('Target Bytes: ${codeTarget.text.buffer.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      print('Adding Target to Runtime...');
      final targetFn = rt.add(codeTarget);
      final targetPtr = targetFn.address; // This is the pointer to the JIT code
      print('Target Address: 0x${targetPtr.toRadixString(16)}');

      // ---------------------------------------------------------
      // 2. Compile the Tester Function (Assembler - Manual Control)
      // ---------------------------------------------------------

      final codeTester = CodeHolder(env: Environment.host());
      final a = X86Assembler(codeTester);
      
      // Standard Prolog for the Tester itself
      a.push(rbp);
      a.mov(rbp, rsp);

      // Save ALL callee-saved regs of the HOST (Dart/OS) so we don't crash the runner
      // Windows: RBX, RBP, RDI, RSI, RSP, R12-R15
      // Linux: RBX, RBP, RSP, R12-R15
      // We'll just save everything relevant to be safe.
      a.push(rbx);
      a.push(rdi);
      a.push(rsi);
      a.push(r12);
      a.push(r13);
      a.push(r14);
      a.push(r15);
      
      // Align stack to 16 bytes
      // We pushed 7 registers (56 bytes).
      // Original RSP (after push rbp) was 16-byte aligned.
      // Current RSP is aligned to 8.
      // We need to subtract 8 from RSP to align it.
      a.subRI(rsp, 8);

      // Set Canary Values
      final canary = 0xDEADBEEF;
      a.mov(rbx, canary + 1);
      a.mov(rdi, canary + 2);
      a.mov(rsi, canary + 3);
      a.mov(r12, canary + 4);
      a.mov(r13, canary + 5);
      a.mov(r14, canary + 6);
      a.mov(r15, canary + 7);

      // Call the Target Function
      // We need to move the address to a register to call it
      a.mov(rax, targetPtr);
      a.callR(rax);

      // Check Canary Values
      // We will accumulate errors in RAX. 0 = Success.
      final errorAcc = rax; // Reuse RAX for result
      a.xorRR(errorAcc, errorAcc); // errorAcc = 0

      // Helper to check register
      void check(X86Gp reg, int expected) {
        final tmp = rcx; // Use RCX as scratch
        a.mov(tmp, expected);
        a.cmpRR(reg, tmp);
        final L_Ok = a.newLabel();
        a.je(L_Ok);
        a.inc(errorAcc); // Error!
        a.bind(L_Ok);
      }

      check(rbx, canary + 1);
      check(rdi, canary + 2);
      check(rsi, canary + 3);
      check(r12, canary + 4);
      check(r13, canary + 5);
      check(r14, canary + 6);
      check(r15, canary + 7);

      // Restore stack alignment
      a.addRI(rsp, 8);

      // Restore HOST registers
      a.pop(r15);
      a.pop(r14);
      a.pop(r13);
      a.pop(r12);
      a.pop(rsi);
      a.pop(rdi);
      a.pop(rbx);

      // Epilog
      a.pop(rbp);
      a.ret();

      // Finalize Tester
      print('Adding Tester to Runtime...');
      print('Tester Code Size (before add): ${codeTester.text.buffer.length}');
      print('Tester Bytes: ${codeTester.text.buffer.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      final testerFn = rt.add(codeTester);
      final testerFunc = testerFn.pointer.cast<NativeFunction<IntFunc>>().asFunction<IntDart>();
      print('Tester Address: 0x${testerFn.address.toRadixString(16)}');

      // ---------------------------------------------------------
      // 3. Run Test
      // ---------------------------------------------------------
      print('Running Tester...');
      final result = testerFunc();
      print('Tester Result: $result');
      expect(result, equals(0), reason: "One or more callee-saved registers were corrupted");
    });
  });
}
