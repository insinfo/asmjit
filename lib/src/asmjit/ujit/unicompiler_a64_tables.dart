/// AArch64 lowering tables for UniCompiler.
///
/// Ported from `opcode_info_3v` in asmjit's `ujit/unicompiler_a64.cpp`; one
/// entry per [UniOpVVV] value, in enum order.

import '../arm/a64_inst_db.g.dart';

/// `SameVecOp`: result when both sources are the same register.
const int kSameNone = 0, kSameZero = 1, kSameOnes = 2, kSameSrc = 3;

/// `FloatMode`.
const int kFmNone = 0, kFmF32S = 1, kFmF64S = 2, kFmF32V = 3, kFmF64V = 4;

/// `VecPart`.
const int kPartNA = 0, kPartLo = 1, kPartHi = 2;

/// `UniOpVInfo` (subset used by the A64 lowering).
class A64UniOpVInfo {
  /// A64 instruction (or -1 when the operation is an intrinsic sequence).
  final int instId;

  /// Whether the operation maps to a single ASIMD instruction.
  final bool asimd;

  /// Swap the two sources when emitting.
  final int reverse;
  final int sameVecOp;
  final int floatMode;

  /// Element sizes (0 = 8-bit .. 3 = 64-bit) and halves of dst/sources.
  final int dstElement, dstPart, srcElement, srcPart;
  final int imm;

  const A64UniOpVInfo(
      this.instId,
      this.asimd,
      this.reverse,
      this.sameVecOp,
      this.floatMode,
      this.dstElement,
      this.dstPart,
      this.srcElement,
      this.srcPart,
      this.imm);
}

typedef _V3 = A64UniOpVInfo;

