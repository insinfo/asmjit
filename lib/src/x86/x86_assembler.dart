/// AsmJit x86/x64 Assembler
///
/// High-level x86/x64 instruction emission API.
/// Ported from asmjit/x86/x86assembler.h

import 'dart:io' show Platform;

import '../core/code_holder.dart';
import '../core/code_buffer.dart';
import '../core/labels.dart';
import '../core/environment.dart';
import '../core/arch.dart';
import 'x86.dart';
import 'x86_operands.dart';
import 'x86_encoder.dart';

/// x86/x64 Assembler.
///
/// Provides a high-level API for emitting x86/x64 instructions.
/// Handles label binding, relocations, and instruction encoding.
class X86Assembler {
  /// The code holder.
  final CodeHolder code;

  /// The internal code buffer.
  late final CodeBuffer _buf;

  /// The instruction encoder.
  late final X86Encoder _enc;

  /// Creates an x86 assembler for the given code holder.
  X86Assembler(this.code) {
    _buf = code.text.buffer;
    _enc = X86Encoder(_buf);
  }

  /// Creates an x86 assembler with a new code holder.
  factory X86Assembler.create({Environment? env}) {
    final code = CodeHolder(env: env);
    return X86Assembler(code);
  }

  // ===========================================================================
  // Properties
  // ===========================================================================

  /// The current offset in the code buffer.
  int get offset => _buf.length;

  /// The environment.
  Environment get environment => code.env;

  /// Whether this is a 64-bit assembler.
  bool get is64Bit => environment.arch == Arch.x64;

  /// The calling convention for this environment.
  CallingConvention get callingConvention => environment.callingConvention;

  // ===========================================================================
  // Label management
  // ===========================================================================

  /// Creates a new label.
  Label newLabel() => code.newLabel();

  /// Creates a new named label.
  Label newNamedLabel(String name) => code.newNamedLabel(name);

  /// Binds a label to the current position.
  void bind(Label label) => code.bind(label);

  // ===========================================================================
  // Raw byte emission
  // ===========================================================================

  /// Emits raw bytes.
  void emitBytes(List<int> bytes) => _buf.emitBytes(bytes);

  /// Emits a single byte.
  void emit8(int value) => _buf.emit8(value);

  /// Emits a 16-bit value.
  void emit16(int value) => _buf.emit16(value);

  /// Emits a 32-bit value.
  void emit32(int value) => _buf.emit32(value);

  /// Emits a 64-bit value.
  void emit64(int value) => _buf.emit64(value);

  /// Aligns to [alignment] bytes with NOPs.
  void align(int alignment) => _buf.alignWithNops(alignment);

  // ===========================================================================
  // Basic instructions
  // ===========================================================================

  /// RET - Return from procedure.
  void ret() => _enc.ret();

  /// RET imm16 - Return and pop bytes from stack.
  void retImm(int imm16) => _enc.retImm(imm16);

  /// NOP - No operation.
  void nop() => _enc.nop();

  /// Multi-byte NOP.
  void nopN(int bytes) => _enc.nopN(bytes);

  /// INT3 - Breakpoint.
  void int3() => _enc.int3();

  /// INT n - Software interrupt.
  void intN(int n) => _enc.intN(n);

  // ===========================================================================
  // MOV instructions
  // ===========================================================================

  /// MOV dst, src (register to register).
  void movRR(X86Gp dst, X86Gp src) {
    if (dst.bits == 64 || src.bits == 64) {
      _enc.movR64R64(dst, src);
    } else {
      _enc.movR32R32(dst, src);
    }
  }

  /// MOV r64, imm64.
  void movRI64(X86Gp dst, int imm) {
    // Optimize: if immediate fits in 32 bits, use shorter encoding
    if (imm >= 0 && imm <= 0xFFFFFFFF) {
      _enc.movR32Imm32(dst.r32, imm);
    } else if (imm >= -2147483648 && imm <= 2147483647) {
      _enc.movR64Imm32(dst, imm);
    } else {
      _enc.movR64Imm64(dst, imm);
    }
  }

  /// MOV r32, imm32.
  void movRI32(X86Gp dst, int imm) {
    _enc.movR32Imm32(dst.r32, imm);
  }

  /// MOV r64, [mem].
  void movRM(X86Gp dst, X86Mem mem) {
    _enc.movR64Mem(dst, mem);
  }

