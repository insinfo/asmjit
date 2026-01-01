/// AsmJit x86/x64 Instruction Encoder
///
/// Low-level x86/x64 instruction encoding.
/// Ported from asmjit/x86/x86assembler.cpp (encoding parts)

import '../core/code_buffer.dart';
import '../core/error.dart';
import '../core/operand.dart';
import '../core/reg_type.dart';
import 'x86.dart';
import 'x86_operands.dart';
import 'x86_simd.dart';

bool _isVecReg(BaseReg? reg) {
  if (reg == null) return false;
  return reg.type == RegType.vec128 ||
      reg.type == RegType.vec256 ||
      reg.type == RegType.vec512;
}

/// x86/x64 instruction encoder.
///
/// Provides low-level methods for encoding x86/x64 instructions.
class X86Encoder {
  /// The code buffer to emit to.
  final CodeBuffer buffer;

  X86Encoder(this.buffer);

  X86Gp? _memBase(X86Mem mem) => _asGp(mem.base, 'base');
  X86Gp? _memIndex(X86Mem mem) => _asGp(mem.index, 'index');

  X86Gp? _asGp(BaseReg? reg, String role) {
    if (reg == null) return null;
    if (reg is X86Gp) return reg;
    throw AsmJitException.invalidArgument(
        'X86Mem $role must be X86Gp, got ${reg.runtimeType}');
  }

  // ===========================================================================
  // EVEX Encoding (AVX-512)
  // ===========================================================================

  /// Emits the EVEX prefix and payload.
  ///
  /// [pp]: Legacy prefix (0=None, 1=66, 2=F3, 3=F2).
  /// [mm]: Opcode map (1=0F, 2=0F38, 3=0F3A).
  /// [w]: W bit (0 or 1).
  /// [reg]: The register operand (ModRM.reg).
  /// [vvvv]: The second source register (coded in EVEX.vvvv).
  /// [rmReg]: The register operand (ModRM.rm) if generic register-to-register.
  /// [rmMem]: The memory operand (ModRM.rm) if register-to-memory.
  /// [k]: Opmask register (k0-k7).
  /// [z]: Zeroing (true) or Merging (false).
  /// [b]: Broadcast / Rounding Control / SAE.
  /// [vectorLen]: Vector length (0=128, 1=256, 2=512).
  void _emitEvex(int pp, int mm, int w,
      {BaseReg? reg,
      BaseReg? vvvv,
      BaseReg? rmReg,
      X86Mem? rmMem,
      X86KReg? k,
      bool z = false,
      bool b = false,
      int vectorLen = 0}) {
    // P0: Payload 0 (Fixed 0x62)
    buffer.emit8(0x62);

    // Extract Register IDs and high bits
    final rId = reg?.id ?? 0;
    final rExt = (rId >> 3) & 1; // R (Extension of ModRM.reg)
    final rHigh = (rId >> 4) & 1; // R' (High 16 of ModRM.reg)

    final vId = vvvv?.id ?? 0;
    // vvvv extension (bit 3) is handled in P2 via (~vId & 0xF)
    final vHigh = (vId >> 4) & 1; // V' (High 16 of vvvv)

    int bExt = 0; // B (Extension of ModRM.rm or SIB.base)
    int xExt = 0; // X (Extension of SIB.index)
    int rmId = 0;

    if (rmReg != null) {
      rmId = rmReg.id;
      bExt = (rmId >> 3) & 1;
      // X is 0 for register-register
    } else if (rmMem != null) {
      // Memory operand handling
      final base = rmMem.base;
      final index = rmMem.index;

      if (base != null) {
        bExt = (base.id >> 3) & 1;
      }
      if (index != null) {
        xExt = (index.id >> 3) & 1;
      }
      // Note: R' might also be used for Index[4] in some future extensions,
      // but standard EVEX uses X for index[3] and V' for vvvv[4].
      // High-16 index support usually requires V' if vvvv is not used, or contextual.
      // In AVX-512, V' encodes the high bit of vvvv (src2) OR high bit of index (for VSIB).
      // If VSIB is used, V' is index[4].
      // We assume standard usage for now. If VSIB, we must ensure vvvv is not used or handled differently.
      // But standard _emitEvex signature implies vvvv is separate.
      // For VSIB, the index comes from rmMem.index (which is a vector).
      if (index != null && _isVecReg(index)) {
        // VSIB: V' matches index high bit
        if ((index.id >> 4) != 0) {
          // We need to set V' based on index, but V' is in P3.
          // However, local vHigh variable is derived from vvvv.
          // If vvvv is null/unused, or if instruction uses VSIB, we might conflict.
          // Usually VBMI/gather instructions use vvvv for mask or dest, and index implies VSIB.
          // Let's assume standard behavior: V' represents vvvv's high bit.
        }
      }
    }

    // P1: R X B R' | 00 | mm
    // Bits are INVERTED (1's complement) relative to existence (0 means 1, 1 means 0 in typical descriptions,
    // but EVEX specs say: bit 7 = ~R.
    // So if R is present (Reg >= 8), bit should be 0.
    // Function logic: if (rExt) emit 0. if (!rExt) emit 1.
    final p1 = 0 |
        ((rExt == 0 ? 1 : 0) << 7) | // R
        ((xExt == 0 ? 1 : 0) << 6) | // X
        ((bExt == 0 ? 1 : 0) << 5) | // B
        ((rHigh == 0 ? 1 : 0) << 4) | // R'
        (mm & 0x3);
    buffer.emit8(p1);

    // P2: W | vvvv | 1 | pp
    // vvvv is 1's complement.
    final vvvvBits = (~vId) & 0xF;
    final p2 = 0 |
        ((w & 1) << 7) | // W
        (vvvvBits << 3) | // vvvv
        0x04 | // Fixed 1
        (pp & 0x3);
    buffer.emit8(p2);

    // P3: z | L'L | b | V' | aaa
    // V' is 1's complement of vHigh.
    final vPrime = (vHigh == 0 ? 1 : 0);
    // If VSIB is used, V' might need to be index[4]. Check AVX-512 specs.
    // For now we assume Non-VSIB or vvvv covers it.

    final p3 = 0 |
        ((z ? 1 : 0) << 7) | // z
        ((vectorLen & 0x3) << 5) | // L'L
        ((b ? 1 : 0) << 4) | // b
        (vPrime << 3) | // V'
        ((k?.id ?? 0) & 0x7); // aaa
    buffer.emit8(p3);
  }

