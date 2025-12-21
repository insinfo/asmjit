/// AsmJit Unit Tests - x86 Encoder
///
/// Tests for x86/x64 instruction encoding.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('X86Encoder', () {
    late CodeBuffer buffer;
    late X86Encoder encoder;

    setUp(() {
      buffer = CodeBuffer();
      encoder = X86Encoder(buffer);
    });

    group('Basic Instructions', () {
      test('ret encodes correctly', () {
        encoder.ret();
        expect(buffer.bytes, equals([0xC3]));
      });

      test('ret imm16 encodes correctly', () {
        encoder.retImm(8);
        expect(buffer.bytes, equals([0xC2, 0x08, 0x00]));
      });

      test('nop encodes correctly', () {
        encoder.nop();
        expect(buffer.bytes, equals([0x90]));
      });

      test('int3 encodes correctly', () {
        encoder.int3();
        expect(buffer.bytes, equals([0xCC]));
      });

      test('intN encodes correctly', () {
        encoder.intN(0x80);
        expect(buffer.bytes, equals([0xCD, 0x80]));
      });
    });

    group('MOV Instructions', () {
      test('mov rax, rcx encodes correctly', () {
        encoder.movR64R64(rax, rcx);
        // REX.W (48) + MOV r/m64,r64 (89) + ModR/M (C8 = 11 001 000)
        expect(buffer.bytes, equals([0x48, 0x89, 0xC8]));
      });

      test('mov r8, r9 encodes correctly', () {
        encoder.movR64R64(r8, r9);
        // REX.WRB (4D) + MOV (89) + ModR/M (C8)
        expect(buffer.bytes, equals([0x4D, 0x89, 0xC8]));
      });

      test('mov eax, ecx encodes correctly (32-bit)', () {
        encoder.movR32R32(eax, ecx);
        expect(buffer.bytes, equals([0x89, 0xC8]));
      });

      test('mov r8d, r9d encodes correctly (32-bit extended)', () {
        encoder.movR32R32(r8d, r9d);
        // REX.RB (45) + MOV (89) + ModR/M
        expect(buffer.bytes, equals([0x45, 0x89, 0xC8]));
      });

      test('mov rax, imm32 encodes correctly', () {
        encoder.movR32Imm32(eax, 42);
        // MOV r32, imm32: B8+rd + imm32
        expect(buffer.bytes, equals([0xB8, 0x2A, 0x00, 0x00, 0x00]));
      });

      test('mov r8, imm32 encodes correctly', () {
        encoder.movR32Imm32(r8d, 100);
        // REX.B (41) + B8+0 + imm32
        expect(buffer.bytes, equals([0x41, 0xB8, 0x64, 0x00, 0x00, 0x00]));
      });

      test('mov rax, imm64 encodes correctly', () {
        encoder.movR64Imm64(rax, 0x123456789ABCDEF0);
        // REX.W + B8+rd + imm64
        expect(
          buffer.bytes,
          equals([
            0x48, 0xB8, // REX.W + MOV rax, imm64
            0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12
          ]),
        );
      });
    });

    group('ADD Instructions', () {
      test('add rax, rcx encodes correctly', () {
        encoder.addR64R64(rax, rcx);
        // REX.W (48) + ADD r/m64,r64 (01) + ModR/M
        expect(buffer.bytes, equals([0x48, 0x01, 0xC8]));
      });

      test('add r8, r9 encodes correctly', () {
        encoder.addR64R64(r8, r9);
        expect(buffer.bytes, equals([0x4D, 0x01, 0xC8]));
      });

      test('add rax, imm8 encodes correctly', () {
        encoder.addR64Imm8(rax, 10);
        // REX.W + ADD r/m64,imm8 (83 /0) + imm8
        expect(buffer.bytes, equals([0x48, 0x83, 0xC0, 0x0A]));
      });

      test('add rcx, imm32 encodes correctly', () {
        encoder.addR64Imm32(rcx, 0x12345678);
        // REX.W + ADD r/m64,imm32 (81 /0) + imm32
        expect(
          buffer.bytes,
          equals([0x48, 0x81, 0xC1, 0x78, 0x56, 0x34, 0x12]),
        );
      });

      test('add rax, imm32 uses short form', () {
        encoder.addR64Imm32(rax, 0x12345678);
        // REX.W + ADD rax,imm32 (05) + imm32
        expect(
          buffer.bytes,
          equals([0x48, 0x05, 0x78, 0x56, 0x34, 0x12]),
        );
      });
    });

    group('SUB Instructions', () {
      test('sub rax, rcx encodes correctly', () {
        encoder.subR64R64(rax, rcx);
        expect(buffer.bytes, equals([0x48, 0x29, 0xC8]));
      });

      test('sub rax, imm8 encodes correctly', () {
        encoder.subR64Imm8(rax, 8);
        expect(buffer.bytes, equals([0x48, 0x83, 0xE8, 0x08]));
      });
    });

    group('Stack Instructions', () {
      test('push rax encodes correctly', () {
        encoder.pushR64(rax);
        expect(buffer.bytes, equals([0x50]));
      });

      test('push r8 encodes correctly', () {
        encoder.pushR64(r8);
        expect(buffer.bytes, equals([0x41, 0x50]));
      });

      test('pop rax encodes correctly', () {
        encoder.popR64(rax);
        expect(buffer.bytes, equals([0x58]));
      });

      test('pop r15 encodes correctly', () {
        encoder.popR64(r15);
        expect(buffer.bytes, equals([0x41, 0x5F]));
      });

      test('push imm8 encodes correctly', () {
        encoder.pushImm8(42);
        expect(buffer.bytes, equals([0x6A, 0x2A]));
      });

      test('push imm32 encodes correctly', () {
        encoder.pushImm32(0x12345678);
        expect(buffer.bytes, equals([0x68, 0x78, 0x56, 0x34, 0x12]));
      });
    });

    group('Control Flow Instructions', () {
      test('jmp rel32 placeholder', () {
        final offset = encoder.jmpRel32Placeholder();
        expect(offset, equals(1)); // After E9 opcode
        expect(buffer.bytes, equals([0xE9, 0x00, 0x00, 0x00, 0x00]));
      });

      test('call rel32 placeholder', () {
        final offset = encoder.callRel32Placeholder();
        expect(offset, equals(1));
        expect(buffer.bytes, equals([0xE8, 0x00, 0x00, 0x00, 0x00]));
      });

      test('call rax encodes correctly', () {
        encoder.callR64(rax);
        expect(buffer.bytes, equals([0xFF, 0xD0]));
      });

      test('jmp rax encodes correctly', () {
        encoder.jmpR64(rax);
        expect(buffer.bytes, equals([0xFF, 0xE0]));
      });

      test('jcc rel32 placeholder je', () {
        final offset = encoder.jccRel32Placeholder(X86Cond.e);
        expect(offset, equals(2)); // After 0F 84
        expect(buffer.bytes, equals([0x0F, 0x84, 0x00, 0x00, 0x00, 0x00]));
      });

      test('jcc rel32 placeholder jne', () {
        encoder.jccRel32Placeholder(X86Cond.ne);
        expect(buffer.bytes, equals([0x0F, 0x85, 0x00, 0x00, 0x00, 0x00]));
      });
    });

    group('Logical Instructions', () {
      test('xor rax, rax encodes correctly', () {
        encoder.xorR64R64(rax, rax);
        expect(buffer.bytes, equals([0x48, 0x31, 0xC0]));
      });

      test('and rax, rcx encodes correctly', () {
        encoder.andR64R64(rax, rcx);
        expect(buffer.bytes, equals([0x48, 0x21, 0xC8]));
      });

      test('or rax, rdx encodes correctly', () {
        encoder.orR64R64(rax, rdx);
        expect(buffer.bytes, equals([0x48, 0x09, 0xD0]));
      });

      test('test rax, rax encodes correctly', () {
        encoder.testR64R64(rax, rax);
        expect(buffer.bytes, equals([0x48, 0x85, 0xC0]));
      });

      test('cmp rax, rcx encodes correctly', () {
        encoder.cmpR64R64(rax, rcx);
        expect(buffer.bytes, equals([0x48, 0x39, 0xC8]));
      });
    });

    group('IMUL Instruction', () {
      test('imul rax, rcx encodes correctly', () {
        encoder.imulR64R64(rax, rcx);
        // REX.W + 0F AF /r
        expect(buffer.bytes, equals([0x48, 0x0F, 0xAF, 0xC1]));
      });
    });
  });
}
