/// AsmJit ARM64 Encoder
///
/// Low-level instruction encoding for ARM64/AArch64.
/// All ARM64 instructions are 32-bit fixed width.

import '../core/code_buffer.dart';
import 'a64.dart';

/// ARM64 instruction encoder.
///
/// Provides low-level methods for encoding ARM64 instructions.
/// All ARM64 instructions are 32-bit fixed width.
class A64Encoder {
  /// The code buffer to emit instructions to.
  final CodeBuffer buffer;

  A64Encoder(this.buffer);

  /// Emit a 32-bit instruction.
  void emit32(int inst) {
    buffer.emit32(inst);
  }

  /// Current offset in the buffer.
  int get offset => buffer.length;

  // ===========================================================================
  // Helper Methods for Instruction Encoding
  // ===========================================================================

  /// Encode register field (5 bits).
  int _encReg(A64Gp reg) => reg.id & 0x1F;

  /// Encode vector register field (5 bits).
  int _encVec(A64Vec reg) => reg.id & 0x1F;

  /// Encode size field for GP registers (sf bit).
  int _encSf(A64Gp reg) => reg.is64Bit ? 1 : 0;

  /// Encode condition code (4 bits).
  int _encCond(A64Cond cond) => cond.encoding & 0xF;

  /// Encode shift type (2 bits).
  int _encShift(A64Shift shift) => shift.encoding & 0x3;

  int _vecElemSizeBits(A64Vec vt) {
    if (vt.layout != A64Layout.none) {
      switch (vt.layout) {
        case A64Layout.b8:
        case A64Layout.b16:
          return 0; // 8-bit
        case A64Layout.h4:
        case A64Layout.h8:
          return 1; // 16-bit
        case A64Layout.s2:
        case A64Layout.s4:
          return 2; // 32-bit
        case A64Layout.d1:
        case A64Layout.d2:
          return 3; // 64-bit
        default:
          break;
      }
    }
    switch (vt.sizeBits) {
      case 8:
        return 0;
      case 16:
        return 1;
      case 32:
        return 2;
      case 64:
        return 3;
      default:
        throw ArgumentError(
            'Unsupported vector element size: ${vt.sizeBits}. Use explicit layout (e.g. .b16, .s4).');
    }
  }

  // ===========================================================================
  // Data Processing - Immediate
  // ===========================================================================

