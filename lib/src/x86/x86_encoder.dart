/// AsmJit x86/x64 Instruction Encoder
///
/// Low-level x86/x64 instruction encoding.
/// Ported from asmjit/x86/x86assembler.cpp (encoding parts)

import '../core/code_buffer.dart';
import 'x86.dart';
import 'x86_operands.dart';
import 'x86_simd.dart';

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

  // ===========================================================================
  // High-precision arithmetic (for cryptography)
  // ===========================================================================

  /// ADC r64, r64 - Add with carry
  void adcR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x11);
    emitModRmReg(src.encoding, dst);
  }

  /// ADC r64, imm8 - Add with carry (sign-extended imm8)
  void adcR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(2, dst);
    buffer.emit8(imm8);
  }

  /// ADC r64, imm32 - Add with carry (sign-extended imm32)
  void adcR64Imm32(X86Gp dst, int imm32) {
    if (dst.id == 0) {
      // ADC RAX, imm32 has shorter encoding
      buffer.emit8(0x48); // REX.W
      buffer.emit8(0x15);
      buffer.emit32(imm32);
    } else {
      emitRexForReg(dst, w: true);
      buffer.emit8(0x81);
      emitModRmReg(2, dst);
      buffer.emit32(imm32);
    }
  }

  /// SBB r64, r64 - Subtract with borrow
  void sbbR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(src, dst, w: true);
    buffer.emit8(0x19);
    emitModRmReg(src.encoding, dst);
  }

  /// SBB r64, imm8 - Subtract with borrow (sign-extended imm8)
  void sbbR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(3, dst);
    buffer.emit8(imm8);
  }

  /// SBB r64, imm32 - Subtract with borrow (sign-extended imm32)
  void sbbR64Imm32(X86Gp dst, int imm32) {
    if (dst.id == 0) {
      // SBB RAX, imm32 has shorter encoding
      buffer.emit8(0x48); // REX.W
      buffer.emit8(0x1D);
      buffer.emit32(imm32);
    } else {
      emitRexForReg(dst, w: true);
      buffer.emit8(0x81);
      emitModRmReg(3, dst);
      buffer.emit32(imm32);
    }
  }

  /// MUL r64 - Unsigned multiply RDX:RAX = RAX * r64
  void mulR64(X86Gp src) {
    emitRexForReg(src, w: true);
    buffer.emit8(0xF7);
    emitModRmReg(4, src);
  }

  /// MULX r64, r64, r64 (BMI2) - Unsigned multiply without affecting flags
  /// MULX rdx, rax, src: (RDX, RAX) = RDX * src (EDX is implicit input)
  /// Encoding: VEX.LZ.F2.0F38.W1 F6 /r
  void mulxR64R64R64(X86Gp hi, X86Gp lo, X86Gp src) {
    // VEX.128.F2.0F38.W1 F6 /r
    // VEX prefix for 3-byte VEX
    final vvvv = (~lo.encoding) & 0xF;
    final r = hi.isExtended ? 0 : 0x80;
    final x = 0; // Not used for reg-reg
    final b = src.isExtended ? 0 : 0x20;

    // VEX.C4 RXB.m-mmmm W.vvvv.L.pp
    buffer.emit8(0xC4); // 3-byte VEX
    buffer.emit8(r | x | b | 0x02); // R.X.B.m-mmmm (0F38)
    buffer.emit8(0x80 | (vvvv << 3) | 0x03); // W.vvvv.L.pp (W=1, L=0, pp=11=F2)
    buffer.emit8(0xF6);
    emitModRmReg(hi.encoding, src);
  }

  /// ADCX r64, r64 (ADX) - Unsigned add with carry flag
  /// Only uses CF, leaves OF unchanged
  /// Encoding: 66 0F 38 F6 /r
  void adcxR64R64(X86Gp dst, X86Gp src) {
    buffer.emit8(0x66); // Mandatory prefix
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xF6);
    emitModRmReg(dst.encoding, src);
  }

  /// ADOX r64, r64 (ADX) - Unsigned add with overflow flag
  /// Only uses OF, leaves CF unchanged
  /// Encoding: F3 0F 38 F6 /r
  void adoxR64R64(X86Gp dst, X86Gp src) {
    buffer.emit8(0xF3); // Mandatory prefix
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xF6);
    emitModRmReg(dst.encoding, src);
  }

  // ===========================================================================
  // Flag manipulation
  // ===========================================================================

  /// CLC - Clear carry flag
  void clc() {
    buffer.emit8(0xF8);
  }

  /// STC - Set carry flag
  void stc() {
    buffer.emit8(0xF9);
  }

  /// CMC - Complement carry flag
  void cmc() {
    buffer.emit8(0xF5);
  }

  /// CLD - Clear direction flag
  void cld() {
    buffer.emit8(0xFC);
  }

  /// STD - Set direction flag
  void std() {
    buffer.emit8(0xFD);
  }

  // ===========================================================================
  // String operations (useful for memcpy/memset)
  // ===========================================================================

  /// REP MOVSB - Repeat move string (byte)
  void repMovsb() {
    buffer.emit8(0xF3); // REP prefix
    buffer.emit8(0xA4); // MOVSB
  }

  /// REP MOVSQ - Repeat move string (qword)
  void repMovsq() {
    buffer.emit8(0xF3); // REP prefix
    buffer.emit8(0x48); // REX.W
    buffer.emit8(0xA5); // MOVSQ
  }

  /// REP STOSB - Repeat store string (byte)
  void repStosb() {
    buffer.emit8(0xF3); // REP prefix
    buffer.emit8(0xAA); // STOSB
  }

  /// REP STOSQ - Repeat store string (qword)
  void repStosq() {
    buffer.emit8(0xF3); // REP prefix
    buffer.emit8(0x48); // REX.W
    buffer.emit8(0xAB); // STOSQ
  }

  // ===========================================================================
  // Memory fence instructions
  // ===========================================================================

  /// MFENCE - Memory fence
  void mfence() {
    buffer.emit8(0x0F);
    buffer.emit8(0xAE);
    buffer.emit8(0xF0);
  }

  /// SFENCE - Store fence
  void sfence() {
    buffer.emit8(0x0F);
    buffer.emit8(0xAE);
    buffer.emit8(0xF8);
  }

  /// LFENCE - Load fence
  void lfence() {
    buffer.emit8(0x0F);
    buffer.emit8(0xAE);
    buffer.emit8(0xE8);
  }

  /// PAUSE - Spin loop hint
  void pause() {
    buffer.emit8(0xF3);
    buffer.emit8(0x90);
  }

  // ===========================================================================
  // SSE/SSE2 instructions
  // ===========================================================================

  /// Helper to emit REX for XMM register.
  void _emitRexForXmm(X86Xmm reg, {bool w = false}) {
    if (reg.isExtended || w) {
      emitRex(w, reg.isExtended, false, false);
    }
  }

  /// Helper to emit REX for XMM reg, XMM rm.
  void _emitRexForXmmXmm(X86Xmm reg, X86Xmm rm, {bool w = false}) {
    if (reg.isExtended || rm.isExtended || w) {
      emitRex(w, reg.isExtended, false, rm.isExtended);
    }
  }

  /// MOVAPS xmm, xmm (move aligned packed single-precision)
  void movapsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x28);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MOVAPS xmm, [mem] (move aligned packed single-precision)
  void movapsXmmMem(X86Xmm dst, X86Mem mem) {
    if (dst.isExtended ||
        mem.base?.isExtended == true ||
        mem.index?.isExtended == true) {
      emitRex(false, dst.isExtended, mem.index?.isExtended ?? false,
          mem.base?.isExtended ?? false);
    }
    buffer.emit8(0x0F);
    buffer.emit8(0x28);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOVAPS [mem], xmm (move aligned packed single-precision)
  void movapsMemXmm(X86Mem mem, X86Xmm src) {
    if (src.isExtended ||
        mem.base?.isExtended == true ||
        mem.index?.isExtended == true) {
      emitRex(false, src.isExtended, mem.index?.isExtended ?? false,
          mem.base?.isExtended ?? false);
    }
    buffer.emit8(0x0F);
    buffer.emit8(0x29);
    emitModRmMem(src.encoding, mem);
  }

  /// MOVUPS xmm, xmm (move unaligned packed single-precision)
  void movupsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MOVUPD xmm, xmm (move unaligned packed double-precision)
  void movupdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66); // Mandatory prefix
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MOVSD xmm, xmm (move scalar double-precision)
  void movsdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF2); // Mandatory prefix
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MOVSS xmm, xmm (move scalar single-precision)
  void movssXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF3); // Mandatory prefix
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PXOR xmm, xmm (packed XOR - commonly used to zero a register)
  void pxorXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66); // Mandatory prefix
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xEF);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// XORPS xmm, xmm (XOR packed single-precision - commonly used to zero)
  void xorpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x57);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// XORPD xmm, xmm (XOR packed double-precision)
  void xorpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66); // Mandatory prefix
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x57);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// ADDSS xmm, xmm (add scalar single-precision)
  void addssXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF3);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// ADDSD xmm, xmm (add scalar double-precision)
  void addsdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF2);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SUBSS xmm, xmm (subtract scalar single-precision)
  void subssXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF3);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SUBSD xmm, xmm (subtract scalar double-precision)
  void subsdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF2);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MULSS xmm, xmm (multiply scalar single-precision)
  void mulssXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF3);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MULSD xmm, xmm (multiply scalar double-precision)
  void mulsdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF2);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// DIVSS xmm, xmm (divide scalar single-precision)
  void divssXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF3);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// DIVSD xmm, xmm (divide scalar double-precision)
  void divsdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF2);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SQRTSS xmm, xmm (square root scalar single-precision)
  void sqrtssXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF3);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x51);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SQRTSD xmm, xmm (square root scalar double-precision)
  void sqrtsdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF2);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x51);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// CVTSI2SD xmm, r64 (convert signed integer to scalar double)
  void cvtsi2sdXmmR64(X86Xmm dst, X86Gp src) {
    buffer.emit8(0xF2);
    emitRex(true, dst.isExtended, false, src.isExtended);
    buffer.emit8(0x0F);
    buffer.emit8(0x2A);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// CVTSI2SS xmm, r64 (convert signed integer to scalar single)
  void cvtsi2ssXmmR64(X86Xmm dst, X86Gp src) {
    buffer.emit8(0xF3);
    emitRex(true, dst.isExtended, false, src.isExtended);
    buffer.emit8(0x0F);
    buffer.emit8(0x2A);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// CVTTSD2SI r64, xmm (convert with truncation scalar double to signed int)
  void cvttsd2siR64Xmm(X86Gp dst, X86Xmm src) {
    buffer.emit8(0xF2);
    emitRex(true, dst.isExtended, false, src.isExtended);
    buffer.emit8(0x0F);
    buffer.emit8(0x2C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// CVTTSS2SI r64, xmm (convert with truncation scalar single to signed int)
  void cvttss2siR64Xmm(X86Gp dst, X86Xmm src) {
    buffer.emit8(0xF3);
    emitRex(true, dst.isExtended, false, src.isExtended);
    buffer.emit8(0x0F);
    buffer.emit8(0x2C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// CVTSD2SS xmm, xmm (convert scalar double to single)
  void cvtsd2ssXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF2);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5A);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// CVTSS2SD xmm, xmm (convert scalar single to double)
  void cvtss2sdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0xF3);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5A);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// COMISS xmm, xmm (compare scalar single-precision, set EFLAGS)
  void comissXmmXmm(X86Xmm a, X86Xmm b) {
    _emitRexForXmmXmm(a, b);
    buffer.emit8(0x0F);
    buffer.emit8(0x2F);
    buffer.emit8(0xC0 | (a.encoding << 3) | b.encoding);
  }

  /// COMISD xmm, xmm (compare scalar double-precision, set EFLAGS)
  void comisdXmmXmm(X86Xmm a, X86Xmm b) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(a, b);
    buffer.emit8(0x0F);
    buffer.emit8(0x2F);
    buffer.emit8(0xC0 | (a.encoding << 3) | b.encoding);
  }

  /// UCOMISS xmm, xmm (unordered compare scalar single-precision)
  void ucomissXmmXmm(X86Xmm a, X86Xmm b) {
    _emitRexForXmmXmm(a, b);
    buffer.emit8(0x0F);
    buffer.emit8(0x2E);
    buffer.emit8(0xC0 | (a.encoding << 3) | b.encoding);
  }

  /// UCOMISD xmm, xmm (unordered compare scalar double-precision)
  void ucomisdXmmXmm(X86Xmm a, X86Xmm b) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(a, b);
    buffer.emit8(0x0F);
    buffer.emit8(0x2E);
    buffer.emit8(0xC0 | (a.encoding << 3) | b.encoding);
  }

  /// MOVQ xmm, r64 (move quadword from GP to XMM)
  void movqXmmR64(X86Xmm dst, X86Gp src) {
    buffer.emit8(0x66);
    emitRex(true, dst.isExtended, false, src.isExtended);
    buffer.emit8(0x0F);
    buffer.emit8(0x6E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MOVQ r64, xmm (move quadword from XMM to GP)
  void movqR64Xmm(X86Gp dst, X86Xmm src) {
    buffer.emit8(0x66);
    emitRex(true, src.isExtended, false, dst.isExtended);
    buffer.emit8(0x0F);
    buffer.emit8(0x7E);
    buffer.emit8(0xC0 | (src.encoding << 3) | dst.encoding);
  }

  /// MOVD xmm, r32 (move doubleword from GP to XMM)
  void movdXmmR32(X86Xmm dst, X86Gp src) {
    buffer.emit8(0x66);
    if (dst.isExtended || src.isExtended) {
      emitRex(false, dst.isExtended, false, src.isExtended);
    }
    buffer.emit8(0x0F);
    buffer.emit8(0x6E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MOVD r32, xmm (move doubleword from XMM to GP)
  void movdR32Xmm(X86Gp dst, X86Xmm src) {
    buffer.emit8(0x66);
    if (src.isExtended || dst.isExtended) {
      emitRex(false, src.isExtended, false, dst.isExtended);
    }
    buffer.emit8(0x0F);
    buffer.emit8(0x7E);
    buffer.emit8(0xC0 | (src.encoding << 3) | dst.encoding);
  }

  // ===========================================================================
  // VEX prefix helpers (for AVX instructions)
  // ===========================================================================

  /// Emit 2-byte VEX prefix: C5 RvvvvLpp
  ///
  /// VEX.R = NOT(REX.R): 1 if reg is NOT extended (0-7), 0 if extended (8-15)
  /// vvvv = NOT(second source reg id), L = 128/256, pp = prefix
  void _emitVex2(bool dstIsExtended, int vvvv, bool l, int pp) {
    buffer.emit8(0xC5);
    // R bit: 0x80 if dst is NOT extended
    int byte =
        (dstIsExtended ? 0 : 0x80) | ((~vvvv & 0xF) << 3) | (l ? 0x04 : 0) | pp;
    buffer.emit8(byte);
  }

  /// Emit 3-byte VEX prefix: C4 RXBmmmmm WvvvvLpp
  void _emitVex3(bool dstIsExtended, bool needsRexX, bool srcIsExtended,
      int mmmmm, bool w, int vvvv, bool l, int pp) {
    buffer.emit8(0xC4);
    // R, X, B bits are inverted: 1 = not extended, 0 = extended
    int byte1 = (dstIsExtended ? 0 : 0x80) |
        (needsRexX ? 0 : 0x40) |
        (srcIsExtended ? 0 : 0x20) |
        mmmmm;
    buffer.emit8(byte1);
    int byte2 = (w ? 0x80 : 0) | ((~vvvv & 0xF) << 3) | (l ? 0x04 : 0) | pp;
    buffer.emit8(byte2);
  }

  // VEX prefix values
  static const int _vexPpNone = 0;
  static const int _vexPp66 = 1;
  static const int _vexPpF3 = 2;
  static const int _vexPpF2 = 3;

  static const int _vexMmmmm0F = 1;
  static const int _vexMmmmm0F38 = 2;
  static const int _vexMmmmm0F3A = 3;

  // ===========================================================================
  // AVX instructions (VEX-encoded)
  // ===========================================================================

  /// VMOVAPS xmm, xmm (VEX.128.0F 28)
  void vmovapsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitVex2(dst.isExtended, 0, false, _vexPpNone);
    buffer.emit8(0x28);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// VMOVAPS ymm, ymm (VEX.256.0F 28)
  void vmovapsYmmYmm(X86Ymm dst, X86Ymm src) {
    _emitVex2(dst.isExtended, 0, true, _vexPpNone);
    buffer.emit8(0x28);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// VMOVUPS xmm, xmm (VEX.128.0F 10)
  void vmovupsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitVex2(dst.isExtended, 0, false, _vexPpNone);
    buffer.emit8(0x10);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// VMOVUPS ymm, ymm (VEX.256.0F 10)
  void vmovupsYmmYmm(X86Ymm dst, X86Ymm src) {
    _emitVex2(dst.isExtended, 0, true, _vexPpNone);
    buffer.emit8(0x10);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// VXORPS xmm, xmm, xmm (VEX.128.0F 57) - zero register idiom
  void vxorpsXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpNone);
    }
    buffer.emit8(0x57);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VXORPS ymm, ymm, ymm (VEX.256.0F 57)
  void vxorpsYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPpNone);
    }
    buffer.emit8(0x57);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPXOR xmm, xmm, xmm (VEX.128.66.0F EF)
  void vpxorXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0xEF);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VADDSD xmm, xmm, xmm (VEX.LIG.F2.0F 58)
  void vaddsdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpF2);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpF2);
    }
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VSUBSD xmm, xmm, xmm (VEX.LIG.F2.0F 5C)
  void vsubsdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpF2);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpF2);
    }
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VMULSD xmm, xmm, xmm (VEX.LIG.F2.0F 59)
  void vmulsdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpF2);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpF2);
    }
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VDIVSD xmm, xmm, xmm (VEX.LIG.F2.0F 5E)
  void vdivsdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpF2);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpF2);
    }
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VADDPS xmm, xmm, xmm (VEX.128.0F 58) - packed single add
  void vaddpsXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpNone);
    }
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VADDPS ymm, ymm, ymm (VEX.256.0F 58) - packed single add 256-bit
  void vaddpsYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPpNone);
    }
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VMULPS ymm, ymm, ymm (VEX.256.0F 59) - packed single multiply 256-bit
  void vmulpsYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPpNone);
    }
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VADDPD ymm, ymm, ymm (VEX.256.66.0F 58) - packed double add 256-bit
  void vaddpdYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VMULPD ymm, ymm, ymm (VEX.256.66.0F 59) - packed double multiply 256-bit
  void vmulpdYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VZEROUPPER (VEX.128.0F 77) - zero upper bits of YMM regs (perf critical!)
  void vzeroupper() {
    _emitVex2(false, 0, false, _vexPpNone);
    buffer.emit8(0x77);
  }

  /// VZEROALL (VEX.256.0F 77) - zero all YMM regs
  void vzeroall() {
    _emitVex2(false, 0, true, _vexPpNone);
    buffer.emit8(0x77);
  }

  // ===========================================================================
  // AVX2 integer instructions
  // ===========================================================================

  /// VPADDD xmm, xmm, xmm (VEX.128.66.0F FE) - packed dword add
  void vpadddXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0xFE);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPADDD ymm, ymm, ymm (VEX.256.66.0F FE)
  void vpadddYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0xFE);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPADDQ xmm, xmm, xmm (VEX.128.66.0F D4) - packed qword add
  void vpaddqXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0xD4);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPMULLD xmm, xmm, xmm (VEX.128.66.0F38 40) - packed dword multiply low
  void vpmulldXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F38, false,
        src1.id, false, _vexPp66);
    buffer.emit8(0x40);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  // ===========================================================================
  // FMA instructions (requires FMA feature)
  // ===========================================================================

  /// VFMADD132SD xmm, xmm, xmm (VEX.DDS.LIG.66.0F38.W1 99)
  /// dst = dst * src2 + src1
  void vfmadd132sdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F38, true,
        src1.id, false, _vexPp66);
    buffer.emit8(0x99);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VFMADD231SD xmm, xmm, xmm (VEX.DDS.LIG.66.0F38.W1 B9)
  /// dst = src1 * src2 + dst
  void vfmadd231sdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F38, true,
        src1.id, false, _vexPp66);
    buffer.emit8(0xB9);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
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
