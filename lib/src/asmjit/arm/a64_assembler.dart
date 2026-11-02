/// AsmJit ARM64 Assembler
///
/// High-level ARM64 instruction emission API.

import '../core/code_holder.dart';
import '../core/code_buffer.dart';
import '../core/labels.dart';
import 'a64.dart';
import 'a64_emit.dart';
import 'a64_inst_db.g.dart';

import '../core/assembler.dart';

/// ARM64 Assembler.
///
/// Provides a high-level API for emitting ARM64 instructions.
/// Handles label binding, relocations, and instruction encoding.
class A64Assembler extends BaseAssembler {
  /// The buffer of the current section.
  CodeBuffer get _buf => buffer;

  /// Creates an ARM64 assembler for the given code holder.
  A64Assembler(super.code);

  /// Creates an ARM64 assembler with a new code holder.
  factory A64Assembler.create() {
    final code = CodeHolder();
    return A64Assembler(code);
  }

  /// Port of upstream `a64::Assembler::_emit()` (a64_emit.dart).
  late final A64Emitter _emitter = A64Emitter(code, currentSection);

  @override
  void onSectionChanged(Section section) => _emitter.section = section;

  /// Emits a raw instruction by ID with generic operands (registers,
  /// [A64Mem], integers, [A64ShiftOp], [A64Cond] and [Label]s), encoded as
  /// upstream `a64::Assembler::_emit()`.
  void emit(int instId, List<Object> ops) {
    instructionCount++;
    _emitter.emit(instId, ops);
  }

  // ===========================================================================
  // Vector arrangements
  // ===========================================================================

  static const _arrangements = [
    [A64Layout.b8, A64Layout.b16],
    [A64Layout.h4, A64Layout.h8],
    [A64Layout.s2, A64Layout.s4],
    [A64Layout.d1, A64Layout.d2],
  ];

  /// Element size (0 = B, 1 = H, 2 = S, 3 = D) of [v]: its arrangement, or
  /// the register size of a scalar register.
  static int _elementSize(A64Vec v) => switch (v.layout) {
        A64Layout.b8 || A64Layout.b16 => 0,
        A64Layout.h4 || A64Layout.h8 => 1,
        A64Layout.s2 || A64Layout.s4 => 2,
        A64Layout.d1 || A64Layout.d2 => 3,
        _ => switch (v.sizeBits) {
            8 => 0,
            16 => 1,
            32 => 2,
            64 => 3,
            _ => throw ArgumentError('Unsupported vector element size: '
                '${v.sizeBits}. Use explicit layout (e.g. .b16, .s4).'),
          },
      };

  /// Whether [v] is a 128-bit vector: its arrangement or size, else [wide].
  static bool _isQ(A64Vec v, bool wide) => switch (v.layout) {
        A64Layout.b16 ||
        A64Layout.h8 ||
        A64Layout.s4 ||
        A64Layout.d2 ||
        A64Layout.q1 =>
          true,
        A64Layout.b8 || A64Layout.h4 || A64Layout.s2 || A64Layout.d1 => false,
        A64Layout.none => v.sizeBits == 128
            ? true
            : v.sizeBits == 64
                ? false
                : wide,
      };

  /// [v] with the arrangement of [size] elements in a 128-bit ([q]) or
  /// 64-bit register (`v.b16()`, `v.s2()`...).
  static A64Vec _arr(A64Vec v, int size, bool q) {
    if (size < 0 || size >= _arrangements.length) {
      throw ArgumentError('No vector arrangement with ${8 << size}-bit '
          'elements for $v');
    }
    return A64Vec(v.id, q ? 128 : 64, _arrangements[size][q ? 1 : 0]);
  }

  /// [v] as a scalar register of its size (`q0`, `d0`, `s0`...), the form
  /// upstream loads and stores take.
  static A64Vec _scalar(A64Vec v) => A64Vec(v.id, v.sizeBits);

  /// Element [index] of [size] (0 = B ... 3 = D) of [v] (`v.s(index)`).
  static A64Vec _elem(A64Vec v, int size, int index) => v.at(size + 1, index);

  /// Operands of a "same arrangement" vector instruction: the arrangement of
  /// [rd] (or [wide] when [rd] has neither arrangement nor 64/128-bit size).
  void _vecSame(int instId, List<A64Vec> regs,
      {bool wide = true, int? size, List<Object> extra = const []}) {
    final rd = regs.first;
    final sz = size ?? _elementSize(rd);
    final q = _isQ(rd, wide);
    emit(instId, [for (final r in regs) _arr(r, sz, q), ...extra]);
  }

  /// Bitwise vector instruction (`and v0.16b, v1.16b, v2.16b`).
  void _vecLogic(int instId, List<A64Vec> regs, {bool wide = true}) =>
      _vecSame(instId, regs, wide: wide, size: 0);

  /// FP vector instruction: S or D elements (`fadd v0.4s, ...`).
  void _vecFp(int instId, List<A64Vec> regs, {bool wide = true}) =>
      _vecSame(instId, regs,
          wide: wide, size: _elementSize(regs.first) == 3 ? 3 : 2);

  /// Long instruction (`smull v0.8h, v1.8b, v2.8b`, `smull2` when [q]): the
  /// element size of the narrow sources.
  void _vecLong(int instId, int instId2, A64Vec rd, A64Vec rn, A64Vec rm,
      {required bool q}) {
    final sz = _elementSize(rn);
    emit(q ? instId2 : instId,
        [_arr(rd, sz + 1, true), _arr(rn, sz, q), _arr(rm, sz, q)]);
  }

  /// Narrowing instruction (`xtn v0.8b, v1.8h`, `xtn2` when [q]): the element
  /// size of the narrow destination.
  void _vecNarrow(int instId, int instId2, A64Vec rd, A64Vec rn,
      {required bool q, List<Object> extra = const []}) {
    final sz = _elementSize(rd);
    emit(q ? instId2 : instId,
        [_arr(rd, sz, q), _arr(rn, sz + 1, true), ...extra]);
  }

  // ===========================================================================
  // Data Processing - Immediate
  // ===========================================================================

