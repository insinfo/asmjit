/// AsmJit Unit Tests - Short Jumps
///
/// Tests for short jump (rel8) automatic selection.

import 'dart:ffi';
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

// Native function signatures
typedef NativeOneArg = Int64 Function(Int64);
typedef DartOneArg = int Function(int);

void main() {
  group('Short Jump - Backward Jump Encoding', () {
    test('short jmp is used for close backward jumps', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // Create a simple loop that uses a backward jump
      final loopStart = code.newLabel();

      // loop:
      code.bind(loopStart);
      asm.nop();
      asm.nop();
      asm.nop();

      // This should generate a short jump (EB xx) because the label is close
      asm.jmp(loopStart);

      final bytes = code.finalize().textBytes;

      // The jump should be:
      // EB fd (-3: back over 3 NOPs + 2 byte instruction = -5 offset from end of jmp)
      // Actually: target = 0, current = 3, disp = 0 - (3 + 2) = -5 = 0xFB
      expect(bytes.length, equals(5)); // 3 NOPs + 2 byte short jmp
      expect(bytes[3], equals(0xEB)); // short jmp opcode
      expect(bytes[4], equals(0xFB)); // -5 in two's complement
    });

    test('short jcc is used for close backward jumps', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final loopStart = code.newLabel();

      code.bind(loopStart);
      asm.nop();

      // This should generate a short conditional jump (7x xx)
      asm.je(loopStart);

      final bytes = code.finalize().textBytes;

      // Short JE: 74 xx (2 bytes)
      expect(bytes.length, equals(3)); // 1 NOP + 2 byte short jcc
      expect(bytes[1], equals(0x74)); // short JE opcode
    });
  });

  group('Short Jump - JIT Execution', () {
    late JitRuntime runtime;

    setUp(() {
      runtime = JitRuntime();
    });

    tearDown(() {
      runtime.dispose();
    });

    test('backward jump loop works correctly', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);

      // Simple countdown loop:
      // while (n > 0) { n--; }
      // return n;

      asm.movRR(rax, arg0);

      final loopStart = code.newLabel();
      final done = code.newLabel();

      code.bind(loopStart);
      asm.testRR(rax, rax);
      asm.jz(done);
      asm.dec(rax);
      asm.jmp(loopStart); // Backward jump (should use rel8)

      code.bind(done);
      asm.ret();

      final fn = runtime.add(code);
      final countdown = fn.pointer
          .cast<NativeFunction<NativeOneArg>>()
          .asFunction<DartOneArg>();

      expect(countdown(0), equals(0));
      expect(countdown(1), equals(0));
      expect(countdown(10), equals(0));
      expect(countdown(100), equals(0));

      fn.dispose();
    });

    test('sum with backward jump loop', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);

      // Sum from 1 to n:
      // result = 0
      // while (n > 0) { result += n; n--; }
      // return result;

      asm.xorRR(rax, rax); // result = 0 in rax
      asm.movRR(r8, arg0); // n = arg0 (use R8 to avoid conflicts)

      final loopStart = code.newLabel();
      final done = code.newLabel();

      code.bind(loopStart);
      asm.testRR(r8, r8);
      asm.jz(done);
      asm.addRR(rax, r8); // result += n
      asm.dec(r8); // n--
      asm.jmp(loopStart); // backward jump

      code.bind(done);
      asm.ret();

      final fn = runtime.add(code);
      final sum = fn.pointer
          .cast<NativeFunction<NativeOneArg>>()
          .asFunction<DartOneArg>();

      expect(sum(0), equals(0));
      expect(sum(1), equals(1));
      expect(sum(5), equals(15)); // 1+2+3+4+5
      expect(sum(10), equals(55)); // 1+2+...+10
      expect(sum(100), equals(5050));

      fn.dispose();
    });
  });

  group('Forward Jump with forceShort', () {
    test('forceShort option works for forward jumps', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final target = code.newLabel();

      // Force short jump (dangerous if distance too large!)
      asm.jmp(target, forceShort: true);
      asm.nop();
      asm.nop();
      code.bind(target);
      asm.ret();

      final bytes = code.finalize().textBytes;

      // Short jmp: EB 02 (jump over 2 NOPs)
      expect(bytes[0], equals(0xEB)); // short jmp
      expect(bytes[1], equals(0x02)); // +2 (over 2 NOPs)
    });
  });
}
