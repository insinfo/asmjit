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
        throw ArgumentError('Unsupported vector element size: ${vt.sizeBits}');
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
    final inst = (0 << 31) | (immlo << 29) | (0x10 << 24) | (immhi << 5) | _encReg(rd);
    emit32(inst);
  }

  /// ADRP - PC-relative to page (imm scaled by 4096).
  /// Encoding: op|00|10000|immlo|immhi|Rd  (op=1 for ADRP, imm = (offset >> 12))
  void adrp(A64Gp rd, int offset) {
    final imm = offset >> 12;
    final immlo = (imm & 0x3);
    final immhi = (imm >> 2) & 0x7FFFF;
    final inst = (1 << 31) | (immlo << 29) | (0x10 << 24) | (immhi << 5) | _encReg(rd);
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
    final inst = (size << 30) | (0x18 << 24) | (1 << 22) | (imm19 << 5) | _encVec(vt);
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
    final q = wide ? 1 : 0;
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

  void _vec3SameLogic(int base, int op2, int op, A64Vec rd, A64Vec rn, A64Vec rm,
      {bool wide = true}) {
    final q = wide ? 1 : 0;
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
    // TODO: Support explicit 64-bit vectors (Q=0) through API call sites.
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
}
