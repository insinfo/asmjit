import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

import '../support/host.dart';

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
  Uint8List getBytes(CodeHolder code) {
    return code.text.buffer.bytes;
  }

  group('BMI1 Instructions', () {
    test('ANDN encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAndn, [rax, rbx, rcx]);

      expect(buffer.bytes.length, greaterThan(0));
      expect(buffer.bytes[0], 0xC4);
    });

    test('BEXTR encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kBextr, [rax, rbx, rcx]);

      expect(buffer.bytes[0], 0xC4);
    });

    test('BLSI encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kBlsi, [rax, rbx]);

      expect(buffer.bytes[0], 0xC4);
    });

    test('BLSMSK encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kBlsmsk, [rax, rbx]);

      expect(buffer.bytes[0], 0xC4);
    });

    test('BLSR encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kBlsr, [rax, rbx]);

      expect(buffer.bytes[0], 0xC4);
    });
  });

  group('BMI2 Instructions', () {
    test('BZHI encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kBzhi, [rax, rbx, rcx]);

      expect(buffer.bytes[0], 0xC4);
    });

    test('PDEP encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kPdep, [rax, rbx, rcx]);

      expect(buffer.bytes[0], 0xC4);
    });

    test('PEXT encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kPext, [rax, rbx, rcx]);

      expect(buffer.bytes[0], 0xC4);
    });

    test('RORX encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kRorx, [rax, rbx, 5]);

      expect(buffer.bytes[0], 0xC4);
      expect(buffer.bytes.last, 5);
    });

    test('SARX encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSarx, [rax, rbx, rcx]);

      expect(buffer.bytes[0], 0xC4);
    });

    test('SHLX encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kShlx, [rax, rbx, rcx]);

      expect(buffer.bytes[0], 0xC4);
    });

    test('SHRX encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kShrx, [rax, rbx, rcx]);

      expect(buffer.bytes[0], 0xC4);
    });
  });

  group('AES-NI Instructions', () {
    test('AESENC encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAesenc, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[1], 0x0F);
      expect(bytes[2], 0x38);
      expect(bytes[3], 0xDC);
    });

    test('AESENCLAST encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAesenclast, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[3], 0xDD);
    });

    test('AESDEC encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAesdec, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[3], 0xDE);
    });

    test('AESDECLAST encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAesdeclast, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[3], 0xDF);
    });

    test('AESKEYGENASSIST encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAeskeygenassist, [xmm0, xmm1, 0x01]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes.last, 0x01);
    });

    test('AESIMC encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAesimc, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x66);
      expect(bytes[3], 0xDB);
    });
  });

  group('Memory-Immediate Instructions', () {
    test('MOV [mem], imm32 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kMov, [X86Mem.baseDisp(rax, 8, size: 8), 0x12345678]);

      expect(buffer.bytes.length, greaterThan(4));
    });

    test('ADD [mem], r64 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAdd, [X86Mem.baseDisp(rax, 8), rbx]);

      expect(buffer.bytes.length, greaterThan(0));
    });

    test('ADD [mem], imm32 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kAdd, [X86Mem.baseDisp(rax, 8, size: 8), 100]);

      expect(buffer.bytes.length, greaterThan(4));
    });

    test('SUB [mem], r64 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSub, [X86Mem.baseDisp(rax, 8), rbx]);

      expect(buffer.bytes.length, greaterThan(0));
    });

    test('CMP [mem], imm32 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kCmp, [X86Mem.baseDisp(rax, 8, size: 8), 0xFF]);

      expect(buffer.bytes.length, greaterThan(4));
    });
  });

  group('IMUL 3-operand form', () {
    test('IMUL r64, r64, imm8 encoding', () {
      final code = CodeHolder(env: x64TestEnv());
      final asm = X86Assembler(code);

      asm.imulRRI(rax, rbx, 10);

      final bytes = getBytes(code);
      expect(bytes.length, greaterThan(0));
    });

    test('IMUL r64, r64, imm32 encoding', () {
      final code = CodeHolder(env: x64TestEnv());
      final asm = X86Assembler(code);

      asm.imulRRI(rax, rbx, 1000);

      final bytes = getBytes(code);
      expect(bytes.length, greaterThan(4));
    });
  });

  group('SHA Extensions', () {
    test('SHA1RNDS4 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSha1rnds4, [xmm0, xmm1, 0x01]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x0F);
      expect(bytes[1], 0x3A);
      expect(bytes[2], 0xCC);
      expect(bytes.last, 0x01);
    });

    test('SHA1NEXTE encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSha1nexte, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x0F);
      expect(bytes[1], 0x38);
      expect(bytes[2], 0xC8);
    });

    test('SHA1MSG1 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSha1msg1, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x0F);
      expect(bytes[2], 0xC9);
    });

    test('SHA1MSG2 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSha1msg2, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[2], 0xCA);
    });

    test('SHA256RNDS2 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSha256rnds2, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[0], 0x0F);
      expect(bytes[2], 0xCB);
    });

    test('SHA256MSG1 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSha256msg1, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[2], 0xCC);
    });

    test('SHA256MSG2 encoding', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final buffer = code.text.buffer;
      final enc = X86Assembler(code);

      enc.emit(X86InstId.kSha256msg2, [xmm0, xmm1]);

      final bytes = buffer.bytes;
      expect(bytes[2], 0xCD);
    });
  });

  group('FuncDetail', () {
    test('allocates Win64 GP args correctly', () {
      final sig = FuncSignature.i64i64i64();
      final detail = FuncDetail(sig, CallingConvention.win64);

      expect(detail.argCount, 3);
      expect(detail.getArg(0).isReg, isTrue);
      expect(detail.getArg(0).regId, 1); // RCX
      expect(detail.getArg(1).regId, 2); // RDX
    });

    test('allocates SysV GP args correctly', () {
      final sig = FuncSignature.i64i64i64();
      final detail = FuncDetail(sig, CallingConvention.sysV64);

      expect(detail.argCount, 3);
      expect(detail.getArg(0).regId, 7); // RDI
      expect(detail.getArg(1).regId, 6); // RSI
    });

    test('allocates float args in XMM', () {
      final sig = FuncSignature.f64f64f64();
      final detail = FuncDetail(sig, CallingConvention.sysV64);

      expect(detail.getArg(0).regType, FuncRegType.xmm);
      expect(detail.getArg(1).regType, FuncRegType.xmm);
    });

    test('allocates return in RAX for int64', () {
      final sig = FuncSignature.i64i64();
      final detail = FuncDetail(sig, CallingConvention.sysV64);

      expect(detail.retValue.isReg, isTrue);
      expect(detail.retValue.regId, 0); // RAX
    });

    test('allocates return in XMM0 for float64', () {
      final sig = FuncSignature.f64f64f64();
      final detail = FuncDetail(sig, CallingConvention.sysV64);

      expect(detail.retValue.regType, FuncRegType.xmm);
      expect(detail.retValue.regId, 0); // XMM0
    });

    test('spills excess args to stack', () {
      final sig = FuncSignature();
      for (int i = 0; i < 8; i++) {
        sig.addArg(TypeId.int64);
      }
      final detail = FuncDetail(sig, CallingConvention.win64);

      // Win64: 4 GP regs, so 4 passed via registers.
      // Win64 calling convention allocates shadow space (32 bytes) on the stack for the first 4 arguments.
      // Plus 4 overflowing arguments are on the stack. Total 8 stack slots reserved.
      expect(detail.gpArgCount, 4);
      expect(detail.stackArgCount, 8);
    });
  });
}
