/// AsmJit Testing Port - Emitters Suite
///
/// Porta da suite asmjit_test_emitters.cpp - testa os diferentes níveis
/// de abstração do emitter (Assembler, Builder).

import 'dart:ffi';
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('asmjit_test_emitters port', () {
    group('X86 Assembler', () {
      test('basic instruction emission', () {
        final env = Environment.host();
        final code = CodeHolder(env: env);
        final asm = X86Assembler(code);

        // Basic mov, add, ret sequence
        asm.movRR(rax, rdi);
        asm.addRR(rax, rsi);
        asm.ret();

        final bytes = code.finalize().textBytes;
        expect(bytes.isNotEmpty, isTrue);
        expect(bytes.last, equals(0xC3)); // ret
      });

      test('function with prolog/epilog', () {
        final env = Environment.host();
        final code = CodeHolder(env: env);
        final asm = X86Assembler(code);

        // Simula prolog
        asm.push(rbp);
        asm.movRR(rbp, rsp);
        asm.subRI(rsp, 32);

        // Corpo da função
        asm.movRR(rax, rdi);
        asm.addRR(rax, rsi);

        // Simula epilog
        asm.addRI(rsp, 32);
        asm.pop(rbp);
        asm.ret();

        final bytes = code.finalize().textBytes;
        expect(bytes.length, greaterThan(10));
        expect(bytes.last, equals(0xC3)); // ret
      });

      test('AVX instructions in function', () {
        final env = Environment.host();
        final code = CodeHolder(env: env);
        final asm = X86Assembler(code);

        // VEX-encoded AVX instructions
        asm.vaddpsXXX(xmm0, xmm1, xmm2);
        asm.vaddpsYYY(ymm0, ymm1, ymm2);
        asm.vmulpsYYY(ymm3, ymm0, ymm1);
        asm.ret();

        final bytes = code.finalize().textBytes;
        expect(bytes.isNotEmpty, isTrue);
      });

      test('conditional execution pattern', () {
        final env = Environment.host();
        final code = CodeHolder(env: env);
        final asm = X86Assembler(code);

        final loopLabel = asm.newLabel();
        final endLabel = asm.newLabel();

        asm.xorRR(rax, rax);
        asm.bind(loopLabel);
        asm.cmpRR(rdi, rax);
        asm.jcc(X86Cond.le, endLabel);
        asm.addRR(rax, rdi);
        asm.dec(rdi);
        asm.jmp(loopLabel);
        asm.bind(endLabel);
        asm.ret();

        final bytes = code.finalize().textBytes;
        expect(bytes.isNotEmpty, isTrue);
        expect(bytes.last, equals(0xC3));
      });
    });

    group('X86 Builder', () {
      test('basic IR to Assembler', () {
        final builder = X86CodeBuilder.create();

        final a = builder.getArgReg(0);
        final b = builder.getArgReg(1);
        final result = builder.newGpReg();

        builder.mov(result, a);
        builder.add(result, b);
        builder.mov(rax, result);
        builder.ret();

        final runtime = JitRuntime();
        final fn = builder.build(runtime);

        // Verify it compiled successfully
        expect(fn.pointer.address, isNonZero);

        fn.dispose();
        runtime.dispose();
      });

      test('builder with multiple labels', () {
        final builder = X86CodeBuilder.create();

        final labels = <Label>[];
        for (var i = 0; i < 10; i++) {
          labels.add(builder.newLabel());
        }

        for (var i = 0; i < labels.length - 1; i++) {
          builder.jmp(labels[i + 1]);
          builder.label(labels[i]);
        }
        builder.label(labels.last);
        builder.mov(rax, 42);
        builder.ret();

        final runtime = JitRuntime();
        final fn = builder.build(runtime);

        final call = fn.pointer
            .cast<NativeFunction<Int64 Function()>>()
            .asFunction<int Function()>();
        expect(call(), equals(42));

        fn.dispose();
        runtime.dispose();
      });

      test('builder register allocation stress', () {
        final builder = X86CodeBuilder.create();
        final regs = <VirtReg>[];

        // Create many virtual registers to force spilling
        for (var i = 0; i < 20; i++) {
          final r = builder.newGpReg();
          regs.add(r);
          builder.mov(r, i);
        }

        // Sum all registers
        final sum = builder.newGpReg();
        builder.mov(sum, 0);
        for (final r in regs) {
          builder.add(sum, r);
        }
        builder.mov(rax, sum);
        builder.ret();

        final runtime = JitRuntime();
        final fn = builder.build(runtime);

        // Verify code was generated and execute
        expect(fn.pointer.address, isNonZero);
        final bytes = builder.code.text.buffer.bytes;
        expect(bytes.isNotEmpty, isTrue);
        expect(bytes.last, equals(0xC3)); // ret

        // Execute function
        final ptr = fn.pointer.cast<NativeFunction<Int64 Function()>>();
        final exec = ptr.asFunction<int Function()>();
        final res = exec();
        expect(res, equals(190));

        fn.dispose();
        runtime.dispose();
      });
    });

    group('A64 Assembler', () {
      test('basic instruction emission', () {
        final env = Environment.aarch64();
        final code = CodeHolder(env: env);
        final asm = A64Assembler(code);

        asm.add(x0, x0, x1);
        asm.sub(x2, x3, x4);
        asm.ret();

        final bytes = asm.finalize().textBytes;
        expect(bytes.length, equals(12)); // 3 instructions * 4 bytes
        // RET encoding: D65F03C0 (little-endian)
        expect(bytes.sublist(8), equals([0xC0, 0x03, 0x5F, 0xD6]));
      });

      test('function with prolog/epilog', () {
        final env = Environment.aarch64();
        final code = CodeHolder(env: env);
        final asm = A64Assembler(code);

        asm.emitPrologue(stackSize: 64);

        // Corpo da função
        asm.add(x0, x0, x1);
        asm.mul(x0, x0, x2);

        asm.emitEpilogue(stackSize: 64);

        final bytes = asm.finalize().textBytes;
        expect(bytes.isNotEmpty, isTrue);
        // Verifica que termina com RET
        expect(
            bytes.sublist(bytes.length - 4), equals([0xC0, 0x03, 0x5F, 0xD6]));
      });

      test('NEON vector operations', () {
        final env = Environment.aarch64();
        final code = CodeHolder(env: env);
        final asm = A64Assembler(code);

        asm.ldrVec(v0, x0, 0);
        asm.ldrVec(v1, x1, 0);
        asm.addVec(v2.s, v0.s, v1.s);
        asm.strVec(v2, x2, 0);
        asm.ret();

        final bytes = asm.finalize().textBytes;
        expect(bytes.length, equals(20)); // 5 instructions
      });

      test('conditional branches', () {
        final env = Environment.aarch64();
        final code = CodeHolder(env: env);
        final asm = A64Assembler(code);

        final loopLabel = asm.newLabel();
        final endLabel = asm.newLabel();

        asm.bind(loopLabel);
        asm.cmpImm(x0, 0);
        asm.beq(endLabel);
        asm.subImm(x0, x0, 1);
        asm.b(loopLabel);
        asm.bind(endLabel);
        asm.ret();

        final bytes = asm.finalize().textBytes;
        expect(bytes.isNotEmpty, isTrue);
      });
    });

    group('A64 Builder', () {
      test('basic IR generation', () {
        final env = Environment.aarch64();
        final builder = A64CodeBuilder.create(env: env);

        builder.mov(x0, x1);
        builder.add(x0, x0, 10);
        builder.ret();

        final finalized = builder.finalize();
        final bytes = finalized.textBytes;
        expect(bytes.isNotEmpty, isTrue);
      });

      test('builder with stack allocation', () {
        final env = Environment.aarch64();
        final builder = A64CodeBuilder.create(env: env);
        builder.setStackSize(128);

        // Cria vários registros virtuais para forçar spilling
        final regs = <A64Gp>[];
        for (var i = 0; i < 25; i++) {
          final r = builder.newGpReg();
          regs.add(r);
          builder.mov(r, x0);
          builder.add(r, r, i);
        }

        final acc = builder.newGpReg();
        builder.mov(acc, xzr);
        for (final r in regs) {
          builder.add(acc, acc, r);
        }
        builder.mov(x0, acc);
        builder.ret();

        final finalized = builder.finalize();
        final bytes = finalized.textBytes;
        expect(bytes.isNotEmpty, isTrue);
        expect(
            bytes.sublist(bytes.length - 4), equals([0xC0, 0x03, 0x5F, 0xD6]));
      });
    });

    group('Cross-arch consistency', () {
      test('both arches generate valid code', () {
        // X86
        final x86Code = CodeHolder(env: Environment.host());
        final x86Asm = X86Assembler(x86Code);
        x86Asm.nop();
        x86Asm.ret();
        final x86Bytes = x86Code.finalize().textBytes;
        expect(x86Bytes, equals([0x90, 0xC3]));

        // A64
        final a64Code = CodeHolder(env: Environment.aarch64());
        final a64Asm = A64Assembler(a64Code);
        a64Asm.nop();
        a64Asm.ret();
        final a64Bytes = a64Asm.finalize().textBytes;
        // NOP: D503201F, RET: D65F03C0 (little-endian)
        expect(
            a64Bytes, equals([0x1F, 0x20, 0x03, 0xD5, 0xC0, 0x03, 0x5F, 0xD6]));
      });
    });
  });
}