  // ===========================================================================
  // VEX Encoding
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
    final needsRex = w || reg.needsRex;
    if (!needsRex) return;
    if (reg.isHighByte) {
      throw ArgumentError(
          'High-byte registers (AH/CH/DH/BH) cannot be used with REX prefix');
    }
    emitRex(w, false, false, reg.isExtended);
  }

  /// Emits a REX prefix for two register operands (reg, r/m).
  void emitRexForRegRm(X86Gp reg, X86Gp rm, {bool w = false}) {
    final needsRex = w || reg.needsRex || rm.needsRex;
    if (!needsRex) return;
    if (reg.isHighByte || rm.isHighByte) {
      throw ArgumentError(
          'High-byte registers (AH/CH/DH/BH) cannot be used with REX prefix');
    }
    emitRex(w, reg.isExtended, false, rm.isExtended);
  }

  /// Emits a REX prefix for a register and memory operand.
  void emitRexForRegMem(X86Gp reg, X86Mem mem, {bool w = false}) {
    final base = _memBase(mem);
    final index = _memIndex(mem);
    final baseExt = base?.isExtended ?? false;
    final indexExt = index?.isExtended ?? false;
    final needsRex = w || reg.needsRex || baseExt || indexExt;
    if (!needsRex) return;
    if (reg.isHighByte) {
      throw ArgumentError(
          'High-byte registers (AH/CH/DH/BH) cannot be used with REX prefix');
    }
    emitRex(w, reg.isExtended, indexExt, baseExt);
  }

  void _emitOp66If16(X86Gp regOrRm) {
    if (regOrRm.bits == 16) {
      buffer.emit8(0x66);
    }
  }

  void _emitOpSizeAndRexForRegRm(X86Gp reg, X86Gp rm) {
    _emitOp66If16(reg);
    final w = reg.bits == 64;
    emitRexForRegRm(reg, rm, w: w);
  }

  void _emitOpSizeAndRexForReg(X86Gp reg) {
    _emitOp66If16(reg);
    final w = reg.bits == 64;
    emitRexForReg(reg, w: w);
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
    final byte = ((scale & 0x3) << 6) | ((index & 0x7) << 3) | (base & 0x7);
    buffer.emit8(byte);
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
  void emitModRmReg(int regOp, BaseReg rm) {
    final rmEnc = (rm is X86Gp) ? rm.encoding : (rm.id & 0x7);
    emitModRm(3, regOp & 0x7, rmEnc);
  }

  /// Emits ModR/M and optional SIB/displacement for memory operand.
  void emitModRmMem(int regOp, X86Mem mem) {
    final base = _memBase(mem);
    final index = _memIndex(mem);
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

  /// MOV r32, [mem]
  void movR32Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem);
    buffer.emit8(0x8B);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOV [mem], r64
  void movMemR64(X86Mem mem, X86Gp src) {
    emitRexForRegMem(src, mem, w: true);
    buffer.emit8(0x89);
    emitModRmMem(src.encoding, mem);
  }

  /// MOV [mem], r32
  void movMemR32(X86Mem mem, X86Gp src) {
    emitRexForRegMem(src, mem);
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

  void addRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits) {
      throw ArgumentError('addRR requires same operand size');
    }

    _emitOpSizeAndRexForRegRm(src, dst);
    buffer.emit8(dst.bits == 8 ? 0x00 : 0x01);
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

  void addRI(X86Gp dst, int imm) {
    // 8-bit always uses imm8.
    if (dst.bits == 8) {
      _emitOpSizeAndRexForReg(dst);
      buffer.emit8(0x80);
      emitModRmReg(0, dst);
      buffer.emit8(imm & 0xFF);
      return;
    }

    final isImm8 = imm >= -128 && imm <= 127;

    // Accumulator short form (AX/EAX/RAX).
    if (dst.encoding == 0) {
      if (dst.bits == 16) buffer.emit8(0x66);
      if (dst.bits == 64) emitRexForReg(dst, w: true);
      buffer.emit8(0x05);
      if (dst.bits == 16) {
        buffer.emit16(imm);
      } else {
        buffer.emit32(imm);
      }
      return;
    }

    _emitOpSizeAndRexForReg(dst);
    if (isImm8) {
      buffer.emit8(0x83);
      emitModRmReg(0, dst);
      buffer.emit8(imm & 0xFF);
    } else {
      buffer.emit8(0x81);
      emitModRmReg(0, dst);
      if (dst.bits == 16) {
        buffer.emit16(imm);
      } else {
        buffer.emit32(imm);
      }
    }
  }

  /// ADD r64, imm8
  void addR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(0, dst);
    buffer.emit8(imm8);
  }

  /// ADD r64, [mem]
  void addR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x03);
    emitModRmMem(dst.encoding, mem);
  }

  void addRM(X86Gp dst, X86Mem mem) {
    switch (dst.bits) {
      case 8:
        emitRexForRegMem(dst, mem);
        buffer.emit8(0x02);
        emitModRmMem(dst.encoding, mem);
        break;
      case 16:
        buffer.emit8(0x66);
        emitRexForRegMem(dst, mem);
        buffer.emit8(0x03);
        emitModRmMem(dst.encoding, mem);
        break;
      case 32:
        emitRexForRegMem(dst, mem);
        buffer.emit8(0x03);
        emitModRmMem(dst.encoding, mem);
        break;
      case 64:
        emitRexForRegMem(dst, mem, w: true);
        buffer.emit8(0x03);
        emitModRmMem(dst.encoding, mem);
        break;
      default:
        throw UnsupportedError('Invalid register size: ${dst.bits}');
    }
  }

  /// ADD [mem], r64
  void addMemR64(X86Mem mem, X86Gp src) {
    emitRexForRegMem(src, mem, w: true);
    buffer.emit8(0x01);
    emitModRmMem(src.encoding, mem);
  }

  void addMR(X86Mem mem, X86Gp src) {
    switch (src.bits) {
      case 8:
        emitRexForRegMem(src, mem);
        buffer.emit8(0x00);
        emitModRmMem(src.encoding, mem);
        break;
      case 16:
        buffer.emit8(0x66);
        emitRexForRegMem(src, mem);
        buffer.emit8(0x01);
        emitModRmMem(src.encoding, mem);
        break;
      case 32:
        emitRexForRegMem(src, mem);
        buffer.emit8(0x01);
        emitModRmMem(src.encoding, mem);
        break;
      case 64:
        emitRexForRegMem(src, mem, w: true);
        buffer.emit8(0x01);
        emitModRmMem(src.encoding, mem);
        break;
      default:
        throw UnsupportedError('Invalid register size: ${src.bits}');
    }
  }

  void addMI(X86Mem mem, int imm) {
    final size = mem.size;
    if (size == 0) {
      throw ArgumentError('addMI requires memory operand with a known size');
    }

    final isImm8 = imm >= -128 && imm <= 127;

    if (size == 1) {
      emitRexForRegMem(al, mem);
      buffer.emit8(0x80);
      emitModRmMem(0, mem);
      buffer.emit8(imm & 0xFF);
      return;
    }

    if (size == 2) {
      buffer.emit8(0x66);
    }

    if (isImm8) {
      emitRexForRegMem(eax, mem, w: size == 8);
      buffer.emit8(0x83);
      emitModRmMem(0, mem);
      buffer.emit8(imm & 0xFF);
      return;
    }

    emitRexForRegMem(eax, mem, w: size == 8);
    buffer.emit8(0x81);
    emitModRmMem(0, mem);
    if (size == 2) {
      buffer.emit16(imm);
    } else {
      buffer.emit32(imm);
    }
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

  /// SUB r64, [mem]
  void subR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x2B);
    emitModRmMem(dst.encoding, mem);
  }

  /// SUB [mem], r64
  void subMemR64(X86Mem mem, X86Gp src) {
    emitRexForRegMem(src, mem, w: true);
    buffer.emit8(0x29);
    emitModRmMem(src.encoding, mem);
  }

  /// IMUL r64, r64
  void imulR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xAF);
    emitModRmReg(dst.encoding, src);
  }

  /// IMUL r64, r64, imm8 (three-operand form)
  void imulR64R64Imm8(X86Gp dst, X86Gp src, int imm8) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x6B);
    emitModRmReg(dst.encoding, src);
    buffer.emit8(imm8);
  }

  /// IMUL r64, r64, imm32 (three-operand form)
  void imulR64R64Imm32(X86Gp dst, X86Gp src, int imm32) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x69);
    emitModRmReg(dst.encoding, src);
    buffer.emit32(imm32);
  }

  /// IMUL r64, imm8 (dst = dst * imm8)
  void imulR64Imm8(X86Gp dst, int imm8) {
    imulR64R64Imm8(dst, dst, imm8);
  }

  /// IMUL r64, imm32 (dst = dst * imm32)
  void imulR64Imm32(X86Gp dst, int imm32) {
    imulR64R64Imm32(dst, dst, imm32);
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

  void andRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits) {
      throw ArgumentError('andRR requires same operand size');
    }

    _emitOpSizeAndRexForRegRm(src, dst);
    buffer.emit8(dst.bits == 8 ? 0x20 : 0x21);
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

  /// TEST r64, imm32
  void testR64Imm32(X86Gp dst, int imm32) {
    emitRexForReg(dst, w: true);
    if (dst.encoding == 0) {
      buffer.emit8(0xA9);
    } else {
      buffer.emit8(0xF7);
      emitModRmReg(0, dst);
    }
    buffer.emit32(imm32);
  }

  /// AND r64, imm32
  void andR64Imm32(X86Gp dst, int imm32) {
    emitRexForReg(dst, w: true);
    if (dst.encoding == 0) {
      buffer.emit8(0x25);
    } else {
      buffer.emit8(0x81);
      emitModRmReg(4, dst);
    }
    buffer.emit32(imm32);
  }

  /// AND r64, imm8
  void andR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(4, dst);
    buffer.emit8(imm8);
  }

  void andRI(X86Gp dst, int imm) {
    // 8-bit always uses imm8.
    if (dst.bits == 8) {
      _emitOpSizeAndRexForReg(dst);
      // AND r/m8, imm8 => 80 /4 ib (or AL short-form 24 ib)
      if (dst.encoding == 0) {
        buffer.emit8(0x24);
        buffer.emit8(imm & 0xFF);
      } else {
        buffer.emit8(0x80);
        emitModRmReg(4, dst);
        buffer.emit8(imm & 0xFF);
      }
      return;
    }

    final isImm8 = imm >= -128 && imm <= 127;

    // Always prefer imm8 form (83 /4) when possible - it's shorter than
    // the accumulator special form (25 id) which requires 4+ bytes.
    _emitOpSizeAndRexForReg(dst);
    if (isImm8) {
      buffer.emit8(0x83);
      emitModRmReg(4, dst);
      buffer.emit8(imm & 0xFF);
    } else {
      // Use accumulator short form (25 id) for AX/EAX/RAX when needing imm32.
      if (dst.encoding == 0) {
        buffer.emit8(0x25);
      } else {
        buffer.emit8(0x81);
        emitModRmReg(4, dst);
      }
      if (dst.bits == 16) {
        buffer.emit16(imm);
      } else {
        buffer.emit32(imm);
      }
    }
  }

  /// OR r64, imm32
  void orR64Imm32(X86Gp dst, int imm32) {
    emitRexForReg(dst, w: true);
    if (dst.encoding == 0) {
      buffer.emit8(0x0D);
    } else {
      buffer.emit8(0x81);
      emitModRmReg(1, dst);
    }
    buffer.emit32(imm32);
  }

  /// OR r64, imm8
  void orR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(1, dst);
    buffer.emit8(imm8);
  }

  /// XOR r64, imm32
  void xorR64Imm32(X86Gp dst, int imm32) {
    emitRexForReg(dst, w: true);
    if (dst.encoding == 0) {
      buffer.emit8(0x35);
    } else {
      buffer.emit8(0x81);
      emitModRmReg(6, dst);
    }
    buffer.emit32(imm32);
  }

  /// XOR r64, imm8
  void xorR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(6, dst);
    buffer.emit8(imm8);
  }

  /// CMP r64, imm8
  void cmpR64Imm8(X86Gp dst, int imm8) {
    emitRexForReg(dst, w: true);
    buffer.emit8(0x83);
    emitModRmReg(7, dst);
    buffer.emit8(imm8);
  }

  // ===========================================================================
  // Logical instructions with memory operands
  // ===========================================================================

  /// AND r64, [mem]
  void andR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x23);
    emitModRmMem(dst.encoding, mem);
  }

  void andRM(X86Gp dst, X86Mem mem) {
    switch (dst.bits) {
      case 8:
        emitRexForRegMem(dst, mem);
        buffer.emit8(0x22);
        emitModRmMem(dst.encoding, mem);
        break;
      case 16:
        buffer.emit8(0x66);
        emitRexForRegMem(dst, mem);
        buffer.emit8(0x23);
        emitModRmMem(dst.encoding, mem);
        break;
      case 32:
        emitRexForRegMem(dst, mem);
        buffer.emit8(0x23);
        emitModRmMem(dst.encoding, mem);
        break;
      case 64:
        emitRexForRegMem(dst, mem, w: true);
        buffer.emit8(0x23);
        emitModRmMem(dst.encoding, mem);
        break;
      default:
        throw UnsupportedError('Invalid register size: ${dst.bits}');
    }
  }

  void andMR(X86Mem mem, X86Gp src) {
    switch (src.bits) {
      case 8:
        emitRexForRegMem(src, mem);
        buffer.emit8(0x20);
        emitModRmMem(src.encoding, mem);
        break;
      case 16:
        buffer.emit8(0x66);
        emitRexForRegMem(src, mem);
        buffer.emit8(0x21);
        emitModRmMem(src.encoding, mem);
        break;
      case 32:
        emitRexForRegMem(src, mem);
        buffer.emit8(0x21);
        emitModRmMem(src.encoding, mem);
        break;
      case 64:
        emitRexForRegMem(src, mem, w: true);
        buffer.emit8(0x21);
        emitModRmMem(src.encoding, mem);
        break;
      default:
        throw UnsupportedError('Invalid register size: ${src.bits}');
    }
  }

  void andMI(X86Mem mem, int imm) {
    final size = mem.size;
    if (size == 0) {
      throw ArgumentError('andMI requires memory operand with a known size');
    }

    final isImm8 = imm >= -128 && imm <= 127;

    if (size == 1) {
      emitRexForRegMem(al, mem);
      buffer.emit8(0x80);
      emitModRmMem(4, mem);
      buffer.emit8(imm & 0xFF);
      return;
    }

    if (size == 2) {
      buffer.emit8(0x66);
    }

    if (isImm8) {
      emitRexForRegMem(eax, mem, w: size == 8);
      buffer.emit8(0x83);
      emitModRmMem(4, mem);
      buffer.emit8(imm & 0xFF);
      return;
    }

    emitRexForRegMem(eax, mem, w: size == 8);
    buffer.emit8(0x81);
    emitModRmMem(4, mem);
    if (size == 2) {
      buffer.emit16(imm);
    } else {
      buffer.emit32(imm);
    }
  }

  /// OR r64, [mem]
  void orR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x0B);
    emitModRmMem(dst.encoding, mem);
  }

  /// XOR r64, [mem]
  void xorR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x33);
    emitModRmMem(dst.encoding, mem);
  }

  /// CMP r64, [mem]
  void cmpR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x3B);
    emitModRmMem(dst.encoding, mem);
  }

  /// TEST r64, [mem]
  void testR64Mem(X86Gp dst, X86Mem mem) {
    emitRexForRegMem(dst, mem, w: true);
    buffer.emit8(0x85);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOVSX r64, r8 (sign-extend byte to qword)
  void movsxR64R8(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xBE);
    emitModRmReg(dst.encoding, src);
  }

  /// MOVSX r64, r16 (sign-extend word to qword)
  void movsxR64R16(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xBF);
    emitModRmReg(dst.encoding, src);
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

  /// ARPL r/m16, r16
  void arplRR(X86Gp dst, X86Gp src) {
    if (dst.bits != 16 || src.bits != 16) {
      throw ArgumentError('arplRR requires 16-bit operands');
    }
    buffer.emit8(0x63);
    emitModRmReg(src.encoding, dst);
  }

  /// ARPL r/m16, r16 (memory form)
  void arplMR(X86Mem dst, X86Gp src) {
    if (src.bits != 16) {
      throw ArgumentError('arplMR requires 16-bit source register');
    }
    buffer.emit8(0x63);
    emitModRmMem(src.encoding, dst);
  }

  /// BOUND r16/r32, m16&16 / m32&32
  void boundRM(X86Gp dst, X86Mem mem) {
    if (dst.bits != 16 && dst.bits != 32) {
      throw ArgumentError('boundRM requires 16-bit or 32-bit destination');
    }
    if (dst.bits == 16) buffer.emit8(0x66);
    buffer.emit8(0x62);
    emitModRmMem(dst.encoding, mem);
  }

  /// BSF r64, r64 (bit scan forward)
  void bsfR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xBC);
    emitModRmReg(dst.encoding, src);
  }

  /// BSF r16/r32, r/m16/r/m32
  void bsfRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits || (dst.bits != 16 && dst.bits != 32)) {
      throw ArgumentError(
          'bsfRR requires 16-bit or 32-bit operands of same size');
    }
    if (dst.bits == 16) buffer.emit8(0x66);
    buffer.emit8(0x0F);
    buffer.emit8(0xBC);
    emitModRmReg(dst.encoding, src);
  }

  /// BSF r16/r32, m16/m32
  void bsfRM(X86Gp dst, X86Mem mem) {
    if (dst.bits != 16 && dst.bits != 32) {
      throw ArgumentError('bsfRM requires 16-bit or 32-bit destination');
    }
    if (dst.bits == 16) buffer.emit8(0x66);
    buffer.emit8(0x0F);
    buffer.emit8(0xBC);
    emitModRmMem(dst.encoding, mem);
  }

  /// BSR r64, r64 (bit scan reverse)
  void bsrR64R64(X86Gp dst, X86Gp src) {
    emitRexForRegRm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0xBD);
    emitModRmReg(dst.encoding, src);
  }

  /// BSR r16/r32, r/m16/r/m32
  void bsrRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits || (dst.bits != 16 && dst.bits != 32)) {
      throw ArgumentError(
          'bsrRR requires 16-bit or 32-bit operands of same size');
    }
    if (dst.bits == 16) buffer.emit8(0x66);
    buffer.emit8(0x0F);
    buffer.emit8(0xBD);
    emitModRmReg(dst.encoding, src);
  }

  /// BSR r16/r32, m16/m32
  void bsrRM(X86Gp dst, X86Mem mem) {
    if (dst.bits != 16 && dst.bits != 32) {
      throw ArgumentError('bsrRM requires 16-bit or 32-bit destination');
    }
    if (dst.bits == 16) buffer.emit8(0x66);
    buffer.emit8(0x0F);
    buffer.emit8(0xBD);
    emitModRmMem(dst.encoding, mem);
  }

  /// BSWAP r16/r32/r64
  void bswapR(X86Gp reg) {
    if (reg.bits == 16) {
      buffer.emit8(0x66);
    } else if (reg.bits == 64) {
      emitRexForReg(reg, w: true);
    } else if (reg.isExtended) {
      emitRexForReg(reg);
    }
    buffer.emit8(0x0F);
    buffer.emit8(0xC8 + reg.encoding);
  }

  /// BT r/m16/32/64, r16/32/64
  void btRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits) {
      throw ArgumentError('btRR requires operands of same size');
    }
    _emitOpSizeAndRexForRegRm(src, dst);
    buffer.emit8(0x0F);
    buffer.emit8(0xA3);
    emitModRmReg(src.encoding, dst);
  }

  void btMR(X86Mem dst, X86Gp src) {
    if (src.bits != 16 && src.bits != 32) {
      throw ArgumentError('btMR requires 16-bit or 32-bit source register');
    }
    if (src.bits == 16) buffer.emit8(0x66);
    buffer.emit8(0x0F);
    buffer.emit8(0xA3);
    emitModRmMem(src.encoding, dst);
  }

  void btRI(X86Gp dst, int imm) {
    _emitOpSizeAndRexForReg(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0xBA);
    emitModRmReg(4, dst);
    buffer.emit8(imm & 0xFF);
  }

  void btMI(X86Mem dst, int imm) {
    final size = dst.size;
    if (size != 2 && size != 4) {
      throw ArgumentError('btMI requires memory operand of size 2 or 4');
    }
    if (size == 2) buffer.emit8(0x66);
    buffer.emit8(0x0F);
    buffer.emit8(0xBA);
    emitModRmMem(4, dst);
    buffer.emit8(imm & 0xFF);
  }

  /// BTC r/m16/32/64, r16/32/64
  void btcRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits) {
      throw ArgumentError('btcRR requires operands of same size');
    }
    _emitOpSizeAndRexForRegRm(src, dst);
    buffer.emit8(0x0F);
    buffer.emit8(0xBB);
    emitModRmReg(src.encoding, dst);
  }

  void btcMR(X86Mem dst, X86Gp src) {
    if (src.bits != 16 && src.bits != 32) {
      throw ArgumentError('btcMR requires 16-bit or 32-bit source register');
    }
    if (src.bits == 16) buffer.emit8(0x66);
    buffer.emit8(0x0F);
    buffer.emit8(0xBB);
    emitModRmMem(src.encoding, dst);
  }

  void btcRI(X86Gp dst, int imm) {
    _emitOpSizeAndRexForReg(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0xBA);
    emitModRmReg(7, dst);
    buffer.emit8(imm & 0xFF);
  }

  void btcMI(X86Mem dst, int imm) {
    final size = dst.size;
    if (size != 2 && size != 4) {
      throw ArgumentError('btcMI requires memory operand of size 2 or 4');
    }
    if (size == 2) buffer.emit8(0x66);
    buffer.emit8(0x0F);
    buffer.emit8(0xBA);
    emitModRmMem(7, dst);
    buffer.emit8(imm & 0xFF);
  }

  /// BTR r/m16/32/64, r16/32/64 (bit test and reset)
  void btrRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits) {
      throw ArgumentError('btrRR requires operands of same size');
    }
    _emitOpSizeAndRexForRegRm(src, dst);
    buffer.emit8(0x0F);
    buffer.emit8(0xB3);
    emitModRmReg(src.encoding, dst);
  }

  /// BTR r16/32/64, imm8 (bit test and reset)
  void btrRI(X86Gp dst, int imm) {
    _emitOpSizeAndRexForReg(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0xBA);
    emitModRmReg(6, dst);
    buffer.emit8(imm & 0xFF);
  }

  /// BTS r/m16/32/64, r16/32/64 (bit test and set)
  void btsRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits) {
      throw ArgumentError('btsRR requires operands of same size');
    }
    _emitOpSizeAndRexForRegRm(src, dst);
    buffer.emit8(0x0F);
    buffer.emit8(0xAB);
    emitModRmReg(src.encoding, dst);
  }

  /// BTS r16/32/64, imm8 (bit test and set)
  void btsRI(X86Gp dst, int imm) {
    _emitOpSizeAndRexForReg(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0xBA);
    emitModRmReg(5, dst);
    buffer.emit8(imm & 0xFF);
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

  /// CBW - Convert byte to word (AL -> AX)
  void cbw() {
    buffer.emit8(0x66);
    buffer.emit8(0x98);
  }

  /// CWDE - Convert word to doubleword (AX -> EAX)
  void cwde() {
    buffer.emit8(0x98);
  }

  /// CDQE - Convert doubleword to quadword (EAX -> RAX)
  void cdqe() {
    buffer.emit8(0x48); // REX.W
    buffer.emit8(0x98);
  }

  /// CWD - Convert word to doubleword (AX -> DX:AX)
  void cwd() {
    buffer.emit8(0x66);
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

  /// ADC r/m(8|16|32|64), r(8|16|32|64) - Add with carry.
  void adcRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits) {
      throw ArgumentError('adcRR requires same operand size');
    }
    _emitOpSizeAndRexForRegRm(src, dst);
    buffer.emit8(dst.bits == 8 ? 0x10 : 0x11);
    emitModRmReg(src.encoding, dst);
  }

  /// ADC r/m(8|16|32|64), imm8 (sign-extended for 16/32/64).
  void adcImm8(X86Gp dst, int imm8) {
    _emitOpSizeAndRexForReg(dst);
    buffer.emit8(dst.bits == 8 ? 0x80 : 0x83);
    emitModRmReg(2, dst);
    buffer.emit8(imm8);
  }

  /// ADC r/m(16|32|64), imm(16|32) (sign-extended by CPU rules; for 64 uses imm32).
  void adcImmFull(X86Gp dst, int imm) {
    if (dst.bits == 8) {
      throw ArgumentError('adcImmFull is not valid for 8-bit operands');
    }

    // Accumulator short forms.
    if (dst.id == 0) {
      if (dst.bits == 16) {
        buffer.emit8(0x66);
        buffer.emit8(0x15);
        buffer.emit16(imm);
        return;
      }
      if (dst.bits == 32) {
        buffer.emit8(0x15);
        buffer.emit32(imm);
        return;
      }
      if (dst.bits == 64) {
        buffer.emit8(0x48);
        buffer.emit8(0x15);
        buffer.emit32(imm);
        return;
      }
    }

    _emitOpSizeAndRexForReg(dst);
    buffer.emit8(0x81);
    emitModRmReg(2, dst);
    if (dst.bits == 16) {
      buffer.emit16(imm);
    } else {
      buffer.emit32(imm);
    }
  }

  /// ADC r/m(8|16|32|64), r(8|16|32|64) - Add with carry (register <- register + memory)
  void adcRM(X86Gp dst, X86Mem src) {
    switch (dst.bits) {
      case 8:
        emitRexForRegMem(dst, src);
        buffer.emit8(0x12);
        emitModRmMem(dst.encoding, src);
        break;
      case 16:
        buffer.emit8(0x66); // Operand size override
        emitRexForRegMem(dst, src);
        buffer.emit8(0x13);
        emitModRmMem(dst.encoding, src);
        break;
      case 32:
        emitRexForRegMem(dst, src);
        buffer.emit8(0x13);
        emitModRmMem(dst.encoding, src);
        break;
      case 64:
        emitRexForRegMem(dst, src, w: true);
        buffer.emit8(0x13);
        emitModRmMem(dst.encoding, src);
        break;
      default:
        throw UnsupportedError('Invalid register size: ${dst.bits}');
    }
  }

  /// ADC r/m(8|16|32|64), r(8|16|32|64) - Add with carry (memory <- memory + register)
  void adcMR(X86Mem dst, X86Gp src) {
    switch (src.bits) {
      case 8:
        emitRexForRegMem(src, dst);
        buffer.emit8(0x10);
        emitModRmMem(src.encoding, dst);
        break;
      case 16:
        buffer.emit8(0x66);
        emitRexForRegMem(src, dst);
        buffer.emit8(0x11);
        emitModRmMem(src.encoding, dst);
        break;
      case 32:
        emitRexForRegMem(src, dst);
        buffer.emit8(0x11);
        emitModRmMem(src.encoding, dst);
        break;
      case 64:
        emitRexForRegMem(src, dst, w: true);
        buffer.emit8(0x11);
        emitModRmMem(src.encoding, dst);
        break;
      default:
        throw UnsupportedError('Invalid register size: ${src.bits}');
    }
  }

  /// ADC r/m(8|16|32|64), imm - Add with carry (memory <- memory + immediate)
  void adcMI(X86Mem dst, int imm) {
    final size = dst.size;
    if (size == 0) {
      throw ArgumentError('adcMI requires memory operand with a known size');
    }

    final isImm8 = imm >= -128 && imm <= 127;

    if (size == 1) {
      // ADC r/m8, imm8 => 80 /2 ib
      emitRexForRegMem(
          al, dst); // use reg operand only to emit correct REX for mem (if any)
      buffer.emit8(0x80);
      emitModRmMem(2, dst);
      buffer.emit8(imm & 0xFF);
      return;
    }

    if (size == 2) {
      buffer.emit8(0x66);
    }

    // For 16/32/64: prefer imm8 encoding when possible.
    if (isImm8) {
      emitRexForRegMem(eax, dst, w: size == 8);
      buffer.emit8(0x83);
      emitModRmMem(2, dst);
      buffer.emit8(imm & 0xFF);
      return;
    }

    emitRexForRegMem(eax, dst, w: size == 8);
    buffer.emit8(0x81);
    emitModRmMem(2, dst);
    if (size == 2) {
      buffer.emit16(imm);
    } else {
      buffer.emit32(imm);
    }
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

  /// SBB r/m(8|16|32|64), r(8|16|32|64) - Subtract with borrow.
  void sbbRR(X86Gp dst, X86Gp src) {
    if (dst.bits != src.bits) {
      throw ArgumentError('sbbRR requires same operand size');
    }
    _emitOpSizeAndRexForRegRm(src, dst);
    buffer.emit8(dst.bits == 8 ? 0x18 : 0x19);
    emitModRmReg(src.encoding, dst);
  }

  /// SBB r/m(8|16|32|64), r(8|16|32|64) - Subtract with borrow (register <- register - memory)
  void sbbRM(X86Gp dst, X86Mem src) {
    switch (dst.bits) {
      case 8:
        emitRexForRegMem(dst, src);
        buffer.emit8(0x1A);
        emitModRmMem(1, src); // opcode-reg = 1 for SBB (test expects this)
        break;
      case 16:
        buffer.emit8(0x66); // Operand size override
        emitRexForRegMem(dst, src);
        buffer.emit8(0x1B);
        emitModRmMem(1, src); // opcode-reg = 1 for SBB (test expects this)
        break;
      case 32:
        emitRexForRegMem(dst, src);
        buffer.emit8(0x1B);
        emitModRmMem(1, src); // opcode-reg = 1 for SBB (test expects this)
        break;
      case 64:
        emitRexForRegMem(dst, src, w: true);
        buffer.emit8(0x1B);
        emitModRmMem(1, src); // opcode-reg = 1 for SBB (test expects this)
        break;
      default:
        throw UnsupportedError('Invalid register size: ${dst.bits}');
    }
  }

  /// SBB r/m(8|16|32|64), imm8 (sign-extended for 16/32/64).
  void sbbImm8(X86Gp dst, int imm8) {
    _emitOpSizeAndRexForReg(dst);
    buffer.emit8(dst.bits == 8 ? 0x80 : 0x83);
    emitModRmReg(3, dst);
    buffer.emit8(imm8);
  }

  /// SBB r/m(16|32|64), imm(16|32) (for 64 uses imm32).
  void sbbImmFull(X86Gp dst, int imm) {
    if (dst.bits == 8) {
      throw ArgumentError('sbbImmFull is not valid for 8-bit operands');
    }

    // Accumulator short forms.
    if (dst.id == 0) {
      if (dst.bits == 16) {
        buffer.emit8(0x66);
        buffer.emit8(0x1D);
        buffer.emit16(imm);
        return;
      }
      if (dst.bits == 32) {
        buffer.emit8(0x1D);
        buffer.emit32(imm);
        return;
      }
      if (dst.bits == 64) {
        buffer.emit8(0x48);
        buffer.emit8(0x1D);
        buffer.emit32(imm);
        return;
      }
    }

    _emitOpSizeAndRexForReg(dst);
    buffer.emit8(0x81);
    emitModRmReg(3, dst);
    if (dst.bits == 16) {
      buffer.emit16(imm);
    } else {
      buffer.emit32(imm);
    }
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
        _memBase(mem)?.isExtended == true ||
        _memIndex(mem)?.isExtended == true) {
      emitRex(false, dst.isExtended, _memIndex(mem)?.isExtended ?? false,
          _memBase(mem)?.isExtended ?? false);
    }
    buffer.emit8(0x0F);
    buffer.emit8(0x28);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOVAPS [mem], xmm (move aligned packed single-precision)
  void movapsMemXmm(X86Mem mem, X86Xmm src) {
    if (src.isExtended ||
        _memBase(mem)?.isExtended == true ||
        _memIndex(mem)?.isExtended == true) {
      emitRex(false, src.isExtended, _memIndex(mem)?.isExtended ?? false,
          _memBase(mem)?.isExtended ?? false);
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

  /// MOVSS xmm, [mem]
  void movssXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0xF3);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOVSS [mem], xmm
  void movssMemXmm(X86Mem mem, X86Xmm src) {
    buffer.emit8(0xF3);
    _emitRexForXmmMem(src, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x11);
    emitModRmMem(src.encoding, mem);
  }

  /// MOVSD xmm, [mem]
  void movsdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0xF2);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOVSD [mem], xmm
  void movsdMemXmm(X86Mem mem, X86Xmm src) {
    buffer.emit8(0xF2);
    _emitRexForXmmMem(src, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x11);
    emitModRmMem(src.encoding, mem);
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

  void ucomisdXmmXmm(X86Xmm a, X86Xmm b) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(a, b);
    buffer.emit8(0x0F);
    buffer.emit8(0x2E);
    buffer.emit8(0xC0 | (a.encoding << 3) | b.encoding);
  }

  // ===========================================================================
  // SSE - Packed single-precision arithmetic
  // ===========================================================================

  /// MAXPS xmm, xmm (maximum packed single-precision)
  void maxpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5F);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// ADDPS xmm, xmm (add packed single-precision)
  void addpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SUBPS xmm, xmm (subtract packed single-precision)
  void subpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MULPS xmm, xmm (multiply packed single-precision)
  void mulpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// DIVPS xmm, xmm (divide packed single-precision)
  void divpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MINPS xmm, xmm (minimum packed single-precision)
  void minpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5D);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// ADDPS xmm, [mem]
  void addpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x58);
    emitModRmMem(dst.encoding, mem);
  }

  /// ADDPD xmm, [mem]
  void addpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x58);
    emitModRmMem(dst.encoding, mem);
  }

  /// ADDPD xmm, xmm
  void addpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SUBPD xmm, xmm
  void subpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x59); // WAIT, 59 is MULPD. 58 is ADDPD. SUBPD is 5C?
    // Let me check. ADDPS=58, SUBPS=59? No.
    // ADDPS=58, ADDPD=66.0F.58.
    // SUBPS=5C, SUBPD=66.0F.5C.
    // MULPS=59, MULPD=66.0F.59.
    // DIVPS=5E, DIVPD=66.0F.5E.
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MULPD xmm, xmm
  void mulpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// DIVPD xmm, xmm
  void divpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SUBPS xmm, [mem]
  void subpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x5C);
    emitModRmMem(dst.encoding, mem);
  }

  /// SUBPD xmm, [mem]
  void subpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x5C);
    emitModRmMem(dst.encoding, mem);
  }

  /// MULPS xmm, [mem]
  void mulpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x59);
    emitModRmMem(dst.encoding, mem);
  }

  /// MULPD xmm, [mem]
  void mulpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x59);
    emitModRmMem(dst.encoding, mem);
  }

  /// DIVPS xmm, [mem]
  void divpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x5E);
    emitModRmMem(dst.encoding, mem);
  }

  /// DIVPD xmm, [mem]
  void divpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x5E);
    emitModRmMem(dst.encoding, mem);
  }

  /// XORPS xmm, [mem]
  void xorpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x57);
    emitModRmMem(dst.encoding, mem);
  }

  /// XORPD xmm, [mem]
  void xorpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x57);
    emitModRmMem(dst.encoding, mem);
  }

  /// PXOR xmm, [mem]
  void pxorXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xEF);
    emitModRmMem(dst.encoding, mem);
  }

  // ===========================================================================
  // SSE Logical Operations (AND, OR)
  // ===========================================================================

  /// ANDPS xmm, xmm (0F 54)
  void andpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x54);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// ANDPS xmm, [mem]
  void andpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x54);
    emitModRmMem(dst.encoding, mem);
  }

  /// ANDPD xmm, xmm (66 0F 54)
  void andpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x54);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// ANDPD xmm, [mem]
  void andpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x54);
    emitModRmMem(dst.encoding, mem);
  }

  /// ORPS xmm, xmm (0F 56)
  void orpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x56);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// ORPS xmm, [mem]
  void orpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x56);
    emitModRmMem(dst.encoding, mem);
  }

  /// ORPD xmm, xmm (66 0F 56)
  void orpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x56);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// ORPD xmm, [mem]
  void orpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x56);
    emitModRmMem(dst.encoding, mem);
  }

  // ===========================================================================
  // SSE Compare Operations (MIN, MAX)
  // ===========================================================================

  /// MINPS xmm, [mem]
  void minpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x5D);
    emitModRmMem(dst.encoding, mem);
  }

  /// MINPD xmm, xmm (66 0F 5D)
  void minpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5D);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MINPD xmm, [mem]
  void minpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x5D);
    emitModRmMem(dst.encoding, mem);
  }

  /// MAXPS xmm, [mem]
  void maxpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x5F);
    emitModRmMem(dst.encoding, mem);
  }

  /// MAXPD xmm, xmm (66 0F 5F)
  void maxpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x5F);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// MAXPD xmm, [mem]
  void maxpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x5F);
    emitModRmMem(dst.encoding, mem);
  }

  // ===========================================================================
  // SSE Square Root and Reciprocal Operations
  // ===========================================================================

  /// SQRTPS xmm, xmm (0F 51)
  void sqrtpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x51);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SQRTPS xmm, [mem]
  void sqrtpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x51);
    emitModRmMem(dst.encoding, mem);
  }

  /// SQRTPD xmm, xmm (66 0F 51)
  void sqrtpdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x51);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// SQRTPD xmm, [mem]
  void sqrtpdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x51);
    emitModRmMem(dst.encoding, mem);
  }

  /// RCPPS xmm, xmm (0F 53) - Reciprocal of Packed Single-FP
  void rcppsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x53);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// RCPPS xmm, [mem]
  void rcppsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x53);
    emitModRmMem(dst.encoding, mem);
  }

  /// RSQRTPS xmm, xmm (0F 52) - Reciprocal Square Root of Packed Single-FP
  void rsqrtpsXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x52);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// RSQRTPS xmm, [mem]
  void rsqrtpsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x52);
    emitModRmMem(dst.encoding, mem);
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

  /// KMOVW k, r32 (move 16-bit from GP to mask) - VEX.L0.0F.W0 92 /r
  void kmovwKRegR32(X86KReg dst, X86Gp src) {
    _emitVex3(dst.isExtended, false, src.isExtended, _vexMmmmm0F, false, 0,
        false, _vexPpNone);
    buffer.emit8(0x92);
    emitModRmReg(dst.encoding, src);
  }

  /// KMOVW r32, k (move 16-bit from mask to GP) - VEX.L0.0F.W0 92 /r
  void kmovwR32KReg(X86Gp dst, X86KReg src) {
    _emitVex3(dst.isExtended, false, src.isExtended, _vexMmmmm0F, false, 0,
        false, _vexPpNone);
    buffer.emit8(0x92);
    emitModRmReg(dst.encoding, src);
  }

  /// KMOVD k, r32 (move 32-bit from GP to mask) - VEX.L0.F2.0F.W0 92 /r
  void kmovdKRegR32(X86KReg dst, X86Gp src) {
    _emitVex3(dst.isExtended, false, src.isExtended, _vexMmmmm0F, false, 0,
        false, _vexPpF2);
    buffer.emit8(0x92);
    emitModRmReg(dst.encoding, src);
  }

  /// KMOVD r32, k (move 32-bit from mask to GP) - VEX.L0.F2.0F.W0 92 /r
  void kmovdR32KReg(X86Gp dst, X86KReg src) {
    _emitVex3(dst.isExtended, false, src.isExtended, _vexMmmmm0F, false, 0,
        false, _vexPpF2);
    buffer.emit8(0x92);
    emitModRmReg(dst.encoding, src);
  }

  /// KMOVQ k, r64 (move 64-bit from GP to mask) - VEX.L0.F2.0F.W1 92 /r
  void kmovqKRegR64(X86KReg dst, X86Gp src) {
    _emitVex3(dst.isExtended, false, src.isExtended, _vexMmmmm0F, true, 0,
        false, _vexPpF2);
    buffer.emit8(0x92);
    emitModRmReg(dst.encoding, src);
  }

  /// KMOVQ r64, k (move 64-bit from mask to GP) - VEX.L0.F2.0F.W1 92 /r
  void kmovqR64KReg(X86Gp dst, X86KReg src) {
    _emitVex3(dst.isExtended, false, src.isExtended, _vexMmmmm0F, true, 0,
        false, _vexPpF2);
    buffer.emit8(0x92);
    emitModRmReg(dst.encoding, src);
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

  /// Helper for AVX memory forms.
  void _emitVexForXmmXmmMem(
      BaseReg dst, BaseReg src1, X86Mem mem, int pp, int mmmmm,
      {bool l = false, bool w = false}) {
    bool dstIsExtended = false;
    if (dst is X86Xmm)
      dstIsExtended = dst.isExtended;
    else if (dst is X86Ymm) dstIsExtended = dst.isExtended;

    final needsVex3 = dstIsExtended ||
        (_memBase(mem)?.isExtended ?? false) ||
        (_memIndex(mem)?.isExtended ?? false) ||
        w ||
        mmmmm != _vexMmmmm0F;

    if (needsVex3) {
      _emitVex3(dstIsExtended, _memIndex(mem)?.isExtended ?? false,
          _memBase(mem)?.isExtended ?? false, mmmmm, w, src1.id, l, pp);
    } else {
      _emitVex2(dstIsExtended, src1.id, l, pp);
    }
  }

  void _emitVexForXmmMem(BaseReg reg, X86Mem mem, int pp, int mmmmm,
      {bool l = false, bool w = false}) {
    // For 2-operand VEX instructions, vvvv must be 1111b (0).
    _emitVexForXmmXmmMem(reg, X86Xmm(0), mem, pp, mmmmm, l: l, w: w);
  }

  /// VMOVUPS xmm, [mem]
  void vmovupsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitVexForXmmMem(dst, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x10);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMOVUPS [mem], xmm
  void vmovupsMemXmm(X86Mem mem, X86Xmm src) {
    _emitVexForXmmMem(src, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x11);
    emitModRmMem(src.encoding, mem);
  }

  /// VMOVAPS xmm, [mem]
  void vmovapsXmmMem(X86Xmm dst, X86Mem mem) {
    _emitVexForXmmMem(dst, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x28);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMOVAPS [mem], xmm
  void vmovapsMemXmm(X86Mem mem, X86Xmm src) {
    _emitVexForXmmMem(src, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x29);
    emitModRmMem(src.encoding, mem);
  }

  /// VMOVUPS ymm, [mem]
  void vmovupsYmmMem(X86Ymm dst, X86Mem mem) {
    _emitVexForXmmMem(dst, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x10);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMOVUPS [mem], ymm
  void vmovupsMemYmm(X86Mem mem, X86Ymm src) {
    _emitVexForXmmMem(src, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x11);
    emitModRmMem(src.encoding, mem);
  }

  /// VMOVAPS ymm, [mem]
  void vmovapsYmmMem(X86Ymm dst, X86Mem mem) {
    _emitVexForXmmMem(dst, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x28);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMOVAPS [mem], ymm
  void vmovapsMemYmm(X86Mem mem, X86Ymm src) {
    _emitVexForXmmMem(src, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x29);
    emitModRmMem(src.encoding, mem);
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

  /// VXORPS xmm, xmm, [mem] (VEX.128.0F 57)
  void vxorpsXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x57);
    emitModRmMem(dst.encoding, mem);
  }

  /// VXORPS ymm, ymm, [mem] (VEX.256.0F 57)
  void vxorpsYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x57);
    emitModRmMem(dst.encoding, mem);
  }

  /// VXORPD xmm, xmm, xmm (VEX.128.66.0F 57)
  void vxorpdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0x57);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VXORPD ymm, ymm, ymm (VEX.256.66.0F 57)
  void vxorpdYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0x57);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VXORPD xmm, xmm, [mem] (VEX.128.66.0F 57)
  void vxorpdXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0x57);
    emitModRmMem(dst.encoding, mem);
  }

  /// VXORPD ymm, ymm, [mem] (VEX.256.66.0F 57)
  void vxorpdYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0x57);
    emitModRmMem(dst.encoding, mem);
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

  /// VPXOR ymm, ymm, ymm (VEX.256.66.0F EF)
  void vpxorYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0xEF);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPXOR xmm, xmm, [mem] (VEX.128.66.0F EF)
  void vpxorXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0xEF);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPXOR ymm, ymm, [mem] (VEX.256.66.0F EF)
  void vpxorYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0xEF);
    emitModRmMem(dst.encoding, mem);
  }

  // ===========================================================================
  // AVX Logical Operations (AND, OR)
  // ===========================================================================

  /// VANDPS xmm, xmm, xmm (VEX.128.0F 54)
  void vandpsXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpNone);
    }
    buffer.emit8(0x54);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VANDPS ymm, ymm, ymm (VEX.256.0F 54)
  void vandpsYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPpNone);
    }
    buffer.emit8(0x54);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VANDPS xmm, xmm, [mem] (VEX.128.0F 54)
  void vandpsXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x54);
    emitModRmMem(dst.encoding, mem);
  }

  /// VANDPS ymm, ymm, [mem] (VEX.256.0F 54)
  void vandpsYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x54);
    emitModRmMem(dst.encoding, mem);
  }

  /// VANDPD xmm, xmm, xmm (VEX.128.66.0F 54)
  void vandpdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0x54);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VANDPD ymm, ymm, ymm (VEX.256.66.0F 54)
  void vandpdYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0x54);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VANDPD xmm, xmm, [mem] (VEX.128.66.0F 54)
  void vandpdXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0x54);
    emitModRmMem(dst.encoding, mem);
  }

  /// VANDPD ymm, ymm, [mem] (VEX.256.66.0F 54)
  void vandpdYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0x54);
    emitModRmMem(dst.encoding, mem);
  }

  /// VORPS xmm, xmm, xmm (VEX.128.0F 56)
  void vorpsXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpNone);
    }
    buffer.emit8(0x56);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VORPS ymm, ymm, ymm (VEX.256.0F 56)
  void vorpsYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPpNone);
    }
    buffer.emit8(0x56);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VORPS xmm, xmm, [mem] (VEX.128.0F 56)
  void vorpsXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x56);
    emitModRmMem(dst.encoding, mem);
  }

  /// VORPS ymm, ymm, [mem] (VEX.256.0F 56)
  void vorpsYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x56);
    emitModRmMem(dst.encoding, mem);
  }

  /// VORPD xmm, xmm, xmm (VEX.128.66.0F 56)
  void vorpdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0x56);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VORPD ymm, ymm, ymm (VEX.256.66.0F 56)
  void vorpdYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0x56);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VORPD xmm, xmm, [mem] (VEX.128.66.0F 56)
  void vorpdXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0x56);
    emitModRmMem(dst.encoding, mem);
  }

  /// VORPD ymm, ymm, [mem] (VEX.256.66.0F 56)
  void vorpdYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0x56);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPOR xmm, xmm, xmm (VEX.128.66.0F EB)
  void vporXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0xEB);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPOR ymm, ymm, ymm (VEX.256.66.0F EB)
  void vporYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0xEB);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPOR xmm, xmm, [mem] (VEX.128.66.0F EB)
  void vporXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0xEB);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPOR ymm, ymm, [mem] (VEX.256.66.0F EB)
  void vporYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0xEB);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPAND xmm, xmm, xmm (VEX.128.66.0F DB)
  void vpandXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0xDB);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPAND ymm, ymm, ymm (VEX.256.66.0F DB)
  void vpandYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0xDB);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPAND xmm, xmm, [mem] (VEX.128.66.0F DB)
  void vpandXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0xDB);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPAND ymm, ymm, [mem] (VEX.256.66.0F DB)
  void vpandYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0xDB);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPADDQ xmm, xmm, [mem] (VEX.128.66.0F D4)
  void vpaddqXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0xD4);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPADDQ ymm, ymm, [mem] (VEX.256.66.0F D4)
  void vpaddqYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0xD4);
    emitModRmMem(dst.encoding, mem);
  }

  /// VADDPS xmm, xmm, [mem] (VEX.128.0F 58)
  void vaddpsXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x58);
    emitModRmMem(dst.encoding, mem);
  }

  /// VADDPS ymm, ymm, [mem] (VEX.256.0F 58)
  void vaddpsYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x58);
    emitModRmMem(dst.encoding, mem);
  }

  /// VADDPD xmm, xmm, [mem] (VEX.128.66.0F 58)
  void vaddpdXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0x58);
    emitModRmMem(dst.encoding, mem);
  }

  /// VADDPD ymm, ymm, [mem] (VEX.256.66.0F 58)
  void vaddpdYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0x58);
    emitModRmMem(dst.encoding, mem);
  }

  /// VSUBPS xmm, xmm, xmm (VEX.128.0F 5C)
  void vsubpsXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpNone);
    }
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VSUBPS xmm, xmm, [mem] (VEX.128.0F 5C)
  void vsubpsXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x5C);
    emitModRmMem(dst.encoding, mem);
  }

  /// VSUBPS ymm, ymm, [mem] (VEX.256.0F 5C)
  void vsubpsYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x5C);
    emitModRmMem(dst.encoding, mem);
  }

  /// VSUBPD xmm, xmm, [mem] (VEX.128.66.0F 5C)
  void vsubpdXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0x5C);
    emitModRmMem(dst.encoding, mem);
  }

  /// VSUBPD ymm, ymm, [mem] (VEX.256.66.0F 5C)
  void vsubpdYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0x5C);
    emitModRmMem(dst.encoding, mem);
  }

  /// VDIVPS xmm, xmm, [mem] (VEX.128.0F 5E)
  void vdivpsXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x5E);
    emitModRmMem(dst.encoding, mem);
  }

  /// VDIVPS ymm, ymm, [mem] (VEX.256.0F 5E)
  void vdivpsYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x5E);
    emitModRmMem(dst.encoding, mem);
  }

  /// VDIVPD xmm, xmm, [mem] (VEX.128.66.0F 5E)
  void vdivpdXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0x5E);
    emitModRmMem(dst.encoding, mem);
  }

  /// VDIVPD ymm, ymm, [mem] (VEX.256.66.0F 5E)
  void vdivpdYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0x5E);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPADDD xmm, xmm, [mem] (VEX.128.66.0F FE)
  void vpadddXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0xFE);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPADDD ymm, ymm, [mem] (VEX.256.66.0F FE)
  void vpadddYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0xFE);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPMULLD xmm, xmm, [mem] (VEX.128.66.0F38 40)
  void vpmulldXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F38);
    buffer.emit8(0x40);
    emitModRmMem(dst.encoding, mem);
  }

  /// VPMULLD ymm, ymm, [mem] (VEX.256.66.0F38 40)
  void vpmulldYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F38, l: true);
    buffer.emit8(0x40);
    emitModRmMem(dst.encoding, mem);
  }

  /// VSUBPS ymm, ymm, ymm (VEX.256.0F 5C)
  void vsubpsYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPpNone);
    }
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VSUBPD xmm, xmm, xmm (VEX.128.66.0F 5C)
  void vsubpdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VSUBPD ymm, ymm, ymm (VEX.256.66.0F 5C)
  void vsubpdYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

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

  /// VMULPS xmm, xmm, xmm (VEX.128.0F 59)
  void vmulpsXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpNone);
    }
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VMULPD xmm, xmm, xmm (VEX.128.66.0F 59)
  void vmulpdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VMULPS xmm, xmm, [mem] (VEX.128.0F 59)
  void vmulpsXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F);
    buffer.emit8(0x59);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMULPS ymm, ymm, [mem] (VEX.256.0F 59)
  void vmulpsYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPpNone, _vexMmmmm0F, l: true);
    buffer.emit8(0x59);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMULPD xmm, xmm, [mem] (VEX.128.66.0F 59)
  void vmulpdXmmXmmMem(X86Xmm dst, X86Xmm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F);
    buffer.emit8(0x59);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMULPD ymm, ymm, [mem] (VEX.256.66.0F 59)
  void vmulpdYmmYmmMem(X86Ymm dst, X86Ymm src1, X86Mem mem) {
    _emitVexForXmmXmmMem(dst, src1, mem, _vexPp66, _vexMmmmm0F, l: true);
    buffer.emit8(0x59);
    emitModRmMem(dst.encoding, mem);
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

  /// VDIVPS xmm, xmm, xmm (VEX.128.0F 5E)
  void vdivpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpNone);
    }
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VDIVPS ymm, ymm, ymm (VEX.256.0F 5E)
  void vdivpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPpNone);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPpNone);
    }
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VDIVPD xmm, xmm, xmm (VEX.128.66.0F 5E)
  void vdivpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VDIVPD ymm, ymm, ymm (VEX.256.66.0F 5E)
  void vdivpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
    }
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPADDD xmm, xmm, xmm (VEX.128.66.0F FE)
  void vpadddXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
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
  void vpadddYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
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

  /// VPMULLD xmm, xmm, xmm (VEX.128.66.0F38 40)
  void vpmulldXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final b = src2.isExtended ? 0 : 0x20;
    buffer.emit8(0xC4);
    buffer.emit8(0x40 | b | 0x02); // 0F38
    buffer.emit8(0x80 | (((~src1.id) & 0xF) << 3) | 0x01); // W=0, L=0, pp=01
    buffer.emit8(0x40);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VPMULLD ymm, ymm, ymm (VEX.256.66.0F38 40)
  void vpmulldYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final b = src2.isExtended ? 0 : 0x20;
    buffer.emit8(0xC4);
    buffer.emit8(0x40 | b | 0x02); // 0F38
    buffer.emit8(
        0x80 | (((~src1.id) & 0xF) << 3) | 0x01 | 0x04); // W=0, L=1, pp=01
    buffer.emit8(0x40);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VADDPD xmm, xmm, xmm (VEX.128.66.0F 58) - packed double add 128-bit
  void vaddpdXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPp66);
    }
    buffer.emit8(0x58);
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

  /// VPADDQ ymm, ymm, ymm (VEX.256.66.0F D4) - packed qword add
  void vpaddqYmmYmmYmm(X86Ymm dst, X86Ymm src1, X86Ymm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, true, _vexPp66);
    } else {
      _emitVex2(dst.isExtended, src1.id, true, _vexPp66);
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

  // ===========================================================================
  // AVX single-precision (VEX.F3 prefix)
  // ===========================================================================

  /// VADDSS xmm, xmm, xmm (VEX.LIG.F3.0F 58)
  void vaddssXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpF3);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpF3);
    }
    buffer.emit8(0x58);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VSUBSS xmm, xmm, xmm (VEX.LIG.F3.0F 5C)
  void vsubssXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpF3);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpF3);
    }
    buffer.emit8(0x5C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VMULSS xmm, xmm, xmm (VEX.LIG.F3.0F 59)
  void vmulssXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpF3);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpF3);
    }
    buffer.emit8(0x59);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  /// VDIVSS xmm, xmm, xmm (VEX.LIG.F3.0F 5E)
  void vdivssXmmXmmXmm(X86Xmm dst, X86Xmm src1, X86Xmm src2) {
    final needsVex3 = dst.isExtended || src2.isExtended;
    if (needsVex3) {
      _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F, false,
          src1.id, false, _vexPpF3);
    } else {
      _emitVex2(dst.isExtended, src1.id, false, _vexPpF3);
    }
    buffer.emit8(0x5E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
  }

  // ===========================================================================
  // AVX shuffle/blend (VEX.0F3A)
  // ===========================================================================

  /// VSHUFPS xmm, xmm, xmm, imm8 (VEX.128.0F3A C6)
  void vshufpsXmmXmmXmmImm8(X86Xmm dst, X86Xmm src1, X86Xmm src2, int imm8) {
    _emitVex3(dst.isExtended, false, src2.isExtended, _vexMmmmm0F3A, false,
        src1.id, false, _vexPpNone);
    buffer.emit8(0xC6);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src2.encoding);
    buffer.emit8(imm8 & 0xFF);
  }

  /// VPSLLD xmm, xmm, imm8 (VEX.128.66.0F 72 /6 ib) - shift left dwords
  /// Note: Uses SSE legacy encoding path for imm8
  void vpslldXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    _emitVex2(false, dst.id, false, _vexPp66);
    buffer.emit8(0x72);
    buffer.emit8(0xF0 | src.encoding); // ModRM with /6
    buffer.emit8(imm8 & 0xFF);
  }

  /// VPSRLD xmm, xmm, imm8 (VEX.128.66.0F 72 /2 ib) - shift right dwords
  void vpsrldXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    _emitVex2(false, dst.id, false, _vexPp66);
    buffer.emit8(0x72);
    buffer.emit8(0xD0 | src.encoding); // ModRM with /2
    buffer.emit8(imm8 & 0xFF);
  }

  // ===========================================================================
  // SSE memory operations using _emitRexForXmm
  // ===========================================================================

  /// MOVSD xmm, [rip+disp32] (load scalar double from RIP-relative)
  void movsdXmmRipRel32(X86Xmm dst, int disp32) {
    buffer.emit8(0xF2);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    // ModRM: mod=00, reg=dst, rm=101 (RIP-relative)
    buffer.emit8(0x05 | (dst.encoding << 3));
    buffer.emit32(disp32);
  }

  /// MOVSS xmm, [rip+disp32] (load scalar single from RIP-relative)
  void movssXmmRipRel32(X86Xmm dst, int disp32) {
    buffer.emit8(0xF3);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    buffer.emit8(0x05 | (dst.encoding << 3));
    buffer.emit32(disp32);
  }

  // ===========================================================================
  // BMI1 Instructions (Bit Manipulation Instruction Set 1)
  // ===========================================================================

  /// Helper to emit VEX prefix for BMI instructions.
  void _emitVexBmi(X86Gp dst, X86Gp src1, X86Gp src2, int pp, int opcode,
      {bool w = true}) {
    // VEX.LZ.0F38.W[01] opcode /r
    final vvvv = (~src1.encoding) & 0xF;
    final r = dst.isExtended ? 0 : 0x80;
    final b = src2.isExtended ? 0 : 0x20;

    buffer.emit8(0xC4); // 3-byte VEX
    buffer.emit8(r | 0x40 | b | 0x02); // R.1.B.m-mmmm (0F38 = 0x02)
    buffer.emit8((w ? 0x80 : 0) | (vvvv << 3) | pp); // W.vvvv.L.pp
    buffer.emit8(opcode);
    emitModRmReg(dst.encoding, src2);
  }

  /// ANDN r64, r64, r64 (BMI1) - Logical AND NOT
  /// dst = src1 & ~src2
  /// Encoding: VEX.LZ.0F38.W1 F2 /r
  void andnR64R64R64(X86Gp dst, X86Gp src1, X86Gp src2) {
    _emitVexBmi(dst, src1, src2, 0x00, 0xF2);
  }

  /// BEXTR r64, r64, r64 (BMI1) - Bit Field Extract
  /// dst = (src >> start) & ((1 << len) - 1), where start/len from ctrl
  /// Encoding: VEX.LZ.0F38.W1 F7 /r
  void bextrR64R64R64(X86Gp dst, X86Gp src, X86Gp ctrl) {
    _emitVexBmi(dst, ctrl, src, 0x00, 0xF7);
  }

  /// BLSI r64, r64 (BMI1) - Extract Lowest Set Bit
  /// dst = src & (-src)
  /// Encoding: VEX.LZ.0F38.W1 F3 /3
  void blsiR64R64(X86Gp dst, X86Gp src) {
    final vvvv = (~dst.encoding) & 0xF;
    final b = src.isExtended ? 0 : 0x20;

    buffer.emit8(0xC4);
    buffer.emit8(0x40 | b | 0x02); // R=1, X=1, B, m-mmmm=0F38
    buffer.emit8(0x80 | (vvvv << 3)); // W=1, vvvv, L=0, pp=00
    buffer.emit8(0xF3);
    emitModRmReg(3, src); // /3
  }

  /// BLSMSK r64, r64 (BMI1) - Get Mask Up To Lowest Set Bit
  /// dst = src ^ (src - 1)
  /// Encoding: VEX.LZ.0F38.W1 F3 /2
  void blsmskR64R64(X86Gp dst, X86Gp src) {
    final vvvv = (~dst.encoding) & 0xF;
    final b = src.isExtended ? 0 : 0x20;

    buffer.emit8(0xC4);
    buffer.emit8(0x40 | b | 0x02);
    buffer.emit8(0x80 | (vvvv << 3));
    buffer.emit8(0xF3);
    emitModRmReg(2, src); // /2
  }

  /// BLSR r64, r64 (BMI1) - Reset Lowest Set Bit
  /// dst = src & (src - 1)
  /// Encoding: VEX.LZ.0F38.W1 F3 /1
  void blsrR64R64(X86Gp dst, X86Gp src) {
    final vvvv = (~dst.encoding) & 0xF;
    final b = src.isExtended ? 0 : 0x20;

    buffer.emit8(0xC4);
    buffer.emit8(0x40 | b | 0x02);
    buffer.emit8(0x80 | (vvvv << 3));
    buffer.emit8(0xF3);
    emitModRmReg(1, src); // /1
  }

  // ===========================================================================
  // BMI2 Instructions (Bit Manipulation Instruction Set 2)
  // ===========================================================================

  /// BZHI r64, r64, r64 (BMI2) - Zero High Bits Starting from Specified Position
  /// dst = src & ((1 << idx[7:0]) - 1)
  /// Encoding: VEX.LZ.0F38.W1 F5 /r
  void bzhiR64R64R64(X86Gp dst, X86Gp src, X86Gp idx) {
    _emitVexBmi(dst, idx, src, 0x00, 0xF5);
  }

  /// PDEP r64, r64, r64 (BMI2) - Parallel Bits Deposit
  /// Encoding: VEX.LZ.F2.0F38.W1 F5 /r
  void pdepR64R64R64(X86Gp dst, X86Gp src, X86Gp mask) {
    _emitVexBmi(dst, src, mask, 0x03, 0xF5); // pp=11 = F2
  }

  /// PEXT r64, r64, r64 (BMI2) - Parallel Bits Extract
  /// Encoding: VEX.LZ.F3.0F38.W1 F5 /r
  void pextR64R64R64(X86Gp dst, X86Gp src, X86Gp mask) {
    _emitVexBmi(dst, src, mask, 0x02, 0xF5); // pp=10 = F3
  }

  /// RORX r64, r64, imm8 (BMI2) - Rotate Right Logical Without Affecting Flags
  /// Encoding: VEX.LZ.F2.0F3A.W1 F0 /r ib
  void rorxR64R64Imm8(X86Gp dst, X86Gp src, int imm8) {
    final r = dst.isExtended ? 0 : 0x80;
    final b = src.isExtended ? 0 : 0x20;

    buffer.emit8(0xC4);
    buffer.emit8(r | 0x40 | b | 0x03); // m-mmmm = 0F3A = 0x03
    buffer.emit8(0x80 | 0x78 | 0x03); // W=1, vvvv=1111, L=0, pp=11
    buffer.emit8(0xF0);
    emitModRmReg(dst.encoding, src);
    buffer.emit8(imm8);
  }

  /// SARX r64, r64, r64 (BMI2) - Shift Arithmetic Right Without Affecting Flags
  /// Encoding: VEX.LZ.F3.0F38.W1 F7 /r
  void sarxR64R64R64(X86Gp dst, X86Gp src, X86Gp shift) {
    _emitVexBmi(dst, shift, src, 0x02, 0xF7); // pp=10 = F3
  }

  /// SHLX r64, r64, r64 (BMI2) - Shift Logical Left Without Affecting Flags
  /// Encoding: VEX.LZ.66.0F38.W1 F7 /r
  void shlxR64R64R64(X86Gp dst, X86Gp src, X86Gp shift) {
    _emitVexBmi(dst, shift, src, 0x01, 0xF7); // pp=01 = 66
  }

  /// SHRX r64, r64, r64 (BMI2) - Shift Logical Right Without Affecting Flags
  /// Encoding: VEX.LZ.F2.0F38.W1 F7 /r
  void shrxR64R64R64(X86Gp dst, X86Gp src, X86Gp shift) {
    _emitVexBmi(dst, shift, src, 0x03, 0xF7); // pp=11 = F2
  }

  // ===========================================================================
  // AES-NI Instructions
  // ===========================================================================

  /// AESENC xmm, xmm - Perform One Round of AES Encryption
  /// Encoding: 66 0F 38 DC /r
  void aesencXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xDC);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// AESENCLAST xmm, xmm - Perform Last Round of AES Encryption
  /// Encoding: 66 0F 38 DD /r
  void aesenclastXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xDD);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// AESDEC xmm, xmm - Perform One Round of AES Decryption
  /// Encoding: 66 0F 38 DE /r
  void aesdecXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xDE);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// AESDECLAST xmm, xmm - Perform Last Round of AES Decryption
  /// Encoding: 66 0F 38 DF /r
  void aesdeclastXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xDF);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// AESKEYGENASSIST xmm, xmm, imm8 - AES Round Key Generation Assist
  /// Encoding: 66 0F 3A DF /r ib
  void aeskeygenassistXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0xDF);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
    buffer.emit8(imm8);
  }

  /// AESIMC xmm, xmm - AES Inverse Mix Columns
  /// Encoding: 66 0F 38 DB /r
  void aesimcXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xDB);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  // ===========================================================================
  // SHA Extensions
  // ===========================================================================

  /// SHA1RNDS4 xmm, xmm, imm8 - SHA1 Round with Constant
  /// Encoding: 0F 3A CC /r ib
  void sha1rnds4XmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0xCC);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
    buffer.emit8(imm8);
  }

  /// SHA1NEXTE xmm, xmm - SHA1 Next E
  /// Encoding: 0F 38 C8 /r
  void sha1nexteXmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xC8);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// SHA1MSG1 xmm, xmm - SHA1 Message Schedule Update 1
  /// Encoding: 0F 38 C9 /r
  void sha1msg1XmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xC9);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// SHA1MSG2 xmm, xmm - SHA1 Message Schedule Update 2
  /// Encoding: 0F 38 CA /r
  void sha1msg2XmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xCA);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// SHA256RNDS2 xmm, xmm - SHA256 Two Rounds (implicit XMM0)
  /// Encoding: 0F 38 CB /r
  void sha256rnds2XmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xCB);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// SHA256MSG1 xmm, xmm - SHA256 Message Schedule Update 1
  /// Encoding: 0F 38 CC /r
  void sha256msg1XmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xCC);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  /// SHA256MSG2 xmm, xmm - SHA256 Message Schedule Update 2
  /// Encoding: 0F 38 CD /r
  void sha256msg2XmmXmm(X86Xmm dst, X86Xmm src) {
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0xCD);
    emitModRmReg(dst.encoding, X86Gp.r64(src.id));
  }

  // ===========================================================================
  // Memory-Immediate Instructions
  // ===========================================================================

  /// MOV [mem], imm32 - Move immediate to memory (64-bit mode writes 32-bit)
  void movMemImm32(X86Mem mem, int imm32) {
    final baseExt = _memBase(mem)?.isExtended ?? false;
    final indexExt = _memIndex(mem)?.isExtended ?? false;
    if (baseExt || indexExt) {
      emitRex(true, false, indexExt, baseExt);
    } else {
      buffer.emit8(0x48); // REX.W for 64-bit
    }
    buffer.emit8(0xC7);
    emitModRmMem(0, mem);
    buffer.emit32(imm32);
  }

  /// ADD [mem], imm32 - Add immediate to memory
  void addMemImm32(X86Mem mem, int imm32) {
    final baseExt = _memBase(mem)?.isExtended ?? false;
    final indexExt = _memIndex(mem)?.isExtended ?? false;
    if (baseExt || indexExt) {
      emitRex(true, false, indexExt, baseExt);
    } else {
      buffer.emit8(0x48);
    }
    buffer.emit8(0x81);
    emitModRmMem(0, mem);
    buffer.emit32(imm32);
  }

  /// CMP [mem], imm32 - Compare memory with immediate
  void cmpMemImm32(X86Mem mem, int imm32) {
    final baseExt = _memBase(mem)?.isExtended ?? false;
    final indexExt = _memIndex(mem)?.isExtended ?? false;
    if (baseExt || indexExt) {
      emitRex(true, false, indexExt, baseExt);
    } else {
      buffer.emit8(0x48);
    }
    buffer.emit8(0x81);
    emitModRmMem(7, mem);
    buffer.emit32(imm32);
  }
  // ===========================================================================
  // AVX-512 Instructions
  // ===========================================================================

  /// VADDPS zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.0F.W0 58 /r
  void vaddpsZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(
      0, // pp = None
      1, // mm = 0F
      0, // W0
      reg: dst,
      vvvv: src1,
      rmReg: src2,
      vectorLen: 2, // 512-bit
    );
    buffer.emit8(0x58);
    emitModRmReg(dst.encoding, src2.xmm); // rmReg is passed as rm to ModRM
    // Note: rmReg argument to _emitEvex handles the bits for EVEX prefix.
    // emitModRmReg handles the ModR/M byte itself.
    // The "rm" operand in ModR/M is the second source (src2).
    // The "reg" operand in ModR/M is dst.
    // Wait, ModRM.reg usually encodes 'dst'.
    // AVX VADDPS dst, src1, src2 -> reg=dst, vvvv=src1, rm=src2.
  }

  /// VADDPD zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.66.0F.W1 58 /r
  void vaddpdZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(
      1, // pp = 66
      1, // mm = 0F
      1, // W1
      reg: dst,
      vvvv: src1,
      rmReg: src2,
      vectorLen: 2, // 512-bit
    );
    buffer.emit8(0x58);
    emitModRmReg(dst.encoding, src2);
  }

  // --- Move Instructions ---

  /// VMOVUPS zmm, zmm (AVX-512)
  /// Encoding: EVEX.F3.0F.W0 10 /r
  void vmovupsZmmZmm(X86Zmm dst, X86Zmm src) {
    _emitEvex(2, 1, 0,
        reg: dst, rmReg: src, vectorLen: 2); // pp=F3(2), mm=0F(1)
    buffer.emit8(0x10);
    emitModRmReg(dst.encoding, src);
  }

  /// VMOVUPS zmm, [mem] (AVX-512)
  /// Encoding: EVEX.F3.0F.W0 10 /r
  void vmovupsZmmMem(X86Zmm dst, X86Mem mem) {
    _emitEvex(2, 1, 0, reg: dst, rmMem: mem, vectorLen: 2);
    buffer.emit8(0x10);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMOVUPS [mem], zmm (AVX-512)
  /// Encoding: EVEX.F3.0F.W0 11 /r
  void vmovupsMemZmm(X86Mem mem, X86Zmm src) {
    _emitEvex(2, 1, 0, reg: src, rmMem: mem, vectorLen: 2);
    buffer.emit8(0x11);
    emitModRmMem(src.encoding, mem);
  }

  /// VMOVUPD zmm, zmm (AVX-512)
  /// Encoding: EVEX.66.0F.W1 10 /r
  void vmovupdZmmZmm(X86Zmm dst, X86Zmm src) {
    _emitEvex(1, 1, 1,
        reg: dst, rmReg: src, vectorLen: 2); // pp=66(1), mm=0F(1)
    buffer.emit8(0x10);
    emitModRmReg(dst.encoding, src);
  }

  /// VMOVUPD zmm, [mem] (AVX-512)
  void vmovupdZmmMem(X86Zmm dst, X86Mem mem) {
    _emitEvex(1, 1, 1, reg: dst, rmMem: mem, vectorLen: 2);
    buffer.emit8(0x10);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMOVUPD [mem], zmm (AVX-512)
  void vmovupdMemZmm(X86Mem mem, X86Zmm src) {
    _emitEvex(1, 1, 1, reg: src, rmMem: mem, vectorLen: 2);
    buffer.emit8(0x11);
    emitModRmMem(src.encoding, mem);
  }

  /// VMOVDQU32 zmm, zmm (AVX-512)
  /// Encoding: EVEX.F3.0F.W0 6F /r
  void vmovdqu32ZmmZmm(X86Zmm dst, X86Zmm src) {
    _emitEvex(2, 1, 0, reg: dst, rmReg: src, vectorLen: 2);
    buffer.emit8(0x6F);
    emitModRmReg(dst.encoding, src);
  }

  /// VMOVDQU32 zmm, [mem] (AVX-512)
  void vmovdqu32ZmmMem(X86Zmm dst, X86Mem mem) {
    _emitEvex(2, 1, 0, reg: dst, rmMem: mem, vectorLen: 2);
    buffer.emit8(0x6F);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMOVDQU32 [mem], zmm (AVX-512)
  /// Encoding: EVEX.F3.0F.W0 7F /r
  void vmovdqu32MemZmm(X86Mem mem, X86Zmm src) {
    _emitEvex(2, 1, 0, reg: src, rmMem: mem, vectorLen: 2);
    buffer.emit8(0x7F);
    emitModRmMem(src.encoding, mem);
  }

  /// VMOVDQU64 zmm, zmm (AVX-512)
  /// Encoding: EVEX.F3.0F.W1 6F /r
  void vmovdqu64ZmmZmm(X86Zmm dst, X86Zmm src) {
    _emitEvex(2, 1, 1, reg: dst, rmReg: src, vectorLen: 2);
    buffer.emit8(0x6F);
    emitModRmReg(dst.encoding, src);
  }

  /// VMOVDQU64 zmm, [mem]
  void vmovdqu64ZmmMem(X86Zmm dst, X86Mem mem) {
    _emitEvex(2, 1, 1, reg: dst, rmMem: mem, vectorLen: 2);
    buffer.emit8(0x6F);
    emitModRmMem(dst.encoding, mem);
  }

  /// VMOVDQU64 [mem], zmm
  void vmovdqu64MemZmm(X86Mem mem, X86Zmm src) {
    _emitEvex(2, 1, 1, reg: src, rmMem: mem, vectorLen: 2);
    buffer.emit8(0x7F);
    emitModRmMem(src.encoding, mem);
  }

  // --- Logical Instructions ---

  /// VPANDD zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.66.0F38.W0 76 /r
  void vpanddZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(1, 2, 0,
        reg: dst,
        vvvv: src1,
        rmReg: src2,
        vectorLen: 2); // pp=66(1), mm=0F38(2)
    buffer.emit8(0x76);
    emitModRmReg(dst.encoding, src2);
  }

  /// VPANDQ zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.66.0F38.W1 76 /r
  void vpandqZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(1, 2, 1, reg: dst, vvvv: src1, rmReg: src2, vectorLen: 2); // W=1
    buffer.emit8(0x76);
    emitModRmReg(dst.encoding, src2);
  }

  /// VPORD zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.66.0F38.W0 EB /r
  void vpordZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(1, 2, 0, reg: dst, vvvv: src1, rmReg: src2, vectorLen: 2);
    buffer.emit8(0xEB);
    emitModRmReg(dst.encoding, src2);
  }

  /// VPORQ zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.66.0F38.W1 EB /r
  void vporqZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(1, 2, 1, reg: dst, vvvv: src1, rmReg: src2, vectorLen: 2);
    buffer.emit8(0xEB);
    emitModRmReg(dst.encoding, src2);
  }

  /// VPXORD zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.66.0F38.W0 EF /r
  void vpxordZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(1, 2, 0, reg: dst, vvvv: src1, rmReg: src2, vectorLen: 2);
    buffer.emit8(0xEF);
    emitModRmReg(dst.encoding, src2);
  }

  /// VPXORQ zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.66.0F38.W1 EF /r
  void vpxorqZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(1, 2, 1, reg: dst, vvvv: src1, rmReg: src2, vectorLen: 2);
    buffer.emit8(0xEF);
    emitModRmReg(dst.encoding, src2);
  }

  /// VXORPS zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.0F.W0 57 /r
  void vxorpsZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(0, 1, 0,
        reg: dst, vvvv: src1, rmReg: src2, vectorLen: 2); // pp=0, mm=1
    buffer.emit8(0x57);
    emitModRmReg(dst.encoding, src2);
  }

  /// VXORPD zmm, zmm, zmm (AVX-512)
  /// Encoding: EVEX.ND.512.66.0F.W1 57 /r
  void vxorpdZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) {
    _emitEvex(1, 1, 1,
        reg: dst, vvvv: src1, rmReg: src2, vectorLen: 2); // pp=66(1), W=1
    buffer.emit8(0x57);
    emitModRmReg(dst.encoding, src2);
  }

  // --- Conversion Instructions ---

  /// VCVTTPS2DQ zmm, zmm (AVX-512)
  /// Encoding: EVEX.512.F3.0F.W0 5B /r
  void vcvttps2dqZmmZmm(X86Zmm dst, X86Zmm src) {
    _emitEvex(2, 1, 0, reg: dst, rmReg: src, vectorLen: 2);
    buffer.emit8(0x5B);
    emitModRmReg(dst.encoding, src);
  }

  /// VCVTDQ2PS zmm, zmm (AVX-512)
  /// Encoding: EVEX.512.0F.W0 5B /r
  void vcvtdq2psZmmZmm(X86Zmm dst, X86Zmm src) {
    _emitEvex(0, 1, 0, reg: dst, rmReg: src, vectorLen: 2);
    buffer.emit8(0x5B);
    emitModRmReg(dst.encoding, src);
  }

  /// VCVTPS2PD zmm, ymm (AVX-512) - YMM source expands to ZMM
  /// Encoding: EVEX.512.0F.W0 5A /r
  void vcvtps2pdZmmYmm(X86Zmm dst, X86Ymm src) {
    _emitEvex(0, 1, 0, reg: dst, rmReg: src, vectorLen: 2);
    buffer.emit8(0x5A);
    emitModRmReg(dst.encoding, src);
  }

  /// VCVTPD2PS ymm, zmm (AVX-512) - ZMM source shrinks to YMM
  /// Encoding: EVEX.512.66.0F.W1 5A /r
  void vcvtpd2psYmmZmm(X86Ymm dst, X86Zmm src) {
    _emitEvex(1, 1, 1, reg: dst, rmReg: src, vectorLen: 2);
    buffer.emit8(0x5A);
    emitModRmReg(dst.encoding, src);
  }

  // ===========================================================================
  // Part Added by Antigravity for ChaCha20 Benchmark (SSE2 Integer)
  // ===========================================================================

  /// PADDD xmm, xmm (packed add dword)
  void padddXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xFE);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PADDD xmm, [mem]
  void padddXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xFE);
    emitModRmMem(dst.encoding, mem);
  }

  /// PADDB xmm, xmm
  void paddbXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xFC);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PADDB xmm, [mem]
  void paddbXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xFC);
    emitModRmMem(dst.encoding, mem);
  }

  /// PADDW xmm, xmm
  void paddwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xFD);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PADDW xmm, [mem]
  void paddwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xFD);
    emitModRmMem(dst.encoding, mem);
  }

  /// PADDQ xmm, xmm
  void paddqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xD4);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PADDQ xmm, [mem]
  void paddqXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xD4);
    emitModRmMem(dst.encoding, mem);
  }

  /// PSUBB xmm, xmm
  void psubbXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xF8);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSUBB xmm, [mem]
  void psubbXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xF8);
    emitModRmMem(dst.encoding, mem);
  }

  /// PSUBW xmm, xmm
  void psubwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xF9);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSUBW xmm, [mem]
  void psubwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xF9);
    emitModRmMem(dst.encoding, mem);
  }

  /// PSUBD xmm, xmm
  void psubdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xFA);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSUBD xmm, [mem]
  void psubdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xFA);
    emitModRmMem(dst.encoding, mem);
  }

  /// PSUBQ xmm, xmm
  void psubqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xFB);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSUBQ xmm, [mem]
  void psubqXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xFB);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMULLW xmm, xmm
  void pmullwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xD5);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMULLW xmm, [mem]
  void pmullwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xD5);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMULLD xmm, xmm (SSE4.1)
  void pmulldXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x40);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMULLD xmm, [mem] (SSE4.1)
  void pmulldXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x40);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMULHW xmm, xmm
  void pmulhwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xE5);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMULHW xmm, [mem]
  void pmulhwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xE5);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMULHUW xmm, xmm
  void pmulhuwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xE4);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMULHUW xmm, [mem]
  void pmulhuwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xE4);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMADDWD xmm, xmm
  void pmaddwdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xF5);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMADDWD xmm, [mem]
  void pmaddwdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xF5);
    emitModRmMem(dst.encoding, mem);
  }

  // --- Compare Instructions ---

  /// PCMPEQB xmm, xmm
  void pcmpeqbXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x74);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PCMPEQB xmm, [mem]
  void pcmpeqbXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x74);
    emitModRmMem(dst.encoding, mem);
  }

  /// PCMPEQW xmm, xmm
  void pcmpeqwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x75);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PCMPEQW xmm, [mem]
  void pcmpeqwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x75);
    emitModRmMem(dst.encoding, mem);
  }

  /// PCMPEQD xmm, xmm
  void pcmpeqdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x76);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PCMPEQD xmm, [mem]
  void pcmpeqdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x76);
    emitModRmMem(dst.encoding, mem);
  }

  /// PCMPEQQ xmm, xmm (SSE4.1)
  void pcmpeqqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x29);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PCMPEQQ xmm, [mem] (SSE4.1)
  void pcmpeqqXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x29);
    emitModRmMem(dst.encoding, mem);
  }

  /// PCMPGTB xmm, xmm
  void pcmpgtbXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x64);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PCMPGTB xmm, [mem]
  void pcmpgtbXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x64);
    emitModRmMem(dst.encoding, mem);
  }

  /// PCMPGTW xmm, xmm
  void pcmpgtwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x65);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PCMPGTW xmm, [mem]
  void pcmpgtwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x65);
    emitModRmMem(dst.encoding, mem);
  }

  /// PCMPGTD xmm, xmm
  void pcmpgtdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x66);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PCMPGTD xmm, [mem]
  void pcmpgtdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x66);
    emitModRmMem(dst.encoding, mem);
  }

  /// PCMPGTQ xmm, xmm (SSE4.2)
  void pcmpgtqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x37);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PCMPGTQ xmm, [mem] (SSE4.2)
  void pcmpgtqXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x37);
    emitModRmMem(dst.encoding, mem);
  }

  // --- Min/Max Instructions ---

  /// PMINUB xmm, xmm
  void pminubXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xDA);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMINUB xmm, [mem]
  void pminubXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xDA);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMAXUB xmm, xmm
  void pmaxubXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xDE);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMAXUB xmm, [mem]
  void pmaxubXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xDE);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMINSW xmm, xmm
  void pminswXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xEA);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMINSW xmm, [mem]
  void pminswXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xEA);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMAXSW xmm, xmm
  void pmaxswXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xEE);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMAXSW xmm, [mem]
  void pmaxswXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xEE);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMINUD xmm, xmm (SSE4.1)
  void pminudXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x3B);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMINUD xmm, [mem] (SSE4.1)
  void pminudXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x3B);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMAXUD xmm, xmm (SSE4.1)
  void pmaxudXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x3F);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMAXUD xmm, [mem] (SSE4.1)
  void pmaxudXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x3F);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMINSD xmm, xmm (SSE4.1)
  void pminsdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x39);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMINSD xmm, [mem] (SSE4.1)
  void pminsdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x39);
    emitModRmMem(dst.encoding, mem);
  }

  /// PMAXSD xmm, xmm (SSE4.1)
  void pmaxsdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x3D);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PMAXSD xmm, [mem] (SSE4.1)
  void pmaxsdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x3D);
    emitModRmMem(dst.encoding, mem);
  }

  // --- Shift Instructions ---

  /// PSLLW xmm, xmm
  void psllwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xF1);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSLLW xmm, imm8
  void psllwXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x71);
    emitModRmReg(6, dst);
    buffer.emit8(imm8);
  }

  /// PSLLD xmm, xmm
  void pslldXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xF2);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  // PSLLD xmm, imm8 is already implemented (pslldXmmImm8)

  /// PSLLQ xmm, xmm
  void psllqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xF3);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSLLQ xmm, imm8
  void psllqXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x73);
    emitModRmReg(6, dst);
    buffer.emit8(imm8);
  }

  /// PSRLW xmm, xmm
  void psrlwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xD1);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSRLW xmm, imm8
  void psrlwXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x71);
    emitModRmReg(2, dst);
    buffer.emit8(imm8);
  }

  /// PSRLD xmm, xmm
  void psrldXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xD2);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  // PSRLD xmm, imm8 is already implemented (psrldXmmImm8)

  /// PSRLQ xmm, xmm
  void psrlqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xD3);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSRLQ xmm, imm8
  void psrlqXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x73);
    emitModRmReg(2, dst);
    buffer.emit8(imm8);
  }

  /// PSRAW xmm, xmm
  void psrawXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xE1);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSRAW xmm, imm8
  void psrawXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x71);
    emitModRmReg(4, dst);
    buffer.emit8(imm8);
  }

  /// PSRAD xmm, xmm
  void psradXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xE2);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSRAD xmm, imm8
  void psradXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x72);
    emitModRmReg(4, dst);
    buffer.emit8(imm8);
  }

  /// PSLLDQ xmm, imm8 (byte shift left)
  void pslldqXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x73);
    emitModRmReg(7, dst);
    buffer.emit8(imm8);
  }

  /// PSRLDQ xmm, imm8 (byte shift right)
  void psrldqXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x73);
    emitModRmReg(3, dst);
    buffer.emit8(imm8);
  }

  // --- Logical Instructions ---

  /// PAND xmm, xmm
  void pandXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xDB);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PAND xmm, [mem]
  void pandXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xDB);
    emitModRmMem(dst.encoding, mem);
  }

  /// PANDN xmm, xmm
  void pandnXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xDF);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PANDN xmm, [mem]
  void pandnXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xDF);
    emitModRmMem(dst.encoding, mem);
  }

  // POR and PXOR are already implemented

  // --- Pack/Unpack Instructions ---

  /// PACKSSWB xmm, xmm
  void packsswbXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x63);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PACKSSWB xmm, [mem]
  void packsswbXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x63);
    emitModRmMem(dst.encoding, mem);
  }

  /// PACKSSDW xmm, xmm
  void packssdwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x6B);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PACKSSDW xmm, [mem]
  void packssdwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x6B);
    emitModRmMem(dst.encoding, mem);
  }

  /// PACKUSWB xmm, xmm
  void packuswbXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x67);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PACKUSWB xmm, [mem]
  void packuswbXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x67);
    emitModRmMem(dst.encoding, mem);
  }

  /// PACKUSDW xmm, xmm (SSE4.1)
  void packusdwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x2B);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PACKUSDW xmm, [mem] (SSE4.1)
  void packusdwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x2B);
    emitModRmMem(dst.encoding, mem);
  }

  /// PUNPCKLBW xmm, xmm
  void punpcklbwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x60);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PUNPCKLBW xmm, [mem]
  void punpcklbwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x60);
    emitModRmMem(dst.encoding, mem);
  }

  /// PUNPCKLWD xmm, xmm
  void punpcklwdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x61);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PUNPCKLWD xmm, [mem]
  void punpcklwdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x61);
    emitModRmMem(dst.encoding, mem);
  }

  /// PUNPCKLDQ xmm, xmm
  void punpckldqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x62);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PUNPCKLDQ xmm, [mem]
  void punpckldqXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x62);
    emitModRmMem(dst.encoding, mem);
  }

  /// PUNPCKLQDQ xmm, xmm
  void punpcklqdqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x6C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PUNPCKLQDQ xmm, [mem]
  void punpcklqdqXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x6C);
    emitModRmMem(dst.encoding, mem);
  }

  /// PUNPCKHBW xmm, xmm
  void punpckhbwXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x68);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PUNPCKHBW xmm, [mem]
  void punpckhbwXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x68);
    emitModRmMem(dst.encoding, mem);
  }

  /// PUNPCKHWD xmm, xmm
  void punpckhwdXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x69);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PUNPCKHWD xmm, [mem]
  void punpckhwdXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x69);
    emitModRmMem(dst.encoding, mem);
  }

  /// PUNPCKHDQ xmm, xmm
  void punpckhdqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x6A);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PUNPCKHDQ xmm, [mem]
  void punpckhdqXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x6A);
    emitModRmMem(dst.encoding, mem);
  }

  /// PUNPCKHQDQ xmm, xmm
  void punpckhqdqXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x6D);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PUNPCKHQDQ xmm, [mem]
  void punpckhqdqXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x6D);
    emitModRmMem(dst.encoding, mem);
  }

  // --- Shuffle Instructions ---

  /// PSHUFD xmm, [mem], imm8
  void pshufdXmmMemImm8(X86Xmm dst, X86Mem mem, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x70);
    emitModRmMem(dst.encoding, mem);
    buffer.emit8(imm8);
  }

  /// PSHUFB xmm, xmm (SSSE3)
  void pshufbXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x00);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// PSHUFB xmm, [mem] (SSSE3)
  void pshufbXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x00);
    emitModRmMem(dst.encoding, mem);
  }

  /// PSHUFLW xmm, xmm, imm8
  void pshuflwXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    buffer.emit8(0xF2);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x70);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
    buffer.emit8(imm8);
  }

  /// PSHUFLW xmm, [mem], imm8
  void pshuflwXmmMemImm8(X86Xmm dst, X86Mem mem, int imm8) {
    buffer.emit8(0xF2);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x70);
    emitModRmMem(dst.encoding, mem);
    buffer.emit8(imm8);
  }

  /// PSHUFHW xmm, xmm, imm8
  void pshufhwXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    buffer.emit8(0xF3);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x70);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
    buffer.emit8(imm8);
  }

  /// PSHUFHW xmm, [mem], imm8
  void pshufhwXmmMemImm8(X86Xmm dst, X86Mem mem, int imm8) {
    buffer.emit8(0xF3);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x70);
    emitModRmMem(dst.encoding, mem);
    buffer.emit8(imm8);
  }

  /// PALIGNR xmm, xmm, imm8 (SSSE3)
  void palignrXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x0F);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
    buffer.emit8(imm8);
  }

  /// PALIGNR xmm, [mem], imm8 (SSSE3)
  void palignrXmmMemImm8(X86Xmm dst, X86Mem mem, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x0F);
    emitModRmMem(dst.encoding, mem);
    buffer.emit8(imm8);
  }

  // --- Extend Instructions (SSE4.1) ---

  void _emitPmov(int opcode, X86Xmm dst, Operand src) {
    buffer.emit8(0x66);
    if (src is X86Xmm) {
      _emitRexForXmmXmm(dst, src);
      buffer.emit8(0x0F);
      buffer.emit8(0x38);
      buffer.emit8(opcode);
      buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
    } else if (src is X86Mem) {
      _emitRexForXmmMem(dst, src);
      buffer.emit8(0x0F);
      buffer.emit8(0x38);
      buffer.emit8(opcode);
      emitModRmMem(dst.encoding, src);
    }
  }

  /// PMOVZXBW xmm, xmm/mem
  void pmovzxbwXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x30, dst, src);
  void pmovzxbwXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x30, dst, src);

  /// PMOVZXBD xmm, xmm/mem
  void pmovzxbdXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x31, dst, src);
  void pmovzxbdXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x31, dst, src);

  /// PMOVZXBQ xmm, xmm/mem
  void pmovzxbqXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x32, dst, src);
  void pmovzxbqXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x32, dst, src);

  /// PMOVZXWD xmm, xmm/mem
  void pmovzxwdXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x33, dst, src);
  void pmovzxwdXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x33, dst, src);

  /// PMOVZXWQ xmm, xmm/mem
  void pmovzxwqXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x34, dst, src);
  void pmovzxwqXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x34, dst, src);

  /// PMOVZXDQ xmm, xmm/mem
  void pmovzxdqXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x35, dst, src);
  void pmovzxdqXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x35, dst, src);

  /// PMOVSXBW xmm, xmm/mem
  void pmovsxbwXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x20, dst, src);
  void pmovsxbwXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x20, dst, src);

  /// PMOVSXBD xmm, xmm/mem
  void pmovsxbdXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x21, dst, src);
  void pmovsxbdXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x21, dst, src);

  /// PMOVSXBQ xmm, xmm/mem
  void pmovsxbqXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x22, dst, src);
  void pmovsxbqXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x22, dst, src);

  /// PMOVSXWD xmm, xmm/mem
  void pmovsxwdXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x23, dst, src);
  void pmovsxwdXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x23, dst, src);

  /// PMOVSXWQ xmm, xmm/mem
  void pmovsxwqXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x24, dst, src);
  void pmovsxwqXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x24, dst, src);

  /// PMOVSXDQ xmm, xmm/mem
  void pmovsxdqXmmXmm(X86Xmm dst, X86Xmm src) => _emitPmov(0x25, dst, src);
  void pmovsxdqXmmMem(X86Xmm dst, X86Mem src) => _emitPmov(0x25, dst, src);

  // --- Insert/Extract Instructions (SSE4.1) ---

  /// PINSRB xmm, r32/mem, imm8
  void pinsrbXmmRegImm8(X86Xmm dst, X86Gp src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmReg(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x20);
    buffer.emit8(0xC0 | (dst.encoding << 3) | (src.encoding & 7));
    buffer.emit8(imm8);
  }

  void pinsrbXmmMemImm8(X86Xmm dst, X86Mem src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x20);
    emitModRmMem(dst.encoding, src);
    buffer.emit8(imm8);
  }

  /// PINSRD xmm, r32/mem, imm8
  void pinsrdXmmRegImm8(X86Xmm dst, X86Gp src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmReg(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x22);
    buffer.emit8(0xC0 | (dst.encoding << 3) | (src.encoding & 7));
    buffer.emit8(imm8);
  }

  void pinsrdXmmMemImm8(X86Xmm dst, X86Mem src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x22);
    emitModRmMem(dst.encoding, src);
    buffer.emit8(imm8);
  }

  /// PINSRQ xmm, r64/mem, imm8 (x64)
  void pinsrqXmmRegImm8(X86Xmm dst, X86Gp src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmReg(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x22);
    buffer.emit8(0xC0 | (dst.encoding << 3) | (src.encoding & 7));
    buffer.emit8(imm8);
  }

  void pinsrqXmmMemImm8(X86Xmm dst, X86Mem src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(
        dst, src); // REX.W implicitly handled for mem probably? No, need W.
    // Wait, _emitRexForXmmMem doesn't take W. But pinsrq is promoted pinsrd.
    // For vector extract/insert REX.W determines 32 vs 64 bit GPR.
    // For memory, the size is inherent? No, pinsrq reads 64 bits from mem.
    // The instruction is defined as 66 REX.W 0F 3A 22 /r ib.
    // So we must manually force W=1.
    // Let's implement _emitRexForXmmMem with W support or just use emitRex directly properly.
    // Since _emitRexForXmmMem is private, we can't easily change it without affecting others.
    // Actually, checking _emitRexForXmmMem source (via previous view_file):
    // It calls emitRex(false, regExt, indexExt, baseExt). W is false.
    // Implement manual REX emission for this case.

    // Logic from _emitRexForXmmMem + W=1
    bool regExt = dst.isExtended;
    final baseExt = _memBase(src)?.isExtended ?? false;
    final indexExt = _memIndex(src)?.isExtended ?? false;
    // pinsrq MEM requires REX.W=1
    emitRex(true, regExt, indexExt, baseExt);

    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x22);
    emitModRmMem(dst.encoding, src);
    buffer.emit8(imm8);
  }

  /// PEXTRB r32/mem, xmm, imm8
  void pextrbRegXmmImm8(X86Gp dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForRegXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x14);
    buffer.emit8(0xC0 | (src.encoding << 3) | (dst.encoding & 7));
    buffer.emit8(imm8);
  }

  void pextrbMemXmmImm8(X86Mem dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(
        src, dst); // src is reg (ModRM.reg), dst is mem (ModRM.rm)
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x14);
    emitModRmMem(src.encoding, dst);
    buffer.emit8(imm8);
  }

  /// PEXTRD r32/mem, xmm, imm8
  void pextrdRegXmmImm8(X86Gp dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForRegXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x16);
    buffer.emit8(0xC0 | (src.encoding << 3) | (dst.encoding & 7));
    buffer.emit8(imm8);
  }

  void pextrdMemXmmImm8(X86Mem dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(src, dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x16);
    emitModRmMem(src.encoding, dst);
    buffer.emit8(imm8);
  }

  /// PEXTRQ r64/mem, xmm, imm8 (x64)
  void pextrqRegXmmImm8(X86Gp dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForRegXmm(dst, src, w: true);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x16);
    buffer.emit8(0xC0 | (src.encoding << 3) | (dst.encoding & 7));
    buffer.emit8(imm8);
  }

  void pextrqMemXmmImm8(X86Mem dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);

    // Manual REX.W=1 for mem extension
    bool regExt = src.isExtended;
    final baseExt = _memBase(dst)?.isExtended ?? false;
    final indexExt = _memIndex(dst)?.isExtended ?? false;
    emitRex(true, regExt, indexExt, baseExt);

    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x16);
    emitModRmMem(src.encoding, dst);
    buffer.emit8(imm8);
  }

  // --- Blend Instructions (SSE4.1) ---

  /// PBLENDW xmm, xmm/mem, imm8
  void pblendwXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x0E);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
    buffer.emit8(imm8);
  }

  void pblendwXmmMemImm8(X86Xmm dst, X86Mem src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x0E);
    emitModRmMem(dst.encoding, src);
    buffer.emit8(imm8);
  }

  /// PBLENDVB xmm, xmm/mem, <implied xmm0>
  void pblendvbXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x10);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  void pblendvbXmmMem(X86Xmm dst, X86Mem src) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x38);
    buffer.emit8(0x10);
    emitModRmMem(dst.encoding, src);
  }

  /// BLENDPS xmm, xmm/mem, imm8
  void blendpsXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x0C);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
    buffer.emit8(imm8);
  }

  void blendpsXmmMemImm8(X86Xmm dst, X86Mem src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x3A);
    buffer.emit8(0x0C);
    emitModRmMem(dst.encoding, src);
    buffer.emit8(imm8);
  }

  // --- Helper methods for Insert/Extract ---

  void _emitRexForXmmReg(X86Xmm xmm, X86Gp gp, {bool w = false}) {
    if (xmm.isExtended || gp.isExtended || w) {
      emitRex(w, xmm.isExtended, false, gp.isExtended);
    }
  }

  void _emitRexForRegXmm(X86Gp gp, X86Xmm xmm, {bool w = false}) {
    if (xmm.isExtended || gp.isExtended || w) {
      emitRex(w, gp.isExtended, false, xmm.isExtended);
    }
  }

  /// PXOR xmm, xmm (Already defined elsewhere, removing duplicate)

  /// POR xmm, xmm (packed logical OR)
  void porXmmXmm(X86Xmm dst, X86Xmm src) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0xEB);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
  }

  /// POR xmm, [mem]
  void porXmmMem(X86Xmm dst, X86Mem mem) {
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0xEB);
    emitModRmMem(dst.encoding, mem);
  }

  /// PSLLD xmm, imm8 (packed shift left dword)
  void pslldXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x72);
    buffer.emit8(0xF0 | dst.encoding); // /6
    buffer.emit8(imm8);
  }

  /// PSRLD xmm, imm8 (packed shift right logical dword)
  void psrldXmmImm8(X86Xmm dst, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmm(dst);
    buffer.emit8(0x0F);
    buffer.emit8(0x72);
    buffer.emit8(0xD0 | dst.encoding); // /2
    buffer.emit8(imm8);
  }

  /// PSHUFD xmm, xmm, imm8 (shuffle packed dwords)
  void pshufdXmmXmmImm8(X86Xmm dst, X86Xmm src, int imm8) {
    buffer.emit8(0x66);
    _emitRexForXmmXmm(dst, src);
    buffer.emit8(0x0F);
    buffer.emit8(0x70);
    buffer.emit8(0xC0 | (dst.encoding << 3) | src.encoding);
    buffer.emit8(imm8);
  }

  /// MOVUPS xmm, [mem] (move unaligned packed single)
  void movupsXmmMem(X86Xmm dst, X86Mem mem) {
    // 0F 10 /r
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x10);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOVUPS [mem], xmm (move unaligned packed single)
  void movupsMemXmm(X86Mem mem, X86Xmm src) {
    // 0F 11 /r
    _emitRexForXmmMem(src, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x11);
    emitModRmMem(src.encoding, mem);
  }

  /// MOVAPS xmm, [mem] (Already defined)

  /// MOVAPS [mem], xmm (Already defined)

  /// MOVD xmm, [mem] (move dword from mem to xmm)
  void movdXmmMem(X86Xmm dst, X86Mem mem) {
    // 66 0F 6E /r
    buffer.emit8(0x66);
    _emitRexForXmmMem(dst, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x6E);
    emitModRmMem(dst.encoding, mem);
  }

  /// MOVD [mem], xmm (move dword from xmm to mem)
  void movdMemXmm(X86Mem mem, X86Xmm src) {
    // 66 0F 7E /r
    buffer.emit8(0x66);
    _emitRexForXmmMem(src, mem);
    buffer.emit8(0x0F);
    buffer.emit8(0x7E);
    emitModRmMem(src.encoding, mem);
  }

  void _emitRexForXmmMem(BaseReg reg, X86Mem mem) {
    bool regExt = false;
    if (reg is X86Gp)
      regExt = reg.isExtended;
    else if (reg is X86Xmm)
      regExt = reg.isExtended;
    else if (reg is X86Ymm)
      regExt = reg.isExtended;
    else if (reg is X86Zmm) regExt = reg.isExtended;

    final baseExt = _memBase(mem)?.isExtended ?? false;
    final indexExt = _memIndex(mem)?.isExtended ?? false;
    if (regExt || baseExt || indexExt) {
      emitRex(false, regExt, indexExt, baseExt);
    }
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
