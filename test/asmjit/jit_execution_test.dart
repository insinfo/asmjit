/// AsmJit Unit Tests - JIT Execution
///
/// Integration tests for JIT code generation and execution.

import 'dart:ffi';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

// Native function signatures
typedef NativeNoArgs = Int64 Function();
typedef DartNoArgs = int Function();

typedef NativeOneArg = Int64 Function(Int64);
typedef DartOneArg = int Function(int);

typedef NativeTwoArgs = Int64 Function(Int64, Int64);
typedef DartTwoArgs = int Function(int, int);

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
  late JitRuntime runtime;

  setUp(() {
    runtime = JitRuntime();
  });

  tearDown(() {
    runtime.dispose();
  });

  group('JIT Execution', () {
    test('return constant 0', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.xorRR(rax, rax); // rax = 0
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(0));

      fn.dispose();
    });

    test('return constant 42', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.movRI64(rax, 42);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(42));

      fn.dispose();
    });

    test('return large constant', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.movRI64(rax, 0x7FFFFFFFFFFFFFFF);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(0x7FFFFFFFFFFFFFFF));

      fn.dispose();
    });

    test('identity function', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // Return first argument
      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final identity = ptr.asFunction<DartOneArg>();

      expect(identity(123), equals(123));
      expect(identity(-456), equals(-456));
      expect(identity(0), equals(0));

      fn.dispose();
    });

    test('add two integers', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      final arg1 = asm.getArgReg(1);

      asm.movRR(rax, arg0);
      asm.addRR(rax, arg1);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final add = ptr.asFunction<DartTwoArgs>();

      expect(add(5, 3), equals(8));
      expect(add(100, 200), equals(300));
      expect(add(-10, 25), equals(15));
      expect(add(0, 0), equals(0));

      fn.dispose();
    });

    test('subtract two integers', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      final arg1 = asm.getArgReg(1);

      asm.movRR(rax, arg0);
      asm.subRR(rax, arg1);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final sub = ptr.asFunction<DartTwoArgs>();

      expect(sub(10, 3), equals(7));
      expect(sub(5, 5), equals(0));
      expect(sub(0, 10), equals(-10));

      fn.dispose();
    });

    test('multiply two integers', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      final arg1 = asm.getArgReg(1);

      asm.movRR(rax, arg0);
      asm.imulRR(rax, arg1);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final mul = ptr.asFunction<DartTwoArgs>();

      expect(mul(6, 7), equals(42));
      expect(mul(-3, 4), equals(-12));
      expect(mul(0, 100), equals(0));

      fn.dispose();
    });

    test('add constant to argument', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.addRI(rax, 100);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final add100 = ptr.asFunction<DartOneArg>();

      expect(add100(0), equals(100));
      expect(add100(50), equals(150));
      expect(add100(-100), equals(0));

      fn.dispose();
    });

    test('negate value', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // Negate: mov rax, 0; sub rax, arg0
      final arg0 = asm.getArgReg(0);
      asm.xorRR(rax, rax);
      asm.subRR(rax, arg0);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final neg = ptr.asFunction<DartOneArg>();

      expect(neg(42), equals(-42));
      expect(neg(-100), equals(100));
      expect(neg(0), equals(0));

      fn.dispose();
    });

    test('function with prologue/epilogue', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.emitPrologue(stackSize: 0);
      asm.movRI64(rax, 999);
      asm.emitEpilogue();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(999));

      fn.dispose();
    });
  });

  group('JIT Execution with Labels', () {
    test('conditional return with jump', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // if (arg0 == 0) return 1; else return 0;
      final arg0 = asm.getArgReg(0);
      final isZero = asm.newLabel();
      final done = asm.newLabel();

      asm.testRR(arg0, arg0);
      asm.je(isZero);

      // Not zero: return 0
      asm.xorRR(rax, rax);
      asm.jmp(done);

      // Is zero: return 1
      asm.bind(isZero);
      asm.movRI64(rax, 1);

      asm.bind(done);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final isZeroFn = ptr.asFunction<DartOneArg>();

      expect(isZeroFn(0), equals(1));
      expect(isZeroFn(1), equals(0));
      expect(isZeroFn(100), equals(0));
      expect(isZeroFn(-5), equals(0));

      fn.dispose();
    });

    test('max function', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // return max(arg0, arg1)
      final arg0 = asm.getArgReg(0);
      final arg1 = asm.getArgReg(1);
      final arg0Greater = asm.newLabel();
      final done = asm.newLabel();

      asm.cmpRR(arg0, arg1);
      asm.jg(arg0Greater);

      // arg1 >= arg0
      asm.movRR(rax, arg1);
      asm.jmp(done);

      asm.bind(arg0Greater);
      asm.movRR(rax, arg0);

      asm.bind(done);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final max = ptr.asFunction<DartTwoArgs>();

      expect(max(5, 3), equals(5));
      expect(max(3, 5), equals(5));
      expect(max(10, 10), equals(10));
      expect(max(-5, -3), equals(-3));

      fn.dispose();
    });
  });

  group('JIT addBytes', () {
    test('raw bytes execution', () {
      // Pre-compiled shellcode for: mov eax, 42; ret
      final bytes = [0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3];

      final fn = runtime.addBytes(Uint8List.fromList(bytes));
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(42));

      fn.dispose();
    });
  });
}
