/// AsmJit x86/x64 Assembler
///
/// High-level x86/x64 instruction emission API.
/// Ported from asmjit/x86/x86assembler.h

import '../core/code_holder.dart';
import '../core/code_buffer.dart';
import '../core/emitter.dart';
import '../core/error.dart';
import '../core/func.dart';
import '../core/labels.dart';
import '../core/environment.dart';
import '../core/arch.dart';
import '../core/reg_utils.dart';
import '../core/operand.dart';
import 'x86.dart';
import 'x86_operands.dart';
import 'x86_encoder.dart';
import 'x86_simd.dart';
import 'x86_inst_db.g.dart';
import 'x86_dispatcher.g.dart';
import 'x86_emit_helper.dart';

/// x86/x64 Assembler.
///
/// Provides a high-level API for emitting x86/x64 instructions.
/// Handles label binding, relocations, and instruction encoding.
class X86Assembler extends BaseEmitter {
  /// The internal code buffer.
  late final CodeBuffer _buf;

  /// The instruction encoder.
  late final X86Encoder _enc;

  /// Encoding options (used by higher-level pipelines).
  int encodingOptions = EncodingOptions.kNone;

  /// Diagnostic options (used by higher-level pipelines).
  int diagnosticOptions = DiagnosticOptions.kNone;

  /// Creates an x86 assembler for the given code holder.
  X86Assembler(CodeHolder code) : super(code) {
    _buf = code.text.buffer;
    _enc = X86Encoder(_buf);
  }

  /// Emits a raw instruction by ID with generic operands.
  void emit(int instId, List<Object> ops) {
    instructionCount++;
    x86Dispatch(this, instId, ops);
  }