const List<A64UniOpVInfo> kA64OpcodeInfo3v = [
  _V3(A64InstId.kAnd, true, 0, 3, 0, 0, 0, 0, 0, 0), // andU32
  _V3(A64InstId.kAnd, true, 0, 3, 0, 0, 0, 0, 0, 0), // andU64
  _V3(A64InstId.kOrr, true, 0, 3, 0, 0, 0, 0, 0, 0), // orU32
  _V3(A64InstId.kOrr, true, 0, 3, 0, 0, 0, 0, 0, 0), // orU64
  _V3(A64InstId.kEor, true, 0, 1, 0, 0, 0, 0, 0, 0), // xorU32
  _V3(A64InstId.kEor, true, 0, 1, 0, 0, 0, 0, 0, 0), // xorU64
  _V3(A64InstId.kBic, true, 1, 1, 0, 0, 0, 0, 0, 0), // andnU32
  _V3(A64InstId.kBic, true, 1, 1, 0, 0, 0, 0, 0, 0), // andnU64
  _V3(A64InstId.kBic, true, 0, 1, 0, 0, 0, 0, 0, 0), // bicU32
  _V3(A64InstId.kBic, true, 0, 1, 0, 0, 0, 0, 0, 0), // bicU64
  // upstream has kIdNone here; URHADD is the unsigned rounding average.
  _V3(A64InstId.kUrhadd, true, 0, 3, 0, 0, 0, 0, 0, 0), // avgrU8
  _V3(A64InstId.kUrhadd, true, 0, 3, 0, 1, 0, 1, 0, 0), // avgrU16
  _V3(A64InstId.kAdd, true, 0, 0, 0, 0, 0, 0, 0, 0), // addU8
  _V3(A64InstId.kAdd, true, 0, 0, 0, 1, 0, 1, 0, 0), // addU16
  _V3(A64InstId.kAdd, true, 0, 0, 0, 2, 0, 2, 0, 0), // addU32
  _V3(A64InstId.kAdd, true, 0, 0, 0, 3, 0, 3, 0, 0), // addU64
  _V3(A64InstId.kSub, true, 0, 1, 0, 0, 0, 0, 0, 0), // subU8
  _V3(A64InstId.kSub, true, 0, 1, 0, 1, 0, 1, 0, 0), // subU16
  _V3(A64InstId.kSub, true, 0, 1, 0, 2, 0, 2, 0, 0), // subU32
  _V3(A64InstId.kSub, true, 0, 1, 0, 3, 0, 3, 0, 0), // subU64
  _V3(A64InstId.kSqadd, true, 0, 0, 0, 0, 0, 0, 0, 0), // addsI8
  _V3(A64InstId.kUqadd, true, 0, 0, 0, 0, 0, 0, 0, 0), // addsU8
  _V3(A64InstId.kSqadd, true, 0, 0, 0, 1, 0, 1, 0, 0), // addsI16
  _V3(A64InstId.kUqadd, true, 0, 0, 0, 1, 0, 1, 0, 0), // addsU16
  _V3(A64InstId.kSqsub, true, 0, 0, 0, 0, 0, 0, 0, 0), // subsI8
  _V3(A64InstId.kUqsub, true, 0, 1, 0, 0, 0, 0, 0, 0), // subsU8
  _V3(A64InstId.kSqsub, true, 0, 0, 0, 1, 0, 1, 0, 0), // subsI16
  _V3(A64InstId.kUqsub, true, 0, 1, 0, 1, 0, 1, 0, 0), // subsU16
  _V3(A64InstId.kMul, true, 0, 0, 0, 1, 0, 1, 0, 0), // mulU16
  _V3(A64InstId.kMul, true, 0, 0, 0, 2, 0, 2, 0, 0), // mulU32
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // mulU64
  _V3(-1, false, 0, 0, 0, 1, 0, 1, 0, 0), // mulhI16
  _V3(-1, false, 0, 0, 0, 1, 0, 1, 0, 0), // mulhU16
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // mulU64LoU32
  _V3(-1, false, 0, 0, 0, 2, 0, 1, 0, 0), // mHAddI16I32
  _V3(A64InstId.kSmin, true, 0, 3, 0, 0, 0, 0, 0, 0), // minI8
  _V3(A64InstId.kUmin, true, 0, 3, 0, 0, 0, 0, 0, 0), // minU8
  _V3(A64InstId.kSmin, true, 0, 3, 0, 1, 0, 1, 0, 0), // minI16
  _V3(A64InstId.kUmin, true, 0, 3, 0, 1, 0, 1, 0, 0), // minU16
  _V3(A64InstId.kSmin, true, 0, 3, 0, 2, 0, 2, 0, 0), // minI32
  _V3(A64InstId.kUmin, true, 0, 3, 0, 2, 0, 2, 0, 0), // minU32
  _V3(A64InstId.kCmgt, false, 0, 3, 0, 3, 0, 3, 0, 0), // minI64
  _V3(A64InstId.kCmhi, false, 0, 3, 0, 3, 0, 3, 0, 0), // minU64
  _V3(A64InstId.kSmax, true, 0, 3, 0, 0, 0, 0, 0, 0), // maxI8
  _V3(A64InstId.kUmax, true, 0, 3, 0, 0, 0, 0, 0, 0), // maxU8
  _V3(A64InstId.kSmax, true, 0, 3, 0, 1, 0, 1, 0, 0), // maxI16
  _V3(A64InstId.kUmax, true, 0, 3, 0, 1, 0, 1, 0, 0), // maxU16
  _V3(A64InstId.kSmax, true, 0, 3, 0, 2, 0, 2, 0, 0), // maxI32
  _V3(A64InstId.kUmax, true, 0, 3, 0, 2, 0, 2, 0, 0), // maxU32
  _V3(A64InstId.kCmgt, false, 0, 3, 0, 3, 0, 3, 0, 1), // maxI64
  _V3(A64InstId.kCmhi, false, 0, 3, 0, 3, 0, 3, 0, 1), // maxU64
  _V3(A64InstId.kCmeq, true, 0, 2, 0, 0, 0, 0, 0, 0), // cmpEqU8
  _V3(A64InstId.kCmeq, true, 0, 2, 0, 1, 0, 1, 0, 0), // cmpEqU16
  _V3(A64InstId.kCmeq, true, 0, 2, 0, 2, 0, 2, 0, 0), // cmpEqU32
  _V3(A64InstId.kCmeq, true, 0, 2, 0, 3, 0, 3, 0, 0), // cmpEqU64
  _V3(A64InstId.kCmgt, true, 0, 1, 0, 0, 0, 0, 0, 0), // cmpGtI8
  _V3(A64InstId.kCmhi, true, 0, 1, 0, 0, 0, 0, 0, 0), // cmpGtU8
  _V3(A64InstId.kCmgt, true, 0, 1, 0, 1, 0, 1, 0, 0), // cmpGtI16
  _V3(A64InstId.kCmhi, true, 0, 1, 0, 1, 0, 1, 0, 0), // cmpGtU16
  _V3(A64InstId.kCmgt, true, 0, 1, 0, 2, 0, 2, 0, 0), // cmpGtI32
  _V3(A64InstId.kCmhi, true, 0, 1, 0, 2, 0, 2, 0, 0), // cmpGtU32
  _V3(A64InstId.kCmgt, true, 0, 1, 0, 3, 0, 3, 0, 0), // cmpGtI64
  _V3(A64InstId.kCmhi, true, 0, 1, 0, 3, 0, 3, 0, 0), // cmpGtU64
  _V3(A64InstId.kCmge, true, 0, 2, 0, 0, 0, 0, 0, 0), // cmpGeI8
  _V3(A64InstId.kCmhs, true, 0, 2, 0, 0, 0, 0, 0, 0), // cmpGeU8
  _V3(A64InstId.kCmge, true, 0, 2, 0, 1, 0, 1, 0, 0), // cmpGeI16
  _V3(A64InstId.kCmhs, true, 0, 2, 0, 1, 0, 1, 0, 0), // cmpGeU16
  _V3(A64InstId.kCmge, true, 0, 2, 0, 2, 0, 2, 0, 0), // cmpGeI32
  _V3(A64InstId.kCmhs, true, 0, 2, 0, 2, 0, 2, 0, 0), // cmpGeU32
  _V3(A64InstId.kCmge, true, 0, 2, 0, 3, 0, 3, 0, 0), // cmpGeI64
  _V3(A64InstId.kCmhs, true, 0, 2, 0, 3, 0, 3, 0, 0), // cmpGeU64
  _V3(A64InstId.kCmgt, true, 1, 1, 0, 0, 0, 0, 0, 0), // cmpLtI8
  _V3(A64InstId.kCmhi, true, 1, 1, 0, 0, 0, 0, 0, 0), // cmpLtU8
  _V3(A64InstId.kCmgt, true, 1, 1, 0, 1, 0, 1, 0, 0), // cmpLtI16
  _V3(A64InstId.kCmhi, true, 1, 1, 0, 1, 0, 1, 0, 0), // cmpLtU16
  _V3(A64InstId.kCmgt, true, 1, 1, 0, 2, 0, 2, 0, 0), // cmpLtI32
  _V3(A64InstId.kCmhi, true, 1, 1, 0, 2, 0, 2, 0, 0), // cmpLtU32
  _V3(A64InstId.kCmgt, true, 1, 1, 0, 3, 0, 3, 0, 0), // cmpLtI64
  _V3(A64InstId.kCmhi, true, 1, 1, 0, 3, 0, 3, 0, 0), // cmpLtU64
  _V3(A64InstId.kCmge, true, 1, 2, 0, 0, 0, 0, 0, 0), // cmpLeI8
  _V3(A64InstId.kCmhs, true, 1, 2, 0, 0, 0, 0, 0, 0), // cmpLeU8
  _V3(A64InstId.kCmge, true, 1, 2, 0, 1, 0, 1, 0, 0), // cmpLeI16
  _V3(A64InstId.kCmhs, true, 1, 2, 0, 1, 0, 1, 0, 0), // cmpLeU16
  _V3(A64InstId.kCmge, true, 1, 2, 0, 2, 0, 2, 0, 0), // cmpLeI32
  _V3(A64InstId.kCmhs, true, 1, 2, 0, 2, 0, 2, 0, 0), // cmpLeU32
  _V3(A64InstId.kCmge, true, 1, 2, 0, 3, 0, 3, 0, 0), // cmpLeI64
  _V3(A64InstId.kCmhs, true, 1, 2, 0, 3, 0, 3, 0, 0), // cmpLeU64
  _V3(A64InstId.kAnd, true, 0, 3, 3, 0, 0, 0, 0, 0), // andF32
  _V3(A64InstId.kAnd, true, 0, 3, 4, 0, 0, 0, 0, 0), // andF64
  _V3(A64InstId.kOrr, true, 0, 3, 3, 0, 0, 0, 0, 0), // orF32
  _V3(A64InstId.kOrr, true, 0, 3, 4, 0, 0, 0, 0, 0), // orF64
  _V3(A64InstId.kEor, true, 0, 1, 3, 0, 0, 0, 0, 0), // xorF32
  _V3(A64InstId.kEor, true, 0, 1, 4, 0, 0, 0, 0, 0), // xorF64
  _V3(A64InstId.kBic, true, 1, 1, 3, 0, 0, 0, 0, 0), // andnF32
  _V3(A64InstId.kBic, true, 1, 1, 4, 0, 0, 0, 0, 0), // andnF64
  _V3(A64InstId.kBic, true, 0, 1, 3, 0, 0, 0, 0, 0), // bicF32
  _V3(A64InstId.kBic, true, 0, 1, 4, 0, 0, 0, 0, 0), // bicF64
  _V3(A64InstId.kFadd, true, 0, 0, 1, 2, 0, 2, 0, 0), // addF32S
  _V3(A64InstId.kFadd, true, 0, 0, 2, 3, 0, 3, 0, 0), // addF64S
  _V3(A64InstId.kFadd, true, 0, 0, 3, 2, 0, 2, 0, 0), // addF32
  _V3(A64InstId.kFadd, true, 0, 0, 4, 3, 0, 3, 0, 0), // addF64
  _V3(A64InstId.kFsub, true, 0, 0, 1, 2, 0, 2, 0, 0), // subF32S
  _V3(A64InstId.kFsub, true, 0, 0, 2, 3, 0, 3, 0, 0), // subF64S
  _V3(A64InstId.kFsub, true, 0, 0, 3, 2, 0, 2, 0, 0), // subF32
  _V3(A64InstId.kFsub, true, 0, 0, 4, 3, 0, 3, 0, 0), // subF64
  _V3(A64InstId.kFmul, true, 0, 0, 1, 2, 0, 2, 0, 0), // mulF32S
  _V3(A64InstId.kFmul, true, 0, 0, 2, 3, 0, 3, 0, 0), // mulF64S
  _V3(A64InstId.kFmul, true, 0, 0, 3, 2, 0, 2, 0, 0), // mulF32
  _V3(A64InstId.kFmul, true, 0, 0, 4, 3, 0, 3, 0, 0), // mulF64
  _V3(A64InstId.kFdiv, true, 0, 0, 1, 2, 0, 2, 0, 0), // divF32S
  _V3(A64InstId.kFdiv, true, 0, 0, 2, 3, 0, 3, 0, 0), // divF64S
  _V3(A64InstId.kFdiv, true, 0, 0, 3, 2, 0, 2, 0, 0), // divF32
  _V3(A64InstId.kFdiv, true, 0, 0, 4, 3, 0, 3, 0, 0), // divF64
  _V3(-1, false, 0, 0, 1, 2, 0, 2, 0, 0), // modF32S
  _V3(-1, false, 0, 0, 2, 3, 0, 3, 0, 0), // modF64S
  _V3(-1, false, 0, 0, 3, 2, 0, 2, 0, 0), // modF32
  _V3(-1, false, 0, 0, 4, 3, 0, 3, 0, 0), // modF64
  _V3(A64InstId.kFminnm, true, 0, 3, 1, 2, 0, 2, 0, 0), // minF32S
  _V3(A64InstId.kFminnm, true, 0, 3, 2, 3, 0, 3, 0, 0), // minF64S
  _V3(A64InstId.kFminnm, true, 0, 3, 3, 2, 0, 2, 0, 0), // minF32
  _V3(A64InstId.kFminnm, true, 0, 3, 4, 3, 0, 3, 0, 0), // minF64
  _V3(A64InstId.kFmaxnm, true, 0, 3, 1, 2, 0, 2, 0, 0), // maxF32S
  _V3(A64InstId.kFmaxnm, true, 0, 3, 2, 3, 0, 3, 0, 0), // maxF64S
  _V3(A64InstId.kFmaxnm, true, 0, 3, 3, 2, 0, 2, 0, 0), // maxF32
  _V3(A64InstId.kFmaxnm, true, 0, 3, 4, 3, 0, 3, 0, 0), // maxF64
  _V3(A64InstId.kFcmeq, true, 0, 0, 1, 2, 0, 2, 0, 0), // cmpEqF32S
  _V3(A64InstId.kFcmeq, true, 0, 0, 2, 3, 0, 3, 0, 0), // cmpEqF64S
  _V3(A64InstId.kFcmeq, true, 0, 0, 3, 2, 0, 2, 0, 0), // cmpEqF32
  _V3(A64InstId.kFcmeq, true, 0, 0, 4, 3, 0, 3, 0, 0), // cmpEqF64
  _V3(A64InstId.kFcmeq, false, 0, 0, 1, 2, 0, 2, 0, 0), // cmpNeF32S
  _V3(A64InstId.kFcmeq, false, 0, 0, 2, 3, 0, 3, 0, 0), // cmpNeF64S
  _V3(A64InstId.kFcmeq, false, 0, 0, 3, 2, 0, 2, 0, 0), // cmpNeF32
  _V3(A64InstId.kFcmeq, false, 0, 0, 4, 3, 0, 3, 0, 0), // cmpNeF64
  _V3(A64InstId.kFcmgt, true, 0, 0, 1, 2, 0, 2, 0, 0), // cmpGtF32S
  _V3(A64InstId.kFcmgt, true, 0, 0, 2, 3, 0, 3, 0, 0), // cmpGtF64S
  _V3(A64InstId.kFcmgt, true, 0, 0, 3, 2, 0, 2, 0, 0), // cmpGtF32
  _V3(A64InstId.kFcmgt, true, 0, 0, 4, 3, 0, 3, 0, 0), // cmpGtF64
  _V3(A64InstId.kFcmge, true, 0, 0, 1, 2, 0, 2, 0, 0), // cmpGeF32S
  _V3(A64InstId.kFcmge, true, 0, 0, 2, 3, 0, 3, 0, 0), // cmpGeF64S
  _V3(A64InstId.kFcmge, true, 0, 0, 3, 2, 0, 2, 0, 0), // cmpGeF32
  _V3(A64InstId.kFcmge, true, 0, 0, 4, 3, 0, 3, 0, 0), // cmpGeF64
  _V3(A64InstId.kFcmgt, true, 1, 0, 1, 2, 0, 2, 0, 0), // cmpLtF32S
  _V3(A64InstId.kFcmgt, true, 1, 0, 2, 3, 0, 3, 0, 0), // cmpLtF64S
  _V3(A64InstId.kFcmgt, true, 1, 0, 3, 2, 0, 2, 0, 0), // cmpLtF32
  _V3(A64InstId.kFcmgt, true, 1, 0, 4, 3, 0, 3, 0, 0), // cmpLtF64
  _V3(A64InstId.kFcmge, true, 1, 0, 1, 2, 0, 2, 0, 0), // cmpLeF32S
  _V3(A64InstId.kFcmge, true, 1, 0, 2, 3, 0, 3, 0, 0), // cmpLeF64S
  _V3(A64InstId.kFcmge, true, 1, 0, 3, 2, 0, 2, 0, 0), // cmpLeF32
  _V3(A64InstId.kFcmge, true, 1, 0, 4, 3, 0, 3, 0, 0), // cmpLeF64
  _V3(A64InstId.kFcmeq, false, 0, 0, 1, 2, 0, 2, 0, 0), // cmpOrdF32S
  _V3(A64InstId.kFcmeq, false, 0, 0, 2, 3, 0, 3, 0, 0), // cmpOrdF64S
  _V3(A64InstId.kFcmeq, false, 0, 0, 3, 2, 0, 2, 0, 0), // cmpOrdF32
  _V3(A64InstId.kFcmeq, false, 0, 0, 4, 3, 0, 3, 0, 0), // cmpOrdF64
  _V3(A64InstId.kFcmeq, false, 0, 0, 1, 2, 0, 2, 0, 1), // cmpUnordF32S
  _V3(A64InstId.kFcmeq, false, 0, 0, 2, 3, 0, 3, 0, 1), // cmpUnordF64S
  _V3(A64InstId.kFcmeq, false, 0, 0, 3, 2, 0, 2, 0, 1), // cmpUnordF32
  _V3(A64InstId.kFcmeq, false, 0, 0, 4, 3, 0, 3, 0, 1), // cmpUnordF64
  _V3(-1, false, 0, 0, 4, 3, 0, 3, 0, 0), // hAddF64
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // combineLoHiU64
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // combineLoHiF64
  _V3(-1, false, 0, 3, 0, 3, 0, 3, 0, 0), // combineHiLoU64
  _V3(-1, false, 0, 3, 0, 3, 0, 3, 0, 0), // combineHiLoF64
  _V3(A64InstId.kZip1, true, 0, 0, 0, 0, 0, 0, 0, 0), // interleaveLoU8
  _V3(A64InstId.kZip2, true, 0, 0, 0, 0, 0, 0, 0, 0), // interleaveHiU8
  _V3(A64InstId.kZip1, true, 0, 0, 0, 1, 0, 1, 0, 0), // interleaveLoU16
  _V3(A64InstId.kZip2, true, 0, 0, 0, 1, 0, 1, 0, 0), // interleaveHiU16
  _V3(A64InstId.kZip1, true, 0, 0, 0, 2, 0, 2, 0, 0), // interleaveLoU32
  _V3(A64InstId.kZip2, true, 0, 0, 0, 2, 0, 2, 0, 0), // interleaveHiU32
  _V3(A64InstId.kZip1, true, 0, 0, 0, 3, 0, 3, 0, 0), // interleaveLoU64
  _V3(A64InstId.kZip2, true, 0, 0, 0, 3, 0, 3, 0, 0), // interleaveHiU64
  _V3(A64InstId.kZip1, true, 0, 0, 0, 2, 0, 2, 0, 0), // interleaveLoF32
  _V3(A64InstId.kZip2, true, 0, 0, 0, 2, 0, 2, 0, 0), // interleaveHiF32
  _V3(A64InstId.kZip1, true, 0, 0, 0, 3, 0, 3, 0, 0), // interleaveLoF64
  _V3(A64InstId.kZip2, true, 0, 0, 0, 3, 0, 3, 0, 0), // interleaveHiF64
  _V3(A64InstId.kSqxtn, false, 0, 0, 0, 0, 0, 1, 0, 0), // packsI16I8
  _V3(A64InstId.kSqxtun, false, 0, 0, 0, 0, 0, 1, 0, 0), // packsI16U8
  _V3(A64InstId.kSqxtn, false, 0, 0, 0, 1, 0, 2, 0, 0), // packsI32I16
  _V3(A64InstId.kSqxtun, false, 0, 0, 0, 1, 0, 2, 0, 0), // packsI32U16
  _V3(A64InstId.kTbl, true, 0, 0, 0, 0, 0, 0, 0, 0), // swizzlevU8
  _V3(A64InstId.kSmull, true, 0, 0, 0, 1, 0, 0, 1, 0), // mulwLoI8
  _V3(A64InstId.kUmull, true, 0, 0, 0, 1, 0, 0, 1, 0), // mulwLoU8
  _V3(A64InstId.kSmull2, true, 0, 0, 0, 1, 0, 0, 2, 0), // mulwHiI8
  _V3(A64InstId.kUmull2, true, 0, 0, 0, 1, 0, 0, 2, 0), // mulwHiU8
  _V3(A64InstId.kSmull, true, 0, 0, 0, 2, 0, 1, 1, 0), // mulwLoI16
  _V3(A64InstId.kUmull, true, 0, 0, 0, 2, 0, 1, 1, 0), // mulwLoU16
  _V3(A64InstId.kSmull2, true, 0, 0, 0, 2, 0, 1, 2, 0), // mulwHiI16
  _V3(A64InstId.kUmull2, true, 0, 0, 0, 2, 0, 1, 2, 0), // mulwHiU16
  _V3(A64InstId.kSmull, true, 0, 0, 0, 3, 0, 2, 1, 0), // mulwLoI32
  _V3(A64InstId.kUmull, true, 0, 0, 0, 3, 0, 2, 1, 0), // mulwLoU32
  _V3(A64InstId.kSmull2, true, 0, 0, 0, 3, 0, 2, 2, 0), // mulwHiI32
  _V3(A64InstId.kUmull2, true, 0, 0, 0, 3, 0, 2, 2, 0), // mulwHiU32
  _V3(A64InstId.kSmlal, true, 0, 0, 0, 1, 0, 0, 1, 0), // mAddwLoI8
  _V3(A64InstId.kUmlal, true, 0, 0, 0, 1, 0, 0, 1, 0), // mAddwLoU8
  _V3(A64InstId.kSmlal2, true, 0, 0, 0, 1, 0, 0, 2, 0), // mAddwHiI8
  _V3(A64InstId.kUmlal2, true, 0, 0, 0, 1, 0, 0, 2, 0), // mAddwHiU8
  _V3(A64InstId.kSmlal, true, 0, 0, 0, 2, 0, 1, 1, 0), // mAddwLoI16
  _V3(A64InstId.kUmlal, true, 0, 0, 0, 2, 0, 1, 1, 0), // mAddwLoU16
  _V3(A64InstId.kSmlal2, true, 0, 0, 0, 2, 0, 1, 2, 0), // mAddwHiI16
  _V3(A64InstId.kUmlal2, true, 0, 0, 0, 2, 0, 1, 2, 0), // mAddwHiU16
  _V3(A64InstId.kSmlal, true, 0, 0, 0, 3, 0, 2, 1, 0), // mAddwLoI32
  _V3(A64InstId.kUmlal, true, 0, 0, 0, 3, 0, 2, 1, 0), // mAddwLoU32
  _V3(A64InstId.kSmlal2, true, 0, 0, 0, 3, 0, 2, 2, 0), // mAddwHiI32
  _V3(A64InstId.kUmlal2, true, 0, 0, 0, 3, 0, 2, 2, 0), // mAddwHiU32
];

