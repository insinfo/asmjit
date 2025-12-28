/// AsmJit Unit Tests - X86 Assembler
///
/// Tests for high-level X86Assembler functionality.

import 'dart:io' show Platform;
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
  group('X86Assembler', () {
    test('creates assembler with code holder', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      expect(asm.offset, equals(0));
      expect(asm.is64Bit, isTrue);
    });

    test('factory create initializes correctly', () {
      final asm = X86Assembler.create();
      expect(asm.code, isNotNull);
    });

    test('environment detection', () {
      final asm = X86Assembler.create();
      if (Platform.isWindows) {
        expect(asm.callingConvention, equals(CallingConvention.win64));
      } else {
        expect(asm.callingConvention, equals(CallingConvention.sysV64));
      }
    });

    test('getArgReg returns correct registers for Win64', () {
      final env = Environment.x64Windows();
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);

      expect(asm.getArgReg(0), equals(rcx));
      expect(asm.getArgReg(1), equals(rdx));
      expect(asm.getArgReg(2), equals(r8));
      expect(asm.getArgReg(3), equals(r9));
    });

    test('getArgReg returns correct registers for SysV', () {
      final env = Environment.x64SysV();
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);

      expect(asm.getArgReg(0), equals(rdi));
      expect(asm.getArgReg(1), equals(rsi));
      expect(asm.getArgReg(2), equals(rdx));
      expect(asm.getArgReg(3), equals(rcx));
      expect(asm.getArgReg(4), equals(r8));
      expect(asm.getArgReg(5), equals(r9));
    });

    test('getArgReg throws for too many args', () {
      final asm = X86Assembler.create();
      expect(
        () => asm.getArgReg(10),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('X86Assembler Labels', () {
    test('creates and binds labels', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final label = asm.newLabel();
      asm.nop();
      asm.nop();
      asm.bind(label);

      expect(code.isLabelBound(label), isTrue);
      expect(code.getLabelOffset(label), equals(2));
    });

    test('named labels work correctly', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final entry = asm.newNamedLabel('entry');
      asm.bind(entry);
      asm.ret();

      expect(code.getLabelByName('entry'), equals(entry));
    });
  });

  group('X86Assembler Code Generation', () {
    test('simple ret function', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.movRI64(rax, 42);
      asm.ret();

      final finalized = code.finalize();
      // mov eax, 42 (optimized from r64) + ret
      expect(finalized.textBytes, equals([0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3]));
    });

    test('add function generates correct bytes', () {
      final env =
          Environment.x64Windows(); // Force Win64 for deterministic test
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);

      // Assume Win64 style: arg0 in rcx, arg1 in rdx
      asm.movRR(rax, rcx);
      asm.addRR(rax, rdx);
      asm.ret();

      final finalized = code.finalize();
      expect(
        finalized.textBytes,
        equals([0x48, 0x89, 0xC8, 0x48, 0x01, 0xD0, 0xC3]),
      );
    });

    test('jump to label', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final skip = asm.newLabel();
      asm.jmp(skip);
      asm.int3();
      asm.int3();
      asm.bind(skip);
      asm.ret();

      final finalized = code.finalize();
      // jmp rel32 (E9 02 00 00 00) + int3 + int3 + ret
      expect(
        finalized.textBytes,
        equals([0xE9, 0x02, 0x00, 0x00, 0x00, 0xCC, 0xCC, 0xC3]),
      );
    });

    test('conditional jump', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      final ifTrue = asm.newLabel();
      asm.cmpRR(rax, rcx);
      asm.je(ifTrue);
      asm.nop();
      asm.bind(ifTrue);
      asm.ret();

      final finalized = code.finalize();
      // cmp rax,rcx + je rel32 + nop + ret
      expect(finalized.textBytes.length, greaterThan(0));
    });

    test('prologue and epilogue', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.emitPrologue();
      asm.movRI64(rax, 0);
      asm.emitEpilogue();

      final finalized = code.finalize();
      // push rbp + mov rbp,rsp + mov eax,0 + mov rsp,rbp + pop rbp + ret
      expect(finalized.textBytes.length, greaterThan(10));
    });
  });

  group('X86Assembler Inline Bytes', () {
    test('emitInline adds raw bytes', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.emitInline([0x90, 0x90, 0x90]);
      asm.ret();

      final finalized = code.finalize();
      expect(finalized.textBytes, equals([0x90, 0x90, 0x90, 0xC3]));
    });

    test('emitBytes adds raw bytes', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.emitBytes([0x48, 0x31, 0xC0]); // xor rax, rax
      asm.ret();

      final finalized = code.finalize();
      expect(finalized.textBytes, equals([0x48, 0x31, 0xC0, 0xC3]));
    });
  });

  group('FuncSignature', () {
    test('default constructor creates empty signature', () {
      final sig = FuncSignature();
      expect(sig.argCount, 0);
      expect(sig.hasRet, isFalse);
      expect(sig.retType.isVoid, isTrue);
    });

    test('noArgs factory creates signature with return type', () {
      final sig = FuncSignature.noArgs(ret: TypeId.int64);
      expect(sig.argCount, 0);
      expect(sig.hasRet, isTrue);
      expect(sig.retType, TypeId.int64);
    });

    test('i64i64 factory creates binary function', () {
      final sig = FuncSignature.i64i64();
      expect(sig.argCount, 2);
      expect(sig.arg(0), TypeId.int64);
      expect(sig.arg(1), TypeId.int64);
      expect(sig.retType, TypeId.int64);
    });

    test('i64i64i64 factory creates ternary function', () {
      final sig = FuncSignature.i64i64i64();
      expect(sig.argCount, 3);
      expect(sig.arg(0), TypeId.int64);
      expect(sig.arg(1), TypeId.int64);
      expect(sig.arg(2), TypeId.int64);
    });

    test('f64f64f64 factory creates ternary double function', () {
      final sig = FuncSignature.f64f64f64();
      expect(sig.argCount, 3);
      expect(sig.retType, TypeId.float64);
    });

    test('addArg adds arguments', () {
      final sig = FuncSignature();
      sig.addArg(TypeId.int32);
      sig.addArg(TypeId.int64);

      expect(sig.argCount, 2);
      expect(sig.arg(0), TypeId.int32);
      expect(sig.arg(1), TypeId.int64);
    });

    test('setRet changes return type', () {
      final sig = FuncSignature();
      expect(sig.hasRet, isFalse);

      sig.setRet(TypeId.float32);
      expect(sig.hasRet, isTrue);
      expect(sig.retType, TypeId.float32);
    });

    test('hasVarArgs detects variadic functions', () {
      final sig = FuncSignature();
      expect(sig.hasVarArgs, isFalse);

      final vaSig = FuncSignature(vaIndex: 2);
      expect(vaSig.hasVarArgs, isTrue);
    });

    test('toString provides readable output', () {
      final sig = FuncSignature.i64i64i64();
      expect(sig.toString(), contains('int64'));
    });
  });

  group('CallConvId', () {
    test('contains expected values', () {
      expect(CallConvId.cdecl, isNotNull);
      expect(CallConvId.x64SystemV, isNotNull);
      expect(CallConvId.x64Windows, isNotNull);
    });
  });

  group('X86Gp encoding rules', () {
    test('high-byte registers use encoding 4..7 (AH/CH/DH/BH)', () {
      expect(ah.encoding, equals(4));
      expect(ch.encoding, equals(5));
      expect(dh.encoding, equals(6));
      expect(bh.encoding, equals(7));
    });

    test('spl/bpl/sil/dil (ids 4..7) require REX in 64-bit mode', () {
      // SPL/BPL/SIL/DIL are the low 8-bit regs of SP/BP/SI/DI.
      // In x86-64 they need a REX prefix to disambiguate from AH/CH/DH/BH.
      expect(X86Gp.r8(4).needsRex, isTrue); // spl
      expect(X86Gp.r8(5).needsRex, isTrue); // bpl
      expect(X86Gp.r8(6).needsRex, isTrue); // sil
      expect(X86Gp.r8(7).needsRex, isTrue); // dil
    });
  });
}
