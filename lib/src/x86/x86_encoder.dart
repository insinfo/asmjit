/// AsmJit x86/x64 Instruction Encoder
///
/// Low-level x86/x64 instruction encoding.
/// Ported from asmjit/x86/x86assembler.cpp (encoding parts)

import '../core/code_buffer.dart';
import 'x86.dart';
import 'x86_operands.dart';

/// x86/x64 instruction encoder.
///
/// Provides low-level methods for encoding x86/x64 instructions.
class X86Encoder {
  /// The code buffer to emit to.
  final CodeBuffer buffer;

  X86Encoder(this.buffer);

  // ===========================================================================
  // Prefix encoding
  // ===========================================================================

  /// Emits a REX prefix if needed.
  ///
  /// REX prefix format: 0100 WRXB
  /// - W: 64-bit operand size
  /// - R: Extension of ModR/M reg field
  /// - X: Extension of SIB index field
  /// - B: Extension of ModR/M r/m, SIB base, or opcode reg field
  void emitRex(bool w, bool r, bool x, bool b) {
    final rex = 0x40 |
        (w ? 0x08 : 0) |
        (r ? 0x04 : 0) |
        (x ? 0x02 : 0) |
        (b ? 0x01 : 0);
    buffer.emit8(rex);
  }

  /// Emits a REX prefix for a single register operand.
  void emitRexForReg(X86Gp reg, {bool w = false}) {
    final needsRex = w || reg.isExtended;
    if (needsRex) {
      emitRex(w, false, false, reg.isExtended);
    }
  }

  /// Emits a REX prefix for two register operands (reg, r/m).
  void emitRexForRegRm(X86Gp reg, X86Gp rm, {bool w = false}) {
    final needsRex = w || reg.isExtended || rm.isExtended;
    if (needsRex) {
      emitRex(w, reg.isExtended, false, rm.isExtended);
    }
  }

  /// Emits a REX prefix for a register and memory operand.
  void emitRexForRegMem(X86Gp reg, X86Mem mem, {bool w = false}) {
    final baseExt = mem.base?.isExtended ?? false;
    final indexExt = mem.index?.isExtended ?? false;
    final needsRex = w || reg.isExtended || baseExt || indexExt;
    if (needsRex) {
      emitRex(w, reg.isExtended, indexExt, baseExt);
    }
  }

  // ===========================================================================
  // ModR/M and SIB encoding
  // ===========================================================================

  /// Emits a ModR/M byte.
  ///
  /// ModR/M format: mod(2) reg(3) rm(3)
  void emitModRm(int mod, int reg, int rm) {
    buffer.emit8(((mod & 0x3) << 6) | ((reg & 0x7) << 3) | (rm & 0x7));
  }

  /// Emits a SIB byte.
  ///
  /// SIB format: scale(2) index(3) base(3)
  void emitSib(int scale, int index, int base) {
    buffer.emit8(((scale & 0x3) << 6) | ((index & 0x7) << 3) | (base & 0x7));
  }

  /// Encodes scale factor to SIB scale bits.
  int encodeScale(int scale) {
    switch (scale) {
      case 1:
        return 0;
      case 2:
        return 1;
      case 4:
        return 2;
      case 8:
        return 3;
      default:
        throw ArgumentError('Invalid scale: $scale');
    }
  }

  /// Emits ModR/M for register-to-register.
  void emitModRmReg(int regOp, X86Gp rm) {
    emitModRm(3, regOp, rm.encoding);
  }

  /// Emits ModR/M and optional SIB/displacement for memory operand.
  void emitModRmMem(int regOp, X86Mem mem) {
    final base = mem.base;
    final index = mem.index;
    final disp = mem.displacement;

    // Special case: no base or index (absolute address)
    if (base == null && index == null) {
      // [disp32] - use SIB form with no base/index
      emitModRm(0, regOp, 4); // r/m = 4 means SIB follows
      emitSib(0, 4, 5); // index=4(none), base=5(disp32)
      buffer.emit32(disp);
      return;
    }

    // Determine if we need SIB
    final needsSib = index != null ||
        (base != null &&
            (base.encoding == 4 || base.encoding == 12)); // RSP/R12

    // Determine displacement size
    int mod;
    if (disp == 0 &&
        base != null &&
        base.encoding != 5 &&
        base.encoding != 13) {
      // No displacement needed (unless base is RBP/R13)
      mod = 0;
    } else if (mem.dispFitsI8) {
      mod = 1; // disp8
    } else {
      mod = 2; // disp32
    }

    // Special case: RBP/R13 with no displacement still needs disp8=0
    if (base != null &&
        (base.encoding == 5 || base.encoding == 13) &&
        disp == 0) {
      mod = 1;
    }

    if (needsSib) {
      emitModRm(mod, regOp, 4); // r/m = 4 means SIB follows

      final baseEnc = base?.encoding ?? 5; // 5 = no base (disp32)
      final indexEnc = index?.encoding ?? 4; // 4 = no index
      final scaleEnc = index != null ? encodeScale(mem.scale) : 0;

      emitSib(scaleEnc, indexEnc, baseEnc);
    } else {
      emitModRm(mod, regOp, base!.encoding);
    }

    // Emit displacement
    if (mod == 1) {
      buffer.emit8(disp);
    } else if (mod == 2 || (base == null && index == null)) {
      buffer.emit32(disp);
    }
  }

