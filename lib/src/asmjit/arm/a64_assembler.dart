/// AsmJit ARM64 Assembler
///
/// High-level ARM64 instruction emission API.

import '../core/code_holder.dart';
import '../core/code_buffer.dart';
import '../core/labels.dart';
import 'a64.dart';
import 'a64_encoder.dart';
import 'a64_dispatcher.g.dart';

import '../core/emitter.dart';

/// ARM64 Assembler.
///
/// Provides a high-level API for emitting ARM64 instructions.
/// Handles label binding, relocations, and instruction encoding.
class A64Assembler extends BaseEmitter {
  /// Pending label fixups.
  final List<_A64LabelFixup> _fixups = [];

  /// The internal code buffer.
  late final CodeBuffer _buf;

  /// The instruction encoder.
  late final A64Encoder _enc;

  /// Creates an ARM64 assembler for the given code holder.
  A64Assembler(CodeHolder code) : super(code) {
    _buf = code.text.buffer;
    _enc = A64Encoder(_buf, this);
  }

  /// Creates an ARM64 assembler with a new code holder.
  factory A64Assembler.create() {
    final code = CodeHolder();
    return A64Assembler(code);
  }

  /// Emits a raw instruction by ID with generic operands.
  void emit(int instId, List<Object> ops) {
    instructionCount++;
    a64Dispatch(this, instId, ops);
  }

  // ===========================================================================
  // Properties
  // ===========================================================================

  /// The current offset in the code buffer.
  int get offset => _buf.length;

  // ===========================================================================
  // Labels
  // ===========================================================================

  /// Creates a new label.
  Label newLabel() => code.newLabel();

  /// Creates a new named label.
  Label newNamedLabel(String name) => code.newNamedLabel(name);

  /// Binds a label to the current position.
  void bind(Label label) {
    code.bindAt(label, offset);
  }

  // ===========================================================================
  // Data Processing - Immediate
  // ===========================================================================