/// Ported from `opcode_info_2vi`; one entry per [UniOpVVI] value present in
/// upstream (Dart-only values after the last entry are handled separately).
const List<A64UniOpVInfo> kA64OpcodeInfo2vi = [
  _V3(A64InstId.kShl, true, 0, 0, 0, 1, 0, 1, 0, 0), // sllU16
  _V3(A64InstId.kShl, true, 0, 0, 0, 2, 0, 2, 0, 0), // sllU32
  _V3(A64InstId.kShl, true, 0, 0, 0, 3, 0, 3, 0, 0), // sllU64
  _V3(A64InstId.kUshr, true, 0, 0, 0, 1, 0, 1, 0, 0), // srlU16
  _V3(A64InstId.kUshr, true, 0, 0, 0, 2, 0, 2, 0, 0), // srlU32
  _V3(A64InstId.kUshr, true, 0, 0, 0, 3, 0, 3, 0, 0), // srlU64
  _V3(A64InstId.kSshr, true, 0, 0, 0, 1, 0, 1, 0, 0), // sraI16
  _V3(A64InstId.kSshr, true, 0, 0, 0, 2, 0, 2, 0, 0), // sraI32
  _V3(A64InstId.kSshr, true, 0, 0, 0, 3, 0, 3, 0, 0), // sraI64
  _V3(A64InstId.kExt, false, 0, 0, 0, 0, 0, 0, 0, 0), // sllbU128
  _V3(A64InstId.kExt, false, 0, 0, 0, 0, 0, 0, 0, 0), // srlbU128
  _V3(-1, false, 0, 0, 0, 1, 0, 1, 0, 0), // swizzleU16x4
  _V3(-1, false, 0, 0, 0, 1, 0, 1, 0, 0), // swizzleLoU16x4
  _V3(-1, false, 0, 0, 0, 1, 0, 1, 0, 0), // swizzleHiU16x4
  _V3(-1, false, 0, 0, 0, 2, 0, 2, 0, 0), // swizzleU32x4
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // swizzleU64x2
  _V3(-1, false, 0, 0, 3, 2, 0, 2, 0, 0), // swizzleF32x4
  _V3(-1, false, 0, 0, 4, 3, 0, 3, 0, 0), // swizzleF64x2
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // swizzleU64x4
  _V3(-1, false, 0, 0, 4, 3, 0, 3, 0, 0), // swizzleF64x4
  _V3(-1, false, 0, 0, 0, 2, 0, 2, 0, 0), // extractV128I32
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // extractV128I64
  _V3(-1, false, 0, 0, 3, 2, 0, 2, 0, 0), // extractV128F32
  _V3(-1, false, 0, 0, 4, 3, 0, 3, 0, 0), // extractV128F64
  _V3(-1, false, 0, 0, 0, 2, 0, 2, 0, 0), // extractV256I32
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // extractV256I64
  _V3(-1, false, 0, 0, 3, 2, 0, 2, 0, 0), // extractV256F32
  _V3(-1, false, 0, 0, 4, 3, 0, 3, 0, 0), // extractV256F64
  _V3(A64InstId.kUrshr, true, 0, 0, 0, 1, 0, 1, 0, 0), // srlRndU16
  _V3(A64InstId.kUrshr, true, 0, 0, 0, 2, 0, 2, 0, 0), // srlRndU32
  _V3(A64InstId.kUrshr, true, 0, 0, 0, 3, 0, 3, 0, 0), // srlRndU64
  _V3(A64InstId.kUsra, true, 0, 0, 0, 1, 0, 1, 0, 0), // srlAccU16
  _V3(A64InstId.kUsra, true, 0, 0, 0, 2, 0, 2, 0, 0), // srlAccU32
  _V3(A64InstId.kUsra, true, 0, 0, 0, 3, 0, 3, 0, 0), // srlAccU64
  _V3(A64InstId.kUrsra, true, 0, 0, 0, 1, 0, 1, 0, 0), // srlRndAccU16
  _V3(A64InstId.kUrsra, true, 0, 0, 0, 2, 0, 2, 0, 0), // srlRndAccU32
  _V3(A64InstId.kUrsra, true, 0, 0, 0, 3, 0, 3, 0, 0), // srlRndAccU64
  _V3(A64InstId.kShrn, true, 0, 0, 0, 0, 0, 1, 1, 0), // srlnLoU16
  _V3(A64InstId.kShrn2, true, 0, 0, 0, 0, 0, 1, 2, 0), // srlnHiU16
  _V3(A64InstId.kShrn, true, 0, 0, 0, 1, 0, 2, 1, 0), // srlnLoU32
  _V3(A64InstId.kShrn2, true, 0, 0, 0, 1, 0, 2, 2, 0), // srlnHiU32
  _V3(A64InstId.kShrn, true, 0, 0, 0, 2, 0, 3, 1, 0), // srlnLoU64
  _V3(A64InstId.kShrn2, true, 0, 0, 0, 2, 0, 3, 2, 0), // srlnHiU64
  _V3(A64InstId.kRshrn, true, 0, 0, 0, 0, 1, 1, 0, 0), // srlnRndLoU16
  _V3(A64InstId.kRshrn2, true, 0, 0, 0, 0, 2, 1, 0, 0), // srlnRndHiU16
  _V3(A64InstId.kRshrn, true, 0, 0, 0, 1, 1, 2, 0, 0), // srlnRndLoU32
  _V3(A64InstId.kRshrn2, true, 0, 0, 0, 1, 2, 2, 0, 0), // srlnRndHiU32
  _V3(A64InstId.kRshrn, true, 0, 0, 0, 2, 1, 3, 0, 0), // srlnRndLoU64
  _V3(A64InstId.kRshrn2, true, 0, 0, 0, 2, 2, 3, 0, 0), // srlnRndHiU64
];
