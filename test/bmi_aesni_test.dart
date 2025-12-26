import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  Uint8List getBytes(CodeHolder code) {
    return code.text.buffer.bytes;
  }

  group('BMI1 Instructions', () {
    test('ANDN encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.andnR64R64R64(rax, rbx, rcx);

      expect(buffer.bytes.length, greaterThan(0));
      expect(buffer.bytes[0], 0xC4);
    });

    test('BEXTR encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.bextrR64R64R64(rax, rbx, rcx);

      expect(buffer.bytes[0], 0xC4);
    });

    test('BLSI encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.blsiR64R64(rax, rbx);

      expect(buffer.bytes[0], 0xC4);
    });

    test('BLSMSK encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.blsmskR64R64(rax, rbx);

      expect(buffer.bytes[0], 0xC4);
    });

    test('BLSR encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.blsrR64R64(rax, rbx);

      expect(buffer.bytes[0], 0xC4);
    });
  });

  group('BMI2 Instructions', () {
    test('BZHI encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.bzhiR64R64R64(rax, rbx, rcx);

      expect(buffer.bytes[0], 0xC4);
    });

    test('PDEP encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.pdepR64R64R64(rax, rbx, rcx);

      expect(buffer.bytes[0], 0xC4);
    });

    test('PEXT encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.pextR64R64R64(rax, rbx, rcx);

      expect(buffer.bytes[0], 0xC4);
    });

    test('RORX encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.rorxR64R64Imm8(rax, rbx, 5);

      expect(buffer.bytes[0], 0xC4);
      expect(buffer.bytes.last, 5);
    });

    test('SARX encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.sarxR64R64R64(rax, rbx, rcx);

      expect(buffer.bytes[0], 0xC4);
    });

    test('SHLX encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.shlxR64R64R64(rax, rbx, rcx);

      expect(buffer.bytes[0], 0xC4);
    });

    test('SHRX encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.shrxR64R64R64(rax, rbx, rcx);

      expect(buffer.bytes[0], 0xC4);
    });
  });

  group('AES-NI Instructions', () {
    test('AESENC encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.aesencXmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[1], 0x0F);
      expect(bytes[2], 0x38);
      expect(bytes[3], 0xDC);
    });

    test('AESENCLAST encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.aesenclastXmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[3], 0xDD);
    });

    test('AESDEC encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.aesdecXmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[3], 0xDE);
    });

    test('AESDECLAST encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.aesdeclastXmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[3], 0xDF);
    });

    test('AESKEYGENASSIST encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.aeskeygenassistXmmXmmImm8(xmm0, xmm1, 0x01);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes.last, 0x01);
    });

    test('AESIMC encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.aesimcXmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[3], 0xDB);
    });
  });

  group('Memory-Immediate Instructions', () {
    test('MOV [mem], imm32 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.movMemImm32(X86Mem.baseDisp(rax, 8), 0x12345678);

      expect(buffer.bytes.length, greaterThan(4));
    });

    test('ADD [mem], r64 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.addMemR64(X86Mem.baseDisp(rax, 8), rbx);

      expect(buffer.bytes.length, greaterThan(0));
    });

    test('ADD [mem], imm32 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.addMemImm32(X86Mem.baseDisp(rax, 8), 100);

      expect(buffer.bytes.length, greaterThan(4));
    });

    test('SUB [mem], r64 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.subMemR64(X86Mem.baseDisp(rax, 8), rbx);

      expect(buffer.bytes.length, greaterThan(0));
    });

    test('CMP [mem], imm32 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.cmpMemImm32(X86Mem.baseDisp(rax, 8), 0xFF);

      expect(buffer.bytes.length, greaterThan(4));
    });
  });

  group('IMUL 3-operand form', () {
    test('IMUL r64, r64, imm8 encoding', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.imulRRI(rax, rbx, 10);

      final bytes = getBytes(code);
      expect(bytes.length, greaterThan(0));
    });

    test('IMUL r64, r64, imm32 encoding', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.imulRRI(rax, rbx, 1000);

      final bytes = getBytes(code);
      expect(bytes.length, greaterThan(4));
    });
  });

  group('SHA Extensions', () {
    test('SHA1RNDS4 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.sha1rnds4XmmXmmImm8(xmm0, xmm1, 0x01);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x0F);
      expect(bytes[1], 0x3A);
      expect(bytes[2], 0xCC);
      expect(bytes.last, 0x01);
    });

    test('SHA1NEXTE encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.sha1nexteXmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x0F);
      expect(bytes[1], 0x38);
      expect(bytes[2], 0xC8);
    });

    test('SHA1MSG1 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.sha1msg1XmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x0F);
      expect(bytes[2], 0xC9);
    });

    test('SHA1MSG2 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.sha1msg2XmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[2], 0xCA);
    });

    test('SHA256RNDS2 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.sha256rnds2XmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x0F);
      expect(bytes[2], 0xCB);
    });

    test('SHA256MSG1 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.sha256msg1XmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[2], 0xCC);
    });

    test('SHA256MSG2 encoding', () {
      final buffer = CodeBuffer();
      final enc = X86Encoder(buffer);

      enc.sha256msg2XmmXmm(xmm0, xmm1);

      final bytes = buffer.bytes;
      expect(bytes[2], 0xCD);
    });
  });

  group('FuncDetail', () {
    test('allocates Win64 GP args correctly', () {
      final sig = FuncSignature.i64i64i64();
      final detail = FuncDetail(sig, cc: CallingConvention.win64);

      expect(detail.argValues.length, 2);
      expect(detail.argValues[0].isReg, isTrue);
      expect(detail.argValues[0].regId, 1); // RCX
      expect(detail.argValues[1].regId, 2); // RDX
    });

    test('allocates SysV GP args correctly', () {
      final sig = FuncSignature.i64i64i64();
      final detail = FuncDetail(sig, cc: CallingConvention.sysV64);

      expect(detail.argValues.length, 2);
      expect(detail.argValues[0].regId, 7); // RDI
      expect(detail.argValues[1].regId, 6); // RSI
    });

    test('allocates float args in XMM', () {
      final sig = FuncSignature.f64f64f64();
      final detail = FuncDetail(sig, cc: CallingConvention.sysV64);

      expect(detail.argValues[0].regType, FuncRegType.xmm);
      expect(detail.argValues[1].regType, FuncRegType.xmm);
    });

    test('allocates return in RAX for int64', () {
      final sig = FuncSignature.i64i64();
      final detail = FuncDetail(sig, cc: CallingConvention.sysV64);

      expect(detail.retValue.isReg, isTrue);
      expect(detail.retValue.regId, 0); // RAX
    });

    test('allocates return in XMM0 for float64', () {
      final sig = FuncSignature.f64f64f64();
      final detail = FuncDetail(sig, cc: CallingConvention.sysV64);

      expect(detail.retValue.regType, FuncRegType.xmm);
      expect(detail.retValue.regId, 0); // XMM0
    });

    test('spills excess args to stack', () {
      final sig = FuncSignature();
      for (int i = 0; i < 8; i++) {
        sig.addArg(TypeId.int64);
      }
      final detail = FuncDetail(sig, cc: CallingConvention.win64);

      // Win64: 4 GP regs, so 4 on stack
      expect(detail.gpArgCount, 4);
      expect(detail.stackArgCount, 4);
    });
  });
}