  /// ADD (immediate).
  void addImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) {
    _enc.addImm(rd, rn, imm12, shift: shift);
  }

  /// SUB (immediate).
  void subImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) {
    _enc.subImm(rd, rn, imm12, shift: shift);
  }

  /// ADDS (immediate).
  void addsImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) {
    _enc.addsImm(rd, rn, imm12, shift: shift);
  }

  /// SUBS (immediate).
  void subsImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) {
    _enc.subsImm(rd, rn, imm12, shift: shift);
  }

  /// CMP (immediate).
  void cmpImm(A64Gp rn, int imm12) {
    _enc.cmpImm(rn, imm12);
  }

  /// CMN (immediate).
  void cmnImm(A64Gp rn, int imm12) {
    _enc.cmnImm(rn, imm12);
  }

  // ===========================================================================
  // Data Processing - Register
  // ===========================================================================

  /// ADD (register).
  void add(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    _enc.addReg(rd, rn, rm, shift: shift, amount: amount);
  }

  /// SUB (register).
  void sub(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    _enc.subReg(rd, rn, rm, shift: shift, amount: amount);
  }

  /// AND (register).
  void and(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    _enc.andReg(rd, rn, rm, shift: shift, amount: amount);
  }

  /// ORR (register).
  void orr(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    _enc.orrReg(rd, rn, rm, shift: shift, amount: amount);
  }

  /// EOR (register).
  void eor(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    _enc.eorReg(rd, rn, rm, shift: shift, amount: amount);
  }

  /// CMP (register).
  void cmp(A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    _enc.cmpReg(rn, rm, shift: shift, amount: amount);
  }

  /// ADC - Add with carry.
  void adc(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.adc(rd, rn, rm);

  /// ADCS - Add with carry, setting flags.
  void adcs(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.adcs(rd, rn, rm);

  /// SBC - Subtract with carry.
  void sbc(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.sbc(rd, rn, rm);

  /// ADDS (register).
  void adds(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    _enc.addsReg(rd, rn, rm, shift: shift, amount: amount);
  }

  /// SUBS (register).
  void subs(A64Gp rd, A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    _enc.subsReg(rd, rn, rm, shift: shift, amount: amount);
  }

  /// CMN (register) - Compare negative (alias for ADDS with ZR).
  void cmn(A64Gp rn, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final zr = rn.is64Bit ? xzr : wzr;
    adds(zr, rn, rm, shift: shift, amount: amount);
  }

  /// SBCS - Subtract with carry, setting flags.
  void sbcs(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.sbcs(rd, rn, rm);

  /// ANDS - Bitwise AND, setting flags.
  void ands(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      _enc.andsReg(rd, rn, rm, shift: shift, amount: amount);

  /// BIC - Bitwise Bit Clear.
  void bic(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      _enc.bicReg(rd, rn, rm, shift: shift, amount: amount);

  /// BICS - Bitwise Bit Clear, setting flags.
  void bics(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      _enc.bicsReg(rd, rn, rm, shift: shift, amount: amount);

  /// ORN - Bitwise OR NOT.
  void orn(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      _enc.ornReg(rd, rn, rm, shift: shift, amount: amount);

  /// EON - Bitwise Exclusive OR NOT.
  void eon(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      _enc.eonReg(rd, rn, rm, shift: shift, amount: amount);

  /// MVN - Bitwise NOT (alias for ORN with ZR).
  void mvn(A64Gp rd, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final zr = rd.is64Bit ? xzr : wzr;
    orn(rd, zr, rm, shift: shift, amount: amount);
  }

  /// NEG - Negate (alias for SUB with ZR).
  void neg(A64Gp rd, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final zr = rd.is64Bit ? xzr : wzr;
    sub(rd, zr, rm, shift: shift, amount: amount);
  }

  /// NEGS - Negate setting flags (alias for SUBS with ZR).
  void negs(A64Gp rd, A64Gp rm,
      {A64Shift shift = A64Shift.lsl, int amount = 0}) {
    final zr = rd.is64Bit ? xzr : wzr;
    _enc.subsReg(rd, zr, rm, shift: shift, amount: amount);
  }

  /// NGC - Negate with carry (alias for SBC with ZR).
  void ngc(A64Gp rd, A64Gp rm) {
    final zr = rd.is64Bit ? xzr : wzr;
    sbc(rd, zr, rm);
  }

  /// NGCS - Negate with carry setting flags (alias for SBCS with ZR).
  void ngcs(A64Gp rd, A64Gp rm) {
    final zr = rd.is64Bit ? xzr : wzr;
    sbcs(rd, zr, rm);
  }

  /// ASRV - Arithmetic shift right (register).
  void asrv(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.asrv(rd, rn, rm);

  /// LSLV - Logical shift left (register).
  void lslv(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.lslv(rd, rn, rm);

  /// LSRV - Logical shift right (register).
  void lsrv(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.lsrv(rd, rn, rm);

  /// RORV - Rotate right (register).
  void rorv(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.rorv(rd, rn, rm);

  /// CLZ - Count Leading Zeros.
  void clz(A64Gp rd, A64Gp rn) => _enc.clz(rd, rn);

  /// CLS - Count Leading Sign bits.
  void cls(A64Gp rd, A64Gp rn) => _enc.cls(rd, rn);

  /// RBIT - Reverse Bits.
  void rbit(A64Gp rd, A64Gp rn) => _enc.rbit(rd, rn);

  /// CCMP - Conditional Compare (register).
  void ccmp(A64Gp rn, Object rmOrImm, int nzcv, A64Cond cond) {
    if (rmOrImm is A64Gp) {
      _enc.ccmpReg(rn, rmOrImm, nzcv, cond);
    } else {
      _enc.ccmpImm(rn, rmOrImm as int, nzcv, cond);
    }
  }

  /// CCMN - Conditional Compare Negative (register).
  void ccmn(A64Gp rn, Object rmOrImm, int nzcv, A64Cond cond) {
    if (rmOrImm is A64Gp) {
      _enc.ccmnReg(rn, rmOrImm, nzcv, cond);
    } else {
      _enc.ccmnImm(rn, rmOrImm as int, nzcv, cond);
    }
  }

  void crc32b(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.crc32b(rd, rn, rm);
  void crc32h(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.crc32h(rd, rn, rm);
  void crc32w(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.crc32w(rd, rn, rm);
  void crc32x(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.crc32x(rd, rn, rm);
  void crc32cb(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.crc32cb(rd, rn, rm);
  void crc32ch(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.crc32ch(rd, rn, rm);
  void crc32cw(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.crc32cw(rd, rn, rm);
  void crc32cx(A64Gp rd, A64Gp rn, A64Gp rm) => _enc.crc32cx(rd, rn, rm);

  /// CSEL - Conditional Select.
  void csel(A64Gp rd, A64Gp rn, A64Gp rm, A64Cond cond) =>
      _enc.csel(rd, rn, rm, cond);

  /// CSINC - Conditional Select Increment.
  void csinc(A64Gp rd, A64Gp rn, A64Gp rm, A64Cond cond) =>
      _enc.csinc(rd, rn, rm, cond);

  /// CSINV - Conditional Select Invert.
  void csinv(A64Gp rd, A64Gp rn, A64Gp rm, A64Cond cond) =>
      _enc.csinv(rd, rn, rm, cond);

  /// CSNEG - Conditional Select Negate.
  void csneg(A64Gp rd, A64Gp rn, A64Gp rm, A64Cond cond) =>
      _enc.csneg(rd, rn, rm, cond);

  /// CSET - Conditional Set (alias for CSINC with ZR).
  void cset(A64Gp rd, A64Cond cond) {
    final zr = rd.is64Bit ? xzr : wzr;
    csinc(rd, zr, zr, cond.inverse);
  }

  /// CSETM - Conditional Set Mask (alias for CSINV with ZR).
  void csetm(A64Gp rd, A64Cond cond) {
    final zr = rd.is64Bit ? xzr : wzr;
    csinv(rd, zr, zr, cond.inverse);
  }

  /// CINC - Conditional Increment (alias for CSINC).
  void cinc(A64Gp rd, A64Gp rn, A64Cond cond) =>
      csinc(rd, rn, rn, cond.inverse);

  /// CINV - Conditional Invert (alias for CSINV).
  void cinv(A64Gp rd, A64Gp rn, A64Cond cond) =>
      csinv(rd, rn, rn, cond.inverse);

  /// CNEG - Conditional Negate (alias for CSNEG).
  void cneg(A64Gp rd, A64Gp rn, A64Cond cond) =>
      csneg(rd, rn, rn, cond.inverse);

  /// EXTR - Extract.
  void extr(A64Gp rd, A64Gp rn, A64Gp rm, int amount) =>
      _enc.extr(rd, rn, rm, amount);

  /// SBFM - Signed Bitfield Move.
  void sbfm(A64Gp rd, A64Gp rn, int immr, int imms) =>
      _enc.sbfm(rd, rn, immr, imms);

  /// UBFM - Unsigned Bitfield Move.
  void ubfm(A64Gp rd, A64Gp rn, int immr, int imms) =>
      _enc.ubfm(rd, rn, immr, imms);

  /// SBFX - Signed Bitfield Extract (alias for SBFM).
  void sbfx(A64Gp rd, A64Gp rn, int lsb, int width) =>
      sbfm(rd, rn, lsb, lsb + width - 1);

  /// SBFIZ - Signed Bitfield Insert in Zero (alias for SBFM).
  void sbfiz(A64Gp rd, A64Gp rn, int lsb, int width) {
    final mask = rd.is64Bit ? 63 : 31;
    sbfm(rd, rn, (-lsb) & mask, width - 1);
  }

  /// UBFX - Unsigned Bitfield Extract (alias for UBFM).
  void ubfx(A64Gp rd, A64Gp rn, int lsb, int width) =>
      ubfm(rd, rn, lsb, lsb + width - 1);

  /// UBFIZ - Unsigned Bitfield Insert in Zero (alias for UBFM).
  void ubfiz(A64Gp rd, A64Gp rn, int lsb, int width) {
    final mask = rd.is64Bit ? 63 : 31;
    ubfm(rd, rn, (-lsb) & mask, width - 1);
  }

  /// BFXIL - Bitfield Extract and Insert at Low end (alias for BFM).
  void bfxil(A64Gp rd, A64Gp rn, int lsb, int width) {
    // BFM: opc=01 (BFC/BFI/BFM/BFXIL are all same group)
    // Actually BFXIL is BFM with r=lsb, s=lsb+width-1
    _enc.bfm(rd, rn, lsb, lsb + width - 1);
  }

  /// BFI - Bitfield Insert (alias for BFM).
  void bfi(A64Gp rd, A64Gp rn, int lsb, int width) {
    final mask = rd.is64Bit ? 63 : 31;
    _enc.bfm(rd, rn, (-lsb) & mask, width - 1);
  }

  /// BFC - Bitfield Clear (alias for BFI with ZR).
  void bfc(A64Gp rd, int lsb, int width) {
    final zr = rd.is64Bit ? xzr : wzr;
    bfi(rd, zr, lsb, width);
  }

  /// BFM - Bitfield Move.
  void bfm(A64Gp rd, A64Gp rn, int immr, int imms) {
    _enc.bfm(rd, rn, immr, imms);
  }

  /// SXTB - Sign extend byte.
  void sxtb(A64Gp rd, A64Gp rn) => sbfm(rd, rn, 0, 7);

  /// SXTH - Sign extend halfword.
  void sxth(A64Gp rd, A64Gp rn) => sbfm(rd, rn, 0, 15);

  /// SXTW - Sign extend word (only for 64-bit).
  void sxtw(A64Gp rd, A64Gp rn) => sbfm(rd, rn, 0, 31);

  /// UXTB - Zero extend byte.
  void uxtb(A64Gp rd, A64Gp rn) => ubfm(rd, rn, 0, 7);

  /// UXTH - Zero extend halfword.
  void uxth(A64Gp rd, A64Gp rn) => ubfm(rd, rn, 0, 15);

  /// ASR - Arithmetic shift right (immediate).
  void asr(A64Gp rd, A64Gp rn, int amount) =>
      sbfm(rd, rn, amount, rd.is64Bit ? 63 : 31);

  /// LSR - Logical shift right (immediate).
  void lsr(A64Gp rd, A64Gp rn, int amount) =>
      ubfm(rd, rn, amount, rd.is64Bit ? 63 : 31);

  /// LSL - Logical shift left (immediate).
  void lsl(A64Gp rd, A64Gp rn, int amount) {
    final mask = rd.is64Bit ? 63 : 31;
    ubfm(rd, rn, (-amount) & mask, mask - amount);
  }

  // ===========================================================================
  // Move Instructions
  // ===========================================================================

  /// MOV (register).
  void mov(A64Gp rd, A64Gp rm) {
    _enc.movReg(rd, rm);
  }

  /// MOVZ - Move wide with zero.
  void movz(A64Gp rd, int imm16, {int shift = 0}) {
    _enc.movz(rd, imm16, shift: shift);
  }

  /// MOVK - Move wide with keep.
  void movk(A64Gp rd, int imm16, {int shift = 0}) {
    _enc.movk(rd, imm16, shift: shift);
  }

  /// MOVN - Move wide with not.
  void movn(A64Gp rd, int imm16, {int shift = 0}) {
    _enc.movn(rd, imm16, shift: shift);
  }

  /// Load a 64-bit immediate.
  void movImm64(A64Gp rd, int imm64) {
    _enc.movImm64(rd, imm64);
  }

  // ===========================================================================
  // Branch Instructions
  // ===========================================================================

  /// B - Unconditional branch to label.
  void b(Label label) {
    final currentOffset = offset;
    _enc.b(0); // Placeholder
    _fixups.add(_A64LabelFixup(label, currentOffset, _A64FixupKind.branch26));
  }

  /// ADR - PC-relative address (immediate).
  void adr(A64Gp rd, int offset) {
    _enc.adr(rd, offset);
  }

  /// ADRP - PC-relative page address (immediate, offset is byte distance).
  void adrp(A64Gp rd, int offset) {
    _enc.adrp(rd, offset);
  }

  /// BL - Branch with link to label.
  void bl(Label label) {
    final currentOffset = offset;
    _enc.bl(0);
    _fixups.add(_A64LabelFixup(label, currentOffset, _A64FixupKind.branch26));
  }

  /// B.cond - Conditional branch to label.
  void bCond(A64Cond cond, Label label) {
    final currentOffset = offset;
    _enc.bCond(cond, 0);
    _fixups.add(_A64LabelFixup(label, currentOffset, _A64FixupKind.branch19));
  }

  /// CBZ - Compare and branch if zero.
  void cbz(A64Gp rt, Label label) {
    final currentOffset = offset;
    _enc.cbz(rt, 0);
    _fixups.add(_A64LabelFixup(label, currentOffset, _A64FixupKind.branch19));
  }

  /// CBNZ - Compare and branch if not zero.
  void cbnz(A64Gp rt, Label label) {
    final currentOffset = offset;
    _enc.cbnz(rt, 0);
    _fixups.add(_A64LabelFixup(label, currentOffset, _A64FixupKind.branch19));
  }

  /// Convenience conditional branches.
  void beq(Label label) => bCond(A64Cond.eq, label);
  void bne(Label label) => bCond(A64Cond.ne, label);
  void bge(Label label) => bCond(A64Cond.ge, label);
  void blt(Label label) => bCond(A64Cond.lt, label);
  void bgt(Label label) => bCond(A64Cond.gt, label);
  void ble(Label label) => bCond(A64Cond.le, label);

  /// BR - Branch to register.
  void br(A64Gp rn) {
    _enc.br(rn);
  }

  /// BLR - Branch with link to register.
  void blr(A64Gp rn) {
    _enc.blr(rn);
  }

  /// RET - Return from subroutine.
  void ret([A64Gp rn = x30]) {
    _enc.ret(rn);
  }

  // ===========================================================================
  // Load/Store Instructions
  // ===========================================================================

  /// LDR (immediate).
  void ldr(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.ldrImm(rt, rn, offset);
  }

  /// LDRSB (immediate).
  void ldrsb(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.ldrsb(rt, rn, offset);
  }

  /// LDRSH (immediate).
  void ldrsh(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.ldrsh(rt, rn, offset);
  }

  /// LDRSW (immediate).
  void ldrsw(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.ldrsw(rt, rn, offset);
  }

  /// LDRB (immediate).
  void ldrb(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.ldrb(rt, rn, offset);
  }

  /// LDRH (immediate).
  void ldrh(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.ldrh(rt, rn, offset);
  }

  /// STR (immediate).
  void str(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.strImm(rt, rn, offset);
  }

  /// LDR (SIMD/FP, immediate).
  void ldrVec(A64Vec vt, A64Gp rn, [int offset = 0]) {
    _enc.ldrVec(vt, rn, offset);
  }

  /// STR (SIMD/FP, immediate).
  void strVec(A64Vec vt, A64Gp rn, [int offset = 0]) {
    _enc.strVec(vt, rn, offset);
  }

  /// LDR (SIMD/FP, unscaled signed offset).
  void ldrVecUnscaled(A64Vec vt, A64Gp rn, [int offset = 0]) {
    _enc.ldrVecUnscaled(vt, rn, offset);
  }

  /// STR (SIMD/FP, unscaled signed offset).
  void strVecUnscaled(A64Vec vt, A64Gp rn, [int offset = 0]) {
    _enc.strVecUnscaled(vt, rn, offset);
  }

  /// LDR (SIMD/FP, literal PC-relative).
  void ldrVecLiteral(A64Vec vt, int offset) {
    _enc.ldrVecLiteral(vt, offset);
  }

  /// LDUR (GP, unscaled signed offset).
  void ldur(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.ldur(rt, rn, offset);
  }

  /// STUR (GP, unscaled signed offset).
  void stur(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.stur(rt, rn, offset);
  }

  /// STRB (immediate).
  void strb(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.strb(rt, rn, offset);
  }

  /// STRH (immediate).
  void strh(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _enc.strh(rt, rn, offset);
  }

  /// LDP - Load pair.
  void ldp(A64Gp rt, A64Gp rt2, A64Gp rn, [int offset = 0]) {
    _enc.ldp(rt, rt2, rn, offset);
  }

  /// STP - Store pair.
  void stp(A64Gp rt, A64Gp rt2, A64Gp rn, [int offset = 0]) {
    _enc.stp(rt, rt2, rn, offset);
  }

  // ===========================================================================
  // Multiply/Divide Instructions
  // ===========================================================================

  /// MUL - Multiply.
  void mul(A64Gp rd, A64Gp rn, A64Gp rm) {
    _enc.mul(rd, rn, rm);
  }

  /// MADD - Multiply-add.
  void madd(A64Gp rd, A64Gp rn, A64Gp rm, A64Gp ra) {
    _enc.madd(rd, rn, rm, ra);
  }

  /// MSUB - Multiply-subtract.
  void msub(A64Gp rd, A64Gp rn, A64Gp rm, A64Gp ra) {
    _enc.msub(rd, rn, rm, ra);
  }

  /// SDIV - Signed divide.
  void sdiv(A64Gp rd, A64Gp rn, A64Gp rm) {
    _enc.sdiv(rd, rn, rm);
  }

  /// UDIV - Unsigned divide.
  void udiv(A64Gp rd, A64Gp rn, A64Gp rm) {
    _enc.udiv(rd, rn, rm);
  }

  // ===========================================================================
  // System Instructions
  // ===========================================================================

  /// NOP - No operation.
  void nop() => _enc.nop();

  /// BRK - Breakpoint.
  void brk(int imm) => _enc.brk(imm);

  /// SVC - Supervisor call.
  void svc(int imm) => _enc.svc(imm);

  void dmb(int option) => _enc.dmb(option);
  void dsb(int option) => _enc.dsb(option);
  void isb(int option) => _enc.isb(option);

  // ===========================================================================
  // Floating Point Instructions
  // ===========================================================================

  /// FADD (scalar).
  void fadd(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.fadd(rd, rn, rm);

  /// FSUB (scalar).
  void fsub(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.fsub(rd, rn, rm);

  /// FMUL (scalar).
  void fmul(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.fmul(rd, rn, rm);

  /// FDIV (scalar).
  void fdiv(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.fdiv(rd, rn, rm);

  // ===========================================================================
  // NEON (integer) - Vector ALU
  // ===========================================================================

  void addVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _enc.addVec(rd, rn, rm, wide: wide);
  }

  void subVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _enc.subVec(rd, rn, rm, wide: wide);
  }

  void mulVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _enc.mulVec(rd, rn, rm, wide: wide);
  }

  void andVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _enc.andVec(rd, rn, rm, wide: wide);
  }

  void orrVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _enc.orrVec(rd, rn, rm, wide: wide);
  }

  void eorVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) {
    _enc.eorVec(rd, rn, rm, wide: wide);
  }

  // ===========================================================================
  // Floating Point (Scalar - Additional)
  // ===========================================================================

  void fneg(A64Vec rd, A64Vec rn) => _enc.fneg(rd, rn);
  void fabs(A64Vec rd, A64Vec rn) => _enc.fabs(rd, rn);
  void fsqrt(A64Vec rd, A64Vec rn) => _enc.fsqrt(rd, rn);
  void fcmp(A64Vec rn, A64Vec rm) => _enc.fcmp(rn, rm);
  void fcsel(A64Vec rd, A64Vec rn, A64Vec rm, A64Cond cond) =>
      _enc.fcsel(rd, rn, rm, cond);
  void fmax(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.fmax(rd, rn, rm);
  void fmin(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.fmin(rd, rn, rm);
  void fmaxnm(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.fmaxnm(rd, rn, rm);
  void fminnm(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.fminnm(rd, rn, rm);

  // ===========================================================================
  // NEON (Integer) - Misc and Logic
  // ===========================================================================

  void negVec(A64Vec rd, A64Vec rn) => _enc.negVec(rd, rn);
  void abs(A64Vec rd, A64Vec rn) => _enc.abs(rd, rn);
  void mvnVec(A64Vec rd, A64Vec rn) => _enc.mvnVec(rd, rn);
  void clsVec(A64Vec rd, A64Vec rn) => _enc.clsVec(rd, rn);
  void clzVec(A64Vec rd, A64Vec rn) => _enc.clzVec(rd, rn);
  void cntVec(A64Vec rd, A64Vec rn) => _enc.cntVec(rd, rn);
  void rev64(A64Vec rd, A64Vec rn) => _enc.rev64(rd, rn);
  void rev32(A64Vec rd, A64Vec rn) => _enc.rev32(rd, rn);
  void rev16(A64Vec rd, A64Vec rn) => _enc.rev16(rd, rn);

  void bicVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.bicVec(rd, rn, rm, wide: wide);
  void ornVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.ornVec(rd, rn, rm, wide: wide);
  void bsl(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.bsl(rd, rn, rm, wide: wide);
  void bit(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.bit(rd, rn, rm, wide: wide);
  void bif(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.bif(rd, rn, rm, wide: wide);

  // ===========================================================================
  // NEON (FP) - Vector
  // ===========================================================================

  void faddVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.faddVec(rd, rn, rm, wide: wide);
  void fsubVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.fsubVec(rd, rn, rm, wide: wide);
  void fmulVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.fmulVec(rd, rn, rm, wide: wide);
  void fdivVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.fdivVec(rd, rn, rm, wide: wide);

  void fmaxVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.fmaxVec(rd, rn, rm, wide: wide);
  void fminVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.fminVec(rd, rn, rm, wide: wide);
  void fmaxnmVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.fmaxnmVec(rd, rn, rm, wide: wide);
  void fminnmVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.fminnmVec(rd, rn, rm, wide: wide);
  void faddp(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _enc.faddp(rd, rn, rm, wide: wide);

  // ===========================================================================
  // Permutation Instructions
  // ===========================================================================

  void tbl(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.tbl(rd, rn, rm);

  void zip1(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.zip1(rd, rn, rm);
  void zip2(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.zip2(rd, rn, rm);

  void uzp1(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.uzp1(rd, rn, rm);
  void uzp2(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.uzp2(rd, rn, rm);

  void trn1(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.trn1(rd, rn, rm);
  void trn2(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.trn2(rd, rn, rm);

  // ===========================================================================
  // Load/Store (LD1R)
  // ===========================================================================

  /// LD1R - Load one single-element structure and replicate to all lanes.
  void ld1r(A64Vec vt, A64Gp rn, {int offset = 0}) {
    _enc.ld1r(vt, rn, offset);
  }

  // ===========================================================================
  // Vector Moves
  // ===========================================================================

  void dup(A64Vec rd, A64Vec rn, int index) => _enc.dup(rd, rn, index);
  void ins(A64Vec rd, int rdIdx, A64Vec rn, int rnIdx) =>
      _enc.ins(rd, rdIdx, rn, rnIdx);
  void umov(A64Gp rd, A64Vec rn, int index) => _enc.umov(rd, rn, index);
  void smov(A64Gp rd, A64Vec rn, int index) => _enc.smov(rd, rn, index);

  // ===========================================================================
  // Widening Multiply
  // ===========================================================================

  /// SMULL - Signed multiply long (lo)
  void smull(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.smull(rd, rn, rm);

  /// UMULL - Unsigned multiply long (lo)
  void umull(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.umull(rd, rn, rm);

  /// SMULL2 - Signed multiply long (hi)
  void smull2(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.smull2(rd, rn, rm);

  /// UMULL2 - Unsigned multiply long (hi)
  void umull2(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.umull2(rd, rn, rm);

  /// SMLAL - Signed multiply-accumulate long (lo)
  void smlal(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.smlal(rd, rn, rm);

  /// UMLAL - Unsigned multiply-accumulate long (lo)
  void umlal(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.umlal(rd, rn, rm);

  /// SMLAL2 - Signed multiply-accumulate long (hi)
  void smlal2(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.smlal2(rd, rn, rm);

  /// UMLAL2 - Unsigned multiply-accumulate long (hi)
  void umlal2(A64Vec rd, A64Vec rn, A64Vec rm) => _enc.umlal2(rd, rn, rm);

  // ===========================================================================
  // Narrowing (Packing)
  // ===========================================================================

  /// XTN - Extract narrow
  void xtn(A64Vec rd, A64Vec rn) => _enc.xtn(rd, rn);

  /// XTN2 - Extract narrow (high)
  void xtn2(A64Vec rd, A64Vec rn) => _enc.xtn2(rd, rn);

  /// SQXTN - Signed saturating extract narrow
  void sqxtn(A64Vec rd, A64Vec rn) => _enc.sqxtn(rd, rn);

  /// SQXTN2 - Signed saturating extract narrow (high)
  void sqxtn2(A64Vec rd, A64Vec rn) => _enc.sqxtn2(rd, rn);

  /// UQXTN - Unsigned saturating extract narrow
  void uqxtn(A64Vec rd, A64Vec rn) => _enc.uqxtn(rd, rn);

  /// UQXTN2 - Unsigned saturating extract narrow (high)
  void uqxtn2(A64Vec rd, A64Vec rn) => _enc.uqxtn2(rd, rn);

  // ===========================================================================
  // Conversions
  // ===========================================================================

  /// SCVTF - Signed integer to float
  void scvtf(A64Vec rd, A64Vec rn) => _enc.scvtf(rd, rn);

  /// UCVTF - Unsigned integer to float
  void ucvtf(A64Vec rd, A64Vec rn) => _enc.ucvtf(rd, rn);

  /// FCVTZS - Float to signed integer (round toward zero)
  void fcvtzs(A64Vec rd, A64Vec rn) => _enc.fcvtzs(rd, rn);

  /// FCVTZU - Float to unsigned integer (round toward zero)
  void fcvtzu(A64Vec rd, A64Vec rn) => _enc.fcvtzu(rd, rn);

  /// FCVT - Floating-point convert precision
  void fcvt(A64Vec rd, A64Vec rn) => _enc.fcvt(rd, rn);

  // ===========================================================================
  // Prologue/Epilogue Helpers
  // ===========================================================================

  /// Emit a standard AAPCS64 prologue.
  void emitPrologue({int stackSize = 0}) {
    // STP x29, x30, [sp, #-16]!
    stp(x29, x30, sp, -16);
    mov(x29, sp);
    if (stackSize > 0) {
      subImm(sp, sp, stackSize);
    }
  }

  /// Emit a standard AAPCS64 epilogue.
  void emitEpilogue({int stackSize = 0}) {
    if (stackSize > 0) {
      addImm(sp, sp, stackSize);
    }
    ldp(x29, x30, sp, 16);
    ret();
  }

  // ===========================================================================
  // Finalization
  // ===========================================================================

  /// Resolves all label fixups and returns the finalized code.
  FinalizedCode finalize() {
    // Resolve ARM64-specific fixups
    for (final fixup in _fixups) {
      final labelOffset = code.getLabelOffset(fixup.label);
      if (labelOffset == null) {
        throw StateError('Label ${fixup.label} is not bound');
      }

      final relOffset = labelOffset - fixup.atOffset;

      switch (fixup.kind) {
        case _A64FixupKind.branch26:
          // B/BL: imm26 at bits [25:0], scaled by 4
          final imm26 = (relOffset >> 2) & 0x3FFFFFF;
          final existing = _buf.read32At(fixup.atOffset);
          _buf.write32At(fixup.atOffset, (existing & 0xFC000000) | imm26);
          break;

        case _A64FixupKind.branch19:
          // B.cond/CBZ/CBNZ: imm19 at bits [23:5], scaled by 4
          final imm19 = (relOffset >> 2) & 0x7FFFF;
          final existing = _buf.read32At(fixup.atOffset);
          _buf.write32At(
              fixup.atOffset, (existing & 0xFF00001F) | (imm19 << 5));
          break;
      }
    }

    return code.finalize();
  }

  // ===========================================================================
  // Raw Bytes
  // ===========================================================================

  /// Emit raw bytes.
  void emitBytes(List<int> bytes) {
    for (final b in bytes) {
      _buf.emit8(b);
    }
  }

  /// Emit a 32-bit instruction directly.
  void emit32(int inst) {
    _enc.emit32(inst);
  }
}

/// ARM64 label fixup kind.
enum _A64FixupKind {
  /// 26-bit branch (B, BL).
  branch26,

  /// 19-bit conditional branch (B.cond, CBZ, CBNZ).
  branch19,
}

/// ARM64 label fixup.
class _A64LabelFixup {
  final Label label;
  final int atOffset;
  final _A64FixupKind kind;

  const _A64LabelFixup(this.label, this.atOffset, this.kind);
}