  /// Emits moves required to assign arguments if any remapping is needed.
  AsmJitError emitArgsAssignment(FuncFrame frame, FuncArgsAssignment args) {
    final helper = X86EmitHelper(this);
    return helper.emitArgsAssignment(frame, args);
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
      _enc.movR32Imm32(dst.as32, imm);
    } else if (imm >= -2147483648 && imm <= 2147483647) {
      _enc.movR64Imm32(dst, imm);
    } else {
      _enc.movR64Imm64(dst, imm);
    }
  }

  /// MOV r32, imm32.
  void movRI32(X86Gp dst, int imm) {
    _enc.movR32Imm32(dst.as32, imm);
  }

  /// MOV reg, imm (convenience method - auto-selects size).
  void movRI(X86Gp dst, int imm) {
    if (dst.bits == 64) {
      movRI64(dst, imm);
    } else {
      movRI32(dst, imm);
    }
  }

  /// MOV (generic).
  void mov(Operand dst, Object src) {
    if (dst is X86Gp) {
      if (src is X86Gp) {
        movRR(dst, src);
      } else if (src is int) {
        movRI(dst, src);
      } else if (src is X86Mem) {
        movRM(dst, src);
      }
    } else if (dst is X86Mem) {
      if (src is X86Gp) {
        movMR(dst, src);
      } else if (src is int) {
        movMI(dst, src);
      }
    }
  }

  /// MOV r64, [mem].
  void movRM(X86Gp dst, X86Mem mem) {
    if (dst.bits == 64) {
      _enc.movR64Mem(dst, mem);
    } else {
      _enc.movR32Mem(dst.as32, mem);
    }
  }

  /// MOV [mem], r64.
  void movMR(X86Mem mem, X86Gp src) {
    if (src.bits == 64) {
      _enc.movMemR64(mem, src);
    } else {
      _enc.movMemR32(mem, src.as32);
    }
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
    _enc.addRR(dst, src);
  }

  /// ADD reg, imm.
  void addRI(X86Gp dst, int imm) {
    _enc.addRI(dst, imm);
  }

  /// ADD reg, [mem].
  void addRM(X86Gp dst, X86Mem mem) => _enc.addRM(dst, mem);

  /// ADD [mem], reg.
  void addMR(X86Mem mem, X86Gp src) => _enc.addMR(mem, src);

  /// ADD [mem], imm.
  void addMI(X86Mem mem, int imm) => _enc.addMI(mem, imm);

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

  /// SUB r64, [mem].
  void subRM(X86Gp dst, X86Mem mem) => _enc.subR64Mem(dst, mem);

  /// AND r64, [mem].
  void andRM(X86Gp dst, X86Mem mem) => _enc.andRM(dst, mem);

  /// AND [mem], reg.
  void andMR(X86Mem mem, X86Gp src) => _enc.andMR(mem, src);

  /// AND [mem], imm.
  void andMI(X86Mem mem, int imm) => _enc.andMI(mem, imm);

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
    _enc.andRR(dst, src);
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
    _enc.andRI(dst, imm);
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
      _enc.incR32(reg.as32);
    }
  }

  /// DEC reg.
  void dec(X86Gp reg) {
    if (reg.bits == 64) {
      _enc.decR64(reg);
    } else {
      _enc.decR32(reg.as32);
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
    if (reg.bits == 64) {
      _enc.shlR64Imm8(reg, imm);
    } else {
      _enc.shlR32Imm8(reg.as32, imm);
    }
  }

  /// SHL reg, CL (left shift by CL).
  void shlRCl(X86Gp reg) {
    if (reg.bits == 64) {
      _enc.shlR64Cl(reg);
    } else {
      _enc.shlR32Cl(reg.as32);
    }
  }

  /// SHR reg, imm (logical right shift).
  void shrRI(X86Gp reg, int imm) {
    if (reg.bits == 64) {
      _enc.shrR64Imm8(reg, imm);
    } else {
      _enc.shrR32Imm8(reg.as32, imm);
    }
  }

  /// SHR reg, CL (logical right shift by CL).
  void shrRCl(X86Gp reg) {
    if (reg.bits == 64) {
      _enc.shrR64Cl(reg);
    } else {
      _enc.shrR32Cl(reg.as32);
    }
  }

  /// SAR reg, imm (arithmetic right shift).
  void sarRI(X86Gp reg, int imm) {
    if (reg.bits == 64) {
      _enc.sarR64Imm8(reg, imm);
    } else {
      _enc.sarR32Imm8(reg.as32, imm);
    }
  }

  /// SAR reg, CL (arithmetic right shift by CL).
  void sarRCl(X86Gp reg) {
    if (reg.bits == 64) {
      _enc.sarR64Cl(reg);
    } else {
      _enc.sarR32Cl(reg.as32);
    }
  }

  /// ROL reg, imm (rotate left).
  void rolRI(X86Gp reg, int imm) {
    if (reg.bits == 64) {
      _enc.rolR64Imm8(reg, imm);
    } else {
      _enc.rolR32Imm8(reg.as32, imm);
    }
  }

  /// ROR reg, imm (rotate right).
  void rorRI(X86Gp reg, int imm) {
    if (reg.bits == 64) {
      _enc.rorR64Imm8(reg, imm);
    } else {
      _enc.rorR32Imm8(reg.as32, imm);
    }
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
    _enc.setccR8(cond, reg.as8);
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

  /// ARPL r/m16, r16.
  void arplRR(X86Gp dst, X86Gp src) => _enc.arplRR(dst, src);

  /// ARPL [mem16], r16.
  void arplMR(X86Mem dst, X86Gp src) => _enc.arplMR(dst, src);

  /// BOUND r16/r32, [mem].
  void bound(X86Gp dst, X86Mem mem) => _enc.boundRM(dst, mem);

  /// BSF dst, src (bit scan forward).
  void bsf(X86Gp dst, X86Gp src) {
    if (dst.bits == 64 && src.bits == 64) {
      _enc.bsfR64R64(dst, src);
    } else {
      _enc.bsfRR(dst, src);
    }
  }

  /// BSF dst, [mem].
  void bsfRM(X86Gp dst, X86Mem mem) => _enc.bsfRM(dst, mem);

  /// BSR dst, src (bit scan reverse).
  void bsr(X86Gp dst, X86Gp src) {
    if (dst.bits == 64 && src.bits == 64) {
      _enc.bsrR64R64(dst, src);
    } else {
      _enc.bsrRR(dst, src);
    }
  }

  /// BSR dst, [mem].
  void bsrRM(X86Gp dst, X86Mem mem) => _enc.bsrRM(dst, mem);

  /// BSWAP reg.
  void bswap(X86Gp reg) => _enc.bswapR(reg);

  /// BT reg, imm.
  void btRI(X86Gp dst, int imm) => _enc.btRI(dst, imm);

  /// BT [mem], imm.
  void btMI(X86Mem mem, int imm) => _enc.btMI(mem, imm);

  /// BT reg, reg.
  void btRR(X86Gp dst, X86Gp src) => _enc.btRR(dst, src);

  /// BT [mem], reg.
  void btMR(X86Mem mem, X86Gp src) => _enc.btMR(mem, src);

  /// BTC reg, imm.
  void btcRI(X86Gp dst, int imm) => _enc.btcRI(dst, imm);

  /// BTC [mem], imm.
  void btcMI(X86Mem mem, int imm) => _enc.btcMI(mem, imm);

  /// BTC reg, reg.
  void btcRR(X86Gp dst, X86Gp src) => _enc.btcRR(dst, src);

  /// BTC [mem], reg.
  void btcMR(X86Mem mem, X86Gp src) => _enc.btcMR(mem, src);

  /// BTR reg, imm.
  void btrRI(X86Gp dst, int imm) => _enc.btrRI(dst, imm);

  /// BTR reg, reg.
  void btrRR(X86Gp dst, X86Gp src) => _enc.btrRR(dst, src);

  /// BTS reg, imm.
  void btsRI(X86Gp dst, int imm) => _enc.btsRI(dst, imm);

  /// BTS reg, reg.
  void btsRR(X86Gp dst, X86Gp src) => _enc.btsRR(dst, src);

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

  /// CBW - Convert byte to word (AL -> AX)
  void cbw() => _enc.cbw();

  /// CWDE - Convert word to doubleword (AX -> EAX)
  void cwde() => _enc.cwde();

  /// CDQE - Convert doubleword to quadword (EAX -> RAX)
  void cdqe() => _enc.cdqe();

  /// CWD - Convert word to doubleword (AX -> DX:AX)
  void cwd() => _enc.cwd();

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
    _enc.adcRR(dst, src);
  }

  /// ADC dst, imm - Add with carry
  void adcRI(X86Gp dst, int imm) {
    if (dst.bits == 8) {
      _enc.adcImm8(dst, imm);
      return;
    }

    if (imm >= -128 && imm <= 127) {
      _enc.adcImm8(dst, imm);
    } else {
      _enc.adcImmFull(dst, imm);
    }
  }

  /// ADC dst, [mem] - Add with carry (register <- register + memory)
  void adcRM(X86Gp dst, X86Mem src) {
    _enc.adcRM(dst, src);
  }

  /// ADC [mem], src - Add with carry (memory <- memory + register)
  void adcMR(X86Mem dst, X86Gp src) {
    _enc.adcMR(dst, src);
  }

  /// ADC [mem], imm - Add with carry (memory <- memory + immediate)
  void adcMI(X86Mem dst, int imm) {
    _enc.adcMI(dst, imm);
  }

  /// SBB dst, src - Subtract with borrow
  void sbbRR(X86Gp dst, X86Gp src) {
    _enc.sbbRR(dst, src);
  }

  /// SBB dst, imm - Subtract with borrow
  void sbbRI(X86Gp dst, int imm) {
    if (dst.bits == 8) {
      _enc.sbbImm8(dst, imm);
      return;
    }

    if (imm >= -128 && imm <= 127) {
      _enc.sbbImm8(dst, imm);
    } else {
      _enc.sbbImmFull(dst, imm);
    }
  }

  /// SBB dst, [mem] - Subtract with borrow (register <- register - memory)
  void sbbRM(X86Gp dst, X86Mem src) {
    _enc.sbbRM(dst, src);
  }

  /// MUL src - Unsigned multiply RDX:RAX = RAX * src
  void mul(X86Gp src) {
    _enc.mulR64(src);
  }

  /// MULX hi, lo, src (BMI2) - Unsigned multiply without flags
  void mulx(X86Gp hi, X86Gp lo, X86Gp src) {
    _enc.mulxR64R64R64(hi, lo, src);
  }

  // ==========================================================================
  // BMI2
  // ==========================================================================

  /// BZHI dst, src, idx (BMI2) - Zero high bits starting from idx.
  void bzhi(X86Gp dst, X86Gp src, X86Gp idx) {
    _enc.bzhiR64R64R64(dst, src, idx);
  }

  /// PDEP dst, src, mask (BMI2) - Parallel bit deposit.
  void pdep(X86Gp dst, X86Gp src, X86Gp mask) {
    _enc.pdepR64R64R64(dst, src, mask);
  }

  /// PEXT dst, src, mask (BMI2) - Parallel bit extract.
  void pext(X86Gp dst, X86Gp src, X86Gp mask) {
    _enc.pextR64R64R64(dst, src, mask);
  }

  /// RORX dst, src, imm8 (BMI2) - Rotate right without affecting flags.
  void rorx(X86Gp dst, X86Gp src, int imm8) {
    _enc.rorxR64R64Imm8(dst, src, imm8);
  }

  /// SARX dst, src, shift (BMI2) - Arithmetic shift right without affecting flags.
  void sarx(X86Gp dst, X86Gp src, X86Gp shift) {
    _enc.sarxR64R64R64(dst, src, shift);
  }

  /// SHLX dst, src, shift (BMI2) - Logical shift left without affecting flags.
  void shlx(X86Gp dst, X86Gp src, X86Gp shift) {
    _enc.shlxR64R64R64(dst, src, shift);
  }

  /// SHRX dst, src, shift (BMI2) - Logical shift right without affecting flags.
  void shrx(X86Gp dst, X86Gp src, X86Gp shift) {
    _enc.shrxR64R64R64(dst, src, shift);
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

  /// ADDSD xmm, [mem]
  void addsdXM(X86Xmm dst, X86Mem src) => _enc.addsdXmmMem(dst, src);

  /// SUBSD xmm, [mem]
  void subsdXM(X86Xmm dst, X86Mem src) => _enc.subsdXmmMem(dst, src);

  /// MULSD xmm, [mem]
  void mulsdXM(X86Xmm dst, X86Mem src) => _enc.mulsdXmmMem(dst, src);

  /// DIVSD xmm, [mem]
  void divsdXM(X86Xmm dst, X86Mem src) => _enc.divsdXmmMem(dst, src);

  /// SQRTSD xmm, [mem]
  void sqrtsdXM(X86Xmm dst, X86Mem src) => _enc.sqrtsdXmmMem(dst, src);

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

  /// ADDSS xmm, [mem]
  void addssXM(X86Xmm dst, X86Mem src) => _enc.addssXmmMem(dst, src);

  /// SUBSS xmm, [mem]
  void subssXM(X86Xmm dst, X86Mem src) => _enc.subssXmmMem(dst, src);

  /// MULSS xmm, [mem]
  void mulssXM(X86Xmm dst, X86Mem src) => _enc.mulssXmmMem(dst, src);

  /// DIVSS xmm, [mem]
  void divssXM(X86Xmm dst, X86Mem src) => _enc.divssXmmMem(dst, src);

  /// SQRTSS xmm, [mem]
  void sqrtssXM(X86Xmm dst, X86Mem src) => _enc.sqrtssXmmMem(dst, src);

  // SSE/SSE2 - Scalar Min/Max and Reciprocal
  /// MINSD xmm, xmm
  void minsdXX(X86Xmm dst, X86Xmm src) => _enc.minsdXmmXmm(dst, src);
  void minsdXM(X86Xmm dst, X86Mem src) => _enc.minsdXmmMem(dst, src);

  /// MINSS xmm, xmm
  void minssXX(X86Xmm dst, X86Xmm src) => _enc.minssXmmXmm(dst, src);
  void minssXM(X86Xmm dst, X86Mem src) => _enc.minssXmmMem(dst, src);

  /// MAXSD xmm, xmm
  void maxsdXX(X86Xmm dst, X86Xmm src) => _enc.maxsdXmmXmm(dst, src);
  void maxsdXM(X86Xmm dst, X86Mem src) => _enc.maxsdXmmMem(dst, src);

  /// MAXSS xmm, xmm
  void maxssXX(X86Xmm dst, X86Xmm src) => _enc.maxssXmmXmm(dst, src);
  void maxssXM(X86Xmm dst, X86Mem src) => _enc.maxssXmmMem(dst, src);

  /// RCPSS xmm, xmm
  void rcpssXX(X86Xmm dst, X86Xmm src) => _enc.rcpssXmmXmm(dst, src);
  void rcpssXM(X86Xmm dst, X86Mem src) => _enc.rcpssXmmMem(dst, src);

  /// RSQRTSS xmm, xmm
  void rsqrtssXX(X86Xmm dst, X86Xmm src) => _enc.rsqrtssXmmXmm(dst, src);
  void rsqrtssXM(X86Xmm dst, X86Mem src) => _enc.rsqrtssXmmMem(dst, src);

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

  /// RCPPS xmm, xmm
  void rcppsXX(X86Xmm dst, X86Xmm src) => _enc.rcppsXmmXmm(dst, src);

  /// RCPPS xmm, [mem]
  void rcppsXM(X86Xmm dst, X86Mem src) => _enc.rcppsXmmMem(dst, src);

  /// RSQRTPS xmm, xmm
  void rsqrtpsXX(X86Xmm dst, X86Xmm src) => _enc.rsqrtpsXmmXmm(dst, src);

  /// RSQRTPS xmm, [mem]
  void rsqrtpsXM(X86Xmm dst, X86Mem src) => _enc.rsqrtpsXmmMem(dst, src);

  /// SQRTPS xmm, xmm
  void sqrtpsXX(X86Xmm dst, X86Xmm src) => _enc.sqrtpsXmmXmm(dst, src);

  /// SQRTPS xmm, [mem]
  void sqrtpsXM(X86Xmm dst, X86Mem src) => _enc.sqrtpsXmmMem(dst, src);

  /// SQRTPD xmm, xmm
  void sqrtpdXX(X86Xmm dst, X86Xmm src) => _enc.sqrtpdXmmXmm(dst, src);

  /// SQRTPD xmm, [mem]
  void sqrtpdXM(X86Xmm dst, X86Mem src) => _enc.sqrtpdXmmMem(dst, src);

  /// SQRTPS xmm, xmm (alias)
  void sqrtps(X86Xmm dst, X86Xmm src) => _enc.sqrtpsXmmXmm(dst, src);

  /// SQRTPD xmm, xmm (alias)
  void sqrtpd(X86Xmm dst, X86Xmm src) => _enc.sqrtpdXmmXmm(dst, src);

  /// RCPPS xmm, xmm (alias)
  void rcpps(X86Xmm dst, X86Xmm src) => _enc.rcppsXmmXmm(dst, src);

  /// RSQRTPS xmm, xmm (alias)
  void rsqrtps(X86Xmm dst, X86Xmm src) => _enc.rsqrtpsXmmXmm(dst, src);

  /// MINPS xmm, xmm
  void minpsXX(X86Xmm dst, X86Xmm src) => _enc.minpsXmmXmm(dst, src);

  /// MINPS xmm, [mem]
  void minpsXM(X86Xmm dst, X86Mem src) => _enc.minpsXmmMem(dst, src);

  /// MINPD xmm, xmm
  void minpd(X86Xmm dst, X86Xmm src) => _enc.minpdXmmXmm(dst, src);
  void minpdXX(X86Xmm dst, X86Xmm src) => _enc.minpdXmmXmm(dst, src);

  /// MINPD xmm, [mem]
  void minpdXM(X86Xmm dst, X86Mem src) => _enc.minpdXmmMem(dst, src);

  /// MAXPS xmm, xmm
  void maxpsXX(X86Xmm dst, X86Xmm src) => _enc.maxpsXmmXmm(dst, src);

  /// MAXPS xmm, [mem]
  void maxpsXM(X86Xmm dst, X86Mem src) => _enc.maxpsXmmMem(dst, src);

  /// MAXPD xmm, xmm
  void maxpd(X86Xmm dst, X86Xmm src) => _enc.maxpdXmmXmm(dst, src);
  void maxpdXX(X86Xmm dst, X86Xmm src) => _enc.maxpdXmmXmm(dst, src);

  /// MAXPD xmm, [mem]
  void maxpdXM(X86Xmm dst, X86Mem src) => _enc.maxpdXmmMem(dst, src);

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

  /// CVTSD2SS xmm, [mem] (convert double to float)
  void cvtsd2ssXM(X86Xmm dst, X86Mem src) => _enc.cvtsd2ssXmmMem(dst, src);

  /// CVTSS2SD xmm, [mem] (convert float to double)
  void cvtss2sdXM(X86Xmm dst, X86Mem src) => _enc.cvtss2sdXmmMem(dst, src);

  /// CVTDQ2PS xmm, xmm
  void cvtdq2psXX(X86Xmm dst, X86Xmm src) => _enc.cvtdq2psXmmXmm(dst, src);

  /// CVTDQ2PS xmm, [mem]
  void cvtdq2psXM(X86Xmm dst, X86Mem src) => _enc.cvtdq2psXmmMem(dst, src);

  /// CVTPS2DQ xmm, xmm
  void cvtps2dqXX(X86Xmm dst, X86Xmm src) => _enc.cvtps2dqXmmXmm(dst, src);

  /// CVTPS2DQ xmm, [mem]
  void cvtps2dqXM(X86Xmm dst, X86Mem src) => _enc.cvtps2dqXmmMem(dst, src);

  /// CVTTPS2DQ xmm, xmm
  void cvttps2dqXX(X86Xmm dst, X86Xmm src) => _enc.cvttps2dqXmmXmm(dst, src);

  /// CVTTPS2DQ xmm, [mem]
  void cvttps2dqXM(X86Xmm dst, X86Mem src) => _enc.cvttps2dqXmmMem(dst, src);

  /// CVTSI2SD xmm, [mem] (convert int32/64 to double)
  void cvtsi2sdXM(X86Xmm dst, X86Mem src) => _enc.cvtsi2sdXmmMem(dst, src);

  /// CVTSI2SS xmm, [mem] (convert int32/64 to float)
  void cvtsi2ssXM(X86Xmm dst, X86Mem src) => _enc.cvtsi2ssXmmMem(dst, src);

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

  /// CMPPS xmm, xmm, imm8
  void cmppsXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.cmppsXmmXmmImm8(dst, src, imm8);

  /// CMPPS xmm, [mem], imm8
  void cmppsXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.cmppsXmmMemImm8(dst, src, imm8);

  /// CMPPD xmm, xmm, imm8
  void cmppdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.cmppdXmmXmmImm8(dst, src, imm8);

  /// CMPPD xmm, [mem], imm8
  void cmppdXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.cmppdXmmMemImm8(dst, src, imm8);

  /// CMPSS xmm, xmm, imm8
  void cmpssXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.cmpssXmmXmmImm8(dst, src, imm8);

  /// CMPSS xmm, [mem], imm8
  void cmpssXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.cmpssXmmMemImm8(dst, src, imm8);

  /// CMPSD xmm, xmm, imm8
  void cmpsdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.cmpsdXmmXmmImm8(dst, src, imm8);

  /// CMPSD xmm, [mem], imm8
  void cmpsdXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.cmpsdXmmMemImm8(dst, src, imm8);

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

  /// KMOVW k, r32 (move 16-bit from GP to mask)
  void kmovwKR(X86KReg dst, X86Gp src) => _enc.kmovwKRegR32(dst, src);

  /// KMOVW r32, k (move 16-bit from mask to GP)
  void kmovwRK(X86Gp dst, X86KReg src) => _enc.kmovwR32KReg(dst, src);

  /// KMOVD k, r32 (move 32-bit from GP to mask)
  void kmovdKR(X86KReg dst, X86Gp src) => _enc.kmovdKRegR32(dst, src);

  /// KMOVD r32, k (move 32-bit from mask to GP)
  void kmovdRK(X86Gp dst, X86KReg src) => _enc.kmovdR32KReg(dst, src);

  /// KMOVQ k, r64 (move 64-bit from GP to mask)
  void kmovqKR(X86KReg dst, X86Gp src) => _enc.kmovqKRegR64(dst, src);

  /// KMOVQ r64, k (move 64-bit from mask to GP)
  void kmovqRK(X86Gp dst, X86KReg src) => _enc.kmovqR64KReg(dst, src);

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

  /// VMOVD xmm, r32
  void vmovdXR(X86Xmm dst, X86Gp src) => _enc.vmovdXmmR32(dst, src);

  /// VMOVD r32, xmm
  void vmovdRX(X86Gp dst, X86Xmm src) => _enc.vmovdR32Xmm(dst, src);

  /// VMOVQ xmm, r64
  void vmovqXR(X86Xmm dst, X86Gp src) => _enc.vmovqXmmR64(dst, src);

  /// VMOVQ r64, xmm
  void vmovqRX(X86Gp dst, X86Xmm src) => _enc.vmovqR64Xmm(dst, src);

  /// VBROADCASTSS xmm, mem32
  void vbroadcastssXM(X86Xmm dst, X86Mem mem) =>
      _enc.vbroadcastssXmmMem(dst, mem);

  /// VBROADCASTSS ymm, mem32
  void vbroadcastssYM(X86Ymm dst, X86Mem mem) =>
      _enc.vbroadcastssYmmMem(dst, mem);

  /// VBROADCASTSD ymm, mem64
  void vbroadcastsdYM(X86Ymm dst, X86Mem mem) =>
      _enc.vbroadcastsdYmmMem(dst, mem);

  /// VPBROADCASTB xmm, xmm
  void vpbroadcastbXX(X86Xmm dst, X86Xmm src) =>
      _enc.vpbroadcastbXmmXmm(dst, src);
  void vpbroadcastbXM(X86Xmm dst, X86Mem mem) =>
      _enc.vpbroadcastbXmmMem(dst, mem);

  /// VPBROADCASTW xmm, xmm
  void vpbroadcastwXX(X86Xmm dst, X86Xmm src) =>
      _enc.vpbroadcastwXmmXmm(dst, src);
  void vpbroadcastwXM(X86Xmm dst, X86Mem mem) =>
      _enc.vpbroadcastwXmmMem(dst, mem);

  /// VPBROADCASTD xmm, xmm
  void vpbroadcastdXX(X86Xmm dst, X86Xmm src) =>
      _enc.vpbroadcastdXmmXmm(dst, src);
  void vpbroadcastdXM(X86Xmm dst, X86Mem mem) =>
      _enc.vpbroadcastdXmmMem(dst, mem);

  /// VPBROADCASTQ xmm, xmm
  void vpbroadcastqXX(X86Xmm dst, X86Xmm src) =>
      _enc.vpbroadcastqXmmXmm(dst, src);
  void vpbroadcastqXM(X86Xmm dst, X86Mem mem) =>
      _enc.vpbroadcastqXmmMem(dst, mem);

  /// VPBROADCASTB ymm, xmm
  void vpbroadcastbYX(X86Ymm dst, X86Xmm src) =>
      _enc.vpbroadcastbYmmXmm(dst, src);
  void vpbroadcastbYM(X86Ymm dst, X86Mem mem) =>
      _enc.vpbroadcastbYmmMem(dst, mem);

  /// VPBROADCASTW ymm, xmm
  void vpbroadcastwYX(X86Ymm dst, X86Xmm src) =>
      _enc.vpbroadcastwYmmXmm(dst, src);
  void vpbroadcastwYM(X86Ymm dst, X86Mem mem) =>
      _enc.vpbroadcastwYmmMem(dst, mem);

  /// VPBROADCASTD ymm, xmm
  void vpbroadcastdYX(X86Ymm dst, X86Xmm src) =>
      _enc.vpbroadcastdYmmXmm(dst, src);
  void vpbroadcastdYM(X86Ymm dst, X86Mem mem) =>
      _enc.vpbroadcastdYmmMem(dst, mem);

  /// VPBROADCASTQ ymm, xmm
  void vpbroadcastqYX(X86Ymm dst, X86Xmm src) =>
      _enc.vpbroadcastqYmmXmm(dst, src);
  void vpbroadcastqYM(X86Ymm dst, X86Mem mem) =>
      _enc.vpbroadcastqYmmMem(dst, mem);

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

  /// VADDSD xmm, xmm, [mem]
  void vaddsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vaddsdXmmXmmMem(dst, src1, mem);

  /// VSUBSD xmm, xmm, [mem]
  void vsubsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vsubsdXmmXmmMem(dst, src1, mem);

  /// VMULSD xmm, xmm, [mem]
  void vmulsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vmulsdXmmXmmMem(dst, src1, mem);

  /// VDIVSD xmm, xmm, [mem]
  void vdivsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vdivsdXmmXmmMem(dst, src1, mem);

  // ===========================================================================
  // AVX - Scalar arithmetic (Single Precision)
  // ===========================================================================

  /// VADDSS xmm, xmm, xmm
  void vaddssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vaddssXmmXmmXmm(dst, src1, src2);
  void vaddssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vaddssXmmXmmMem(dst, src1, mem);

  /// VSUBSS xmm, xmm, xmm
  void vsubssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vsubssXmmXmmXmm(dst, src1, src2);
  void vsubssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vsubssXmmXmmMem(dst, src1, mem);

  /// VMULSS xmm, xmm, xmm
  void vmulssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vmulssXmmXmmXmm(dst, src1, src2);
  void vmulssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vmulssXmmXmmMem(dst, src1, mem);

  /// VDIVSS xmm, xmm, xmm
  void vdivssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vdivssXmmXmmXmm(dst, src1, src2);
  void vdivssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vdivssXmmXmmMem(dst, src1, mem);

  // ===========================================================================
  // AVX - Math (SQRT, MIN, MAX)
  // ===========================================================================

  /// VSQRTPS xmm, xmm
  void vsqrtpsXX(X86Xmm dst, X86Xmm src) => _enc.vsqrtpsXmmXmm(dst, src);
  void vsqrtpsXM(X86Xmm dst, X86Mem mem) => _enc.vsqrtpsXmmMem(dst, mem);

  /// VSQRTPD xmm, xmm
  void vsqrtpdXX(X86Xmm dst, X86Xmm src) => _enc.vsqrtpdXmmXmm(dst, src);
  void vsqrtpdXM(X86Xmm dst, X86Mem mem) => _enc.vsqrtpdXmmMem(dst, mem);

  /// VSQRTPS ymm, ymm
  void vsqrtpsYY(X86Ymm dst, X86Ymm src) => _enc.vsqrtpsYmmYmm(dst, src);
  void vsqrtpsYM(X86Ymm dst, X86Mem mem) => _enc.vsqrtpsYmmMem(dst, mem);

  /// VSQRTPD ymm, ymm
  void vsqrtpdYY(X86Ymm dst, X86Ymm src) => _enc.vsqrtpdYmmYmm(dst, src);
  void vsqrtpdYM(X86Ymm dst, X86Mem mem) => _enc.vsqrtpdYmmMem(dst, mem);

  /// VRSQRTPS xmm, xmm
  void vrsqrtpsXX(X86Xmm dst, X86Xmm src) => _enc.vrsqrtpsXmmXmm(dst, src);
  void vrsqrtpsXM(X86Xmm dst, X86Mem mem) => _enc.vrsqrtpsXmmMem(dst, mem);

  /// VRSQRTPS ymm, ymm
  void vrsqrtpsYY(X86Ymm dst, X86Ymm src) => _enc.vrsqrtpsYmmYmm(dst, src);
  void vrsqrtpsYM(X86Ymm dst, X86Mem mem) => _enc.vrsqrtpsYmmMem(dst, mem);

  /// VRCPPS xmm, xmm
  void vrcppsXX(X86Xmm dst, X86Xmm src) => _enc.vrcppsXmmXmm(dst, src);
  void vrcppsXM(X86Xmm dst, X86Mem mem) => _enc.vrcppsXmmMem(dst, mem);

  /// VRCPPS ymm, ymm
  void vrcppsYY(X86Ymm dst, X86Ymm src) => _enc.vrcppsYmmYmm(dst, src);
  void vrcppsYM(X86Ymm dst, X86Mem mem) => _enc.vrcppsYmmMem(dst, mem);

  /// VSQRTSS xmm, xmm, xmm
  void vsqrtssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vsqrtssXmmXmmXmm(dst, src1, src2);
  void vsqrtssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vsqrtssXmmXmmMem(dst, src1, mem);

  /// VSQRTSD xmm, xmm, xmm
  void vsqrtsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vsqrtsdXmmXmmXmm(dst, src1, src2);
  void vsqrtsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vsqrtsdXmmXmmMem(dst, src1, mem);

  /// VMINPS xmm, xmm, xmm
  void vminpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vminpsXmmXmmXmm(dst, src1, src2);
  void vminpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vminpsXmmXmmMem(dst, src1, mem);

  /// VMINPD xmm, xmm, xmm
  void vminpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vminpdXmmXmmXmm(dst, src1, src2);
  void vminpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vminpdXmmXmmMem(dst, src1, mem);

  /// VMINPS ymm, ymm, ymm
  void vminpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vminpsYmmYmmYmm(dst, src1, src2);
  void vminpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vminpsYmmYmmMem(dst, src1, mem);

  /// VMINPD ymm, ymm, ymm
  void vminpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vminpdYmmYmmYmm(dst, src1, src2);
  void vminpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vminpdYmmYmmMem(dst, src1, mem);

  /// VMINSS xmm, xmm, xmm
  void vminssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vminssXmmXmmXmm(dst, src1, src2);
  void vminssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vminssXmmXmmMem(dst, src1, mem);

  /// VMINSD xmm, xmm, xmm
  void vminsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vminsdXmmXmmXmm(dst, src1, src2);
  void vminsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vminsdXmmXmmMem(dst, src1, mem);

  /// VMAXPS xmm, xmm, xmm
  void vmaxpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vmaxpsXmmXmmXmm(dst, src1, src2);
  void vmaxpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vmaxpsXmmXmmMem(dst, src1, mem);

  /// VMAXPD xmm, xmm, xmm
  void vmaxpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vmaxpdXmmXmmXmm(dst, src1, src2);
  void vmaxpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vmaxpdXmmXmmMem(dst, src1, mem);

  /// VMAXPS ymm, ymm, ymm
  void vmaxpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vmaxpsYmmYmmYmm(dst, src1, src2);
  void vmaxpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vmaxpsYmmYmmMem(dst, src1, mem);

  /// VMAXPD ymm, ymm, ymm
  void vmaxpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      _enc.vmaxpdYmmYmmYmm(dst, src1, src2);
  void vmaxpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      _enc.vmaxpdYmmYmmMem(dst, src1, mem);

  /// VMAXSS xmm, xmm, xmm
  void vmaxssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vmaxssXmmXmmXmm(dst, src1, src2);
  void vmaxssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vmaxssXmmXmmMem(dst, src1, mem);

  /// VMAXSD xmm, xmm, xmm
  void vmaxsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      _enc.vmaxsdXmmXmmXmm(dst, src1, src2);
  void vmaxsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      _enc.vmaxsdXmmXmmMem(dst, src1, mem);

  // ===========================================================================
  // AVX - Shuffle / Permute
  // ===========================================================================

  /// VSHUFPS xmm, xmm, xmm, imm8
  void vshufpsXXXI(X86Xmm dst, X86Xmm src1, X86Xmm src2, int imm8) =>
      _enc.vshufpsXmmXmmXmmImm8Corrected(dst, src1, src2, imm8);

  /// VSHUFPD xmm, xmm, xmm, imm8
  void vshufpdXXXI(X86Xmm dst, X86Xmm src1, X86Xmm src2, int imm8) =>
      _enc.vshufpdXmmXmmXmmImm8(dst, src1, src2, imm8);

  /// VPERMILPS xmm, xmm, imm8
  void vpermilpsXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.vpermilpsXmmXmmImm8(dst, src, imm8);

  /// VPERMILPD xmm, xmm, imm8
  void vpermilpdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.vpermilpdXmmXmmImm8(dst, src, imm8);

  /// VPERMD ymm, ymm, ymm (AVX2)
  void vpermdYYY(X86Ymm dst, X86Ymm idx, X86Ymm src) =>
      _enc.vpermdYmmYmmYmm(dst, idx, src);

  /// VPERMQ ymm, ymm, imm8 (AVX2)
  void vpermqYYI(X86Ymm dst, X86Ymm src, int imm8) =>
      _enc.vpermqYmmYmmImm8(dst, src, imm8);

  /// VPERM2F128 ymm, ymm, ymm, imm8
  void vperm2f128YYYI(X86Ymm dst, X86Ymm src1, X86Ymm src2, int imm8) =>
      _enc.vperm2f128YmmYmmYmmImm8(dst, src1, src2, imm8);

  /// VPERM2I128 ymm, ymm, ymm, imm8 (AVX2)
  void vperm2i128YYYI(X86Ymm dst, X86Ymm src1, X86Ymm src2, int imm8) =>
      _enc.vperm2i128YmmYmmYmmImm8(dst, src1, src2, imm8);

  // ===========================================================================
  // AVX - Insert/Extract
  // ===========================================================================

  /// VINSERTF128 ymm, ymm, xmm, imm8
  void vinsertf128YYXI(X86Ymm dst, X86Ymm src1, X86Xmm src2, int imm8) =>
      _enc.vinsertf128YmmYmmXmmImm8(dst, src1, src2, imm8);

  /// VEXTRACTF128 xmm, ymm, imm8
  void vextractf128XYI(X86Xmm dst, X86Ymm src, int imm8) =>
      _enc.vextractf128XmmYmmImm8(dst, src, imm8);

  /// VINSERTI128 ymm, ymm, xmm, imm8 (AVX2)
  void vinserti128YYXI(X86Ymm dst, X86Ymm src1, X86Xmm src2, int imm8) =>
      _enc.vinserti128YmmYmmXmmImm8(dst, src1, src2, imm8);

  /// VEXTRACTI128 xmm, ymm, imm8
  void vextracti128XYI(X86Xmm dst, X86Ymm src, int imm8) =>
      _enc.vextracti128XmmYmmImm8(dst, src, imm8);

  // ===========================================================================
  // AVX - Masked Move
  // ===========================================================================

  /// VPMASKMOVD xmm, xmm, mem (Load)
  void vpmaskmovdLoadXXM(X86Xmm dst, X86Xmm mask, X86Mem mem) =>
      _enc.vpmaskmovdLoadXmmXmmMem(dst, mask, mem);

  /// VPMASKMOVD mem, xmm, xmm (Store)
  // Note: Arguments are mem, mask, src (to match encoder logic)
  void vpmaskmovdStoreMXX(X86Mem mem, X86Xmm mask, X86Xmm src) =>
      _enc.vpmaskmovdStoreMemXmmXmm(mem, mask, src);

  // ===========================================================================
  // AVX2 - Gather Instructions
  // ===========================================================================

  /// VGATHERDPS xmm, [mem], xmm
  void vgatherdpsXMX(X86Xmm dst, X86Mem mem, X86Xmm mask) =>
      _enc.vgatherdpsXmm(dst, mem, mask);

  /// VGATHERDPS ymm, [mem], ymm
  void vgatherdpsYMY(X86Ymm dst, X86Mem mem, X86Ymm mask) =>
      _enc.vgatherdpsYmm(dst, mem, mask);

  /// VGATHERDPD xmm, [mem], xmm
  void vgatherdpdXMX(X86Xmm dst, X86Mem mem, X86Xmm mask) =>
      _enc.vgatherdpdXmm(dst, mem, mask);

  /// VGATHERDPD ymm, [mem], ymm
  void vgatherdpdYMY(X86Ymm dst, X86Mem mem, X86Ymm mask) =>
      _enc.vgatherdpdYmm(dst, mem, mask);

  /// VGATHERQPS xmm, [mem], xmm
  void vgatherqpsXMX(X86Xmm dst, X86Mem mem, X86Xmm mask) =>
      _enc.vgatherqpsXmm(dst, mem, mask);

  /// VGATHERQPS ymm, [mem], ymm
  void vgatherqpsYMY(X86Ymm dst, X86Mem mem, X86Ymm mask) =>
      _enc.vgatherqpsYmm(dst, mem, mask);

  /// VGATHERQPD xmm, [mem], xmm
  void vgatherqpdXMX(X86Xmm dst, X86Mem mem, X86Xmm mask) =>
      _enc.vgatherqpdXmm(dst, mem, mask);

  /// VGATHERQPD ymm, [mem], ymm
  void vgatherqpdYMY(X86Ymm dst, X86Mem mem, X86Ymm mask) =>
      _enc.vgatherqpdYmm(dst, mem, mask);

  // ===========================================================================
  // AVX-512 - Mask Instructions
  // ===========================================================================

  /// KMOVW k, k
  void kmovwKK(X86KReg dst, X86KReg src) => _enc.kmovwKK(dst, src);

  // ===========================================================================
  // AVX-512 - Packed arithmetic
  // ===========================================================================

  /// VPADDD zmm, zmm, zmm
  void vpadddZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      _enc.vpadddZmmZmmZmm(dst, src1, src2);

  /// VPADDD zmm, zmm, zmm {k}
  void vpadddZmmZmmZmmK(X86Zmm dst, X86Zmm src1, X86Zmm src2, X86KReg k) =>
      _enc.vpadddZmmZmmZmmK(dst, src1, src2, k);

  /// VPADDD zmm, zmm, zmm {k}{z}
  void vpadddZmmZmmZmmKz(X86Zmm dst, X86Zmm src1, X86Zmm src2, X86KReg k) =>
      _enc.vpadddZmmZmmZmmKz(dst, src1, src2, k);

  /// VPTERNLOGD zmm, zmm, zmm, imm8
  void vpternlogdZmmZmmZmmI(X86Zmm dst, X86Zmm src1, X86Zmm src2, int imm8) =>
      _enc.vpternlogdZmmZmmZmmImm8(dst, src1, src2, imm8);

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

  /// MOVDQU xmm, xmm (SSE2)
  void movdquXX(X86Xmm dst, X86Xmm src) => _enc.movdquXmmXmm(dst, src);

  /// MOVDQU xmm, [mem] (SSE2)
  void movdquXM(X86Xmm dst, X86Mem src) => _enc.movdquXmmMem(dst, src);

  /// MOVDQU [mem], xmm (SSE2)
  void movdquMX(X86Mem dst, X86Xmm src) => _enc.movdquMemXmm(dst, src);

  /// VMOVDQU xmm, [mem] (AVX)
  void vmovdquXmmMem(X86Xmm dst, X86Mem mem) => _enc.vmovdquXmmMem(dst, mem);

  /// VMOVDQU xmm, xmm (AVX)
  void vmovdquXX(X86Xmm dst, X86Xmm src) => _enc.vmovdquXmmXmm(dst, src);

  /// VMOVDQU [mem], xmm (AVX)
  void vmovdquMemXmm(X86Mem mem, X86Xmm src) => _enc.vmovdquMemXmm(mem, src);

  /// VMOVDQU ymm, [mem] (AVX)
  void vmovdquYmmMem(X86Ymm dst, X86Mem mem) => _enc.vmovdquYmmMem(dst, mem);

  /// VMOVDQU ymm, ymm (AVX)
  void vmovdquYY(X86Ymm dst, X86Ymm src) => _enc.vmovdquYmmYmm(dst, src);

  /// VMOVDQU [mem], ymm (AVX)
  void vmovdquMemYmm(X86Mem mem, X86Ymm src) => _enc.vmovdquMemYmm(mem, src);

  /// VMOVDQA xmm, [mem] (AVX)
  void vmovdqaXmmMem(X86Xmm dst, X86Mem mem) => _enc.vmovdqaXmmMem(dst, mem);

  /// VMOVDQA [mem], xmm (AVX)
  void vmovdqaMemXmm(X86Mem mem, X86Xmm src) => _enc.vmovdqaMemXmm(mem, src);

  /// VMOVDQA xmm, xmm (AVX)
  void vmovdqaXX(X86Xmm dst, X86Xmm src) => _enc.vmovdqaXmmXmm(dst, src);

  /// VMOVDQA ymm, [mem] (AVX)
  void vmovdqaYmmMem(X86Ymm dst, X86Mem mem) => _enc.vmovdqaYmmMem(dst, mem);

  /// VMOVDQA [mem], ymm (AVX)
  void vmovdqaMemYmm(X86Mem mem, X86Ymm src) => _enc.vmovdqaMemYmm(mem, src);

  /// VMOVDQA ymm, ymm (AVX)
  void vmovdqaYY(X86Ymm dst, X86Ymm src) => _enc.vmovdqaYmmYmm(dst, src);

  /// VPSHUFD xmm, xmm/m128, imm8
  void vpshufdXXX(X86Xmm dst, X86Xmm src, int imm) =>
      _enc.vpshufdXmmXmm(dst, src, imm);
  void vpshufdXXM(X86Xmm dst, X86Mem src, int imm) =>
      _enc.vpshufdXmmMem(dst, src, imm);

  /// VPSHUFD ymm, ymm/m256, imm8
  void vpshufdYYY(X86Ymm dst, X86Ymm src, int imm) =>
      _enc.vpshufdYmmYmm(dst, src, imm);
  void vpshufdYYM(X86Ymm dst, X86Mem src, int imm) =>
      _enc.vpshufdYmmMem(dst, src, imm);

  // ===========================================================================
  // SSE2 - Packed Integer Arithmetic
  // ===========================================================================

  /// PADDD xmm, xmm
  void padddXX(X86Xmm dst, X86Xmm src) => _enc.padddXmmXmm(dst, src);

  /// PADDD xmm, [mem]
  void padddXM(X86Xmm dst, X86Mem src) => _enc.padddXmmMem(dst, src);

  /// PADDB xmm, xmm
  void paddbXX(X86Xmm dst, X86Xmm src) => _enc.paddbXmmXmm(dst, src);

  /// PADDB xmm, [mem]
  void paddbXM(X86Xmm dst, X86Mem src) => _enc.paddbXmmMem(dst, src);

  /// PADDW xmm, xmm
  void paddwXX(X86Xmm dst, X86Xmm src) => _enc.paddwXmmXmm(dst, src);

  /// PADDW xmm, [mem]
  void paddwXM(X86Xmm dst, X86Mem src) => _enc.paddwXmmMem(dst, src);

  /// PADDQ xmm, xmm
  void paddqXX(X86Xmm dst, X86Xmm src) => _enc.paddqXmmXmm(dst, src);

  /// PADDQ xmm, [mem]
  void paddqXM(X86Xmm dst, X86Mem src) => _enc.paddqXmmMem(dst, src);

  /// PSUBB xmm, xmm
  void psubbXX(X86Xmm dst, X86Xmm src) => _enc.psubbXmmXmm(dst, src);

  /// PSUBB xmm, [mem]
  void psubbXM(X86Xmm dst, X86Mem src) => _enc.psubbXmmMem(dst, src);

  /// PSUBW xmm, xmm
  void psubwXX(X86Xmm dst, X86Xmm src) => _enc.psubwXmmXmm(dst, src);

  /// PSUBW xmm, [mem]
  void psubwXM(X86Xmm dst, X86Mem src) => _enc.psubwXmmMem(dst, src);

  /// PSUBD xmm, xmm
  void psubdXX(X86Xmm dst, X86Xmm src) => _enc.psubdXmmXmm(dst, src);

  /// PSUBD xmm, [mem]
  void psubdXM(X86Xmm dst, X86Mem src) => _enc.psubdXmmMem(dst, src);

  /// PSUBQ xmm, xmm
  void psubqXX(X86Xmm dst, X86Xmm src) => _enc.psubqXmmXmm(dst, src);

  /// PSUBQ xmm, [mem]
  void psubqXM(X86Xmm dst, X86Mem src) => _enc.psubqXmmMem(dst, src);

  /// PMULLW xmm, xmm
  void pmullwXX(X86Xmm dst, X86Xmm src) => _enc.pmullwXmmXmm(dst, src);

  /// PMULLW xmm, [mem]
  void pmullwXM(X86Xmm dst, X86Mem src) => _enc.pmullwXmmMem(dst, src);

  /// PMULLD xmm, xmm (SSE4.1)
  void pmulldXX(X86Xmm dst, X86Xmm src) => _enc.pmulldXmmXmm(dst, src);

  /// PMULLD xmm, [mem] (SSE4.1)
  void pmulldXM(X86Xmm dst, X86Mem src) => _enc.pmulldXmmMem(dst, src);

  /// PMULHW xmm, xmm
  void pmulhwXX(X86Xmm dst, X86Xmm src) => _enc.pmulhwXmmXmm(dst, src);

  /// PMULHW xmm, [mem]
  void pmulhwXM(X86Xmm dst, X86Mem src) => _enc.pmulhwXmmMem(dst, src);

  /// PMULHUW xmm, xmm
  void pmulhuwXX(X86Xmm dst, X86Xmm src) => _enc.pmulhuwXmmXmm(dst, src);

  /// PMULHUW xmm, [mem]
  void pmulhuwXM(X86Xmm dst, X86Mem src) => _enc.pmulhuwXmmMem(dst, src);

  /// PMADDWD xmm, xmm
  void pmaddwdXX(X86Xmm dst, X86Xmm src) => _enc.pmaddwdXmmXmm(dst, src);

  /// PMADDWD xmm, [mem]
  void pmaddwdXM(X86Xmm dst, X86Mem src) => _enc.pmaddwdXmmMem(dst, src);

  /// PMADDUBSW xmm, xmm (SSSE3)
  void pmaddubswXX(X86Xmm dst, X86Xmm src) => _enc.pmaddubswXmmXmm(dst, src);

  /// PMADDUBSW xmm, [mem] (SSSE3)
  void pmaddubswXM(X86Xmm dst, X86Mem src) => _enc.pmaddubswXmmMem(dst, src);

  /// PABSB xmm, xmm (SSSE3)
  void pabsbXX(X86Xmm dst, X86Xmm src) => _enc.pabsbXmmXmm(dst, src);

  /// PABSB xmm, [mem] (SSSE3)
  void pabsbXM(X86Xmm dst, X86Mem src) => _enc.pabsbXmmMem(dst, src);

  /// PABSW xmm, xmm (SSSE3)
  void pabswXX(X86Xmm dst, X86Xmm src) => _enc.pabswXmmXmm(dst, src);

  /// PABSW xmm, [mem] (SSSE3)
  void pabswXM(X86Xmm dst, X86Mem src) => _enc.pabswXmmMem(dst, src);

  /// PABSD xmm, xmm (SSSE3)
  void pabsdXX(X86Xmm dst, X86Xmm src) => _enc.pabsdXmmXmm(dst, src);

  /// PABSD xmm, [mem] (SSSE3)
  void pabsdXM(X86Xmm dst, X86Mem src) => _enc.pabsdXmmMem(dst, src);

  /// PSADBW xmm, xmm
  void psadbwXX(X86Xmm dst, X86Xmm src) => _enc.psadbwXmmXmm(dst, src);

  /// PSADBW xmm, [mem]
  void psadbwXM(X86Xmm dst, X86Mem src) => _enc.psadbwXmmMem(dst, src);

  // ===========================================================================
  // SSE2/SSE4.1 - Packed Integer Compare
  // ===========================================================================

  /// PCMPEQB xmm, xmm
  void pcmpeqbXX(X86Xmm dst, X86Xmm src) => _enc.pcmpeqbXmmXmm(dst, src);

  /// PCMPEQB xmm, [mem]
  void pcmpeqbXM(X86Xmm dst, X86Mem src) => _enc.pcmpeqbXmmMem(dst, src);

  /// PCMPEQW xmm, xmm
  void pcmpeqwXX(X86Xmm dst, X86Xmm src) => _enc.pcmpeqwXmmXmm(dst, src);

  /// PCMPEQW xmm, [mem]
  void pcmpeqwXM(X86Xmm dst, X86Mem src) => _enc.pcmpeqwXmmMem(dst, src);

  /// PCMPEQD xmm, xmm
  void pcmpeqdXX(X86Xmm dst, X86Xmm src) => _enc.pcmpeqdXmmXmm(dst, src);

  /// PCMPEQD xmm, [mem]
  void pcmpeqdXM(X86Xmm dst, X86Mem src) => _enc.pcmpeqdXmmMem(dst, src);

  /// PCMPEQQ xmm, xmm (SSE4.1)
  void pcmpeqqXX(X86Xmm dst, X86Xmm src) => _enc.pcmpeqqXmmXmm(dst, src);

  /// PCMPEQQ xmm, [mem] (SSE4.1)
  void pcmpeqqXM(X86Xmm dst, X86Mem src) => _enc.pcmpeqqXmmMem(dst, src);

  /// PCMPGTB xmm, xmm
  void pcmpgtbXX(X86Xmm dst, X86Xmm src) => _enc.pcmpgtbXmmXmm(dst, src);

  /// PCMPGTB xmm, [mem]
  void pcmpgtbXM(X86Xmm dst, X86Mem src) => _enc.pcmpgtbXmmMem(dst, src);

  /// PCMPGTW xmm, xmm
  void pcmpgtwXX(X86Xmm dst, X86Xmm src) => _enc.pcmpgtwXmmXmm(dst, src);

  /// PCMPGTW xmm, [mem]
  void pcmpgtwXM(X86Xmm dst, X86Mem src) => _enc.pcmpgtwXmmMem(dst, src);

  /// PCMPGTD xmm, xmm
  void pcmpgtdXX(X86Xmm dst, X86Xmm src) => _enc.pcmpgtdXmmXmm(dst, src);

  /// PCMPGTD xmm, [mem]
  void pcmpgtdXM(X86Xmm dst, X86Mem src) => _enc.pcmpgtdXmmMem(dst, src);

  /// PCMPGTQ xmm, xmm (SSE4.2)
  void pcmpgtqXX(X86Xmm dst, X86Xmm src) => _enc.pcmpgtqXmmXmm(dst, src);

  /// PCMPGTQ xmm, [mem] (SSE4.2)
  void pcmpgtqXM(X86Xmm dst, X86Mem src) => _enc.pcmpgtqXmmMem(dst, src);

  // ===========================================================================
  // SSE2/SSE4.1 - Packed Integer Min/Max
  // ===========================================================================

  /// PMINUB xmm, xmm
  void pminubXX(X86Xmm dst, X86Xmm src) => _enc.pminubXmmXmm(dst, src);

  /// PMINUB xmm, [mem]
  void pminubXM(X86Xmm dst, X86Mem src) => _enc.pminubXmmMem(dst, src);

  /// PMAXUB xmm, xmm
  void pmaxubXX(X86Xmm dst, X86Xmm src) => _enc.pmaxubXmmXmm(dst, src);

  /// PMAXUB xmm, [mem]
  void pmaxubXM(X86Xmm dst, X86Mem src) => _enc.pmaxubXmmMem(dst, src);

  /// PMINSW xmm, xmm
  void pminswXX(X86Xmm dst, X86Xmm src) => _enc.pminswXmmXmm(dst, src);

  /// PMINSW xmm, [mem]
  void pminswXM(X86Xmm dst, X86Mem src) => _enc.pminswXmmMem(dst, src);

  /// PMAXSW xmm, xmm
  void pmaxswXX(X86Xmm dst, X86Xmm src) => _enc.pmaxswXmmXmm(dst, src);

  /// PMAXSW xmm, [mem]
  void pmaxswXM(X86Xmm dst, X86Mem src) => _enc.pmaxswXmmMem(dst, src);

  /// PMINUD xmm, xmm (SSE4.1)
  void pminudXX(X86Xmm dst, X86Xmm src) => _enc.pminudXmmXmm(dst, src);

  /// PMINUD xmm, [mem] (SSE4.1)
  void pminudXM(X86Xmm dst, X86Mem src) => _enc.pminudXmmMem(dst, src);

  /// PMAXUD xmm, xmm (SSE4.1)
  void pmaxudXX(X86Xmm dst, X86Xmm src) => _enc.pmaxudXmmXmm(dst, src);

  /// PMAXUD xmm, [mem] (SSE4.1)
  void pmaxudXM(X86Xmm dst, X86Mem src) => _enc.pmaxudXmmMem(dst, src);

  /// PMINSD xmm, xmm (SSE4.1)
  void pminsdXX(X86Xmm dst, X86Xmm src) => _enc.pminsdXmmXmm(dst, src);

  /// PMINSD xmm, [mem] (SSE4.1)
  void pminsdXM(X86Xmm dst, X86Mem src) => _enc.pminsdXmmMem(dst, src);

  /// PMAXSD xmm, xmm (SSE4.1)
  void pmaxsdXX(X86Xmm dst, X86Xmm src) => _enc.pmaxsdXmmXmm(dst, src);

  /// PMAXSD xmm, [mem] (SSE4.1)
  void pmaxsdXM(X86Xmm dst, X86Mem src) => _enc.pmaxsdXmmMem(dst, src);

  // ===========================================================================
  // SSE2 - Packed Integer Shift
  // ===========================================================================

  /// PSLLW xmm, xmm
  void psllwXX(X86Xmm dst, X86Xmm src) => _enc.psllwXmmXmm(dst, src);

  /// PSLLW xmm, imm8
  void psllwXI(X86Xmm dst, int imm8) => _enc.psllwXmmImm8(dst, imm8);

  /// PSLLD xmm, xmm
  void pslldXX(X86Xmm dst, X86Xmm src) => _enc.pslldXmmXmm(dst, src);

  /// PSLLD xmm, imm8
  void pslldXI(X86Xmm dst, int imm8) => _enc.pslldXmmImm8(dst, imm8);

  /// PSLLQ xmm, xmm
  void psllqXX(X86Xmm dst, X86Xmm src) => _enc.psllqXmmXmm(dst, src);

  /// PSLLQ xmm, imm8
  void psllqXI(X86Xmm dst, int imm8) => _enc.psllqXmmImm8(dst, imm8);

  /// PSRLW xmm, xmm
  void psrlwXX(X86Xmm dst, X86Xmm src) => _enc.psrlwXmmXmm(dst, src);

  /// PSRLW xmm, imm8
  void psrlwXI(X86Xmm dst, int imm8) => _enc.psrlwXmmImm8(dst, imm8);

  /// PSRLD xmm, xmm
  void psrldXX(X86Xmm dst, X86Xmm src) => _enc.psrldXmmXmm(dst, src);

  /// PSRLD xmm, imm8
  void psrldXI(X86Xmm dst, int imm8) => _enc.psrldXmmImm8(dst, imm8);

  /// VPSLLD xmm, xmm, imm8 (AVX)
  void vpslld(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.vpslldXmmXmmImm8(dst, src, imm8);

  /// VPSRLD xmm, xmm, imm8 (AVX)
  void vpsrld(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.vpsrldXmmXmmImm8(dst, src, imm8);

  /// VPSHUFD xmm, xmm, imm8 (AVX)
  void vpshufd(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.vpshufdXmmXmmImm8(dst, src, imm8);

  /// PSRLQ xmm, xmm
  void psrlqXX(X86Xmm dst, X86Xmm src) => _enc.psrlqXmmXmm(dst, src);

  /// PSRLQ xmm, imm8
  void psrlqXI(X86Xmm dst, int imm8) => _enc.psrlqXmmImm8(dst, imm8);

  /// PSRAW xmm, xmm
  void psrawXX(X86Xmm dst, X86Xmm src) => _enc.psrawXmmXmm(dst, src);

  /// PSRAW xmm, imm8
  void psrawXI(X86Xmm dst, int imm8) => _enc.psrawXmmImm8(dst, imm8);

  /// PSRAD xmm, xmm
  void psradXX(X86Xmm dst, X86Xmm src) => _enc.psradXmmXmm(dst, src);

  /// PSRAD xmm, imm8
  void psradXI(X86Xmm dst, int imm8) => _enc.psradXmmImm8(dst, imm8);

  /// PSLLDQ xmm, imm8 (byte shift left)
  void pslldqXI(X86Xmm dst, int imm8) => _enc.pslldqXmmImm8(dst, imm8);

  /// PSRLDQ xmm, imm8 (byte shift right)
  void psrldqXI(X86Xmm dst, int imm8) => _enc.psrldqXmmImm8(dst, imm8);

  // ===========================================================================
  // SSE2/SSE4.1 - Packed Integer Logic
  // ===========================================================================

  /// PAND xmm, xmm
  void pandXX(X86Xmm dst, X86Xmm src) => _enc.pandXmmXmm(dst, src);

  /// PAND xmm, [mem]
  void pandXM(X86Xmm dst, X86Mem src) => _enc.pandXmmMem(dst, src);

  /// PANDN xmm, xmm
  void pandnXX(X86Xmm dst, X86Xmm src) => _enc.pandnXmmXmm(dst, src);

  /// PANDN xmm, [mem]
  void pandnXM(X86Xmm dst, X86Mem src) => _enc.pandnXmmMem(dst, src);

  // POR and PXOR are already implemented as porXX/porXM and pxorXX/pxorXM

  // ===========================================================================
  // SSE2/SSE4.1 - Pack/Unpack
  // ===========================================================================

  /// PACKSSWB xmm, xmm
  void packsswbXX(X86Xmm dst, X86Xmm src) => _enc.packsswbXmmXmm(dst, src);

  /// PACKSSWB xmm, [mem]
  void packsswbXM(X86Xmm dst, X86Mem src) => _enc.packsswbXmmMem(dst, src);

  /// PACKSSDW xmm, xmm
  void packssdwXX(X86Xmm dst, X86Xmm src) => _enc.packssdwXmmXmm(dst, src);

  /// PACKSSDW xmm, [mem]
  void packssdwXM(X86Xmm dst, X86Mem src) => _enc.packssdwXmmMem(dst, src);

  /// PACKUSWB xmm, xmm
  void packuswbXX(X86Xmm dst, X86Xmm src) => _enc.packuswbXmmXmm(dst, src);

  /// PACKUSWB xmm, [mem]
  void packuswbXM(X86Xmm dst, X86Mem src) => _enc.packuswbXmmMem(dst, src);

  /// PACKUSDW xmm, xmm (SSE4.1)
  void packusdwXX(X86Xmm dst, X86Xmm src) => _enc.packusdwXmmXmm(dst, src);

  /// PACKUSDW xmm, [mem] (SSE4.1)
  void packusdwXM(X86Xmm dst, X86Mem src) => _enc.packusdwXmmMem(dst, src);

  /// PUNPCKLBW xmm, xmm
  void punpcklbwXX(X86Xmm dst, X86Xmm src) => _enc.punpcklbwXmmXmm(dst, src);

  /// PUNPCKLBW xmm, [mem]
  void punpcklbwXM(X86Xmm dst, X86Mem src) => _enc.punpcklbwXmmMem(dst, src);

  /// PUNPCKLWD xmm, xmm
  void punpcklwdXX(X86Xmm dst, X86Xmm src) => _enc.punpcklwdXmmXmm(dst, src);

  /// PUNPCKLWD xmm, [mem]
  void punpcklwdXM(X86Xmm dst, X86Mem src) => _enc.punpcklwdXmmMem(dst, src);

  /// PUNPCKLDQ xmm, xmm
  void punpckldqXX(X86Xmm dst, X86Xmm src) => _enc.punpckldqXmmXmm(dst, src);

  /// PUNPCKLDQ xmm, [mem]
  void punpckldqXM(X86Xmm dst, X86Mem src) => _enc.punpckldqXmmMem(dst, src);

  /// PUNPCKLQDQ xmm, xmm
  void punpcklqdqXX(X86Xmm dst, X86Xmm src) => _enc.punpcklqdqXmmXmm(dst, src);

  /// PUNPCKLQDQ xmm, [mem]
  void punpcklqdqXM(X86Xmm dst, X86Mem src) => _enc.punpcklqdqXmmMem(dst, src);

  /// PUNPCKHBW xmm, xmm
  void punpckhbwXX(X86Xmm dst, X86Xmm src) => _enc.punpckhbwXmmXmm(dst, src);

  /// PUNPCKHBW xmm, [mem]
  void punpckhbwXM(X86Xmm dst, X86Mem src) => _enc.punpckhbwXmmMem(dst, src);

  /// PUNPCKHWD xmm, xmm
  void punpckhwdXX(X86Xmm dst, X86Xmm src) => _enc.punpckhwdXmmXmm(dst, src);

  /// PUNPCKHWD xmm, [mem]
  void punpckhwdXM(X86Xmm dst, X86Mem src) => _enc.punpckhwdXmmMem(dst, src);

  /// PUNPCKHDQ xmm, xmm
  void punpckhdqXX(X86Xmm dst, X86Xmm src) => _enc.punpckhdqXmmXmm(dst, src);

  /// PUNPCKHDQ xmm, [mem]
  void punpckhdqXM(X86Xmm dst, X86Mem src) => _enc.punpckhdqXmmMem(dst, src);

  /// PUNPCKHQDQ xmm, xmm
  void punpckhqdqXX(X86Xmm dst, X86Xmm src) => _enc.punpckhqdqXmmXmm(dst, src);

  /// PUNPCKHQDQ xmm, [mem]
  void punpckhqdqXM(X86Xmm dst, X86Mem src) => _enc.punpckhqdqXmmMem(dst, src);

  // ===========================================================================
  // SSE2/SSSE3 - Shuffle and Align
  // ===========================================================================

  /// PSHUFD xmm, xmm, imm8
  void pshufdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.pshufdXmmXmmImm8(dst, src, imm8);

  /// PSHUFD xmm, [mem], imm8
  void pshufdXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.pshufdXmmMemImm8(dst, src, imm8);

  /// PSHUFB xmm, xmm (SSSE3)
  void pshufbXX(X86Xmm dst, X86Xmm src) => _enc.pshufbXmmXmm(dst, src);

  /// PSHUFB xmm, [mem] (SSSE3)
  void pshufbXM(X86Xmm dst, X86Mem src) => _enc.pshufbXmmMem(dst, src);

  /// PSHUFLW xmm, xmm, imm8
  void pshuflwXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.pshuflwXmmXmmImm8(dst, src, imm8);

  /// PSHUFLW xmm, [mem], imm8
  void pshuflwXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.pshuflwXmmMemImm8(dst, src, imm8);

  /// PSHUFHW xmm, xmm, imm8
  void pshufhwXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.pshufhwXmmXmmImm8(dst, src, imm8);

  /// PSHUFHW xmm, [mem], imm8
  void pshufhwXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.pshufhwXmmMemImm8(dst, src, imm8);

  /// PALIGNR xmm, xmm, imm8 (SSSE3)
  void palignrXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.palignrXmmXmmImm8(dst, src, imm8);

  /// PALIGNR xmm, [mem], imm8 (SSSE3)
  void palignrXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.palignrXmmMemImm8(dst, src, imm8);

  // ===========================================================================
  // SSE4.1 - Packed Integer Extend
  // ===========================================================================

  void pmovzxbwXX(X86Xmm dst, X86Xmm src) => _enc.pmovzxbwXmmXmm(dst, src);
  void pmovzxbwXM(X86Xmm dst, X86Mem src) => _enc.pmovzxbwXmmMem(dst, src);

  void pmovzxbdXX(X86Xmm dst, X86Xmm src) => _enc.pmovzxbdXmmXmm(dst, src);
  void pmovzxbdXM(X86Xmm dst, X86Mem src) => _enc.pmovzxbdXmmMem(dst, src);

  void pmovzxbqXX(X86Xmm dst, X86Xmm src) => _enc.pmovzxbqXmmXmm(dst, src);
  void pmovzxbqXM(X86Xmm dst, X86Mem src) => _enc.pmovzxbqXmmMem(dst, src);

  void pmovzxwdXX(X86Xmm dst, X86Xmm src) => _enc.pmovzxwdXmmXmm(dst, src);
  void pmovzxwdXM(X86Xmm dst, X86Mem src) => _enc.pmovzxwdXmmMem(dst, src);

  void pmovzxwqXX(X86Xmm dst, X86Xmm src) => _enc.pmovzxwqXmmXmm(dst, src);
  void pmovzxwqXM(X86Xmm dst, X86Mem src) => _enc.pmovzxwqXmmMem(dst, src);

  void pmovzxdqXX(X86Xmm dst, X86Xmm src) => _enc.pmovzxdqXmmXmm(dst, src);
  void pmovzxdqXM(X86Xmm dst, X86Mem src) => _enc.pmovzxdqXmmMem(dst, src);

  void pmovsxbwXX(X86Xmm dst, X86Xmm src) => _enc.pmovsxbwXmmXmm(dst, src);
  void pmovsxbwXM(X86Xmm dst, X86Mem src) => _enc.pmovsxbwXmmMem(dst, src);

  void pmovsxbdXX(X86Xmm dst, X86Xmm src) => _enc.pmovsxbdXmmXmm(dst, src);
  void pmovsxbdXM(X86Xmm dst, X86Mem src) => _enc.pmovsxbdXmmMem(dst, src);

  void pmovsxbqXX(X86Xmm dst, X86Xmm src) => _enc.pmovsxbqXmmXmm(dst, src);
  void pmovsxbqXM(X86Xmm dst, X86Mem src) => _enc.pmovsxbqXmmMem(dst, src);

  void pmovsxwdXX(X86Xmm dst, X86Xmm src) => _enc.pmovsxwdXmmXmm(dst, src);
  void pmovsxwdXM(X86Xmm dst, X86Mem src) => _enc.pmovsxwdXmmMem(dst, src);

  void pmovsxwqXX(X86Xmm dst, X86Xmm src) => _enc.pmovsxwqXmmXmm(dst, src);
  void pmovsxwqXM(X86Xmm dst, X86Mem src) => _enc.pmovsxwqXmmMem(dst, src);

  void pmovsxdqXX(X86Xmm dst, X86Xmm src) => _enc.pmovsxdqXmmXmm(dst, src);
  void pmovsxdqXM(X86Xmm dst, X86Mem src) => _enc.pmovsxdqXmmMem(dst, src);

  // ===========================================================================
  // SSE4.1 - Insert/Extract
  // ===========================================================================

  void pinsrbR(X86Xmm dst, X86Gp src, int imm8) =>
      _enc.pinsrbXmmRegImm8(dst, src, imm8);
  void pinsrbM(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.pinsrbXmmMemImm8(dst, src, imm8);

  void pinsrdR(X86Xmm dst, X86Gp src, int imm8) =>
      _enc.pinsrdXmmRegImm8(dst, src, imm8);
  void pinsrdM(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.pinsrdXmmMemImm8(dst, src, imm8);

  void pinsrqR(X86Xmm dst, X86Gp src, int imm8) =>
      _enc.pinsrqXmmRegImm8(dst, src, imm8);
  void pinsrqM(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.pinsrqXmmMemImm8(dst, src, imm8);

  void pextrbR(X86Gp dst, X86Xmm src, int imm8) =>
      _enc.pextrbRegXmmImm8(dst, src, imm8);
  void pextrbM(X86Mem dst, X86Xmm src, int imm8) =>
      _enc.pextrbMemXmmImm8(dst, src, imm8);

  void pextrdR(X86Gp dst, X86Xmm src, int imm8) =>
      _enc.pextrdRegXmmImm8(dst, src, imm8);
  void pextrdM(X86Mem dst, X86Xmm src, int imm8) =>
      _enc.pextrdMemXmmImm8(dst, src, imm8);

  void pextrqR(X86Gp dst, X86Xmm src, int imm8) =>
      _enc.pextrqRegXmmImm8(dst, src, imm8);
  void pextrqM(X86Mem dst, X86Xmm src, int imm8) =>
      _enc.pextrqMemXmmImm8(dst, src, imm8);

  // ===========================================================================
  // SSE4.1 - Blend
  // ===========================================================================

  void pblendwXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.pblendwXmmXmmImm8(dst, src, imm8);
  void pblendwXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.pblendwXmmMemImm8(dst, src, imm8);

  void pblendvbXX(X86Xmm dst, X86Xmm src) => _enc.pblendvbXmmXmm(dst, src);
  void pblendvbXM(X86Xmm dst, X86Mem src) => _enc.pblendvbXmmMem(dst, src);

  void blendpsXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.blendpsXmmXmmImm8(dst, src, imm8);
  void blendpsXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.blendpsXmmMemImm8(dst, src, imm8);

  /// POR xmm, xmm
  void porXX(X86Xmm dst, X86Xmm src) => _enc.porXmmXmm(dst, src);

  /// POR xmm, [mem]
  void porXM(X86Xmm dst, X86Mem src) => _enc.porXmmMem(dst, src);

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

  // ===========================================================================
  // SSE4.1 - Blend (Variable)
  // ===========================================================================

  void blendvpsXX(X86Xmm dst, X86Xmm src) => _enc.blendvpsXmmXmm(dst, src);
  void blendvpsXM(X86Xmm dst, X86Mem src) => _enc.blendvpsXmmMem(dst, src);

  void blendvpdXX(X86Xmm dst, X86Xmm src) => _enc.blendvpdXmmXmm(dst, src);
  void blendvpdXM(X86Xmm dst, X86Mem src) => _enc.blendvpdXmmMem(dst, src);

  // ===========================================================================
  // SSE4.1 - Insert/Extract (Remaining)
  // ===========================================================================

  void pextrwRX(X86Gp dst, X86Xmm src, int imm8) =>
      _enc.pextrwRegXmmImm8(dst, src, imm8);
  void pextrwMX(X86Mem dst, X86Xmm src, int imm8) =>
      _enc.pextrwMemXmmImm8(dst, src, imm8);

  void pinsrwXR(X86Xmm dst, X86Gp src, int imm8) =>
      _enc.pinsrwXmmRegImm8(dst, src, imm8);
  void pinsrwXM(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.pinsrwXmmMemImm8(dst, src, imm8);

  void insertpsXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      _enc.insertpsXmmXmmImm8(dst, src, imm8);
  void insertpsXMI(X86Xmm dst, X86Mem src, int imm8) =>
      _enc.insertpsXmmMemImm8(dst, src, imm8);

  void extractpsRX(X86Gp dst, X86Xmm src, int imm8) =>
      _enc.extractpsRegXmmImm8(dst, src, imm8);
  void extractpsMX(X86Mem dst, X86Xmm src, int imm8) =>
      _enc.extractpsMemXmmImm8(dst, src, imm8);

  // ===========================================================================
  // AVX-512 Mask Operations (k*)
  // ===========================================================================

  void kandb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandb, [k1, k2, k3]);
  void kandw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandw, [k1, k2, k3]);
  void kandd(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandd, [k1, k2, k3]);
  void kandq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandq, [k1, k2, k3]);

  void kandnb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandnb, [k1, k2, k3]);
  void kandnw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandnw, [k1, k2, k3]);
  void kandnd(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandnd, [k1, k2, k3]);
  void kandnq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandnq, [k1, k2, k3]);

  void korb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKorb, [k1, k2, k3]);
  void korw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKorw, [k1, k2, k3]);
  void kord(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKord, [k1, k2, k3]);
  void korq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKorq, [k1, k2, k3]);

  void kxnorb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxnorb, [k1, k2, k3]);
  void kxnorw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxnorw, [k1, k2, k3]);
  void kxnord(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxnord, [k1, k2, k3]);
  void kxnorq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxnorq, [k1, k2, k3]);

  void kxorb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxorb, [k1, k2, k3]);
  void kxorw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxorw, [k1, k2, k3]);
  void kxord(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxord, [k1, k2, k3]);
  void kxorq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxorq, [k1, k2, k3]);

  void kmovb(Object dst, Object src) => emit(X86InstId.kKmovb, [dst, src]);
  void kmovw(Object dst, Object src) => emit(X86InstId.kKmovw, [dst, src]);
  void kmovd(Object dst, Object src) => emit(X86InstId.kKmovd, [dst, src]);
  void kmovq(Object dst, Object src) => emit(X86InstId.kKmovq, [dst, src]);

  void knotb(X86KReg dst, X86KReg src) => emit(X86InstId.kKnotb, [dst, src]);
  void knotw(X86KReg dst, X86KReg src) => emit(X86InstId.kKnotw, [dst, src]);
  void knotd(X86KReg dst, X86KReg src) => emit(X86InstId.kKnotd, [dst, src]);
  void knotq(X86KReg dst, X86KReg src) => emit(X86InstId.kKnotq, [dst, src]);

  // ===========================================================================
  // AVX-512 Zero/Sign Extension
  // ===========================================================================

  void vpmovzxbd(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxbd, [dst, src]);
  void vpmovzxbq(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxbq, [dst, src]);
  void vpmovzxbw(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxbw, [dst, src]);
  void vpmovzxdq(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxdq, [dst, src]);
  void vpmovzxwd(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxwd, [dst, src]);
  void vpmovzxwq(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxwq, [dst, src]);

  void vpmovsxbd(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxbd, [dst, src]);
  void vpmovsxbq(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxbq, [dst, src]);
  void vpmovsxbw(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxbw, [dst, src]);
  void vpmovsxdq(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxdq, [dst, src]);
  void vpmovsxwd(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxwd, [dst, src]);
  void vpmovsxwq(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxwq, [dst, src]);

  // ===========================================================================
  // SSE4.1 Rounding Instructions
  // ===========================================================================

  /// ROUNDPS xmm, xmm/m128, imm8 - Round packed single-precision values.
  /// imm8: 0=round to nearest, 1=floor, 2=ceil, 3=truncate
  void roundps(Object dst, Object src, int imm8) =>
      emit(X86InstId.kRoundps, [dst, src, Imm(imm8)]);

  /// ROUNDPD xmm, xmm/m128, imm8 - Round packed double-precision values.
  void roundpd(Object dst, Object src, int imm8) =>
      emit(X86InstId.kRoundpd, [dst, src, Imm(imm8)]);

  /// ROUNDSS xmm, xmm/m32, imm8 - Round scalar single-precision value.
  void roundss(Object dst, Object src, int imm8) =>
      emit(X86InstId.kRoundss, [dst, src, Imm(imm8)]);

  /// ROUNDSD xmm, xmm/m64, imm8 - Round scalar double-precision value.
  void roundsd(Object dst, Object src, int imm8) =>
      emit(X86InstId.kRoundsd, [dst, src, Imm(imm8)]);

  /// VROUNDPS - AVX version of ROUNDPS.
  void vroundps(Object dst, Object src, int imm8) =>
      emit(X86InstId.kVroundps, [dst, src, Imm(imm8)]);

  /// VROUNDPD - AVX version of ROUNDPD.
  void vroundpd(Object dst, Object src, int imm8) =>
      emit(X86InstId.kVroundpd, [dst, src, Imm(imm8)]);

  /// VROUNDSS - AVX version of ROUNDSS.
  void vroundss(Object dst, Object src1, Object src2, int imm8) =>
      emit(X86InstId.kVroundss, [dst, src1, src2, Imm(imm8)]);

  /// VROUNDSD - AVX version of ROUNDSD.
  void vroundsd(Object dst, Object src1, Object src2, int imm8) =>
      emit(X86InstId.kVroundsd, [dst, src1, src2, Imm(imm8)]);
}

extension FuncFrameX86Extensions on FuncFrame {
  /// Returns the GP register used for function arguments.
  X86Gp getArgReg(int index, [CallingConvention? cc]) {
    final regId = getArgRegId(index, cc);
    if (regId == Reg.kIdBad) {
      throw RangeError.index(index, null, 'index');
    }
    return X86Gp.r64(regId);
  }
}
