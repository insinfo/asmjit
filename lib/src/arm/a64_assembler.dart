/// AsmJit ARM64 Assembler
///
/// High-level ARM64 instruction emission API.

import '../core/code_holder.dart';
import '../core/code_buffer.dart';
import '../core/labels.dart';
import 'a64.dart';
import 'a64_encoder.dart';

/// ARM64 Assembler.
///
/// Provides a high-level API for emitting ARM64 instructions.
/// Handles label binding, relocations, and instruction encoding.
class A64Assembler {
  /// The code holder.
  final CodeHolder code;

  /// The internal code buffer.
  late final CodeBuffer _buf;

  /// The instruction encoder.
  late final A64Encoder _enc;

  /// Pending label fixups.
  final List<_A64LabelFixup> _fixups = [];

  /// Creates an ARM64 assembler for the given code holder.
  A64Assembler(this.code) {
    _buf = code.text.buffer;
    _enc = A64Encoder(_buf);
  }

  /// Creates an ARM64 assembler with a new code holder.
  factory A64Assembler.create() {
    final code = CodeHolder();
    return A64Assembler(code);
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
  void nop() {
    _enc.nop();
  }

  /// BRK - Breakpoint.
  void brk(int imm16) {
    _enc.brk(imm16);
  }

  /// SVC - Supervisor call.
  void svc(int imm16) {
    _enc.svc(imm16);
  }

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