  /// MOV [mem], r64.
  void movMR(X86Mem mem, X86Gp src) {
    _enc.movMemR64(mem, src);
  }

  // ===========================================================================
  // Arithmetic instructions
  // ===========================================================================

  /// ADD dst, src (register to register).
  void addRR(X86Gp dst, X86Gp src) {
    if (dst.bits == 64 || src.bits == 64) {
      _enc.addR64R64(dst, src);
    } else {
      _enc.addR32R32(dst, src);
    }
  }

  /// ADD r64, imm.
  void addRI(X86Gp dst, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.addR64Imm8(dst, imm);
    } else {
      _enc.addR64Imm32(dst, imm);
    }
  }

  /// SUB dst, src.
  void subRR(X86Gp dst, X86Gp src) {
    _enc.subR64R64(dst, src);
  }

  /// SUB r64, imm.
  void subRI(X86Gp dst, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.subR64Imm8(dst, imm);
    } else {
      _enc.subR64Imm32(dst, imm);
    }
  }

  /// IMUL dst, src.
  void imulRR(X86Gp dst, X86Gp src) {
    _enc.imulR64R64(dst, src);
  }

  /// XOR dst, src.
  void xorRR(X86Gp dst, X86Gp src) {
    _enc.xorR64R64(dst, src);
  }

  /// AND dst, src.
  void andRR(X86Gp dst, X86Gp src) {
    _enc.andR64R64(dst, src);
  }

  /// OR dst, src.
  void orRR(X86Gp dst, X86Gp src) {
    _enc.orR64R64(dst, src);
  }

  /// CMP dst, src.
  void cmpRR(X86Gp dst, X86Gp src) {
    _enc.cmpR64R64(dst, src);
  }

  /// CMP r64, imm32.
  void cmpRI(X86Gp dst, int imm) {
    _enc.cmpR64Imm32(dst, imm);
  }

  /// TEST dst, src.
  void testRR(X86Gp dst, X86Gp src) {
    _enc.testR64R64(dst, src);
  }

  // ===========================================================================
  // Stack instructions
  // ===========================================================================

  /// PUSH r64.
  void push(X86Gp reg) => _enc.pushR64(reg);

  /// POP r64.
  void pop(X86Gp reg) => _enc.popR64(reg);

  /// PUSH imm8.
  void pushImm8(int imm) => _enc.pushImm8(imm);

  /// PUSH imm32.
  void pushImm32(int imm) => _enc.pushImm32(imm);

  // ===========================================================================
  // Control flow instructions
  // ===========================================================================

  /// JMP to label.
  void jmp(Label target) {
    final placeholderOffset = _enc.jmpRel32Placeholder();
    code.addRel32(target, placeholderOffset);
  }

  /// JMP rel32 (direct displacement).
  void jmpRel(int disp) {
    _enc.jmpRel32(disp);
  }

  /// JMP r64.
  void jmpR(X86Gp reg) {
    _enc.jmpR64(reg);
  }

  /// CALL to label.
  void call(Label target) {
    final placeholderOffset = _enc.callRel32Placeholder();
    code.addRel32(target, placeholderOffset);
  }

  /// CALL rel32 (direct displacement).
  void callRel(int disp) {
    _enc.callRel32(disp);
  }

  /// CALL r64.
  void callR(X86Gp reg) {
    _enc.callR64(reg);
  }

  // ===========================================================================
  // Conditional jumps
  // ===========================================================================

  /// Jcc to label.
  void jcc(X86Cond cond, Label target) {
    final placeholderOffset = _enc.jccRel32Placeholder(cond);
    code.addRel32(target, placeholderOffset);
  }

  /// JE/JZ - Jump if equal/zero.
  void je(Label target) => jcc(X86Cond.e, target);
  void jz(Label target) => jcc(X86Cond.e, target);

  /// JNE/JNZ - Jump if not equal/not zero.
  void jne(Label target) => jcc(X86Cond.ne, target);
  void jnz(Label target) => jcc(X86Cond.ne, target);

  /// JL - Jump if less (signed).
  void jl(Label target) => jcc(X86Cond.l, target);

  /// JLE - Jump if less or equal (signed).
  void jle(Label target) => jcc(X86Cond.le, target);

  /// JG - Jump if greater (signed).
  void jg(Label target) => jcc(X86Cond.g, target);

  /// JGE - Jump if greater or equal (signed).
  void jge(Label target) => jcc(X86Cond.ge, target);

  /// JB - Jump if below (unsigned).
  void jb(Label target) => jcc(X86Cond.b, target);

  /// JBE - Jump if below or equal (unsigned).
  void jbe(Label target) => jcc(X86Cond.be, target);

  /// JA - Jump if above (unsigned).
  void ja(Label target) => jcc(X86Cond.a, target);

  /// JAE - Jump if above or equal (unsigned).
  void jae(Label target) => jcc(X86Cond.ae, target);

  // ===========================================================================
  // LEA instruction
  // ===========================================================================

  /// LEA r64, [mem].
  void lea(X86Gp dst, X86Mem mem) {
    _enc.leaR64Mem(dst, mem);
  }

  // ===========================================================================
  // Prologue/Epilogue helpers
  // ===========================================================================

  /// Emits a standard function prologue.
  ///
  /// ```asm
  /// push rbp
  /// mov rbp, rsp
  /// sub rsp, stackSize  ; if stackSize > 0
  /// ```
  void emitPrologue({int stackSize = 0}) {
    push(rbp);
    movRR(rbp, rsp);
    if (stackSize > 0) {
      // Align stack size to 16 bytes
      stackSize = (stackSize + 15) & ~15;
      subRI(rsp, stackSize);
    }
  }

  /// Emits a standard function epilogue.
  ///
  /// ```asm
  /// mov rsp, rbp  ; or leave
  /// pop rbp
  /// ret
  /// ```
  void emitEpilogue() {
    movRR(rsp, rbp);
    pop(rbp);
    ret();
  }

  /// Emits LEAVE instruction (equivalent to mov rsp, rbp; pop rbp).
  void leave() {
    _buf.emit8(0xC9);
  }

  // ===========================================================================
  // ABI helpers
  // ===========================================================================

  /// Gets the argument register for the given argument index.
  X86Gp getArgReg(int index) {
    if (callingConvention == CallingConvention.win64) {
      const regs = [rcx, rdx, r8, r9];
      if (index >= regs.length) {
        throw ArgumentError('Win64 only has ${regs.length} register arguments');
      }
      return regs[index];
    } else {
      // System V AMD64
      const regs = [rdi, rsi, rdx, rcx, r8, r9];
      if (index >= regs.length) {
        throw ArgumentError('SysV only has ${regs.length} register arguments');
      }
      return regs[index];
    }
  }

  /// Gets the return value register.
  X86Gp get retReg => rax;

  /// Gets callee-saved registers for the current ABI.
  List<X86Gp> get calleeSavedRegs {
    if (callingConvention == CallingConvention.win64) {
      return win64CalleeSaved;
    } else {
      return sysVCalleeSaved;
    }
  }

  // ===========================================================================
  // Inline bytes API
  // ===========================================================================

  /// Emits inline bytes (for raw shellcode).
  void emitInline(List<int> bytes) {
    _buf.emitBytes(bytes);
  }

  // ===========================================================================
  // Unary instructions
  // ===========================================================================

  /// INC reg.
  void inc(X86Gp reg) {
    if (reg.bits == 64) {
      _enc.incR64(reg);
    } else {
      _enc.incR32(reg.r32);
    }
  }

  /// DEC reg.
  void dec(X86Gp reg) {
    if (reg.bits == 64) {
      _enc.decR64(reg);
    } else {
      _enc.decR32(reg.r32);
    }
  }

  /// NEG reg (two's complement negation).
  void neg(X86Gp reg) {
    _enc.negR64(reg);
  }

  /// NOT reg (one's complement).
  void not(X86Gp reg) {
    _enc.notR64(reg);
  }

  // ===========================================================================
  // Shift instructions
  // ===========================================================================

  /// SHL reg, imm (left shift).
  void shlRI(X86Gp reg, int imm) {
    _enc.shlR64Imm8(reg, imm);
  }

  /// SHL reg, CL (left shift by CL).
  void shlRCl(X86Gp reg) {
    _enc.shlR64Cl(reg);
  }

  /// SHR reg, imm (logical right shift).
  void shrRI(X86Gp reg, int imm) {
    _enc.shrR64Imm8(reg, imm);
  }

  /// SHR reg, CL (logical right shift by CL).
  void shrRCl(X86Gp reg) {
    _enc.shrR64Cl(reg);
  }

  /// SAR reg, imm (arithmetic right shift).
  void sarRI(X86Gp reg, int imm) {
    _enc.sarR64Imm8(reg, imm);
  }

  /// SAR reg, CL (arithmetic right shift by CL).
  void sarRCl(X86Gp reg) {
    _enc.sarR64Cl(reg);
  }

  /// ROL reg, imm (rotate left).
  void rolRI(X86Gp reg, int imm) {
    _enc.rolR64Imm8(reg, imm);
  }

  /// ROR reg, imm (rotate right).
  void rorRI(X86Gp reg, int imm) {
    _enc.rorR64Imm8(reg, imm);
  }

  // ===========================================================================
  // Exchange instruction
  // ===========================================================================

  /// XCHG a, b (exchange values).
  void xchg(X86Gp a, X86Gp b) {
    _enc.xchgR64R64(a, b);
  }

  // ===========================================================================
  // Conditional move (CMOVcc)
  // ===========================================================================

  /// CMOVcc dst, src (conditional move).
  void cmovcc(X86Cond cond, X86Gp dst, X86Gp src) {
    _enc.cmovccR64R64(cond, dst, src);
  }

  /// CMOVE dst, src (move if equal).
  void cmove(X86Gp dst, X86Gp src) => cmovcc(X86Cond.e, dst, src);
  void cmovz(X86Gp dst, X86Gp src) => cmovcc(X86Cond.e, dst, src);

  /// CMOVNE dst, src (move if not equal).
  void cmovne(X86Gp dst, X86Gp src) => cmovcc(X86Cond.ne, dst, src);
  void cmovnz(X86Gp dst, X86Gp src) => cmovcc(X86Cond.ne, dst, src);

  /// CMOVL dst, src (move if less, signed).
  void cmovl(X86Gp dst, X86Gp src) => cmovcc(X86Cond.l, dst, src);

  /// CMOVG dst, src (move if greater, signed).
  void cmovg(X86Gp dst, X86Gp src) => cmovcc(X86Cond.g, dst, src);

  /// CMOVLE dst, src (move if less or equal, signed).
  void cmovle(X86Gp dst, X86Gp src) => cmovcc(X86Cond.le, dst, src);

  /// CMOVGE dst, src (move if greater or equal, signed).
  void cmovge(X86Gp dst, X86Gp src) => cmovcc(X86Cond.ge, dst, src);

  /// CMOVB dst, src (move if below, unsigned).
  void cmovb(X86Gp dst, X86Gp src) => cmovcc(X86Cond.b, dst, src);

  /// CMOVA dst, src (move if above, unsigned).
  void cmova(X86Gp dst, X86Gp src) => cmovcc(X86Cond.a, dst, src);

  // ===========================================================================
  // Set byte on condition (SETcc)
  // ===========================================================================

  /// SETcc reg (set byte based on condition).
  void setcc(X86Cond cond, X86Gp reg) {
    _enc.setccR8(cond, reg.r8);
  }

  /// SETE reg (set if equal).
  void sete(X86Gp reg) => setcc(X86Cond.e, reg);

  /// SETNE reg (set if not equal).
  void setne(X86Gp reg) => setcc(X86Cond.ne, reg);

  /// SETL reg (set if less, signed).
  void setl(X86Gp reg) => setcc(X86Cond.l, reg);

  /// SETG reg (set if greater, signed).
  void setg(X86Gp reg) => setcc(X86Cond.g, reg);

  // ===========================================================================
  // Move with extension
  // ===========================================================================

  /// MOVZX dst, src (zero-extend byte to qword).
  void movzxB(X86Gp dst, X86Gp src) {
    _enc.movzxR64R8(dst, src);
  }

  /// MOVZX dst, src (zero-extend word to qword).
  void movzxW(X86Gp dst, X86Gp src) {
    _enc.movzxR64R16(dst, src);
  }

  /// MOVSXD dst, src (sign-extend dword to qword).
  void movsxd(X86Gp dst, X86Gp src) {
    _enc.movsxdR64R32(dst, src);
  }

  // ===========================================================================
  // Bit manipulation
  // ===========================================================================

  /// BSF dst, src (bit scan forward).
  void bsf(X86Gp dst, X86Gp src) {
    _enc.bsfR64R64(dst, src);
  }

  /// BSR dst, src (bit scan reverse).
  void bsr(X86Gp dst, X86Gp src) {
    _enc.bsrR64R64(dst, src);
  }

  /// POPCNT dst, src (population count).
  void popcnt(X86Gp dst, X86Gp src) {
    _enc.popcntR64R64(dst, src);
  }

  /// LZCNT dst, src (leading zero count).
  void lzcnt(X86Gp dst, X86Gp src) {
    _enc.lzcntR64R64(dst, src);
  }

  /// TZCNT dst, src (trailing zero count).
  void tzcnt(X86Gp dst, X86Gp src) {
    _enc.tzcntR64R64(dst, src);
  }

  // ===========================================================================
  // Division
  // ===========================================================================

  /// CDQ - Sign-extend EAX into EDX:EAX
  void cdq() => _enc.cdq();

  /// CQO - Sign-extend RAX into RDX:RAX
  void cqo() => _enc.cqo();

  /// IDIV reg - Signed divide RDX:RAX by reg
  /// Result: quotient in RAX, remainder in RDX
  void idiv(X86Gp reg) {
    _enc.idivR64(reg);
  }

  /// DIV reg - Unsigned divide RDX:RAX by reg
  /// Result: quotient in RAX, remainder in RDX
  void div(X86Gp reg) {
    _enc.divR64(reg);
  }

  // ===========================================================================
  // High-precision arithmetic (for cryptography)
  // ===========================================================================

  /// ADC dst, src - Add with carry
  void adcRR(X86Gp dst, X86Gp src) {
    _enc.adcR64R64(dst, src);
  }

  /// ADC dst, imm - Add with carry
  void adcRI(X86Gp dst, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.adcR64Imm8(dst, imm);
    } else {
      _enc.adcR64Imm32(dst, imm);
    }
  }

  /// SBB dst, src - Subtract with borrow
  void sbbRR(X86Gp dst, X86Gp src) {
    _enc.sbbR64R64(dst, src);
  }

  /// SBB dst, imm - Subtract with borrow
  void sbbRI(X86Gp dst, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.sbbR64Imm8(dst, imm);
    } else {
      _enc.sbbR64Imm32(dst, imm);
    }
  }

  /// MUL src - Unsigned multiply RDX:RAX = RAX * src
  void mul(X86Gp src) {
    _enc.mulR64(src);
  }

  /// MULX hi, lo, src (BMI2) - Unsigned multiply without flags
  void mulx(X86Gp hi, X86Gp lo, X86Gp src) {
    _enc.mulxR64R64R64(hi, lo, src);
  }

  /// ADCX dst, src (ADX) - Add with carry (uses CF only)
  void adcx(X86Gp dst, X86Gp src) {
    _enc.adcxR64R64(dst, src);
  }

  /// ADOX dst, src (ADX) - Add with overflow (uses OF only)
  void adox(X86Gp dst, X86Gp src) {
    _enc.adoxR64R64(dst, src);
  }

  // ===========================================================================
  // Flag manipulation
  // ===========================================================================

  /// CLC - Clear carry flag
  void clc() => _enc.clc();

  /// STC - Set carry flag
  void stc() => _enc.stc();

  /// CMC - Complement carry flag
  void cmc() => _enc.cmc();

  /// CLD - Clear direction flag
  void cld() => _enc.cld();

  /// STD - Set direction flag (use with caution)
  void std() => _enc.std();

  // ===========================================================================
  // String operations
  // ===========================================================================

  /// REP MOVSB - Copy RCX bytes from [RSI] to [RDI]
  void repMovsb() => _enc.repMovsb();

  /// REP MOVSQ - Copy RCX qwords from [RSI] to [RDI]
  void repMovsq() => _enc.repMovsq();

  /// REP STOSB - Store AL to RCX bytes at [RDI]
  void repStosb() => _enc.repStosb();

  /// REP STOSQ - Store RAX to RCX qwords at [RDI]
  void repStosq() => _enc.repStosq();

  // ===========================================================================
  // Memory fences
  // ===========================================================================

  /// MFENCE - Full memory fence
  void mfence() => _enc.mfence();

  /// SFENCE - Store fence
  void sfence() => _enc.sfence();

  /// LFENCE - Load fence
  void lfence() => _enc.lfence();

  /// PAUSE - Spin loop hint
  void pause() => _enc.pause();
}