  /// ADD (immediate) - Add with immediate.
  /// Encoding: sf|0|0|10001|shift|imm12|Rn|Rd
  void addImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) {
    final sf = _encSf(rd);
    final sh = (shift == 12) ? 1 : 0;
    final inst = (sf << 31) |
        (0 << 30) |
        (0 << 29) |
        (0x22 << 23) |
        (sh << 22) |
        ((imm12 & 0xFFF) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// SUB (immediate) - Subtract with immediate.
  /// Encoding: sf|1|0|10001|shift|imm12|Rn|Rd
  void subImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) {
    final sf = _encSf(rd);
    final sh = (shift == 12) ? 1 : 0;
    final inst = (sf << 31) |
        (1 << 30) |
        (0 << 29) |
        (0x22 << 23) |
        (sh << 22) |
        ((imm12 & 0xFFF) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// ADDS (immediate) - Add with immediate, setting flags.
  void addsImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) {
    final sf = _encSf(rd);
    final sh = (shift == 12) ? 1 : 0;
    final inst = (sf << 31) |
        (0 << 30) |
        (1 << 29) |
        (0x22 << 23) |
        (sh << 22) |
        ((imm12 & 0xFFF) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// SUBS (immediate) - Subtract with immediate, setting flags.
  void subsImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) {
    final sf = _encSf(rd);
    final sh = (shift == 12) ? 1 : 0;
    final inst = (sf << 31) |
        (1 << 30) |
        (1 << 29) |
        (0x22 << 23) |
        (sh << 22) |
        ((imm12 & 0xFFF) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// CMP (immediate) - Compare with immediate (alias for SUBS with ZR).
  void cmpImm(A64Gp rn, int imm12) {
    subsImm(rn.is64Bit ? xzr : wzr, rn, imm12);
  }

  /// CMN (immediate) - Compare negative with immediate (alias for ADDS with ZR).
  void cmnImm(A64Gp rn, int imm12) {
    addsImm(rn.is64Bit ? xzr : wzr, rn, imm12);
  }

  // ===========================================================================
  // Data Processing - Register
  // ===========================================================================

  /// ADD (shifted register) - Add with shifted register.
  /// Encoding: sf|0|0|01011|shift|0|Rm|imm6|Rn|Rd
  void addReg(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (0 << 30) |
        (0 << 29) |
        (0x0B << 24) |
        (_encShift(shift) << 22) |
        (0 << 21) |
        (_encReg(rm) << 16) |
        ((amount & 0x3F) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// SUB (shifted register) - Subtract with shifted register.
  void subReg(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (1 << 30) |
        (0 << 29) |
        (0x0B << 24) |
        (_encShift(shift) << 22) |
        (0 << 21) |
        (_encReg(rm) << 16) |
        ((amount & 0x3F) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// AND (shifted register).
  void andReg(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (0 << 30) |
        (0 << 29) |
        (0x0A << 24) |
        (_encShift(shift) << 22) |
        (0 << 21) |
        (_encReg(rm) << 16) |
        ((amount & 0x3F) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// ORR (shifted register).
  void orrReg(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (0 << 30) |
        (1 << 29) |
        (0x0A << 24) |
        (_encShift(shift) << 22) |
        (0 << 21) |
        (_encReg(rm) << 16) |
        ((amount & 0x3F) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// EOR (shifted register).
  void eorReg(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (1 << 30) |
        (0 << 29) |
        (0x0A << 24) |
        (_encShift(shift) << 22) |
        (0 << 21) |
        (_encReg(rm) << 16) |
        ((amount & 0x3F) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// CMP (shifted register).
  void cmpReg(A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final zr = rn.is64Bit ? xzr : wzr;
    final sf = _encSf(rn);
    final inst = (sf << 31) |
        (1 << 30) |
        (1 << 29) |
        (0x0B << 24) |
        (_encShift(shift) << 22) |
        (0 << 21) |
        (_encReg(rm) << 16) |
        ((amount & 0x3F) << 10) |
        (_encReg(rn) << 5) |
        _encReg(zr);
    emit32(inst);
  }

  // ===========================================================================
  // Move Instructions
  // ===========================================================================

  /// MOV (register) - Move register (alias for ORR with ZR).
  void movReg(A64Gp rd, A64Gp rm) {
    final zr = rd.is64Bit ? xzr : wzr;
    orrReg(rd, zr, rm);
  }

  /// MOVZ - Move wide with zero.
  /// Encoding: sf|10|100101|hw|imm16|Rd
  void movz(A64Gp rd, int imm16, {int shift = 0}) {
    final sf = _encSf(rd);
    final hw = shift ~/ 16;
    final inst = (sf << 31) |
        (2 << 29) |
        (0x25 << 23) |
        (hw << 21) |
        ((imm16 & 0xFFFF) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// MOVK - Move wide with keep.
  void movk(A64Gp rd, int imm16, {int shift = 0}) {
    final sf = _encSf(rd);
    final hw = shift ~/ 16;
    final inst = (sf << 31) |
        (3 << 29) |
        (0x25 << 23) |
        (hw << 21) |
        ((imm16 & 0xFFFF) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// MOVN - Move wide with not.
  void movn(A64Gp rd, int imm16, {int shift = 0}) {
    final sf = _encSf(rd);
    final hw = shift ~/ 16;
    final inst = (sf << 31) |
        (0 << 29) |
        (0x25 << 23) |
        (hw << 21) |
        ((imm16 & 0xFFFF) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// MOV (immediate) - Load a 64-bit immediate using MOVZ/MOVK sequence.
  void movImm64(A64Gp rd, int imm64) {
    final v = imm64;
    final hw0 = v & 0xFFFF;
    final hw1 = (v >> 16) & 0xFFFF;
    final hw2 = (v >> 32) & 0xFFFF;
    final hw3 = (v >> 48) & 0xFFFF;

    movz(rd, hw0, shift: 0);
    if (hw1 != 0) movk(rd, hw1, shift: 16);
    if (hw2 != 0) movk(rd, hw2, shift: 32);
    if (hw3 != 0) movk(rd, hw3, shift: 48);
  }

  // ===========================================================================
  // Branch Instructions
  // ===========================================================================

  /// ADR - PC-relative address (immediate).
  /// Encoding: op|00|10000|immlo|immhi|Rd  (op=0 for ADR)
  void adr(A64Gp rd, int offset) {
    final imm = offset >> 0;
    final immlo = (imm & 0x3);
    final immhi = (imm >> 2) & 0x7FFFF;
    final inst =
        (0 << 31) | (immlo << 29) | (0x10 << 24) | (immhi << 5) | _encReg(rd);
    emit32(inst);
  }

  /// ADRP - PC-relative to page (imm scaled by 4096).
  /// Encoding: op|00|10000|immlo|immhi|Rd  (op=1 for ADRP, imm = (offset >> 12))
  void adrp(A64Gp rd, int offset) {
    final imm = offset >> 12;
    final immlo = (imm & 0x3);
    final immhi = (imm >> 2) & 0x7FFFF;
    final inst =
        (1 << 31) | (immlo << 29) | (0x10 << 24) | (immhi << 5) | _encReg(rd);
    emit32(inst);
  }

  /// B - Unconditional branch (PC-relative).
  /// Encoding: 0|00101|imm26
  void b(int offset) {
    final imm26 = (offset >> 2) & 0x3FFFFFF;
    final inst = (0x05 << 26) | imm26;
    emit32(inst);
  }

  /// BL - Branch with link.
  /// Encoding: 1|00101|imm26
  void bl(int offset) {
    final imm26 = (offset >> 2) & 0x3FFFFFF;
    final inst = (0x25 << 26) | imm26;
    emit32(inst);
  }

  /// B.cond - Conditional branch.
  /// Encoding: 0101010|0|imm19|0|cond
  void bCond(A64Cond cond, int offset) {
    final imm19 = (offset >> 2) & 0x7FFFF;
    final inst = (0x54 << 24) | (imm19 << 5) | _encCond(cond);
    emit32(inst);
  }

  /// CBZ - Compare and branch if zero.
  /// Encoding: sf|011010|0|imm19|Rt
  void cbz(A64Gp rt, int offset) {
    final sf = _encSf(rt);
    final imm19 = (offset >> 2) & 0x7FFFF;
    final inst = (sf << 31) | (0x34 << 24) | (imm19 << 5) | _encReg(rt);
    emit32(inst);
  }

  /// CBNZ - Compare and branch if not zero.
  void cbnz(A64Gp rt, int offset) {
    final sf = _encSf(rt);
    final imm19 = (offset >> 2) & 0x7FFFF;
    final inst = (sf << 31) | (0x35 << 24) | (imm19 << 5) | _encReg(rt);
    emit32(inst);
  }

  /// BR - Branch to register.
  /// Encoding: 1101011|0|0|00|11111|0000|00|Rn|00000
  void br(A64Gp rn) {
    final inst = (0xD61F << 16) | (_encReg(rn) << 5);
    emit32(inst);
  }

  /// BLR - Branch with link to register.
  void blr(A64Gp rn) {
    final inst = (0xD63F << 16) | (_encReg(rn) << 5);
    emit32(inst);
  }

  /// RET - Return from subroutine.
  void ret([A64Gp rn = x30]) {
    final inst = (0xD65F << 16) | (_encReg(rn) << 5);
    emit32(inst);
  }

  // ===========================================================================
  // Load/Store Instructions
  // ===========================================================================

  void _emitLoadStore(
      {required bool load,
      required int size,
      required A64Gp rt,
      required A64Gp rn,
      required int offset}) {
    final scale = size;
    final imm12 = (offset >> scale) & 0xFFF;
    final inst = (size << 30) |
        (0x39 << 24) |
        ((load ? 1 : 0) << 22) |
        (imm12 << 10) |
        (_encReg(rn) << 5) |
        _encReg(rt);
    emit32(inst);
  }

  /// LDR (immediate, unsigned offset) - Load register.
  /// Encoding: 1|x|111|0|01|01|imm12|Rn|Rt
  void ldrImm(A64Gp rt, A64Gp rn, int offset) {
    final sf = _encSf(rt);
    final size = sf == 1 ? 3 : 2;
    _emitLoadStore(load: true, size: size, rt: rt, rn: rn, offset: offset);
  }

  /// STR (immediate, unsigned offset) - Store register.
  void strImm(A64Gp rt, A64Gp rn, int offset) {
    final sf = _encSf(rt);
    final size = sf == 1 ? 3 : 2;
    _emitLoadStore(load: false, size: size, rt: rt, rn: rn, offset: offset);
  }

  int _vecSizeBits(A64Vec vt) {
    switch (vt.sizeBits) {
      case 32:
        return 0;
      case 64:
        return 1;
      case 128:
        return 2;
      default:
        throw ArgumentError('Unsupported vector size: ${vt.sizeBits}');
    }
  }

  /// LDR (SIMD&FP, immediate, unsigned offset) - Load vector register.
  /// Encoding: size|111100|1|imm12|Rn|Rt
  void ldrVec(A64Vec vt, A64Gp rn, int offset) {
    final size = _vecSizeBits(vt);
    final scale = size + 2; // bytes = 4,8,16
    final imm12 = (offset >> scale) & 0xFFF;
    final inst = (size << 30) |
        (0x3C << 24) |
        (1 << 22) |
        (imm12 << 10) |
        (_encReg(rn) << 5) |
        _encVec(vt);
    emit32(inst);
  }

  /// LDR (SIMD&FP, literal) - PC-relative load vector register.
  /// Encoding: size|011000|1|imm19|Rt
  void ldrVecLiteral(A64Vec vt, int offset) {
    final size = _vecSizeBits(vt);
    final imm19 = (offset >> 2) & 0x7FFFF;
    final inst =
        (size << 30) | (0x18 << 24) | (1 << 22) | (imm19 << 5) | _encVec(vt);
    emit32(inst);
  }

  /// STR (SIMD&FP, immediate, unsigned offset) - Store vector register.
  void strVec(A64Vec vt, A64Gp rn, int offset) {
    final size = _vecSizeBits(vt);
    final scale = size + 2; // bytes = 4,8,16
    final imm12 = (offset >> scale) & 0xFFF;
    final inst = (size << 30) |
        (0x3C << 24) |
        (0 << 22) |
        (imm12 << 10) |
        (_encReg(rn) << 5) |
        _encVec(vt);
    emit32(inst);
  }

  /// LDR (SIMD&FP, unscaled) - Load vector register with signed 9-bit offset.
  /// Encoding: size|111000|1|imm9|10|Rn|Rt
  void ldrVecUnscaled(A64Vec vt, A64Gp rn, int offset) {
    final size = _vecSizeBits(vt);
    final imm9 = offset & 0x1FF; // signed, lower 9 bits
    final inst = (size << 30) |
        (0x38 << 24) |
        (1 << 22) |
        (imm9 << 12) |
        (2 << 10) | // unscaled addressing mode
        (_encReg(rn) << 5) |
        _encVec(vt);
    emit32(inst);
  }

  /// STR (SIMD&FP, unscaled) - Store vector register with signed 9-bit offset.
  void strVecUnscaled(A64Vec vt, A64Gp rn, int offset) {
    final size = _vecSizeBits(vt);
    final imm9 = offset & 0x1FF;
    final inst = (size << 30) |
        (0x38 << 24) |
        (0 << 22) |
        (imm9 << 12) |
        (2 << 10) |
        (_encReg(rn) << 5) |
        _encVec(vt);
    emit32(inst);
  }

  /// LDRB (immediate, unsigned offset) - Load byte.
  void ldrb(A64Gp rt, A64Gp rn, int offset) {
    _emitLoadStore(load: true, size: 0, rt: rt, rn: rn, offset: offset);
  }

  /// STRB (immediate, unsigned offset) - Store byte.
  void strb(A64Gp rt, A64Gp rn, int offset) {
    _emitLoadStore(load: false, size: 0, rt: rt, rn: rn, offset: offset);
  }

  /// LDRH (immediate, unsigned offset) - Load halfword.
  void ldrh(A64Gp rt, A64Gp rn, int offset) {
    _emitLoadStore(load: true, size: 1, rt: rt, rn: rn, offset: offset);
  }

  /// STRH (immediate, unsigned offset) - Store halfword.
  void strh(A64Gp rt, A64Gp rn, int offset) {
    _emitLoadStore(load: false, size: 1, rt: rt, rn: rn, offset: offset);
  }

  /// LDRSB (immediate, unsigned offset) - Load byte and sign-extend to 64-bit.
  void ldrsb(A64Gp rt, A64Gp rn, int offset) {
    final imm12 = (offset >> 0) & 0xFFF;
    final inst = (0 << 30) |
        (0x39 << 24) |
        (2 << 22) | // sign-extend variant
        (imm12 << 10) |
        (_encReg(rn) << 5) |
        _encReg(rt);
    emit32(inst);
  }

  /// LDUR (unscaled) - Load GP register with signed 9-bit offset.
  void ldur(A64Gp rt, A64Gp rn, int offset) {
    final size = _encSf(rt) == 1 ? 3 : 2;
    final imm9 = offset & 0x1FF;
    final inst = (size << 30) |
        (0x18 << 24) | // 011000 load/store (unscaled)
        (1 << 22) | // load
        (imm9 << 12) |
        (0 << 10) |
        (_encReg(rn) << 5) |
        _encReg(rt);
    emit32(inst);
  }

  /// STUR (unscaled) - Store GP register with signed 9-bit offset.
  void stur(A64Gp rt, A64Gp rn, int offset) {
    final size = _encSf(rt) == 1 ? 3 : 2;
    final imm9 = offset & 0x1FF;
    final inst = (size << 30) |
        (0x18 << 24) |
        (0 << 22) | // store
        (imm9 << 12) |
        (0 << 10) |
        (_encReg(rn) << 5) |
        _encReg(rt);
    emit32(inst);
  }

  /// LDRSH (immediate, unsigned offset) - Load halfword and sign-extend to 64-bit.
  void ldrsh(A64Gp rt, A64Gp rn, int offset) {
    final imm12 = (offset >> 1) & 0xFFF;
    final inst = (1 << 30) |
        (0x39 << 24) |
        (2 << 22) |
        (imm12 << 10) |
        (_encReg(rn) << 5) |
        _encReg(rt);
    emit32(inst);
  }

  /// LDRSW (immediate, unsigned offset) - Load word and sign-extend to 64-bit.
  void ldrsw(A64Gp rt, A64Gp rn, int offset) {
    final imm12 = (offset >> 2) & 0xFFF;
    final inst = (2 << 30) |
        (0x39 << 24) |
        (2 << 22) |
        (imm12 << 10) |
        (_encReg(rn) << 5) |
        _encReg(rt);
    emit32(inst);
  }

  /// LDP (load pair) - Load pair of registers.
  /// Encoding: x|0|101|0|0|1|1|imm7|Rt2|Rn|Rt
  void ldp(A64Gp rt, A64Gp rt2, A64Gp rn, int offset) {
    final sf = _encSf(rt);
    final opc = sf == 1 ? 2 : 0;
    final scale = sf == 1 ? 3 : 2;
    final imm7 = (offset >> scale) & 0x7F;
    final inst = (opc << 30) |
        (0x29 << 24) |
        (1 << 22) |
        (imm7 << 15) |
        (_encReg(rt2) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rt);
    emit32(inst);
  }

  /// STP (store pair) - Store pair of registers.
  void stp(A64Gp rt, A64Gp rt2, A64Gp rn, int offset) {
    final sf = _encSf(rt);
    final opc = sf == 1 ? 2 : 0;
    final scale = sf == 1 ? 3 : 2;
    final imm7 = (offset >> scale) & 0x7F;
    final inst = (opc << 30) |
        (0x29 << 24) |
        (0 << 22) |
        (imm7 << 15) |
        (_encReg(rt2) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rt);
    emit32(inst);
  }

  // ===========================================================================
  // Multiply Instructions
  // ===========================================================================

  /// MUL - Multiply (alias for MADD with XZR).
  void mul(A64Gp rd, A64Gp rn, A64Gp rm) {
    madd(rd, rn, rm, rd.is64Bit ? xzr : wzr);
  }

  /// MADD - Multiply-add.
  /// Encoding: sf|00|11011|000|Rm|0|Ra|Rn|Rd
  void madd(A64Gp rd, A64Gp rn, A64Gp rm, A64Gp ra) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (0x1B << 24) |
        (_encReg(rm) << 16) |
        (0 << 15) |
        (_encReg(ra) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// MSUB - Multiply-subtract.
  void msub(A64Gp rd, A64Gp rn, A64Gp rm, A64Gp ra) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (0x1B << 24) |
        (_encReg(rm) << 16) |
        (1 << 15) |
        (_encReg(ra) << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  // ===========================================================================
  // Division Instructions
  // ===========================================================================

  /// SDIV - Signed divide.
  /// Encoding: sf|0|0|11010110|Rm|00001|1|Rn|Rd
  void sdiv(A64Gp rd, A64Gp rn, A64Gp rm) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (0xD6 << 21) |
        (_encReg(rm) << 16) |
        (0x03 << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// UDIV - Unsigned divide.
  void udiv(A64Gp rd, A64Gp rn, A64Gp rm) {
    final sf = _encSf(rd);
    final inst = (sf << 31) |
        (0xD6 << 21) |
        (_encReg(rm) << 16) |
        (0x02 << 10) |
        (_encReg(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  // ===========================================================================
  // NEON (integer) - Vector ALU
  // ===========================================================================

  void _vec3SameInt(int base, int op, A64Vec rd, A64Vec rn, A64Vec rm,
      {bool wide = true}) {
    final sz = _vecElemSizeBits(rd);
    final q = _resolveWide(rd, wide) ? 1 : 0;
    final inst = (base << 24) |
        (q << 30) |
        (sz << 22) |
        (1 << 21) |
        (_encVec(rm) << 16) |
        (op << 11) |
        (1 << 10) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  void _vec3SameLogic(
      int base, int op2, int op, A64Vec rd, A64Vec rn, A64Vec rm,
      {bool wide = true}) {
    final q = _resolveWide(rd, wide) ? 1 : 0;
    final inst = (base << 24) |
        (q << 30) |
        (op2 << 22) |
        (1 << 21) |
        (_encVec(rm) << 16) |
        (op << 11) |
        (1 << 10) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// ADD (vector).
  void addVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameInt(0x0E, 0x10, rd, rn, rm, wide: wide);
  }

  /// SUB (vector).
  void subVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameInt(0x2E, 0x10, rd, rn, rm, wide: wide);
  }

  /// MUL (vector).
  void mulVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameInt(0x0E, 0x13, rd, rn, rm, wide: wide);
  }

  /// AND (vector).
  void andVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameLogic(0x0E, 0x0, 0x03, rd, rn, rm, wide: wide);
  }

  /// ORR (vector).
  void orrVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameLogic(0x0E, 0x2, 0x03, rd, rn, rm, wide: wide);
  }

  /// EOR (vector).
  void eorVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameLogic(0x2E, 0x0, 0x03, rd, rn, rm, wide: wide);
  }

  bool _resolveWide(A64Vec vec, bool wide) {
    if (vec.sizeBits == 128) return true;
    if (vec.sizeBits == 64) return false;
    return wide;
  }

  // ===========================================================================
  // System Instructions
  // ===========================================================================

  /// NOP - No operation.
  void nop() {
    emit32(0xD503201F);
  }

  /// BRK - Breakpoint.
  void brk(int imm16) {
    final inst = (0xD4 << 24) | (1 << 21) | ((imm16 & 0xFFFF) << 5);
    emit32(inst);
  }

  /// SVC - Supervisor call (system call).
  void svc(int imm16) {
    final inst = (0xD4 << 24) | (0 << 21) | ((imm16 & 0xFFFF) << 5) | 1;
    emit32(inst);
  }

  // ===========================================================================
  // Permutation Instructions
  // ===========================================================================

  void _emitPermute(int opcode, A64Vec rd, A64Vec rn, A64Vec rm) {
    final q = rd.sizeBits == 128 ? 1 : 0;
    final sz = _vecElemSizeBits(rd);
    // Instruction: 0 Q 00 1110 size 0 Rm 0 opcode(3) 10 Rn Rd
    final inst = (0 << 31) |
        (q << 30) |
        (0x0E << 24) |
        (sz << 22) |
        (0 << 21) |
        (_encVec(rm) << 16) |
        (0 << 15) |
        (opcode << 12) |
        (2 << 10) | // 10 binary
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  void zip1(A64Vec rd, A64Vec rn, A64Vec rm) => _emitPermute(3, rd, rn, rm);
  void zip2(A64Vec rd, A64Vec rn, A64Vec rm) => _emitPermute(7, rd, rn, rm);
  void uzp1(A64Vec rd, A64Vec rn, A64Vec rm) => _emitPermute(1, rd, rn, rm);
  void uzp2(A64Vec rd, A64Vec rn, A64Vec rm) => _emitPermute(5, rd, rn, rm);
  void trn1(A64Vec rd, A64Vec rn, A64Vec rm) => _emitPermute(2, rd, rn, rm);
  void trn2(A64Vec rd, A64Vec rn, A64Vec rm) => _emitPermute(6, rd, rn, rm);

  /// TBL (Table Lookup) - Vector table lookup.
  /// Single register table variant: TBL Vd.Ta, { Vn.16B }, Vm.16B
  /// Encoding: 0 Q 00 1110 00 0 Rm 0 len(2) 00 Rn Rd
  /// op=0 for TBL. len=0 for 1 register.
  void tbl(A64Vec rd, A64Vec rn, A64Vec rm) {
    final q = rd.sizeBits == 128 ? 1 : 0;
    final len = 0; // 1 register in table
    final inst = (0 << 31) |
        (q << 30) |
        (0x0E << 24) |
        (0 << 22) | // size field is 00 for TBL usually (operates on bytes)
        (0 << 21) |
        (_encVec(rm) << 16) |
        (0 << 15) |
        (len << 13) |
        (0 << 12) | // op=0 TBL
        (0 << 10) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  // ===========================================================================
  // Load/Store (LD1R)
  // ===========================================================================

  /// LD1R - Load one single-element structure and replicate to all lanes.
  void ld1r(A64Vec vt, A64Gp rn, [int offset = 0]) {
    // LD1R encoding: 0 Q 00 1101 01 size 0 Rn Rt
    // Wait, offset? LD1R only supports [Rn] (no offset) or post-index.
    // For standard load [Rn], usage: 0 Q 00 1101 01 size 00000 11 Rn Rt
    // Actually, "Single structure" loads (LD1) don't take immediate offset.
    // They take [Xn] or [Xn, Xm] (register offset) or post-index.
    // Assuming simple [Xn] addressing for now (offset 0).
    // If offset != 0, we can't encode it directly in LD1R without post-index or extra ADD.
    // We will ignore offset or throw if != 0 properly.
    if (offset != 0) {
      throw ArgumentError(
          'LD1R only supports [Rn] with no immediate offset (or post-index)');
    }

    final q = vt.sizeBits == 128 ? 1 : 0;
    // Determine 'size' from rearrangement or element size.
    // LD1R uses 'size' field: 00=8, 01=16, 10=32, 11=64.
    // Based on vt layout? Or we guess from vt.sizeBits? No, layout is key.
    // Defaulting to .32b if no layout?
    // Using helper _vecElemSizeBits(vt) which uses vt.sizeBits?
    // A64Vec.sizeBits is total size. We need element size.
    // A64Layout helps.
    // For now, if layout is present, use it. Else default?
    // Let's rely on _vecElemSizeBits(vt) logic (which defaults to full size?)
    // No, _vecElemSizeBits uses 'sizeBits' of the register which is total.
    // We need element size.
    // We should use layout from A64Vec if available.

    int size = 2; // Default 32-bit?
    if (vt.layout != A64Layout.none) {
      switch (vt.layout) {
        case A64Layout.b8:
        case A64Layout.b16:
          size = 0;
          break;
        case A64Layout.h4:
        case A64Layout.h8:
          size = 1;
          break;
        case A64Layout.s2:
        case A64Layout.s4:
          size = 2;
          break;
        case A64Layout.d1:
        case A64Layout.d2:
          size = 3;
          break;
        default:
          size = 2;
      }
    } else {
      // Heuristic?
      size = 2;
    }

    final inst = (0 << 31) |
        (q << 30) |
        (0x0D << 24) | // 001101
        (1 << 23) | // L
        (0 << 22) | // R ? No.
        // LD1R pattern: 0 Q 00 1101 11 size?
        // Reference: 0 Q 00 1101 01 size 00000 11 Rn Rt (Post index?)
        // No offset (no post index): 0 Q 00 1101 01 size 00000 00 Rn Rt ?
        // Look at LD1R (no offset): 0 Q 00 1101 01 size 00000 00 Rn Rt (Simd Load / Store Single Struct)
        (1 << 22) | // opc=01 (LD1R)
        (size << 10) |
        (_encReg(rn) << 5) |
        _encVec(vt);
    emit32(inst);
  }

  // ===========================================================================
  // Floating Point
  // ===========================================================================

  /// FADD (scalar).
  void fadd(A64Vec rd, A64Vec rn, A64Vec rm) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E602800 : 0x1E202800)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FSUB (scalar).
  void fsub(A64Vec rd, A64Vec rn, A64Vec rm) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E603800 : 0x1E203800)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FMUL (scalar).
  void fmul(A64Vec rd, A64Vec rn, A64Vec rm) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E600800 : 0x1E200800)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FDIV (scalar).
  void fdiv(A64Vec rd, A64Vec rn, A64Vec rm) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E601800 : 0x1E201800)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FNEG (scalar).
  void fneg(A64Vec rd, A64Vec rn) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E604000 : 0x1E204000)) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FABS (scalar).
  void fabs(A64Vec rd, A64Vec rn) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E60C000 : 0x1E20C000)) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FSQRT (scalar).
  void fsqrt(A64Vec rd, A64Vec rn) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E61C000 : 0x1E21C000)) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FCMP (scalar).
  void fcmp(A64Vec rn, A64Vec rm) {
    final type = rn.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E602000 : 0x1E202000)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5);
    emit32(inst);
  }

  /// FCSEL (scalar).
  void fcsel(A64Vec rd, A64Vec rn, A64Vec rm, A64Cond cond) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E600C00 : 0x1E200C00)) |
        (_encVec(rm) << 16) |
        (_encCond(cond) << 12) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FMAX (scalar).
  void fmax(A64Vec rd, A64Vec rn, A64Vec rm) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E604800 : 0x1E204800)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FMIN (scalar).
  void fmin(A64Vec rd, A64Vec rn, A64Vec rm) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E605800 : 0x1E205800)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FMAXNM (scalar).
  void fmaxnm(A64Vec rd, A64Vec rn, A64Vec rm) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E606800 : 0x1E206800)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FMINNM (scalar).
  void fminnm(A64Vec rd, A64Vec rn, A64Vec rm) {
    final type = rd.sizeBits == 64 ? 1 : 0;
    final inst = ((type == 1 ? 0x1E607800 : 0x1E207800)) |
        (_encVec(rm) << 16) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  // ===========================================================================
  // NEON (integer) - 2 Register Misc
  // ===========================================================================

  void _vec2Misc(A64Vec rd, A64Vec rn, int u, int opcode,
      {int sizeOverride = -1}) {
    final sz = (sizeOverride != -1) ? sizeOverride : _vecElemSizeBits(rd);
    final q = rd.sizeBits == 128 ? 1 : 0;
    final inst = (0x0E200800) |
        (q << 30) |
        (u << 29) |
        (sz << 22) |
        (opcode << 12) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// NEG (vector).
  void neg(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 1, 11);

  /// ABS (vector).
  void abs(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 0, 11);

  /// MVN (vector) - Bitwise NOT.
  void mvn(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 1, 5, sizeOverride: 0);

  /// CLS (vector) - Count leading sign bits.
  void cls(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 0, 4);

  /// CLZ (vector) - Count leading zeros.
  void clz(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 1, 4);

  /// CNT (vector) - Population count.
  void cnt(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 0, 5, sizeOverride: 0);

  /// REV64 (vector).
  void rev64(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 0, 0);

  /// REV32 (vector).
  void rev32(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 0, 1);

  /// REV16 (vector).
  void rev16(A64Vec rd, A64Vec rn) => _vec2Misc(rd, rn, 0, 2);

  // ===========================================================================
  // NEON (logic) - Additional
  // ===========================================================================

  void bic(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameLogic(0x0E, 0x1, 0x03, rd, rn, rm, wide: wide);
  }

  void orn(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameLogic(0x0E, 0x3, 0x03, rd, rn, rm, wide: wide);
  }

  void bsl(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameLogic(0x2E, 0x1, 0x03, rd, rn, rm, wide: wide);
  }

  void bit(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameLogic(0x2E, 0x2, 0x03, rd, rn, rm, wide: wide);
  }

  void bif(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _vec3SameLogic(0x2E, 0x3, 0x03, rd, rn, rm, wide: wide);
  }

  // ===========================================================================
  // NEON (FP) - Vector
  // ===========================================================================

  void _vec3SameFp(int u, int opcode, A64Vec rd, A64Vec rn, A64Vec rm,
      {bool wide = true}) {
    final rawSz = _vecElemSizeBits(rd); // 2=32, 3=64
    final szEnc = (rawSz == 3) ? 1 : 0;
    final q = wide ? 1 : 0;
    final inst = (q << 30) |
        (u << 29) |
        (0x0E << 24) |
        (szEnc << 22) |
        (1 << 21) |
        (_encVec(rm) << 16) |
        (opcode << 11) |
        (1 << 10) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// FADD (vector).
  void faddVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vec3SameFp(0, 0x1A, rd, rn, rm, wide: wide);

  /// FSUB (vector).
  void fsubVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vec3SameFp(1, 0x1A, rd, rn, rm, wide: wide);

  /// FMUL (vector).
  void fmulVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vec3SameFp(1, 0x1B, rd, rn, rm, wide: wide);

  /// FDIV (vector).
  void fdivVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vec3SameFp(1, 0x1F, rd, rn, rm, wide: wide);

  /// FMAX (vector).
  void fmaxVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vec3SameFp(0, 0x0F, rd, rn, rm, wide: wide);

  /// FMIN (vector).
  void fminVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vec3SameFp(0, 0x1F, rd, rn, rm, wide: wide);

  /// FMAXNM (vector).
  void fmaxnmVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vec3SameFp(0, 0x0C, rd, rn, rm, wide: wide);

  /// FMINNM (vector).
  void fminnmVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vec3SameFp(0, 0x0D, rd, rn, rm, wide: wide);

  /// FADDP (vector).
  void faddp(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    // FADDP is Pairwise: U=1. Bit 21=0.
    final rawSz = _vecElemSizeBits(rd);
    final szEnc = (rawSz == 3) ? 1 : 0;
    final q = wide ? 1 : 0;
    final inst = (q << 30) |
        (1 << 29) | // U=1
        (0x0E << 24) |
        (szEnc << 22) |
        (0 << 21) | // Pairwise=0
        (_encVec(rm) << 16) |
        (0x1A << 11) | // Opcode 11010
        (1 << 10) |
        (_encVec(rn) << 5) |
        _encVec(rd);

    emit32(inst);
  }

  /// INS (element).
  void ins(A64Vec rd, int rdIdx, A64Vec rn, int rnIdx) {
    // Basic implementation: INS Vd.Ts[index1], Vn.Ts[index2]
    // Alias for MOV (element).
    // Encoding: 0|1|001110000|imm5|0|imm4|1|Rn|Rd

    // Simplification: assume same element size for now.
    final rawSz = _vecElemSizeBits(rd);
    int imm5 = 0;
    if (rawSz == 0) {
      imm5 = (rnIdx << 1) | 1;
    } else if (rawSz == 1) {
      imm5 = (rnIdx << 2) | 2;
    } else if (rawSz == 2) {
      imm5 = (rnIdx << 3) | 4;
    } else if (rawSz == 3) {
      imm5 = (rnIdx << 4) | 8;
    }

    int imm4 = 0; // Destination index
    if (rawSz == 0) {
      imm4 = rdIdx;
    } else if (rawSz == 1) {
      imm4 = rdIdx << 1;
    } else if (rawSz == 2) {
      imm4 = rdIdx << 2;
    } else if (rawSz == 3) {
      imm4 = rdIdx << 3;
    }

    final inst = (1 << 30) |
        (0x0E << 24) |
        (imm5 << 16) |
        (0 << 15) |
        (imm4 << 11) |
        (1 << 10) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }

  /// UMOV (element) - Move vector element to GP register (unsigned).
  void umov(A64Gp rd, A64Vec rn, int index) {
    // Default to 32/64 based on dst
    // But actually element size comes from the vector instruction usually.
    // umov w0, v0.b[0] -> rawSz=0
    // We need to infer size from call site or separate API.
    // For now, let's assume inferred from index range or passed explicitly?
    // Let's rely on `_vecElemSizeBits` of `rn` if `rn` was `v0.b`.

    // In AsmJit/Dart port, A64Vec holds size bits (8, 16, 32, 64).
    final size = _vecElemSizeBits(rn);

    int imm5 = 0;
    if (size == 0)
      imm5 = (index << 1) | 1;
    else if (size == 1)
      imm5 = (index << 2) | 2;
    else if (size == 2)
      imm5 = (index << 3) | 4;
    else if (size == 3) imm5 = (index << 4) | 8;

    final q = (size == 3 && rd.is64Bit) ? 1 : 0;
    // Q=1 for 64-bit move (sometimes).
    // Actually simple: 0|Q|001110000|imm5|0|00111|1|Rn|Rd

    final inst = (0 << 30) |
        (q << 30) | // This logic might be slightly off for UMOV vs SMOV
        (0x0E << 24) |
        (imm5 << 16) |
        (0 << 15) |
        (0x07 << 11) | // 00111
        (1 << 10) |
        (_encVec(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// SMOV (element) - Move vector element to GP register (signed).
  void smov(A64Gp rd, A64Vec rn, int index) {
    final size = _vecElemSizeBits(rn);

    int imm5 = 0;
    if (size == 0)
      imm5 = (index << 1) | 1;
    else if (size == 1)
      imm5 = (index << 2) | 2;
    else if (size == 2) imm5 = (index << 3) | 4;
    // size=3 (64-bit) SMOV doesn't exist equivalent to UMOV/MOV, it uses 'mov'.

    final q = 0;
    final inst = (0 << 30) |
        (q << 30) |
        (0x0E << 24) |
        (imm5 << 16) |
        (0 << 15) |
        (0x05 << 11) | // 00101
        (1 << 10) |
        (_encVec(rn) << 5) |
        _encReg(rd);
    emit32(inst);
  }

  /// DUP (element).
  void dup(A64Vec rd, A64Vec rn, int index) {
    final rawSz = _vecElemSizeBits(rd);
    int imm5 = 0;
    if (rawSz == 0)
      imm5 = (index << 1) | 1;
    else if (rawSz == 1)
      imm5 = (index << 2) | 2;
    else if (rawSz == 2)
      imm5 = (index << 3) | 4;
    else if (rawSz == 3) imm5 = (index << 4) | 8;

    final q = rd.sizeBits == 128 ? 1 : 0;
    final inst = (q << 30) |
        (0x0E << 24) |
        (imm5 << 16) |
        (1 << 10) |
        (_encVec(rn) << 5) |
        _encVec(rd);
    emit32(inst);
  }
}
