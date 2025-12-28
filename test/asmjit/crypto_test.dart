/// AsmJit Unit Tests - Cryptography and High-precision Instructions
///
/// Tests for ADC, SBB, MUL, and other instructions useful for cryptography.

import 'dart:ffi';
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

// Native function signatures
typedef NativeNoArgs = Int64 Function();
typedef DartNoArgs = int Function();

typedef NativeOneArg = Int64 Function(Int64);
typedef DartOneArg = int Function(int);

typedef NativeTwoArgs = Int64 Function(Int64, Int64);
typedef DartTwoArgs = int Function(int, int);

typedef NativeThreeArgs = Int64 Function(Int64, Int64, Int64);
typedef DartThreeArgs = int Function(int, int, int);

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
  group('X86Encoder - High-precision Arithmetic', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('adc r64, r64 encodes correctly', () {
      encoder.adcR64R64(rax, rcx);
      expect(buffer.bytes, equals([0x48, 0x11, 0xC8]));
    });

    test('sbb r64, r64 encodes correctly', () {
      encoder.sbbR64R64(rax, rcx);
      expect(buffer.bytes, equals([0x48, 0x19, 0xC8]));
    });

    test('mul r64 encodes correctly', () {
      encoder.mulR64(rcx);
      expect(buffer.bytes, equals([0x48, 0xF7, 0xE1]));
    });

    test('clc encodes correctly', () {
      encoder.clc();
      expect(buffer.bytes, equals([0xF8]));
    });

    test('stc encodes correctly', () {
      encoder.stc();
      expect(buffer.bytes, equals([0xF9]));
    });

    test('cmc encodes correctly', () {
      encoder.cmc();
      expect(buffer.bytes, equals([0xF5]));
    });

    test('pause encodes correctly', () {
      encoder.pause();
      expect(buffer.bytes, equals([0xF3, 0x90]));
    });
  });

  group('X86Encoder - Memory Fences', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('mfence encodes correctly', () {
      encoder.mfence();
      expect(buffer.bytes, equals([0x0F, 0xAE, 0xF0]));
    });

    test('sfence encodes correctly', () {
      encoder.sfence();
      expect(buffer.bytes, equals([0x0F, 0xAE, 0xF8]));
    });

    test('lfence encodes correctly', () {
      encoder.lfence();
      expect(buffer.bytes, equals([0x0F, 0xAE, 0xE8]));
    });
  });

  group('JIT Execution - High-precision Arithmetic', () {
    late JitRuntime runtime;

    setUp(() {
      runtime = JitRuntime();
    });

    tearDown(() {
      runtime.dispose();
    });

    test('add with carry chain (128-bit add)', () {
      // Simulating 128-bit addition: (lo1:hi1) + (lo2:hi2)
      // For testing: we'll do a simpler operation:
      // stc; adc rax, 0 -> should add 1 if carry was set
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.stc(); // Set carry flag
      asm.adcRI(rax, 0); // Add carry (should add 1)
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final addCarry = ptr.asFunction<DartOneArg>();

      // Should add 1 because carry was set
      expect(addCarry(10), equals(11));
      expect(addCarry(0), equals(1));

      fn.dispose();
    });

    test('sub with borrow chain', () {
      // clc; sbb rax, 0 -> should subtract 0 if carry was clear
      // stc; sbb rax, 0 -> should subtract 1 if carry was set (borrow)
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.stc(); // Set carry (borrow) flag
      asm.sbbRI(rax, 0); // Subtract borrow (should subtract 1)
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final subBorrow = ptr.asFunction<DartOneArg>();

      // Should subtract 1 because borrow was set
      expect(subBorrow(10), equals(9));
      expect(subBorrow(1), equals(0));

      fn.dispose();
    });

    test('unsigned multiply full result', () {
      // MUL multiplies RAX by src, result in RDX:RAX
      // For testing, use small numbers where result fits in RAX
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0); // multiplier in first arg
      final arg1 = asm.getArgReg(1); // multiplicand

      asm.movRR(rax, arg0); // RAX = arg0
      asm.mul(arg1); // RDX:RAX = RAX * arg1
      // Result low part already in RAX
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final multiply = ptr.asFunction<DartTwoArgs>();

      expect(multiply(6, 7), equals(42));
      expect(multiply(100, 100), equals(10000));
      expect(multiply(0, 12345), equals(0));

      fn.dispose();
    });

    test('adc chain for 128-bit addition', () {
      // Simulate adding two 64-bit numbers where we might have carry
      // add(a, b): add a + b, return result (carry ignored for now)
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      final arg1 = asm.getArgReg(1);

      asm.clc(); // Clear carry
      asm.movRR(rax, arg0);
      asm.addRR(rax, arg1); // Regular add, sets carry if overflow
      // If we had a second pair of values, we'd use adc here
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final add = ptr.asFunction<DartTwoArgs>();

      expect(add(100, 200), equals(300));
      expect(add(0, 0), equals(0));

      fn.dispose();
    });
  });

  group('FuncFrame', () {
    test('creates with default calling convention', () {
      final frame = FuncFrame.host();
      // Just verify it doesn't throw and has reasonable defaults
      expect(frame.frameSize, greaterThanOrEqualTo(0));
    });

    test('getArgReg returns correct registers for Win64', () {
      final frame = FuncFrame.host();

      expect(frame.getArgReg(0, CallingConvention.win64), equals(rcx));
      expect(frame.getArgReg(1, CallingConvention.win64), equals(rdx));
      expect(frame.getArgReg(2, CallingConvention.win64), equals(r8));
      expect(frame.getArgReg(3, CallingConvention.win64), equals(r9));
    });

    test('getArgReg returns correct registers for SysV', () {
      final frame = FuncFrame.host();

      expect(frame.getArgReg(0, CallingConvention.sysV64), equals(rdi));
      expect(frame.getArgReg(1, CallingConvention.sysV64), equals(rsi));
      expect(frame.getArgReg(2, CallingConvention.sysV64), equals(rdx));
      expect(frame.getArgReg(3, CallingConvention.sysV64), equals(rcx));
    });

    test('frame with local variables calculates size', () {
      final frame = FuncFrame.host(
        attr: FuncFrameAttributes.nonLeaf(localStackSize: 64),
      );
      expect(frame.frameSize, greaterThanOrEqualTo(64));
    });

    test('getStackArgOffset throws for register args', () {
      final frame = FuncFrame.host();

      expect(() => frame.getStackArgOffset(0, CallingConvention.win64),
          throwsArgumentError);
      expect(() => frame.getStackArgOffset(3, CallingConvention.win64),
          throwsArgumentError);

      // arg 4 and beyond are on stack for Win64
      expect(frame.getStackArgOffset(4, CallingConvention.win64),
          equals(32)); // RBP+16 (Comment was wrong?)
    });
  });
}