  // ===========================================================================
  // Common instructions
  // ===========================================================================

  /// RET - Return from procedure.
  void ret() {
    buffer.emit8(0xC3);
  }

  /// RET imm16 - Return and pop imm16 bytes.
  void retImm(int imm16) {
    buffer.emit8(0xC2);
    buffer.emit16(imm16);
  }

  /// NOP - No operation.
  void nop() {
    buffer.emit8(0x90);
  }

  /// Multi-byte NOP.
  void nopN(int bytes) {
    // Use optimized multi-byte NOP sequences
    while (bytes > 0) {
      switch (bytes) {
        case 1:
          buffer.emit8(0x90);
          bytes -= 1;
        case 2:
          buffer.emitBytes([0x66, 0x90]);
          bytes -= 2;
        case 3:
          buffer.emitBytes([0x0F, 0x1F, 0x00]);
          bytes -= 3;
        case 4:
          buffer.emitBytes([0x0F, 0x1F, 0x40, 0x00]);
          bytes -= 4;
        case 5:
          buffer.emitBytes([0x0F, 0x1F, 0x44, 0x00, 0x00]);
          bytes -= 5;
        case 6:
          buffer.emitBytes([0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00]);
          bytes -= 6;
        case 7:
          buffer.emitBytes([0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00]);
          bytes -= 7;
        case 8:
          buffer.emitBytes([0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00]);
          bytes -= 8;
        default:
          buffer.emitBytes(
              [0x66, 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00]);
          bytes -= 9;
      }
    }
  }

  /// INT3 - Breakpoint.
  void int3() {
    buffer.emit8(0xCC);
  }

  /// INT imm8 - Interrupt.
  void intN(int n) {
    buffer.emit8(0xCD);
    buffer.emit8(n);
  }

  // ===========================================================================
  // MOV instructions
  // ===========================================================================

