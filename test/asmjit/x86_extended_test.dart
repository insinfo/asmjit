/// AsmJit Unit Tests - Extended x86 Instructions
///
/// Tests for additional x86 instruction encoding.

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

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
  group('X86Encoder - Unary Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('inc r64 encodes correctly', () {
      encoder.incR64(rax);
      expect(buffer.bytes, equals([0x48, 0xFF, 0xC0]));
    });

    test('dec r64 encodes correctly', () {
      encoder.decR64(rcx);
      expect(buffer.bytes, equals([0x48, 0xFF, 0xC9]));
    });

    test('neg r64 encodes correctly', () {
      encoder.negR64(rax);
      expect(buffer.bytes, equals([0x48, 0xF7, 0xD8]));
    });

    test('not r64 encodes correctly', () {
      encoder.notR64(rax);
      expect(buffer.bytes, equals([0x48, 0xF7, 0xD0]));
    });
  });

  group('X86Encoder - Shift Instructions', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('shl r64, 1 encodes correctly', () {
      encoder.shlR64Imm8(rax, 1);
      expect(buffer.bytes, equals([0x48, 0xD1, 0xE0]));
    });

    test('shl r64, imm8 encodes correctly', () {
      encoder.shlR64Imm8(rax, 4);
      expect(buffer.bytes, equals([0x48, 0xC1, 0xE0, 0x04]));
    });

    test('shr r64, imm8 encodes correctly', () {
      encoder.shrR64Imm8(rcx, 8);
      expect(buffer.bytes, equals([0x48, 0xC1, 0xE9, 0x08]));
    });

    test('sar r64, imm8 encodes correctly', () {
      encoder.sarR64Imm8(rax, 2);
      expect(buffer.bytes, equals([0x48, 0xC1, 0xF8, 0x02]));
    });

    test('rol r64, imm8 encodes correctly', () {
      encoder.rolR64Imm8(rax, 3);
      expect(buffer.bytes, equals([0x48, 0xC1, 0xC0, 0x03]));
    });

    test('ror r64, imm8 encodes correctly', () {
      encoder.rorR64Imm8(rax, 5);
      expect(buffer.bytes, equals([0x48, 0xC1, 0xC8, 0x05]));
    });
  });

  group('X86Encoder - Conditional Move', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('cmove r64, r64 encodes correctly', () {
      encoder.cmovccR64R64(X86Cond.e, rax, rcx);
      expect(buffer.bytes, equals([0x48, 0x0F, 0x44, 0xC1]));
    });

    test('cmovne r64, r64 encodes correctly', () {
      encoder.cmovccR64R64(X86Cond.ne, rax, rdx);
      expect(buffer.bytes, equals([0x48, 0x0F, 0x45, 0xC2]));
    });

    test('cmovg r64, r64 encodes correctly', () {
      encoder.cmovccR64R64(X86Cond.g, rax, r8);
      expect(buffer.bytes, equals([0x49, 0x0F, 0x4F, 0xC0]));
    });
  });

  group('X86Encoder - Division', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    test('cqo encodes correctly', () {
      encoder.cqo();
      expect(buffer.bytes, equals([0x48, 0x99]));
    });

    test('cdq encodes correctly', () {
      encoder.cdq();
      expect(buffer.bytes, equals([0x99]));
    });

    test('idiv r64 encodes correctly', () {
      encoder.idivR64(rcx);
      expect(buffer.bytes, equals([0x48, 0xF7, 0xF9]));
    });

    test('div r64 encodes correctly', () {
      encoder.divR64(rcx);
      expect(buffer.bytes, equals([0x48, 0xF7, 0xF1]));
    });
  });

  group('JIT Execution - Extended Instructions', () {
    late JitRuntime runtime;

    setUp(() {
      runtime = JitRuntime();
    });

    tearDown(() {
      runtime.dispose();
    });

    test('inc function', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.inc(rax);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final inc = ptr.asFunction<DartOneArg>();

      expect(inc(5), equals(6));
      expect(inc(0), equals(1));
      expect(inc(-1), equals(0));

      fn.dispose();
    });

    test('dec function', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.dec(rax);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final dec = ptr.asFunction<DartOneArg>();

      expect(dec(5), equals(4));
      expect(dec(1), equals(0));
      expect(dec(0), equals(-1));

      fn.dispose();
    });

    test('neg function', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.neg(rax);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final neg = ptr.asFunction<DartOneArg>();

      expect(neg(5), equals(-5));
      expect(neg(-10), equals(10));
      expect(neg(0), equals(0));

      fn.dispose();
    });

    test('shl function (left shift by 2)', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.shlRI(rax, 2);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final shl2 = ptr.asFunction<DartOneArg>();

      expect(shl2(1), equals(4));
      expect(shl2(5), equals(20));
      expect(shl2(8), equals(32));

      fn.dispose();
    });

    test('shr function (right shift by 2)', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final arg0 = asm.getArgReg(0);
      asm.movRR(rax, arg0);
      asm.shrRI(rax, 2);
      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final shr2 = ptr.asFunction<DartOneArg>();

      expect(shr2(16), equals(4));
      expect(shr2(32), equals(8));
      expect(shr2(5), equals(1));

      fn.dispose();
    });

    test('cmov function (max without branch)', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // max(a, b) without branches using cmov
      final arg0 = asm.getArgReg(0);
      final arg1 = asm.getArgReg(1);

      asm.movRR(rax, arg0); // rax = a
      asm.cmpRR(arg0, arg1); // compare a, b
      asm.cmovl(rax, arg1); // if a < b, rax = b

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

    test('abs function using cmov', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // abs(x) = x < 0 ? -x : x
      final arg0 = asm.getArgReg(0);

      asm.movRR(rax, arg0); // rax = x
      asm.movRR(rcx, arg0); // rcx = x
      asm.neg(rcx); // rcx = -x
      asm.cmpRI(rax, 0); // compare x, 0
      asm.cmovl(rax, rcx); // if x < 0, rax = -x

      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeOneArg>>();
      final abs = ptr.asFunction<DartOneArg>();

      expect(abs(5), equals(5));
      expect(abs(-5), equals(5));
      expect(abs(0), equals(0));
      expect(abs(-100), equals(100));

      fn.dispose();
    });

    test('division function', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // div(a, b) = a / b (signed)
      // Note: arg1 might be RDX on Win64, which CQO overwrites
      // So we save the divisor in R8 first
      final arg0 = asm.getArgReg(0);
      final arg1 = asm.getArgReg(1);

      asm.movRR(r8, arg1); // save divisor (in case it's RDX)
      asm.movRR(rax, arg0); // dividend in rax
      asm.cqo(); // sign-extend rax into rdx:rax
      asm.idiv(r8); // divide by saved divisor, quotient in rax

      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final divide = ptr.asFunction<DartTwoArgs>();

      expect(divide(10, 2), equals(5));
      expect(divide(15, 3), equals(5));
      expect(divide(7, 2), equals(3));
      expect(divide(-10, 2), equals(-5));

      fn.dispose();
    });

    test('modulo function', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      // mod(a, b) = a % b (signed)
      // Note: arg1 might be RDX on Win64, which CQO overwrites
      // So we save the divisor in R8 first
      final arg0 = asm.getArgReg(0);
      final arg1 = asm.getArgReg(1);

      asm.movRR(r8, arg1); // save divisor (in case it's RDX)
      asm.movRR(rax, arg0); // dividend in rax
      asm.cqo(); // sign-extend rax into rdx:rax
      asm.idiv(r8); // divide by saved divisor, remainder in rdx
      asm.movRR(rax, rdx); // move remainder to return register

      asm.ret();

      final fn = runtime.add(code);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final mod = ptr.asFunction<DartTwoArgs>();

      expect(mod(10, 3), equals(1));
      expect(mod(15, 4), equals(3));
      expect(mod(8, 2), equals(0));
      expect(mod(-10, 3), equals(-1));

      fn.dispose();
    });
  });
}
