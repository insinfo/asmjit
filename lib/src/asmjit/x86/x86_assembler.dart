/// AsmJit x86/x64 Assembler
///
/// High-level x86/x64 instruction emission API.
/// Ported from asmjit/x86/x86assembler.h

import '../core/code_holder.dart';
import '../core/code_buffer.dart';
import '../core/labels.dart';
import '../core/environment.dart';
import '../core/arch.dart';
import 'x86.dart';
import 'x86_operands.dart';
import 'x86_encoder.dart';
import 'x86_simd.dart';
import 'x86_dispatcher.g.dart';

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

  /// Emits a raw instruction by ID with generic operands.
  void emit(int instId, List<Object> ops) {
    x86Dispatch(this, instId, ops);
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

  /// MOV reg, imm (convenience method - auto-selects size).
  void movRI(X86Gp dst, int imm) {
    if (dst.bits == 64) {
      movRI64(dst, imm);
    } else {
      movRI32(dst, imm);
    }
  }

  /// MOV r64, [mem].
  void movRM(X86Gp dst, X86Mem mem) {
    _enc.movR64Mem(dst, mem);
  }

  /// MOV [mem], r64.
  void movMR(X86Mem mem, X86Gp src) {
    _enc.movMemR64(mem, src);
  }

  /// MOV [mem], imm.
  void movMI(X86Mem mem, int imm) {
    _enc.movMemImm32(mem, imm);
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

  /// ADD r64, [mem].
  void addRM(X86Gp dst, X86Mem mem) => _enc.addR64Mem(dst, mem);

  /// SUB r64, [mem].
  void subRM(X86Gp dst, X86Mem mem) => _enc.subR64Mem(dst, mem);

  /// AND r64, [mem].
  void andRM(X86Gp dst, X86Mem mem) => _enc.andR64Mem(dst, mem);

  /// OR r64, [mem].
  void orRM(X86Gp dst, X86Mem mem) => _enc.orR64Mem(dst, mem);

  /// XOR r64, [mem].
  void xorRM(X86Gp dst, X86Mem mem) => _enc.xorR64Mem(dst, mem);

  /// CMP r64, [mem].
  void cmpRM(X86Gp dst, X86Mem mem) => _enc.cmpR64Mem(dst, mem);

  /// TEST r64, [mem].
  void testRM(X86Gp dst, X86Mem mem) => _enc.testR64Mem(dst, mem);

  /// IMUL dst, src.
  void imulRR(X86Gp dst, X86Gp src) {
    _enc.imulR64R64(dst, src);
  }

  /// IMUL dst, src, imm (three-operand form).
  void imulRRI(X86Gp dst, X86Gp src, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.imulR64R64Imm8(dst, src, imm);
    } else {
      _enc.imulR64R64Imm32(dst, src, imm);
    }
  }

  /// IMUL dst, imm (dst = dst * imm).
  void imulRI(X86Gp dst, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.imulR64Imm8(dst, imm);
    } else {
      _enc.imulR64Imm32(dst, imm);
    }
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

  /// TEST r64, imm32.
  void testRI(X86Gp dst, int imm) {
    _enc.testR64Imm32(dst, imm);
  }

  /// AND r64, imm.
  void andRI(X86Gp dst, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.andR64Imm8(dst, imm);
    } else {
      _enc.andR64Imm32(dst, imm);
    }
  }

  /// OR r64, imm.
  void orRI(X86Gp dst, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.orR64Imm8(dst, imm);
    } else {
      _enc.orR64Imm32(dst, imm);
    }
  }

  /// XOR r64, imm.
  void xorRI(X86Gp dst, int imm) {
    if (imm >= -128 && imm <= 127) {
      _enc.xorR64Imm8(dst, imm);
    } else {
      _enc.xorR64Imm32(dst, imm);
    }
  }

  /// MOVSX r64, r8 (sign-extend byte).
  void movsxB(X86Gp dst, X86Gp src) {
    _enc.movsxR64R8(dst, src);
  }

  /// MOVSX r64, r16 (sign-extend word).
  void movsxW(X86Gp dst, X86Gp src) {
    _enc.movsxR64R16(dst, src);
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
  ///
  /// For backward jumps (to already bound labels), automatically uses
  /// short jump (rel8) if the distance is within range (-128 to 127).
  /// For forward jumps, uses near jump (rel32).
  void jmp(Label target, {bool forceShort = false}) {
    final targetOffset = code.getLabelOffset(target);

    if (targetOffset != null) {
      // Backward jump - label is already bound
      // Calculate distance from end of instruction
      final currentPos = _enc.buffer.length;

      // For rel8: instruction is 2 bytes (EB xx)
      // For rel32: instruction is 5 bytes (E9 xx xx xx xx)
      // disp = target - (current + instruction_size)
      final dispShort = targetOffset - (currentPos + 2);

      if (dispShort >= -128 && dispShort <= 127) {
        // Use short jump
        _enc.jmpRel8(dispShort);
      } else {
        // Use near jump
        final dispNear = targetOffset - (currentPos + 5);
        _enc.jmpRel32(dispNear);
      }
    } else {
      // Forward jump - use placeholder and patch later
      if (forceShort) {
        // Emit short jump with placeholder (will be patched)
        final placeholderOffset = _enc.buffer.length + 1; // offset of disp8
        _enc.jmpRel8(0);
        code.addRel8(target, placeholderOffset);
      } else {
        final placeholderOffset = _enc.jmpRel32Placeholder();
        code.addRel32(target, placeholderOffset);
      }
    }
  }

  /// JMP rel32 (direct displacement).
  void jmpRel(int disp) {
    _enc.jmpRel32(disp);
  }

  /// JMP rel8 (short jump, direct displacement).
  void jmpRelShort(int disp8) {
    _enc.jmpRel8(disp8);
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
  ///
  /// For backward jumps, automatically uses short jump (rel8) if possible.
  /// For forward jumps, uses near jump (rel32).
  void jcc(X86Cond cond, Label target, {bool forceShort = false}) {
    final targetOffset = code.getLabelOffset(target);

    if (targetOffset != null) {
      // Backward jump - label is already bound
      final currentPos = _enc.buffer.length;

      // For rel8: instruction is 2 bytes (7x xx)
      // For rel32: instruction is 6 bytes (0F 8x xx xx xx xx)
      final dispShort = targetOffset - (currentPos + 2);

      if (dispShort >= -128 && dispShort <= 127) {
        // Use short conditional jump
        _enc.jccRel8(cond, dispShort);
      } else {
        // Use near conditional jump
        final dispNear = targetOffset - (currentPos + 6);
        _enc.jccRel32(cond, dispNear);
      }
    } else {
      // Forward jump - use placeholder
      if (forceShort) {
        final placeholderOffset = _enc.buffer.length + 1;
        _enc.jccRel8(cond, 0);
        code.addRel8(target, placeholderOffset);
      } else {
        final placeholderOffset = _enc.jccRel32Placeholder(cond);
        code.addRel32(target, placeholderOffset);
      }
    }
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

  /// Jcc rel32 (direct displacement).
  void jccRel(X86Cond cond, int disp) {
    _enc.jccRel32(cond, disp);
  }

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

  // ===========================================================================
  // SSE/SSE2 - Move instructions
  // ===========================================================================

  /// MOVAPS xmm, xmm (move aligned packed single-precision)
  void movapsXX(X86Xmm dst, X86Xmm src) => _enc.movapsXmmXmm(dst, src);

  /// MOVUPS xmm, xmm (move unaligned packed single-precision)
  void movupsXX(X86Xmm dst, X86Xmm src) => _enc.movupsXmmXmm(dst, src);

  /// MOVUPS xmm, [mem]
  void movupsXM(X86Xmm dst, X86Mem mem) => _enc.movupsXmmMem(dst, mem);

  /// MOVUPS [mem], xmm
  void movupsMX(X86Mem mem, X86Xmm src) => _enc.movupsMemXmm(mem, src);

  /// MOVAPS xmm, [mem]
  void movapsXM(X86Xmm dst, X86Mem mem) => _enc.movapsXmmMem(dst, mem);

  /// MOVAPS [mem], xmm
  void movapsMX(X86Mem mem, X86Xmm src) => _enc.movapsMemXmm(mem, src);

  /// MOVD xmm, [mem]
  void movdXM(X86Xmm dst, X86Mem mem) => _enc.movdXmmMem(dst, mem);

  /// MOVD [mem], xmm
  void movdMX(X86Mem mem, X86Xmm src) => _enc.movdMemXmm(mem, src);

  /// MOVSD xmm, xmm (move scalar double-precision)
  void movsdXX(X86Xmm dst, X86Xmm src) => _enc.movsdXmmXmm(dst, src);

  /// MOVSD xmm, [mem]
  void movsdXM(X86Xmm dst, X86Mem mem) => _enc.movsdXmmMem(dst, mem);

  /// MOVSD [mem], xmm
  void movsdMX(X86Mem mem, X86Xmm src) => _enc.movsdMemXmm(mem, src);

  /// MOVSS xmm, xmm (move scalar single-precision)
  void movssXX(X86Xmm dst, X86Xmm src) => _enc.movssXmmXmm(dst, src);

  /// MOVSS xmm, [mem]
  void movssXM(X86Xmm dst, X86Mem mem) => _enc.movssXmmMem(dst, mem);

  /// MOVSS [mem], xmm
  void movssMX(X86Mem mem, X86Xmm src) => _enc.movssMemXmm(mem, src);

  // ===========================================================================
  // SSE/SSE2 - Arithmetic (scalar double)
  // ===========================================================================

  /// ADDSD xmm, xmm (add scalar double)
  void addsdXX(X86Xmm dst, X86Xmm src) => _enc.addsdXmmXmm(dst, src);

  /// SUBSD xmm, xmm (subtract scalar double)
  void subsdXX(X86Xmm dst, X86Xmm src) => _enc.subsdXmmXmm(dst, src);

  /// MULSD xmm, xmm (multiply scalar double)
  void mulsdXX(X86Xmm dst, X86Xmm src) => _enc.mulsdXmmXmm(dst, src);

  /// DIVSD xmm, xmm (divide scalar double)
  void divsdXX(X86Xmm dst, X86Xmm src) => _enc.divsdXmmXmm(dst, src);

  /// SQRTSD xmm, xmm (square root scalar double)
  void sqrtsdXX(X86Xmm dst, X86Xmm src) => _enc.sqrtsdXmmXmm(dst, src);

  // ===========================================================================
  // SSE/SSE2 - Arithmetic (scalar single)
  // ===========================================================================

  /// ADDSS xmm, xmm (add scalar single)
  void addssXX(X86Xmm dst, X86Xmm src) => _enc.addssXmmXmm(dst, src);

  /// SUBSS xmm, xmm (subtract scalar single)
  void subssXX(X86Xmm dst, X86Xmm src) => _enc.subssXmmXmm(dst, src);

  /// MULSS xmm, xmm (multiply scalar single)
  void mulssXX(X86Xmm dst, X86Xmm src) => _enc.mulssXmmXmm(dst, src);

  /// DIVSS xmm, xmm (divide scalar single)
  void divssXX(X86Xmm dst, X86Xmm src) => _enc.divssXmmXmm(dst, src);

  /// SQRTSS xmm, xmm (square root scalar single)
  void sqrtssXX(X86Xmm dst, X86Xmm src) => _enc.sqrtssXmmXmm(dst, src);

  // ===========================================================================
  // SSE/SSE2 - Packed single-precision arithmetic
  // ===========================================================================

  /// ADDPS xmm, xmm (add packed single)
  void addps(X86Xmm dst, X86Xmm src) => _enc.addpsXmmXmm(dst, src);

  /// ADDPS xmm, [mem]
  void addpsXM(X86Xmm dst, X86Mem mem) => _enc.addpsXmmMem(dst, mem);

  /// SUBPS xmm, xmm (subtract packed single)
  void subps(X86Xmm dst, X86Xmm src) => _enc.subpsXmmXmm(dst, src);

  /// SUBPS xmm, [mem]
  void subpsXM(X86Xmm dst, X86Mem mem) => _enc.subpsXmmMem(dst, mem);

  /// MULPS xmm, xmm (multiply packed single)
  void mulps(X86Xmm dst, X86Xmm src) => _enc.mulpsXmmXmm(dst, src);

  /// MULPS xmm, [mem]
  void mulpsXM(X86Xmm dst, X86Mem mem) => _enc.mulpsXmmMem(dst, mem);

  /// DIVPS xmm, xmm (divide packed single)
  void divps(X86Xmm dst, X86Xmm src) => _enc.divpsXmmXmm(dst, src);

  /// DIVPS xmm, [mem]
  void divpsXM(X86Xmm dst, X86Mem mem) => _enc.divpsXmmMem(dst, mem);

  /// ADDPD xmm, xmm (add packed double)
  void addpd(X86Xmm dst, X86Xmm src) => _enc.addpdXmmXmm(dst, src);
  void addpdXM(X86Xmm dst, X86Mem mem) => _enc.addpdXmmMem(dst, mem);

  /// SUBPD xmm, xmm (subtract packed double)
  void subpd(X86Xmm dst, X86Xmm src) => _enc.subpdXmmXmm(dst, src);
  void subpdXM(X86Xmm dst, X86Mem mem) => _enc.subpdXmmMem(dst, mem);

  /// MULPD xmm, xmm (multiply packed double)
  void mulpd(X86Xmm dst, X86Xmm src) => _enc.mulpdXmmXmm(dst, src);
  void mulpdXM(X86Xmm dst, X86Mem mem) => _enc.mulpdXmmMem(dst, mem);

  /// DIVPD xmm, xmm (divide packed double)
  void divpd(X86Xmm dst, X86Xmm src) => _enc.divpdXmmXmm(dst, src);
  void divpdXM(X86Xmm dst, X86Mem mem) => _enc.divpdXmmMem(dst, mem);

  /// MINPS xmm, xmm (minimum packed single)
  void minps(X86Xmm dst, X86Xmm src) => _enc.minpsXmmXmm(dst, src);

  /// MAXPS xmm, xmm (maximum packed single)
  void maxps(X86Xmm dst, X86Xmm src) => _enc.maxpsXmmXmm(dst, src);

  // ===========================================================================
  // SSE/SSE2 - Logical (convenience aliases)
  // ===========================================================================

  /// XORPS xmm, xmm (XOR packed single) - also used to zero registers
  void xorps(X86Xmm dst, X86Xmm src) => _enc.xorpsXmmXmm(dst, src);

  // ===========================================================================
  // SSE/SSE2 - Logical
  // ===========================================================================

  /// PXOR xmm, xmm (packed XOR, zero register: pxor xmm, xmm)
  void pxor(X86Xmm dst, X86Xmm src) => _enc.pxorXmmXmm(dst, src);
  void pxorXX(X86Xmm dst, X86Xmm src) => _enc.pxorXmmXmm(dst, src);

  /// PXOR xmm, [mem]
  void pxorXM(X86Xmm dst, X86Mem mem) => _enc.pxorXmmMem(dst, mem);

  /// XORPS xmm, xmm (XOR packed single)
  void xorpsXX(X86Xmm dst, X86Xmm src) => _enc.xorpsXmmXmm(dst, src);

  /// XORPS xmm, [mem]
  void xorpsXM(X86Xmm dst, X86Mem mem) => _enc.xorpsXmmMem(dst, mem);

  /// XORPD xmm, xmm (XOR packed double)
  void xorpd(X86Xmm dst, X86Xmm src) => _enc.xorpdXmmXmm(dst, src);
  void xorpdXX(X86Xmm dst, X86Xmm src) => _enc.xorpdXmmXmm(dst, src);

  /// XORPD xmm, [mem]
  void xorpdXM(X86Xmm dst, X86Mem mem) => _enc.xorpdXmmMem(dst, mem);

  // ===========================================================================
  // SSE/SSE2 - Conversion
  // ===========================================================================

  /// CVTSI2SD xmm, r64 (convert int64 to double)
  void cvtsi2sdXR(X86Xmm dst, X86Gp src) => _enc.cvtsi2sdXmmR64(dst, src);

  /// CVTSI2SS xmm, r64 (convert int64 to float)
  void cvtsi2ssXR(X86Xmm dst, X86Gp src) => _enc.cvtsi2ssXmmR64(dst, src);

  /// CVTTSD2SI r64, xmm (convert double to int64 with truncation)
  void cvttsd2siRX(X86Gp dst, X86Xmm src) => _enc.cvttsd2siR64Xmm(dst, src);

  /// CVTTSS2SI r64, xmm (convert float to int64 with truncation)
  void cvttss2siRX(X86Gp dst, X86Xmm src) => _enc.cvttss2siR64Xmm(dst, src);

  /// CVTSD2SS xmm, xmm (convert double to float)
  void cvtsd2ssXX(X86Xmm dst, X86Xmm src) => _enc.cvtsd2ssXmmXmm(dst, src);

  /// CVTSS2SD xmm, xmm (convert float to double)
  void cvtss2sdXX(X86Xmm dst, X86Xmm src) => _enc.cvtss2sdXmmXmm(dst, src);

  // ===========================================================================
  // SSE/SSE2 - Comparison
  // ===========================================================================

  /// COMISD xmm, xmm (ordered compare double, set EFLAGS)
  void comisdXX(X86Xmm a, X86Xmm b) => _enc.comisdXmmXmm(a, b);

  /// COMISS xmm, xmm (ordered compare single, set EFLAGS)
  void comissXX(X86Xmm a, X86Xmm b) => _enc.comissXmmXmm(a, b);

  /// UCOMISD xmm, xmm (unordered compare double, set EFLAGS)
  void ucomisdXX(X86Xmm a, X86Xmm b) => _enc.ucomisdXmmXmm(a, b);

  /// UCOMISS xmm, xmm (unordered compare single, set EFLAGS)
  void ucomissXX(X86Xmm a, X86Xmm b) => _enc.ucomissXmmXmm(a, b);

  // ===========================================================================
  // SSE/SSE2 - GP <-> XMM Transfer
  // ===========================================================================

  /// MOVQ xmm, r64 (move quadword from GP to XMM)
  void movqXR(X86Xmm dst, X86Gp src) => _enc.movqXmmR64(dst, src);

  /// MOVQ r64, xmm (move quadword from XMM to GP)
  void movqRX(X86Gp dst, X86Xmm src) => _enc.movqR64Xmm(dst, src);

  /// MOVD xmm, r32 (move doubleword from GP to XMM)
  void movdXR(X86Xmm dst, X86Gp src) => _enc.movdXmmR32(dst, src);

  /// MOVD r32, xmm (move doubleword from XMM to GP)
  void movdRX(X86Gp dst, X86Xmm src) => _enc.movdR32Xmm(dst, src);

  // ===========================================================================
  // AVX - Move instructions (VEX-encoded)
  // ===========================================================================

  /// VMOVAPS xmm, xmm (VEX move aligned packed single 128-bit)
  void vmovapsXX(X86Xmm dst, X86Xmm src) => _enc.vmovapsXmmXmm(dst, src);

  /// VMOVAPS ymm, ymm (VEX move aligned packed single 256-bit)
  void vmovapsYY(X86Ymm dst, X86Ymm src) => _enc.vmovapsYmmYmm(dst, src);

  /// VMOVUPS xmm, xmm (VEX move unaligned packed single 128-bit)
  void vmovupsXX(X86Xmm dst, X86Xmm src) => _enc.vmovupsXmmXmm(dst, src);

  /// VMOVUPS ymm, ymm (VEX move unaligned packed single 256-bit)
  void vmovupsYY(X86Ymm dst, X86Ymm src) => _enc.vmovupsYmmYmm(dst, src);

  // ===========================================================================
  // AVX - Scalar arithmetic (VEX-encoded)
  // ===========================================================================

  /// VADDSD xmm, xmm, xmm (VEX add scalar double)
  void vaddsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vaddsdXmmXmmXmm(dst, src1, src2);

  /// VSUBSD xmm, xmm, xmm (VEX subtract scalar double)
  void vsubsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vsubsdXmmXmmXmm(dst, src1, src2);

  /// VMULSD xmm, xmm, xmm (VEX multiply scalar double)
  void vmulsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vmulsdXmmXmmXmm(dst, src1, src2);

  /// VDIVSD xmm, xmm, xmm (VEX divide scalar double)
  void vdivsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vdivsdXmmXmmXmm(dst, src1, src2);

  // ===========================================================================
  // AVX - Packed arithmetic 128-bit (VEX-encoded)
  // ===========================================================================

  /// VADDPS xmm, xmm, xmm (VEX add packed single 128-bit)
  void vaddpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vaddpsXmmXmmXmm(dst, src1, src2);

  /// VADDPS xmm, xmm, [mem]
  void vaddpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vaddpsXmmXmmMem(dst, src1, mem);

  void vaddpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vaddpdXmmXmmXmm(dst, src1, src2);

  /// VADDPD xmm, xmm, [mem]
  void vaddpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vaddpdXmmXmmMem(dst, src1, mem);

  /// VSUBPS xmm, xmm, xmm (VEX subtract packed single 128-bit)
  void vsubpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vsubpsXmmXmmXmm(dst, src1, src2);

  /// VMULPS xmm, xmm, xmm (VEX multiply packed single 128-bit)
  void vmulpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vmulpsXmmXmmXmm(dst, src1, src2);

  /// VMULPS xmm, xmm, [mem]
  void vmulpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vmulpsXmmXmmMem(dst, src1, mem);

  /// VMULPD xmm, xmm, xmm (VEX multiply packed double 128-bit)
  void vmulpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vmulpdXmmXmmXmm(dst, src1, src2);

  /// VSUBPS xmm, xmm, [mem]
  void vsubpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vsubpsXmmXmmMem(dst, src1, mem);

  /// VSUBPD xmm, xmm, xmm (VEX subtract packed double 128-bit)
  void vsubpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vsubpdXmmXmmXmm(dst, src1, src2);

  /// VSUBPD xmm, xmm, [mem]
  void vsubpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vsubpdXmmXmmMem(dst, src1, mem);

  // ===========================================================================
  // AVX - Packed arithmetic 256-bit (VEX-encoded)
  // ===========================================================================

  /// VADDPS ymm, ymm, ymm (VEX add packed single 256-bit)
  void vaddpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vaddpsYmmYmmYmm(dst, src1, src2);

  /// VADDPS ymm, ymm, [mem]
  void vaddpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vaddpsYmmYmmMem(dst, src1, mem);

  /// VMULPS ymm, ymm, ymm (VEX multiply packed single 256-bit)
  void vmulpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vmulpsYmmYmmYmm(dst, src1, src2);

  /// VMULPS ymm, ymm, [mem]
  void vmulpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vmulpsYmmYmmMem(dst, src1, mem);

  /// VADDPD ymm, ymm, ymm (VEX add packed double 256-bit)
  void vaddpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vaddpdYmmYmmYmm(dst, src1, src2);

  /// VADDPD ymm, ymm, [mem]
  void vaddpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vaddpdYmmYmmMem(dst, src1, mem);

  /// VMULPD xmm, xmm, [mem]
  void vmulpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vmulpdXmmXmmMem(dst, src1, mem);

  /// VSUBPS ymm, ymm, ymm (VEX subtract packed single 256-bit)
  void vsubpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vsubpsYmmYmmYmm(dst, src1, src2);

  /// VSUBPS ymm, ymm, [mem]
  void vsubpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vsubpsYmmYmmMem(dst, src1, mem);

  /// VSUBPD ymm, ymm, ymm (VEX subtract packed double 256-bit)
  void vsubpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vsubpdYmmYmmYmm(dst, src1, src2);

  /// VSUBPD ymm, ymm, [mem]
  void vsubpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vsubpdYmmYmmMem(dst, src1, mem);

  /// VMULPD ymm, ymm, ymm (VEX multiply packed double 256-bit)
  void vmulpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vmulpdYmmYmmYmm(dst, src1, src2);

  /// VMULPD ymm, ymm, [mem]
  void vmulpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vmulpdYmmYmmMem(dst, src1, mem);

  // ===========================================================================
  // AVX - Logical (VEX-encoded)
  // ===========================================================================

  /// VXORPS xmm, xmm, xmm (VEX XOR packed single) - use for zeroing
  void vxorpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vxorpsXmmXmmXmm(dst, src1, src2);

  /// VXORPS xmm, xmm, [mem]
  void vxorpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vxorpsXmmXmmMem(dst, src1, mem);

  /// VXORPS ymm, ymm, ymm (VEX XOR packed single 256-bit) - use for zeroing
  void vxorpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vxorpsYmmYmmYmm(dst, src1, src2);

  /// VXORPS ymm, ymm, [mem]
  void vxorpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vxorpsYmmYmmMem(dst, src1, mem);

  /// VXORPD xmm, xmm, xmm (VEX XOR packed double)
  void vxorpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vxorpdXmmXmmXmm(dst, src1, src2);

  /// VXORPD ymm, ymm, ymm (VEX XOR packed double 256-bit)
  void vxorpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vxorpdYmmYmmYmm(dst, src1, src2);

  /// VXORPD xmm, xmm, [mem]
  void vxorpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vxorpdXmmXmmMem(dst, src1, mem);

  /// VXORPD ymm, ymm, [mem]
  void vxorpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vxorpdYmmYmmMem(dst, src1, mem);

  /// VPXOR xmm, xmm, xmm (VEX XOR packed integer)
  void vpxorXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vpxorXmmXmmXmm(dst, src1, src2);

  /// VPXOR xmm, xmm, [mem]
  void vpxorXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vpxorXmmXmmMem(dst, src1, mem);

  /// VPXOR ymm, ymm, ymm (VEX XOR packed integer 256-bit)
  void vpxorYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vpxorYmmYmmYmm(dst, src1, src2);

  /// VPXOR ymm, ymm, [mem]
  void vpxorYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vpxorYmmYmmMem(dst, src1, mem);

  // ===========================================================================
  // AVX2 - Integer arithmetic (VEX-encoded)
  // ===========================================================================

  /// VPADDD xmm, xmm, xmm (VEX add packed dwords)
  void vpadddXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vpadddXmmXmmXmm(dst, src1, src2);

  /// VPADDD ymm, ymm, ymm (VEX add packed dwords 256-bit)
  void vpadddYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vpadddYmmYmmYmm(dst, src1, src2);

  /// VPADDQ xmm, xmm, xmm (VEX add packed qwords)
  void vpaddqXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vpaddqXmmXmmXmm(dst, src1, src2);

  /// VPMULLD xmm, xmm, xmm (VEX multiply packed dwords low)
  void vpmulldXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vpmulldXmmXmmXmm(dst, src1, src2);

  // ===========================================================================
  // FMA - Fused Multiply-Add (VEX-encoded)
  // ===========================================================================

  /// VFMADD132SD xmm, xmm, xmm: dst = dst * src2 + src1
  void vfmadd132sdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vfmadd132sdXmmXmmXmm(dst, src1, src2);

  /// VFMADD231SD xmm, xmm, xmm: dst = src1 * src2 + dst
  void vfmadd231sdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vfmadd231sdXmmXmmXmm(dst, src1, src2);

  // ===========================================================================
  // AVX - Special
  // ===========================================================================

  /// VZEROUPPER - Zero upper 128 bits of all YMM registers.
  ///
  /// CRITICAL: Call this before transitioning from AVX to SSE code!
  /// Avoids expensive AVX-SSE transition penalty.
  void vzeroupper() => _enc.vzeroupper();

  /// VZEROALL - Zero all YMM registers completely.
  void vzeroall() => _enc.vzeroall();

  // ===========================================================================
  // AVX-512 Instructions (EVEX-encoded)
  // ===========================================================================

  /// VADDPS zmm, zmm, zmm (AVX-512 add packed single 512-bit)
  void vaddpsZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vaddpsZmmZmmZmm(dst, src1, src2);

  /// VADDPD zmm, zmm, zmm (AVX-512 add packed double 512-bit)
  void vaddpdZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vaddpdZmmZmmZmm(dst, src1, src2);

  // --- Move Instructions ---

  /// VMOVUPS zmm, zmm (AVX-512)
  void vmovupsZmm(X86Zmm dst, X86Zmm src) => _enc.vmovupsZmmZmm(dst, src);

  /// VMOVUPS zmm, [mem] (AVX-512)
  void vmovupsZmmMem(X86Zmm dst, X86Mem mem) => _enc.vmovupsZmmMem(dst, mem);

  /// VMOVUPS [mem], zmm (AVX-512)
  void vmovupsMemZmm(X86Mem mem, X86Zmm src) => _enc.vmovupsMemZmm(mem, src);

  /// VMOVUPD zmm, zmm (AVX-512)
  void vmovupdZmm(X86Zmm dst, X86Zmm src) => _enc.vmovupdZmmZmm(dst, src);

  /// VMOVUPD zmm, [mem] (AVX-512)
  void vmovupdZmmMem(X86Zmm dst, X86Mem mem) => _enc.vmovupdZmmMem(dst, mem);

  /// VMOVUPD [mem], zmm (AVX-512)
  void vmovupdMemZmm(X86Mem mem, X86Zmm src) => _enc.vmovupdMemZmm(mem, src);

  /// VMOVDQU32 zmm, zmm (AVX-512)
  void vmovdqu32Zmm(X86Zmm dst, X86Zmm src) => _enc.vmovdqu32ZmmZmm(dst, src);

  /// VMOVDQU32 zmm, [mem] (AVX-512)
  void vmovdqu32ZmmMem(X86Zmm dst, X86Mem mem) =>
      _enc.vmovdqu32ZmmMem(dst, mem);

  /// VMOVDQU32 [mem], zmm (AVX-512)
  void vmovdqu32MemZmm(X86Mem mem, X86Zmm src) =>
      _enc.vmovdqu32MemZmm(mem, src);

  /// VMOVDQU64 zmm, zmm (AVX-512)
  void vmovdqu64Zmm(X86Zmm dst, X86Zmm src) => _enc.vmovdqu64ZmmZmm(dst, src);

  /// VMOVDQU64 zmm, [mem] (AVX-512)
  void vmovdqu64ZmmMem(X86Zmm dst, X86Mem mem) =>
      _enc.vmovdqu64ZmmMem(dst, mem);

  /// VMOVDQU64 [mem], zmm (AVX-512)
  void vmovdqu64MemZmm(X86Mem mem, X86Zmm src) =>
      _enc.vmovdqu64MemZmm(mem, src);

  // --- Logic Instructions ---

  /// VPANDD zmm, zmm, zmm (AVX-512)
  void vpanddZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vpanddZmmZmmZmm(dst, src1, src2);

  /// VPANDQ zmm, zmm, zmm (AVX-512)
  void vpandqZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vpandqZmmZmmZmm(dst, src1, src2);

  /// VPORD zmm, zmm, zmm (AVX-512)
  void vpordZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vpordZmmZmmZmm(dst, src1, src2);

  /// VPORQ zmm, zmm, zmm (AVX-512)
  void vporqZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vporqZmmZmmZmm(dst, src1, src2);

  /// VPXORD zmm, zmm, zmm (AVX-512)
  void vpxordZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vpxordZmmZmmZmm(dst, src1, src2);

  /// VPXORQ zmm, zmm, zmm (AVX-512)
  void vpxorqZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vpxorqZmmZmmZmm(dst, src1, src2);

  /// VXORPS zmm, zmm, zmm (AVX-512)
  void vxorpsZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vxorpsZmmZmmZmm(dst, src1, src2);

  /// VXORPD zmm, zmm, zmm (AVX-512)
  void vxorpdZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vxorpdZmmZmmZmm(dst, src1, src2);

  // --- Conversion Instructions ---

  /// VCVTTPS2DQ zmm, zmm (AVX-512) - Convert with truncation
  void vcvttps2dqZmm(X86Zmm dst, X86Zmm src) => _enc.vcvttps2dqZmmZmm(dst, src);

  /// VCVTDQ2PS zmm, zmm (AVX-512)
  void vcvtdq2psZmm(X86Zmm dst, X86Zmm src) => _enc.vcvtdq2psZmmZmm(dst, src);

  /// VCVTPS2PD zmm, ymm (AVX-512)
  void vcvtps2pdZmm(X86Zmm dst, X86Ymm src) => _enc.vcvtps2pdZmmYmm(dst, src);

  /// VCVTPD2PS ymm, zmm (AVX-512)
  void vcvtpd2psYmm(X86Ymm dst, X86Zmm src) => _enc.vcvtpd2psYmmZmm(dst, src);

  // ===========================================================================
  // Part Added by Antigravity for ChaCha20 Benchmark (SSE2 extensions)
  // ===========================================================================

  /// PADDD xmm, xmm
  void padddXX(X86Xmm dst, X86Xmm src) => _enc.padddXmmXmm(dst, src);

  /// POR xmm, xmm
  void porXX(X86Xmm dst, X86Xmm src) => _enc.porXmmXmm(dst, src);

  /// PSLLD xmm, imm8
  void pslldXI(X86Xmm dst, int imm8) => _enc.pslldXmmImm8(dst, imm8);

  /// PSRLD xmm, imm8
  void psrldXI(X86Xmm dst, int imm8) => _enc.psrldXmmImm8(dst, imm8);

  /// PSHUFD xmm, xmm, imm8
  void pshufdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.pshufdXmmXmmImm8(dst, src, imm8);

  void vmovups(X86Xmm dst, X86Xmm src) => _enc.vmovupsXmmXmm(dst, src);
  void vmovupsXM(X86Xmm dst, X86Mem mem) => _enc.vmovupsXmmMem(dst, mem);
  void vmovupsMX(X86Mem mem, X86Xmm src) => _enc.vmovupsMemXmm(mem, src);

  void vmovaps(X86Xmm dst, X86Xmm src) => _enc.vmovapsXmmXmm(dst, src);
  void vmovapsXM(X86Xmm dst, X86Mem mem) => _enc.vmovapsXmmMem(dst, mem);
  void vmovapsMX(X86Mem mem, X86Xmm src) => _enc.vmovapsMemXmm(mem, src);

  void vmovupsY(X86Ymm dst, X86Ymm src) => _enc.vmovupsYmmYmm(dst, src);
  void vmovupsYM(X86Ymm dst, X86Mem mem) => _enc.vmovupsYmmMem(dst, mem);
  void vmovupsMY(X86Mem mem, X86Ymm src) => _enc.vmovupsMemYmm(mem, src);

  void vmovapsY(X86Ymm dst, X86Ymm src) => _enc.vmovapsYmmYmm(dst, src);
  void vmovapsYM(X86Ymm dst, X86Mem mem) => _enc.vmovapsYmmMem(dst, mem);
  void vmovapsMY(X86Mem mem, X86Ymm src) => _enc.vmovapsMemYmm(mem, src);

  // VDIVPS/VDIVPD forms
  void vdivpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vdivpsXXX(dst, src1, src2);
  void vdivpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vdivpsXmmXmmMem(dst, src1, mem);
  void vdivpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vdivpsYYY(dst, src1, src2);
  void vdivpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vdivpsYmmYmmMem(dst, src1, mem);

  void vdivpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vdivpdXXX(dst, src1, src2);
  void vdivpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vdivpdXmmXmmMem(dst, src1, mem);
  void vdivpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vdivpdYYY(dst, src1, src2);
  void vdivpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vdivpdYmmYmmMem(dst, src1, mem);

  // SSE Logical operations
  void andps(X86Xmm dst, X86Xmm src) => _enc.andpsXmmXmm(dst, src);
  void andpsXM(X86Xmm dst, X86Mem mem) => _enc.andpsXmmMem(dst, mem);
  void andpd(X86Xmm dst, X86Xmm src) => _enc.andpdXmmXmm(dst, src);
  void andpdXM(X86Xmm dst, X86Mem mem) => _enc.andpdXmmMem(dst, mem);

  void orps(X86Xmm dst, X86Xmm src) => _enc.orpsXmmXmm(dst, src);
  void orpsXM(X86Xmm dst, X86Mem mem) => _enc.orpsXmmMem(dst, mem);
  void orpd(X86Xmm dst, X86Xmm src) => _enc.orpdXmmXmm(dst, src);
  void orpdXM(X86Xmm dst, X86Mem mem) => _enc.orpdXmmMem(dst, mem);

  // SSE Compare operations (min/max)

  void minpsXM(X86Xmm dst, X86Mem mem) => _enc.minpsXmmMem(dst, mem);
  void minpd(X86Xmm dst, X86Xmm src) => _enc.minpdXmmXmm(dst, src);
  void minpdXM(X86Xmm dst, X86Mem mem) => _enc.minpdXmmMem(dst, mem);

  void maxpsXM(X86Xmm dst, X86Mem mem) => _enc.maxpsXmmMem(dst, mem);
  void maxpd(X86Xmm dst, X86Xmm src) => _enc.maxpdXmmXmm(dst, src);
  void maxpdXM(X86Xmm dst, X86Mem mem) => _enc.maxpdXmmMem(dst, mem);

  // SSE Math operations (sqrt, rcp, rsqrt)
  void sqrtps(X86Xmm dst, X86Xmm src) => _enc.sqrtpsXmmXmm(dst, src);
  void sqrtpsXM(X86Xmm dst, X86Mem mem) => _enc.sqrtpsXmmMem(dst, mem);
  void sqrtpd(X86Xmm dst, X86Xmm src) => _enc.sqrtpdXmmXmm(dst, src);
  void sqrtpdXM(X86Xmm dst, X86Mem mem) => _enc.sqrtpdXmmMem(dst, mem);

  void rcpps(X86Xmm dst, X86Xmm src) => _enc.rcppsXmmXmm(dst, src);
  void rcppsXM(X86Xmm dst, X86Mem mem) => _enc.rcppsXmmMem(dst, mem);
  void rsqrtps(X86Xmm dst, X86Xmm src) => _enc.rsqrtpsXmmXmm(dst, src);
  void rsqrtpsXM(X86Xmm dst, X86Mem mem) => _enc.rsqrtpsXmmMem(dst, mem);

  // AVX Logical operations
  void vandpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vandpsXmmXmmXmm(dst, src1, src2);
  void vandpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vandpsXmmXmmMem(dst, src1, mem);
  void vandpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vandpsYmmYmmYmm(dst, src1, src2);
  void vandpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vandpsYmmYmmMem(dst, src1, mem);

  void vandpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vandpdXmmXmmXmm(dst, src1, src2);
  void vandpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vandpdXmmXmmMem(dst, src1, mem);
  void vandpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vandpdYmmYmmYmm(dst, src1, src2);
  void vandpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vandpdYmmYmmMem(dst, src1, mem);

  void vorpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vorpsXmmXmmXmm(dst, src1, src2);
  void vorpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vorpsXmmXmmMem(dst, src1, mem);
  void vorpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vorpsYmmYmmYmm(dst, src1, src2);
  void vorpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vorpsYmmYmmMem(dst, src1, mem);

  void vorpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vorpdXmmXmmXmm(dst, src1, src2);
  void vorpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vorpdXmmXmmMem(dst, src1, mem);
  void vorpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vorpdYmmYmmYmm(dst, src1, src2);
  void vorpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vorpdYmmYmmMem(dst, src1, mem);

  void vporXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vporXmmXmmXmm(dst, src1, src2);
  void vporXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vporXmmXmmMem(dst, src1, mem);
  void vporYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vporYmmYmmYmm(dst, src1, src2);
  void vporYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vporYmmYmmMem(dst, src1, mem);

  void vpandXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vpandXmmXmmXmm(dst, src1, src2);
  void vpandXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vpandXmmXmmMem(dst, src1, mem);
  void vpandYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vpandYmmYmmYmm(dst, src1, src2);
  void vpandYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vpandYmmYmmMem(dst, src1, mem);

  void vpaddqXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vpaddqXmmXmmMem(dst, src1, mem);

  void vpaddqYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vpaddqYmmYmmYmm(dst, src1, src2);

  void vpaddqYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vpaddqYmmYmmMem(dst, src1, mem);

  void vpadddXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vpadddXmmXmmMem(dst, src1, mem);
  void vpadddYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vpadddYmmYmmMem(dst, src1, mem);

  void vpmulldXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vpmulldXmmXmmMem(dst, src1, mem);
  void vpmulldYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vpmulldYmmYmmMem(dst, src1, mem);

  // TODO: AVX versions (vandps, vorps, etc.) - need encoder implementations
}