  /// MOV r64, r64
  void movR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x89);
    emitModRmReg(src.encoding, dst);
  }

  /// MOV r32, r32
  void movR32R32(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst);
    buffer.emit8(0x89);
    emitModRmReg(src.encoding, dst);
  }

  /// MOV r64, imm64
  void movR64Imm64(X86Gp dst, int imm64) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0xB8 + dst.encoding);
    buffer.emit64(imm64);
  }

  /// MOV r64, imm32 (sign-extended)
  void movR64Imm32(X86Gp dst, int imm32) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0xC7);
    emitModRmReg(0, dst);
    buffer.emit32(imm32);
  }

  /// MOV r32, imm32
  void movR32Imm32(X86Gp dst, int imm32) {
    if (dst.isExtended) {
      emitRex(false, false, false, true);
    }
    buffer.emit8(0xB8 + dst.encoding);
    buffer.emit32(imm32);
  }

  /// MOV r64, [mem]
  void movR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x8B);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOV [mem], r64
  void movMemR64(X86Mem mem, X86Gp src) {
    emitRexForRegMem(src, mem, w: true);
    buffer.emit8(0x89);
    emitModRmMem(src.encoding, mem);
  }

  // ===========================================================================
  // Arithmetic instructions
  // ===========================================================================

  /// ADD r64, r64
  void addR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x01);
    emitModRmReg(src.encoding, dst);
  }

  /// ADD r32, r32
  void addR32R32(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst);
    buffer.emit8(0x01);
    emitModRmReg(src.encoding, dst);
  }

  /// ADD r64, imm32
  void addR64Imm32(X86Gp dst, int imm32) {
    emitRexForReg(dst, w: true);
    if (dst.encoding == 0) {
      // ADD RAX, imm32 has a short form
      buffer.emit8(0x05);
    } else {
      buffer.emit8(0x81);
      emitModRmReg(0, dst);
    }
    buffer.emit32(imm32);
  }

  /// ADD r64, imm8
  void addR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(0, dst);
    buffer.emit8(imm8);
  }

  /// SUB r64, r64
  void subR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x29);
    emitModRmReg(src.encoding, dst);
  }

  /// SUB r64, imm32
  void subR64Imm32(X86Gp dst, int imm32) {
    emitRexForReg(dst, w: true);
    if (dst.encoding == 0) {
      buffer.emit8(0x2D);
    } else {
      buffer.emit8(0x81);
      emitModRmReg(5, dst);
    }
    buffer.emit32(imm32);
  }

  /// SUB r64, imm8
  void subR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(5, dst);
    buffer.emit8(imm8);
  }

  /// IMUL r64, r64
  void imulR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xAF);
    emitModRmReg(dst.encoding, src);
  }

  /// XOR r64, r64
  void xorR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x31);
    emitModRmReg(src.encoding, dst);
  }

  /// AND r64, r64
  void andR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x21);
    emitModRmReg(src.encoding, dst);
  }

  /// OR r64, r64
  void orR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x09);
    emitModRmReg(src.encoding, dst);
  }

  /// CMP r64, r64
  void cmpR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x39);
    emitModRmReg(src.encoding, dst);
  }

  /// CMP r64, imm32
  void cmpR64Imm32(X86Gp dst, int imm32) {
    emitRexForReg(dst, w: true);
    if (dst.encoding == 0) {
      buffer.emit8(0x3D);
    } else {
      buffer.emit8(0x81);
      emitModRmReg(7, dst);
    }
    buffer.emit32(imm32);
  }

  /// TEST r64, r64
  void testR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x85);
    emitModRmReg(src.encoding, dst);
  }

  // ===========================================================================
  // Stack instructions
  // ===========================================================================

  /// PUSH r64
  void pushR64(X86Gp reg) {
    if (reg.isExtended) {
      emitRex(false, false, false, true);
    }
    buffer.emit8(0x50 + reg.encoding);
  }

  /// POP r64
  void popR64(X86Gp reg) {
    if (reg.isExtended) {
      emitRex(false, false, false, true);
    }
    buffer.emit8(0x58 + reg.encoding);
  }

  /// PUSH imm8
  void pushImm8(int imm8) {
    buffer.emit8(0x6A);
    buffer.emit8(imm8);
  }

  /// PUSH imm32
  void pushImm32(int imm32) {
    buffer.emit8(0x68);
    buffer.emit32(imm32);
  }

  // ===========================================================================
  // Control flow instructions
  // ===========================================================================

  /// JMP rel8 (short jump).
  void jmpRel8(int disp8) {
    buffer.emit8(0xEB);
    buffer.emit8(disp8);
  }

  /// JMP rel32 (near jump).
  void jmpRel32(int disp32) {
    buffer.emit8(0xE9);
    buffer.emit32(disp32);
  }

  /// JMP rel32 with placeholder (returns offset of disp32 for patching).
  int jmpRel32Placeholder() {
    buffer.emit8(0xE9);
    final offset = buffer.length;
    buffer.emit32(0);
    return offset;
  }

  /// CALL rel32.
  void callRel32(int disp32) {
    buffer.emit8(0xE8);
    buffer.emit32(disp32);
  }

  /// CALL rel32 with placeholder (returns offset of disp32 for patching).
  int callRel32Placeholder() {
    buffer.emit8(0xE8);
    final offset = buffer.length;
    buffer.emit32(0);
    return offset;
  }

  /// CALL r64
  void callR64(X86Gp reg) {
    if (reg.isExtended) {
      emitRex(false, false, false, true);
    }
    buffer.emit8(0xFF);
    emitModRmReg(2, reg);
  }

  /// JMP r64
  void jmpR64(X86Gp reg) {
    if (reg.isExtended) {
      emitRex(false, false, false, true);
    }
    buffer.emit8(0xFF);
    emitModRmReg(4, reg);
  }

  // ===========================================================================
  // Conditional jumps (Jcc)
  // ===========================================================================

  /// Jcc rel32 (near conditional jump).
  void jccRel32(X86Cond cond, int disp32) {
    buffer.emit8(0x0F);
    buffer.emit8(0x80 + cond.code);
    buffer.emit32(disp32);
  }

  /// Jcc rel32 with placeholder.
  int jccRel32Placeholder(X86Cond cond) {
    buffer.emit8(0x0F);
    buffer.emit8(0x80 + cond.code);
    final offset = buffer.length;
    buffer.emit32(0);
    return offset;
  }

  /// Jcc rel8 (short conditional jump).
  void jccRel8(X86Cond cond, int disp8) {
    buffer.emit8(0x70 + cond.code);
    buffer.emit8(disp8);
  }

  // ===========================================================================
  // LEA instruction
  // ===========================================================================

  /// LEA r64, [mem]
  void leaR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x8D);
    emitModRmMem(dst.encoding, mem);
  }

  // ===========================================================================
  // Unary instructions (INC, DEC, NEG, NOT)
  // ===========================================================================

  /// INC r64
  void incR64(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xFF);
    emitModRmReg(0, reg);
  }

  /// INC r32
  void incR32(X86Gp reg) {
    if (reg.isExtended) {
      emitRex(false, false, false, true);
    }
    buffer.emit8(0xFF);
    emitModRmReg(0, reg);
  }

  /// DEC r64
  void decR64(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xFF);
    emitModRmReg(1, reg);
  }

  /// DEC r32
  void decR32(X86Gp reg) {
    if (reg.isExtended) {
      emitRex(false, false, false, true);
    }
    buffer.emit8(0xFF);
    emitModRmReg(1, reg);
  }

  /// NEG r64 (two's complement negation)
  void negR64(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xF7);
    emitModRmReg(3, reg);
  }

  /// NOT r64 (one's complement)
  void notR64(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xF7);
    emitModRmReg(2, reg);
  }

  // ===========================================================================
  // Shift instructions
  // ===========================================================================

  /// SHL r64, imm8
  void shlR64Imm8(X86Gp reg, int imm8) {
    emitRexForReg(reg, w: true);
    if (imm8 == 1) {
      buffer.emit8(0xD1);
      emitModRmReg(4, reg);
    } else {
      buffer.emit8(0xC1);
      emitModRmReg(4, reg);
      buffer.emit8(imm8);
    }
  }

  /// SHL r64, CL
  void shlR64Cl(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xD3);
    emitModRmReg(4, reg);
  }

  /// SHR r64, imm8 (logical shift right)
  void shrR64Imm8(X86Gp reg, int imm8) {
    emitRexForReg(reg, w: true);
    if (imm8 == 1) {
      buffer.emit8(0xD1);
      emitModRmReg(5, reg);
    } else {
      buffer.emit8(0xC1);
      emitModRmReg(5, reg);
      buffer.emit8(imm8);
    }
  }

  /// SHR r64, CL
  void shrR64Cl(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xD3);
    emitModRmReg(5, reg);
  }

  /// SAR r64, imm8 (arithmetic shift right)
  void sarR64Imm8(X86Gp reg, int imm8) {
    emitRexForReg(reg, w: true);
    if (imm8 == 1) {
      buffer.emit8(0xD1);
      emitModRmReg(7, reg);
    } else {
      buffer.emit8(0xC1);
      emitModRmReg(7, reg);
      buffer.emit8(imm8);
    }
  }

  /// SAR r64, CL
  void sarR64Cl(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xD3);
    emitModRmReg(7, reg);
  }

  /// ROL r64, imm8
  void rolR64Imm8(X86Gp reg, int imm8) {
    emitRexForReg(reg, w: true);
    if (imm8 == 1) {
      buffer.emit8(0xD1);
      emitModRmReg(0, reg);
    } else {
      buffer.emit8(0xC1);
      emitModRmReg(0, reg);
      buffer.emit8(imm8);
    }
  }

  /// ROR r64, imm8
  void rorR64Imm8(X86Gp reg, int imm8) {
    emitRexForReg(reg, w: true);
    if (imm8 == 1) {
      buffer.emit8(0xD1);
      emitModRmReg(1, reg);
    } else {
      buffer.emit8(0xC1);
      emitModRmReg(1, reg);
      buffer.emit8(imm8);
    }
  }

  // ===========================================================================
  // Exchange instruction
  // ===========================================================================

  /// XCHG r64, r64
  void xchgR64R64(X86Gp a, X86Gp b) {
    // Special case: xchg rax, reg has short form
    if (a.id == 0) {
      emitRexForReg(b, w: true);
      buffer.emit8(0x90 + b.encoding);
    } else if (b.id == 0) {
      emitRexForReg(a, w: true);
      buffer.emit8(0x90 + a.encoding);
    } else {
      emitRexForRegRm(a, b, w: true);
      buffer.emit8(0x87);
      emitModRmReg(a.encoding, b);
    }
  }

  // ===========================================================================
  // Conditional move (CMOVcc)
  // ===========================================================================

  /// CMOVcc r64, r64
  void cmovccR64R64(X86Cond cond, X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0x40 + cond.code);
    emitModRmReg(dst.encoding, src);
  }

  // ===========================================================================
  // Set byte on condition (SETcc)
  // ===========================================================================

  /// SETcc r8 (sets the low byte of a register)
  void setccR8(X86Cond cond, X86Gp reg) {
    // May need REX if using SPL/BPL/SIL/DIL or R8B-R15B
    if (reg.isExtended || reg.id >= 4) {
      emitRex(false, false, false, reg.isExtended);
    }
    buffer.emit8(0x0F);
    buffer.emit8(0x90 + cond.code);
    emitModRmReg(0, reg);
  }

  // ===========================================================================
  // Move with zero/sign extension
  // ===========================================================================

  /// MOVZX r64, r8 (zero-extend byte to qword)
  void movzxR64R8(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xB6);
    emitModRmReg(dst.encoding, src);
  }

  /// MOVZX r64, r16 (zero-extend word to qword)
  void movzxR64R16(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xB7);
    emitModRmReg(dst.encoding, src);
  }

  /// MOVSXD r64, r32 (sign-extend dword to qword)
  void movsxdR64R32(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x63);
    emitModRmReg(dst.encoding, src);
  }

  // ===========================================================================
  // Bit manipulation
  // ===========================================================================

  /// BSF r64, r64 (bit scan forward)
  void bsfR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xBC);
    emitModRmReg(dst.encoding, src);
  }

  /// BSR r64, r64 (bit scan reverse)
  void bsrR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xBD);
    emitModRmReg(dst.encoding, src);
  }

  /// POPCNT r64, r64 (population count)
  void popcntR64R64(X86Gp dst, X86Gp src) {
    buffer.emit8(0xF3); // REP prefix for POPCNT
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xB8);
    emitModRmReg(dst.encoding, src);
  }

  /// LZCNT r64, r64 (leading zero count)
  void lzcntR64R64(X86Gp dst, X86Gp src) {
    buffer.emit8(0xF3); // REP prefix for LZCNT
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xBD);
    emitModRmReg(dst.encoding, src);
  }

  /// TZCNT r64, r64 (trailing zero count)
  void tzcntR64R64(X86Gp dst, X86Gp src) {
    buffer.emit8(0xF3); // REP prefix for TZCNT
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xBC);
    emitModRmReg(dst.encoding, src);
  }

  // ===========================================================================
  // CDQ/CQO - Sign extend accumulator
  // ===========================================================================

  /// CDQ - Sign-extend EAX into EDX:EAX
  void cdq() {
    buffer.emit8(0x99);
  }

  /// CQO - Sign-extend RAX into RDX:RAX
  void cqo() {
    buffer.emit8(0x48); // REX.W
    buffer.emit8(0x99);
  }

  // ===========================================================================
  // Division
  // ===========================================================================

  /// IDIV r64 - Signed divide RDX:RAX by r64
  void idivR64(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xF7);
    emitModRmReg(7, reg);
  }

  /// DIV r64 - Unsigned divide RDX:RAX by r64
  void divR64(X86Gp reg) {
    emitRexForReg(reg, w: true);
    buffer.emit8(0xF7);
    emitModRmReg(6, reg);
  }
}

/// x86 condition codes.
enum X86Cond {
  o(0), // Overflow
  no(1), // Not Overflow
  b(2), // Below (unsigned <)
  ae(3), // Above or Equal (unsigned >=)
  e(4), // Equal
  ne(5), // Not Equal
  be(6), // Below or Equal (unsigned <=)
  a(7), // Above (unsigned >)
  s(8), // Sign
  ns(9), // Not Sign
  p(10), // Parity
  np(11), // Not Parity
  l(12), // Less (signed <)
  ge(13), // Greater or Equal (signed >=)
  le(14), // Less or Equal (signed <=)
  g(15); // Greater (signed >)

  final int code;
  const X86Cond(this.code);

  // Aliases
  static const c = b; // Carry
  static const nc = ae; // Not Carry
  static const z = e; // Zero
  static const nz = ne; // Not Zero
  static const pe = p; // Parity Even
  static const po = np; // Parity Odd
  static const nae = b; // Not Above or Equal
  static const nb = ae; // Not Below
  static const nbe = a; // Not Below or Equal
  static const na = be; // Not Above
  static const nge = l; // Not Greater or Equal
  static const nl = ge; // Not Less
  static const nle = g; // Not Less or Equal
  static const ng = le; // Not Greater
}