  /// ADD (immediate); [shift] 12 is `imm12, lsl #12`.
  void addImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) =>
      emit(A64InstId.kAdd, [rd, rn, imm12 << shift]);

  /// SUB (immediate).
  void subImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) =>
      emit(A64InstId.kSub, [rd, rn, imm12 << shift]);

  /// ADDS (immediate).
  void addsImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) =>
      emit(A64InstId.kAdds, [rd, rn, imm12 << shift]);

  /// SUBS (immediate).
  void subsImm(A64Gp rd, A64Gp rn, int imm12, {int shift = 0}) =>
      emit(A64InstId.kSubs, [rd, rn, imm12 << shift]);

  /// CMP (immediate).
  void cmpImm(A64Gp rn, int imm12) => emit(A64InstId.kCmp, [rn, imm12]);

  /// CMN (immediate).
  void cmnImm(A64Gp rn, int imm12) => emit(A64InstId.kCmn, [rn, imm12]);

  // ===========================================================================
  // Data Processing - Register
  // ===========================================================================

  /// Operands of a shifted-register instruction (`add x0, x1, x2, lsl #3`).
  static List<Object> _shifted(List<Object> regs, A64Shift shift, int amount) =>
      [...regs, if (amount != 0) A64ShiftOp(shift, amount)];

  /// ADD (register).
  void add(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kAdd, _shifted([rd, rn, rm], shift, amount));

  /// SUB (register).
  void sub(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kSub, _shifted([rd, rn, rm], shift, amount));

  /// AND (register).
  void and(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kAnd, _shifted([rd, rn, rm], shift, amount));

  /// ORR (register).
  void orr(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kOrr, _shifted([rd, rn, rm], shift, amount));

  /// EOR (register).
  void eor(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kEor, _shifted([rd, rn, rm], shift, amount));

  /// CMP (register).
  void cmp(A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kCmp, _shifted([rn, rm], shift, amount));

  /// ADC - Add with carry.
  void adc(A64Gp rd, A64Gp rn, A64Gp rm) => emit(A64InstId.kAdc, [rd, rn, rm]);

  /// ADCS - Add with carry, setting flags.
  void adcs(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kAdcs, [rd, rn, rm]);

  /// SBC - Subtract with carry.
  void sbc(A64Gp rd, A64Gp rn, A64Gp rm) => emit(A64InstId.kSbc, [rd, rn, rm]);

  /// ADDS (register).
  void adds(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kAdds, _shifted([rd, rn, rm], shift, amount));

  /// SUBS (register).
  void subs(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kSubs, _shifted([rd, rn, rm], shift, amount));

  /// CMN (register) - Compare negative (alias for ADDS with ZR).
  void cmn(A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kCmn, _shifted([rn, rm], shift, amount));

  /// SBCS - Subtract with carry, setting flags.
  void sbcs(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kSbcs, [rd, rn, rm]);

  /// ANDS - Bitwise AND, setting flags.
  void ands(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kAnds, _shifted([rd, rn, rm], shift, amount));

  /// AND/ORR/EOR/ANDS (immediate) with a logical (bitmask) immediate; [opc]
  /// is 0 (AND), 1 (ORR), 2 (EOR) or 3 (ANDS).
  void logicalImm(int opc, A64Gp rd, A64Gp rn, int value) => emit(
      const [
        A64InstId.kAnd,
        A64InstId.kOrr,
        A64InstId.kEor,
        A64InstId.kAnds
      ][opc],
      [rd, rn, value]);

  /// REV (reverse bytes).
  void rev(A64Gp rd, A64Gp rn) => emit(A64InstId.kRev, [rd, rn]);

  /// BIC - Bitwise Bit Clear.
  void bic(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kBic, _shifted([rd, rn, rm], shift, amount));

  /// BICS - Bitwise Bit Clear, setting flags.
  void bics(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kBics, _shifted([rd, rn, rm], shift, amount));

  /// ORN - Bitwise OR NOT.
  void orn(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kOrn, _shifted([rd, rn, rm], shift, amount));

  /// EON - Bitwise Exclusive OR NOT.
  void eon(A64Gp rd, A64Gp rn, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kEon, _shifted([rd, rn, rm], shift, amount));

  /// MVN - Bitwise NOT (alias for ORN with ZR).
  void mvn(A64Gp rd, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kMvn, _shifted([rd, rm], shift, amount));

  /// NEG - Negate (alias for SUB with ZR).
  void neg(A64Gp rd, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kNeg, _shifted([rd, rm], shift, amount));

  /// NEGS - Negate setting flags (alias for SUBS with ZR).
  void negs(A64Gp rd, A64Gp rm,
          {A64Shift shift = A64Shift.lsl, int amount = 0}) =>
      emit(A64InstId.kNegs, _shifted([rd, rm], shift, amount));

  /// NGC - Negate with carry (alias for SBC with ZR).
  void ngc(A64Gp rd, A64Gp rm) => emit(A64InstId.kNgc, [rd, rm]);

  /// NGCS - Negate with carry setting flags (alias for SBCS with ZR).
  void ngcs(A64Gp rd, A64Gp rm) => emit(A64InstId.kNgcs, [rd, rm]);

  /// ASRV - Arithmetic shift right (register).
  void asrv(A64Gp rd, A64Gp rn, A64Gp rm) => emit(A64InstId.kAsr, [rd, rn, rm]);

  /// LSLV - Logical shift left (register).
  void lslv(A64Gp rd, A64Gp rn, A64Gp rm) => emit(A64InstId.kLsl, [rd, rn, rm]);

  /// LSRV - Logical shift right (register).
  void lsrv(A64Gp rd, A64Gp rn, A64Gp rm) => emit(A64InstId.kLsr, [rd, rn, rm]);

  /// RORV - Rotate right (register).
  void rorv(A64Gp rd, A64Gp rn, A64Gp rm) => emit(A64InstId.kRor, [rd, rn, rm]);

  /// CLZ - Count Leading Zeros.
  void clz(A64Gp rd, A64Gp rn) => emit(A64InstId.kClz, [rd, rn]);

  /// CLS - Count Leading Sign bits.
  void cls(A64Gp rd, A64Gp rn) => emit(A64InstId.kCls, [rd, rn]);

  /// RBIT - Reverse Bits.
  void rbit(A64Gp rd, A64Gp rn) => emit(A64InstId.kRbit, [rd, rn]);

  /// CCMP - Conditional Compare (register or immediate).
  void ccmp(A64Gp rn, Object rmOrImm, int nzcv, A64Cond cond) =>
      emit(A64InstId.kCcmp, [rn, rmOrImm, nzcv, cond]);

  /// CCMN - Conditional Compare Negative (register or immediate).
  void ccmn(A64Gp rn, Object rmOrImm, int nzcv, A64Cond cond) =>
      emit(A64InstId.kCcmn, [rn, rmOrImm, nzcv, cond]);

  void crc32b(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kCrc32b, [rd, rn, rm]);
  void crc32h(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kCrc32h, [rd, rn, rm]);
  void crc32w(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kCrc32w, [rd, rn, rm]);
  void crc32x(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kCrc32x, [rd, rn, rm]);
  void crc32cb(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kCrc32cb, [rd, rn, rm]);
  void crc32ch(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kCrc32ch, [rd, rn, rm]);
  void crc32cw(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kCrc32cw, [rd, rn, rm]);
  void crc32cx(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kCrc32cx, [rd, rn, rm]);

  /// CSEL - Conditional Select.
  void csel(A64Gp rd, A64Gp rn, A64Gp rm, A64Cond cond) =>
      emit(A64InstId.kCsel, [rd, rn, rm, cond]);

  /// CSINC - Conditional Select Increment.
  void csinc(A64Gp rd, A64Gp rn, A64Gp rm, A64Cond cond) =>
      emit(A64InstId.kCsinc, [rd, rn, rm, cond]);

  /// CSINV - Conditional Select Invert.
  void csinv(A64Gp rd, A64Gp rn, A64Gp rm, A64Cond cond) =>
      emit(A64InstId.kCsinv, [rd, rn, rm, cond]);

  /// CSNEG - Conditional Select Negate.
  void csneg(A64Gp rd, A64Gp rn, A64Gp rm, A64Cond cond) =>
      emit(A64InstId.kCsneg, [rd, rn, rm, cond]);

  /// CSET - Conditional Set (alias for CSINC with ZR).
  void cset(A64Gp rd, A64Cond cond) => emit(A64InstId.kCset, [rd, cond]);

  /// CSETM - Conditional Set Mask (alias for CSINV with ZR).
  void csetm(A64Gp rd, A64Cond cond) => emit(A64InstId.kCsetm, [rd, cond]);

  /// CINC - Conditional Increment (alias for CSINC).
  void cinc(A64Gp rd, A64Gp rn, A64Cond cond) =>
      emit(A64InstId.kCinc, [rd, rn, cond]);

  /// CINV - Conditional Invert (alias for CSINV).
  void cinv(A64Gp rd, A64Gp rn, A64Cond cond) =>
      emit(A64InstId.kCinv, [rd, rn, cond]);

  /// CNEG - Conditional Negate (alias for CSNEG).
  void cneg(A64Gp rd, A64Gp rn, A64Cond cond) =>
      emit(A64InstId.kCneg, [rd, rn, cond]);

  /// EXTR - Extract.
  void extr(A64Gp rd, A64Gp rn, A64Gp rm, int amount) =>
      emit(A64InstId.kExtr, [rd, rn, rm, amount]);

  /// SBFM - Signed Bitfield Move.
  void sbfm(A64Gp rd, A64Gp rn, int immr, int imms) =>
      emit(A64InstId.kSbfm, [rd, rn, immr, imms]);

  /// UBFM - Unsigned Bitfield Move.
  void ubfm(A64Gp rd, A64Gp rn, int immr, int imms) =>
      emit(A64InstId.kUbfm, [rd, rn, immr, imms]);

  /// SBFX - Signed Bitfield Extract (alias for SBFM).
  void sbfx(A64Gp rd, A64Gp rn, int lsb, int width) =>
      emit(A64InstId.kSbfx, [rd, rn, lsb, width]);

  /// SBFIZ - Signed Bitfield Insert in Zero (alias for SBFM).
  void sbfiz(A64Gp rd, A64Gp rn, int lsb, int width) =>
      emit(A64InstId.kSbfiz, [rd, rn, lsb, width]);

  /// UBFX - Unsigned Bitfield Extract (alias for UBFM).
  void ubfx(A64Gp rd, A64Gp rn, int lsb, int width) =>
      emit(A64InstId.kUbfx, [rd, rn, lsb, width]);

  /// UBFIZ - Unsigned Bitfield Insert in Zero (alias for UBFM).
  void ubfiz(A64Gp rd, A64Gp rn, int lsb, int width) =>
      emit(A64InstId.kUbfiz, [rd, rn, lsb, width]);

  /// BFXIL - Bitfield Extract and Insert at Low end (alias for BFM).
  void bfxil(A64Gp rd, A64Gp rn, int lsb, int width) =>
      emit(A64InstId.kBfxil, [rd, rn, lsb, width]);

  /// BFI - Bitfield Insert (alias for BFM).
  void bfi(A64Gp rd, A64Gp rn, int lsb, int width) =>
      emit(A64InstId.kBfi, [rd, rn, lsb, width]);

  /// BFC - Bitfield Clear (alias for BFM with ZR).
  void bfc(A64Gp rd, int lsb, int width) =>
      emit(A64InstId.kBfc, [rd, lsb, width]);

  /// BFM - Bitfield Move.
  void bfm(A64Gp rd, A64Gp rn, int immr, int imms) =>
      emit(A64InstId.kBfm, [rd, rn, immr, imms]);

  /// SXTB - Sign extend byte (the source is the W view of [rn]).
  void sxtb(A64Gp rd, A64Gp rn) => emit(A64InstId.kSxtb, [rd, rn.w]);

  /// SXTH - Sign extend halfword.
  void sxth(A64Gp rd, A64Gp rn) => emit(A64InstId.kSxth, [rd, rn.w]);

  /// SXTW - Sign extend word (only for 64-bit).
  void sxtw(A64Gp rd, A64Gp rn) => emit(A64InstId.kSxtw, [rd, rn.w]);

  /// UXTB - Zero extend byte.
  void uxtb(A64Gp rd, A64Gp rn) => emit(A64InstId.kUxtb, [rd, rn.w]);

  /// UXTH - Zero extend halfword.
  void uxth(A64Gp rd, A64Gp rn) => emit(A64InstId.kUxth, [rd, rn.w]);

  /// ASR - Arithmetic shift right (immediate).
  void asr(A64Gp rd, A64Gp rn, int amount) =>
      emit(A64InstId.kAsr, [rd, rn, amount]);

  /// LSR - Logical shift right (immediate).
  void lsr(A64Gp rd, A64Gp rn, int amount) =>
      emit(A64InstId.kLsr, [rd, rn, amount]);

  /// LSL - Logical shift left (immediate).
  void lsl(A64Gp rd, A64Gp rn, int amount) =>
      emit(A64InstId.kLsl, [rd, rn, amount]);

  // ===========================================================================
  // Move Instructions
  // ===========================================================================

  /// MOV (register; `add rd, rn, #0` when SP is involved).
  void mov(A64Gp rd, A64Gp rm) => emit(A64InstId.kMov, [rd, rm]);

  /// MOVZ - Move wide with zero ([shift] is 0, 16, 32 or 48).
  void movz(A64Gp rd, int imm16, {int shift = 0}) => emit(A64InstId.kMovz,
      [rd, imm16, if (shift != 0) A64ShiftOp(A64Shift.lsl, shift)]);

  /// MOVK - Move wide with keep.
  void movk(A64Gp rd, int imm16, {int shift = 0}) => emit(A64InstId.kMovk,
      [rd, imm16, if (shift != 0) A64ShiftOp(A64Shift.lsl, shift)]);

  /// MOVN - Move wide with not.
  void movn(A64Gp rd, int imm16, {int shift = 0}) => emit(A64InstId.kMovn,
      [rd, imm16, if (shift != 0) A64ShiftOp(A64Shift.lsl, shift)]);

  /// Loads an immediate: upstream `mov(rd, imm)` (a single MOVZ/MOVN, a
  /// logical ORR or the shortest MOVZ/MOVN + MOVK sequence).
  void movImm64(A64Gp rd, int imm64) => emit(A64InstId.kMov, [rd, imm64]);

  // ===========================================================================
  // Branch Instructions
  // ===========================================================================

  /// B - Unconditional branch to label.
  void b(Label label) => emit(A64InstId.kB, [label]);

  /// A label bound [offset] bytes from the next instruction: the operand of
  /// the PC-relative forms that take a byte offset (upstream takes a label
  /// or an absolute address).
  Label _pcRel(int offset) {
    final label = newLabel();
    code.bindLabel(label, currentSection.id, this.offset + offset);
    return label;
  }

  /// ADR - PC-relative address ([offset] bytes from this instruction).
  void adr(A64Gp rd, int offset) => emit(A64InstId.kAdr, [rd, _pcRel(offset)]);

  /// ADR - PC-relative address of [label] (resolved by CodeHolder).
  void adrLabel(A64Gp rd, Label label) => emit(A64InstId.kAdr, [rd, label]);

  /// ADRP - PC-relative page address (immediate, offset is byte distance).
  void adrp(A64Gp rd, int offset) =>
      emit(A64InstId.kAdrp, [rd, _pcRel(offset)]);

  /// BL - Branch with link to label.
  void bl(Label label) => emit(A64InstId.kBl, [label]);

  /// B.cond - Conditional branch to label.
  void bCond(A64Cond cond, Label label) =>
      emit(A64InstId.kB_cond, [label, cond]);

  /// CBZ - Compare and branch if zero.
  void cbz(A64Gp rt, Label label) => emit(A64InstId.kCbz, [rt, label]);

  /// CBNZ - Compare and branch if not zero.
  void cbnz(A64Gp rt, Label label) => emit(A64InstId.kCbnz, [rt, label]);

  /// Convenience conditional branches.
  void beq(Label label) => bCond(A64Cond.eq, label);
  void bne(Label label) => bCond(A64Cond.ne, label);
  void bge(Label label) => bCond(A64Cond.ge, label);
  void blt(Label label) => bCond(A64Cond.lt, label);
  void bgt(Label label) => bCond(A64Cond.gt, label);
  void ble(Label label) => bCond(A64Cond.le, label);

  /// BR - Branch to register.
  void br(A64Gp rn) => emit(A64InstId.kBr, [rn]);

  /// BLR - Branch with link to register.
  void blr(A64Gp rn) => emit(A64InstId.kBlr, [rn]);

  /// RET - Return from subroutine.
  void ret([A64Gp rn = x30]) => emit(A64InstId.kRet, [rn]);

  // ===========================================================================
  // Load/Store Instructions
  // ===========================================================================

  /// LDR (immediate; upstream picks LDUR for unscaled offsets).
  void ldr(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdr, [rt, A64Mem.baseOffset(rn, offset)]);

  /// LDRSB (immediate).
  void ldrsb(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdrsb, [rt, A64Mem.baseOffset(rn, offset)]);

  /// LDRSH (immediate).
  void ldrsh(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdrsh, [rt, A64Mem.baseOffset(rn, offset)]);

  /// LDRSW (immediate).
  void ldrsw(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdrsw, [rt, A64Mem.baseOffset(rn, offset)]);

  /// LDRB (immediate) into the W view of [rt].
  void ldrb(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdrb, [rt.w, A64Mem.baseOffset(rn, offset)]);

  /// LDRH (immediate) into the W view of [rt].
  void ldrh(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdrh, [rt.w, A64Mem.baseOffset(rn, offset)]);

  /// STR (immediate).
  void str(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kStr, [rt, A64Mem.baseOffset(rn, offset)]);

  /// LDR (SIMD/FP, immediate).
  void ldrVec(A64Vec vt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdr, [_scalar(vt), A64Mem.baseOffset(rn, offset)]);

  /// STR (SIMD/FP, immediate).
  void strVec(A64Vec vt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kStr, [_scalar(vt), A64Mem.baseOffset(rn, offset)]);

  /// LDR (SIMD/FP, unscaled signed offset).
  void ldrVecUnscaled(A64Vec vt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdur, [_scalar(vt), A64Mem.baseOffset(rn, offset)]);

  /// STR (SIMD/FP, unscaled signed offset).
  void strVecUnscaled(A64Vec vt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kStur, [_scalar(vt), A64Mem.baseOffset(rn, offset)]);

  /// LDR (SIMD/FP, literal [offset] bytes from this instruction).
  void ldrVecLiteral(A64Vec vt, int offset) =>
      emit(A64InstId.kLdr, [_scalar(vt), A64Mem.label(_pcRel(offset))]);

  /// LDUR (GP, unscaled signed offset).
  void ldur(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdur, [rt, A64Mem.baseOffset(rn, offset)]);

  /// STUR (GP, unscaled signed offset).
  void stur(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kStur, [rt, A64Mem.baseOffset(rn, offset)]);

  /// STRB (immediate) of the W view of [rt].
  void strb(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kStrb, [rt.w, A64Mem.baseOffset(rn, offset)]);

  /// STRH (immediate) of the W view of [rt].
  void strh(A64Gp rt, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kStrh, [rt.w, A64Mem.baseOffset(rn, offset)]);

  /// LDP - Load pair.
  void ldp(A64Gp rt, A64Gp rt2, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kLdp, [rt, rt2, A64Mem.baseOffset(rn, offset)]);

  /// STP - Store pair.
  void stp(A64Gp rt, A64Gp rt2, A64Gp rn, [int offset = 0]) =>
      emit(A64InstId.kStp, [rt, rt2, A64Mem.baseOffset(rn, offset)]);

  /// LDP (post-index) - `ldp rt, rt2, [rn], #offset`.
  void ldpPost(A64Gp rt, A64Gp rt2, A64Gp rn, int offset) =>
      emit(A64InstId.kLdp, [rt, rt2, A64Mem.postIndex(rn, offset)]);

  /// STP (pre-index) - `stp rt, rt2, [rn, #offset]!`.
  void stpPre(A64Gp rt, A64Gp rt2, A64Gp rn, int offset) =>
      emit(A64InstId.kStp, [rt, rt2, A64Mem.preIndex(rn, offset)]);

  // ===========================================================================
  // Multiply/Divide Instructions
  // ===========================================================================

  /// MUL - Multiply.
  void mul(A64Gp rd, A64Gp rn, A64Gp rm) => emit(A64InstId.kMul, [rd, rn, rm]);

  /// MADD - Multiply-add.
  void madd(A64Gp rd, A64Gp rn, A64Gp rm, A64Gp ra) =>
      emit(A64InstId.kMadd, [rd, rn, rm, ra]);

  /// MSUB - Multiply-subtract.
  void msub(A64Gp rd, A64Gp rn, A64Gp rm, A64Gp ra) =>
      emit(A64InstId.kMsub, [rd, rn, rm, ra]);

  /// SDIV - Signed divide.
  void sdiv(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kSdiv, [rd, rn, rm]);

  /// UDIV - Unsigned divide.
  void udiv(A64Gp rd, A64Gp rn, A64Gp rm) =>
      emit(A64InstId.kUdiv, [rd, rn, rm]);

  // ===========================================================================
  // System Instructions
  // ===========================================================================

  /// NOP - No operation.
  void nop() => emit(A64InstId.kNop, const []);

  /// BRK - Breakpoint.
  void brk(int imm) => emit(A64InstId.kBrk, [imm]);

  /// SVC - Supervisor call.
  void svc(int imm) => emit(A64InstId.kSvc, [imm]);

  void dmb(int option) => emit(A64InstId.kDmb, [option]);
  void dsb(int option) => emit(A64InstId.kDsb, [option]);
  void isb(int option) => emit(A64InstId.kIsb, [option]);

  // ===========================================================================
  // Floating Point Instructions
  // ===========================================================================

  /// FADD (scalar).
  void fadd(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFadd, [rd, rn, rm]);

  /// FSUB (scalar).
  void fsub(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFsub, [rd, rn, rm]);

  /// FMUL (scalar).
  void fmul(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFmul, [rd, rn, rm]);

  /// FDIV (scalar).
  void fdiv(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFdiv, [rd, rn, rm]);

  // ===========================================================================
  // NEON (integer) - Vector ALU
  // ===========================================================================

  void addVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecSame(A64InstId.kAdd, [rd, rn, rm], wide: wide);

  void subVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecSame(A64InstId.kSub, [rd, rn, rm], wide: wide);

  void mulVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecSame(A64InstId.kMul, [rd, rn, rm], wide: wide);

  void andVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecLogic(A64InstId.kAnd, [rd, rn, rm], wide: wide);

  void orrVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecLogic(A64InstId.kOrr, [rd, rn, rm], wide: wide);

  void eorVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecLogic(A64InstId.kEor, [rd, rn, rm], wide: wide);

  // ===========================================================================
  // Floating Point (Scalar - Additional)
  // ===========================================================================

  void fneg(A64Vec rd, A64Vec rn) => emit(A64InstId.kFneg, [rd, rn]);
  void fabs(A64Vec rd, A64Vec rn) => emit(A64InstId.kFabs, [rd, rn]);
  void fsqrt(A64Vec rd, A64Vec rn) => emit(A64InstId.kFsqrt, [rd, rn]);
  void fcmp(A64Vec rn, A64Vec rm) => emit(A64InstId.kFcmp, [rn, rm]);
  void fcsel(A64Vec rd, A64Vec rn, A64Vec rm, A64Cond cond) =>
      emit(A64InstId.kFcsel, [rd, rn, rm, cond]);
  void fmax(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFmax, [rd, rn, rm]);
  void fmin(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFmin, [rd, rn, rm]);
  void fmaxnm(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFmaxnm, [rd, rn, rm]);
  void fminnm(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFminnm, [rd, rn, rm]);

  // ===========================================================================
  // NEON (Integer) - Misc and Logic
  // ===========================================================================

  void negVec(A64Vec rd, A64Vec rn) => _vecSame(A64InstId.kNeg, [rd, rn]);
  void abs(A64Vec rd, A64Vec rn) => _vecSame(A64InstId.kAbs, [rd, rn]);
  void mvnVec(A64Vec rd, A64Vec rn) => _vecLogic(A64InstId.kMvn, [rd, rn]);
  void clsVec(A64Vec rd, A64Vec rn) => _vecSame(A64InstId.kCls, [rd, rn]);
  void clzVec(A64Vec rd, A64Vec rn) => _vecSame(A64InstId.kClz, [rd, rn]);
  void cntVec(A64Vec rd, A64Vec rn) => _vecLogic(A64InstId.kCnt, [rd, rn]);
  void rev64(A64Vec rd, A64Vec rn) => _vecSame(A64InstId.kRev64, [rd, rn]);

  /// UADDLP Vd.<Ta>, Vn.<Tb>: the element size comes from the source.
  void uaddlp(A64Vec rd, A64Vec rn) {
    final sz = _elementSize(rn);
    final q = _isQ(rd, true);
    emit(A64InstId.kUaddlp, [_arr(rd, sz + 1, q), _arr(rn, sz, q)]);
  }

  void fcmeq(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFcmeq, [rd, rn, rm]);
  void fcmge(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFcmge, [rd, rn, rm]);
  void fcmgt(A64Vec rd, A64Vec rn, A64Vec rm) =>
      emit(A64InstId.kFcmgt, [rd, rn, rm]);
  void rev32(A64Vec rd, A64Vec rn) => _vecSame(A64InstId.kRev32, [rd, rn]);
  void rev16(A64Vec rd, A64Vec rn) => _vecSame(A64InstId.kRev16, [rd, rn]);

  void bicVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecLogic(A64InstId.kBic, [rd, rn, rm], wide: wide);
  void ornVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecLogic(A64InstId.kOrn, [rd, rn, rm], wide: wide);
  void bsl(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecLogic(A64InstId.kBsl, [rd, rn, rm], wide: wide);
  void bit(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecLogic(A64InstId.kBit, [rd, rn, rm], wide: wide);
  void bif(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecLogic(A64InstId.kBif, [rd, rn, rm], wide: wide);

  // ===========================================================================
  // NEON (FP) - Vector
  // ===========================================================================

  void faddVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFadd, [rd, rn, rm], wide: wide);
  void fsubVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFsub, [rd, rn, rm], wide: wide);
  void fmulVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFmul, [rd, rn, rm], wide: wide);
  void fdivVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFdiv, [rd, rn, rm], wide: wide);

  void fmaxVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFmax, [rd, rn, rm], wide: wide);
  void fminVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFmin, [rd, rn, rm], wide: wide);
  void fmaxnmVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFmaxnm, [rd, rn, rm], wide: wide);
  void fminnmVec(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFminnm, [rd, rn, rm], wide: wide);

  void fcmeqVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecFp(A64InstId.kFcmeq, [rd, rn, rm]);
  void fcmgeVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecFp(A64InstId.kFcmge, [rd, rn, rm]);
  void fcmgtVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecFp(A64InstId.kFcmgt, [rd, rn, rm]);
  void fmadd(A64Vec rd, A64Vec rn, A64Vec rm, A64Vec ra) =>
      emit(A64InstId.kFmadd, [rd, rn, rm, ra]);
  void fmsub(A64Vec rd, A64Vec rn, A64Vec rm, A64Vec ra) =>
      emit(A64InstId.kFmsub, [rd, rn, rm, ra]);
  void fnmadd(A64Vec rd, A64Vec rn, A64Vec rm, A64Vec ra) =>
      emit(A64InstId.kFnmadd, [rd, rn, rm, ra]);
  void fnmsub(A64Vec rd, A64Vec rn, A64Vec rm, A64Vec ra) =>
      emit(A64InstId.kFnmsub, [rd, rn, rm, ra]);
  void fmlaVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecFp(A64InstId.kFmla, [rd, rn, rm]);
  void fmlsVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecFp(A64InstId.kFmls, [rd, rn, rm]);
  void mlaVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kMla, [rd, rn, rm]);
  void mlsVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kMls, [rd, rn, rm]);
  void sqaddVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kSqadd, [rd, rn, rm]);
  void uqaddVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kUqadd, [rd, rn, rm]);
  void sqsubVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kSqsub, [rd, rn, rm]);
  void uqsubVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kUqsub, [rd, rn, rm]);
  void cmgtVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kCmgt, [rd, rn, rm]);
  void cmhiVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kCmhi, [rd, rn, rm]);
  void cmgeVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kCmge, [rd, rn, rm]);
  void cmhsVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kCmhs, [rd, rn, rm]);
  void sshlVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kSshl, [rd, rn, rm]);
  void ushlVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kUshl, [rd, rn, rm]);
  void smaxVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kSmax, [rd, rn, rm]);
  void umaxVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kUmax, [rd, rn, rm]);
  void sminVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kSmin, [rd, rn, rm]);
  void uminVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kUmin, [rd, rn, rm]);
  void urhaddVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kUrhadd, [rd, rn, rm]);

  /// EXT: `ext Vd.16B, Vn.16B, Vm.16B, #index` (Vd = Vm:Vn >> index*8).
  void extVec(A64Vec rd, A64Vec rn, A64Vec rm, int index) =>
      _vecSame(A64InstId.kExt, [rd, rn, rm], size: 0, extra: [index]);

  void cmtstVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kCmtst, [rd, rn, rm]);
  void cmeqVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kCmeq, [rd, rn, rm]);

  /// SMULL/SMULL2 (vector), selected by the arrangement of [rn].
  void smullVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kSmull, A64InstId.kSmull2, rd, rn, rm,
          q: _isQ(rn, false));
  void umullVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kUmull, A64InstId.kUmull2, rd, rn, rm,
          q: _isQ(rn, false));
  void smlalVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kSmlal, A64InstId.kSmlal2, rd, rn, rm,
          q: _isQ(rn, false));
  void umlalVec(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kUmlal, A64InstId.kUmlal2, rd, rn, rm,
          q: _isQ(rn, false));

  void shlVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kShl, [rd, rn], extra: [shift]);
  void sliVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kSli, [rd, rn], extra: [shift]);
  void sshrVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kSshr, [rd, rn], extra: [shift]);
  void ushrVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kUshr, [rd, rn], extra: [shift]);
  void ssraVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kSsra, [rd, rn], extra: [shift]);
  void usraVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kUsra, [rd, rn], extra: [shift]);
  void sriVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kSri, [rd, rn], extra: [shift]);
  void urshrVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kUrshr, [rd, rn], extra: [shift]);
  void ursraVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecSame(A64InstId.kUrsra, [rd, rn], extra: [shift]);

  /// RSHRN/RSHRN2 and SHRN/SHRN2: element size and Q from the narrow
  /// destination.
  void rshrnVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecNarrow(A64InstId.kRshrn, A64InstId.kRshrn2, rd, rn,
          q: _isQ(rd, true), extra: [shift]);
  void shrnVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecNarrow(A64InstId.kShrn, A64InstId.kShrn2, rd, rn,
          q: _isQ(rd, true), extra: [shift]);

  /// SSHLL/USHLL(2): element size and Q come from the narrow source.
  void sshllVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecWiden(A64InstId.kSshll, A64InstId.kSshll2, rd, rn, shift);
  void ushllVec(A64Vec rd, A64Vec rn, int shift) =>
      _vecWiden(A64InstId.kUshll, A64InstId.kUshll2, rd, rn, shift);

  void _vecWiden(int instId, int instId2, A64Vec rd, A64Vec rn, int shift) {
    final sz = _elementSize(rn);
    final q = _isQ(rn, true);
    emit(
        q ? instId2 : instId, [_arr(rd, sz + 1, true), _arr(rn, sz, q), shift]);
  }

  void fabsVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFabs, [rd, rn]);
  void fnegVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFneg, [rd, rn]);
  void fsqrtVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFsqrt, [rd, rn]);
  void frintnVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFrintn, [rd, rn]);
  void frintmVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFrintm, [rd, rn]);
  void frintpVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFrintp, [rd, rn]);
  void frintzVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFrintz, [rd, rn]);
  void frintaVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFrinta, [rd, rn]);
  void scvtfVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kScvtf, [rd, rn]);
  void ucvtfVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kUcvtf, [rd, rn]);
  void fcvtzsVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFcvtzs, [rd, rn]);
  void fcvtnsVec(A64Vec rd, A64Vec rn) => _vecFp(A64InstId.kFcvtns, [rd, rn]);

  /// FCVTL/FCVTL2 (single -> double, or half -> single when [rd] has S
  /// elements): `.4s`/`.8h` sources select FCVTL2.
  void fcvtlVec(A64Vec rd, A64Vec rn) {
    final sz = _elementSize(rd) == 3 ? 3 : 2;
    final q = _isQ(rn, true);
    emit(q ? A64InstId.kFcvtl2 : A64InstId.kFcvtl,
        [_arr(rd, sz, true), _arr(rn, sz - 1, q)]);
  }

  /// FCVTN/FCVTN2 (double -> single, or single -> half when [rn] has S
  /// elements): `.4s`/`.8h` destinations select FCVTN2.
  void fcvtnVec(A64Vec rd, A64Vec rn) {
    final sz = _elementSize(rn) == 3 ? 3 : 2;
    final q = _isQ(rd, true);
    emit(q ? A64InstId.kFcvtn2 : A64InstId.kFcvtn,
        [_arr(rd, sz - 1, q), _arr(rn, sz, true)]);
  }

  void frintnS(A64Vec rd, A64Vec rn) => emit(A64InstId.kFrintn, [rd, rn]);
  void frintpS(A64Vec rd, A64Vec rn) => emit(A64InstId.kFrintp, [rd, rn]);
  void frintmS(A64Vec rd, A64Vec rn) => emit(A64InstId.kFrintm, [rd, rn]);
  void frintzS(A64Vec rd, A64Vec rn) => emit(A64InstId.kFrintz, [rd, rn]);
  void frintaS(A64Vec rd, A64Vec rn) => emit(A64InstId.kFrinta, [rd, rn]);

  /// MOVI (per-byte immediate).
  void moviB(A64Vec rd, int imm8) =>
      _vecSame(A64InstId.kMovi, [rd], size: 0, extra: [imm8]);

  /// FADDP (vector).
  void faddp(A64Vec rd, A64Vec rn, A64Vec rm, {bool wide = true}) =>
      _vecFp(A64InstId.kFaddp, [rd, rn, rm], wide: wide);

  // ===========================================================================
  // Permutation Instructions
  // ===========================================================================

  /// TBL with a one-register table: `tbl Vd.<T>, {Vn.16B}, Vm.<T>`.
  void tbl(A64Vec rd, A64Vec rn, A64Vec rm) {
    final q = _isQ(rd, true);
    emit(A64InstId.kTbl, [_arr(rd, 0, q), _arr(rn, 0, true), _arr(rm, 0, q)]);
  }

  void zip1(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kZip1, [rd, rn, rm]);
  void zip2(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kZip2, [rd, rn, rm]);

  void uzp1(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kUzp1, [rd, rn, rm]);
  void uzp2(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kUzp2, [rd, rn, rm]);

  void trn1(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kTrn1, [rd, rn, rm]);
  void trn2(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecSame(A64InstId.kTrn2, [rd, rn, rm]);

  // ===========================================================================
  // Load/Store (LD1R)
  // ===========================================================================

  /// LD1R - Load one single-element structure and replicate to all lanes.
  void ld1r(A64Vec vt, A64Gp rn, {int offset = 0}) => emit(A64InstId.kLd1r, [
        vt.layout == A64Layout.none ? _arr(vt, 2, vt.sizeBits == 128) : vt,
        A64Mem.baseOffset(rn, offset)
      ]);

  // ===========================================================================
  // Vector Moves
  // ===========================================================================

  /// DUP (element); a destination without arrangement (`d0`, `s0`...) is
  /// the scalar form.
  void dup(A64Vec rd, A64Vec rn, int index) {
    if (rd.layout == A64Layout.none && rd.sizeBits < 128) {
      emit(A64InstId.kDup, [rd, _elem(rn, _elementSize(rd), index)]);
      return;
    }
    final sz = _elementSize(rd);
    emit(A64InstId.kDup, [_arr(rd, sz, _isQ(rd, true)), _elem(rn, sz, index)]);
  }

  /// DUP (general): every element of [rd] = [rn].
  void dupGp(A64Vec rd, A64Gp rn) {
    final sz = _elementSize(rd);
    emit(A64InstId.kDup, [_arr(rd, sz, _isQ(rd, true)), sz == 3 ? rn.x : rn.w]);
  }

  /// INS (element): `mov Vd.T[rdIdx], Vn.T[rnIdx]` (T from [rd]).
  void ins(A64Vec rd, int rdIdx, A64Vec rn, int rnIdx) {
    final sz = _elementSize(rd);
    emit(A64InstId.kIns_mov, [_elem(rd, sz, rdIdx), _elem(rn, sz, rnIdx)]);
  }

  /// UMOV (element) - Move vector element to GP register (unsigned).
  void umov(A64Gp rd, A64Vec rn, int index) {
    final sz = _elementSize(rn);
    emit(A64InstId.kUmov, [sz == 3 ? rd.x : rd.w, _elem(rn, sz, index)]);
  }

  /// SMOV (element) - Move vector element to GP register (signed).
  void smov(A64Gp rd, A64Vec rn, int index) =>
      emit(A64InstId.kSmov, [rd, _elem(rn, _elementSize(rn), index)]);

  // ===========================================================================
  // Widening Multiply
  // ===========================================================================

  /// SMULL - Signed multiply long (lo)
  void smull(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kSmull, A64InstId.kSmull2, rd, rn, rm, q: false);

  /// UMULL - Unsigned multiply long (lo)
  void umull(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kUmull, A64InstId.kUmull2, rd, rn, rm, q: false);

  /// SMULL2 - Signed multiply long (hi)
  void smull2(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kSmull, A64InstId.kSmull2, rd, rn, rm, q: true);

  /// UMULL2 - Unsigned multiply long (hi)
  void umull2(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kUmull, A64InstId.kUmull2, rd, rn, rm, q: true);

  /// SMLAL - Signed multiply-accumulate long (lo)
  void smlal(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kSmlal, A64InstId.kSmlal2, rd, rn, rm, q: false);

  /// UMLAL - Unsigned multiply-accumulate long (lo)
  void umlal(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kUmlal, A64InstId.kUmlal2, rd, rn, rm, q: false);

  /// SMLAL2 - Signed multiply-accumulate long (hi)
  void smlal2(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kSmlal, A64InstId.kSmlal2, rd, rn, rm, q: true);

  /// UMLAL2 - Unsigned multiply-accumulate long (hi)
  void umlal2(A64Vec rd, A64Vec rn, A64Vec rm) =>
      _vecLong(A64InstId.kUmlal, A64InstId.kUmlal2, rd, rn, rm, q: true);

  // ===========================================================================
  // Narrowing (Packing)
  // ===========================================================================

  /// XTN - Extract narrow
  void xtn(A64Vec rd, A64Vec rn) =>
      _vecNarrow(A64InstId.kXtn, A64InstId.kXtn2, rd, rn, q: false);

  /// XTN2 - Extract narrow (high)
  void xtn2(A64Vec rd, A64Vec rn) =>
      _vecNarrow(A64InstId.kXtn, A64InstId.kXtn2, rd, rn, q: true);

  /// SQXTN - Signed saturating extract narrow
  void sqxtn(A64Vec rd, A64Vec rn) =>
      _vecNarrow(A64InstId.kSqxtn, A64InstId.kSqxtn2, rd, rn, q: false);

  /// SQXTN2 - Signed saturating extract narrow (high)
  void sqxtn2(A64Vec rd, A64Vec rn) =>
      _vecNarrow(A64InstId.kSqxtn, A64InstId.kSqxtn2, rd, rn, q: true);

  /// UQXTN - Unsigned saturating extract narrow
  void uqxtn(A64Vec rd, A64Vec rn) =>
      _vecNarrow(A64InstId.kUqxtn, A64InstId.kUqxtn2, rd, rn, q: false);

  /// UQXTN2 - Unsigned saturating extract narrow (high)
  void uqxtn2(A64Vec rd, A64Vec rn) =>
      _vecNarrow(A64InstId.kUqxtn, A64InstId.kUqxtn2, rd, rn, q: true);

  /// SQXTUN / SQXTUN2 - Signed to unsigned saturating extract narrow.
  void sqxtun(A64Vec rd, A64Vec rn) =>
      _vecNarrow(A64InstId.kSqxtun, A64InstId.kSqxtun2, rd, rn, q: false);
  void sqxtun2(A64Vec rd, A64Vec rn) =>
      _vecNarrow(A64InstId.kSqxtun, A64InstId.kSqxtun2, rd, rn, q: true);

  // ===========================================================================
  // Conversions
  // ===========================================================================

  /// Vector conversion: the arrangement of [rd], or `.2d` for a 128-bit
  /// register without arrangement (`.2s` for a 64-bit one).
  void _vecCvt(int instId, A64Vec rd, A64Vec rn) {
    if (rd.layout != A64Layout.none) return _vecFp(instId, [rd, rn]);
    final q = rd.sizeBits == 128;
    final sz = q ? 3 : 2;
    emit(instId, [_arr(rd, sz, q), _arr(rn, sz, q)]);
  }

  /// SCVTF - Signed integer to float (vector)
  void scvtf(A64Vec rd, A64Vec rn) => _vecCvt(A64InstId.kScvtf, rd, rn);

  /// UCVTF - Unsigned integer to float (vector)
  void ucvtf(A64Vec rd, A64Vec rn) => _vecCvt(A64InstId.kUcvtf, rd, rn);

  /// FCVTZS - Float to signed integer (round toward zero, vector)
  void fcvtzs(A64Vec rd, A64Vec rn) => _vecCvt(A64InstId.kFcvtzs, rd, rn);

  /// FCVTZU - Float to unsigned integer (round toward zero, vector)
  void fcvtzu(A64Vec rd, A64Vec rn) => _vecCvt(A64InstId.kFcvtzu, rd, rn);

  /// FCVT - Floating-point convert precision
  void fcvt(A64Vec rd, A64Vec rn) => emit(A64InstId.kFcvt, [rd, rn]);

  // ===========================================================================
  // Prologue/Epilogue Helpers
  // ===========================================================================

  /// Emit a standard AAPCS64 prologue.
  void emitPrologue({int stackSize = 0}) {
    // STP x29, x30, [sp, #-16]! (pre-index: SP moves down by 16).
    stpPre(x29, x30, sp, -16);
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
    // LDP x29, x30, [sp], #16 (post-index: restores SP).
    ldpPost(x29, x30, sp, 16);
    ret();
  }

  // ===========================================================================
  // Finalization
  // ===========================================================================

  /// Finalizes the code (label relocations are resolved by [CodeHolder]).
  FinalizedCode finalize() => code.finalize();

  // ===========================================================================
  // Raw Bytes
  // ===========================================================================

  /// Emit raw bytes.
  void emitBytes(List<int> bytes) {
    for (final b in bytes) {
      _buf.emit8(b);
    }
  }

  /// Emit a 32-bit instruction word directly.
  void emit32(int inst) {
    instructionCount++;
    _buf.emit32(inst);
  }
}
