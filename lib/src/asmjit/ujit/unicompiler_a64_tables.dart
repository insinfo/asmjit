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

/// Ported from `opcode_info_2v`; one entry per [UniOpVV] value.
const List<A64UniOpVInfo> kA64OpcodeInfo2v = [
  _V3(A64InstId.kMov, false, 0, 0, 0, 0, 0, 0, 0, 0), // mov
  _V3(A64InstId.kMov, false, 0, 0, 0, 3, 1, 3, 1, 0), // movU64
  _V3(A64InstId.kDup, false, 0, 0, 0, 0, 0, 0, 0, 0), // broadcastU8Z
  _V3(A64InstId.kDup, false, 0, 0, 0, 1, 0, 1, 0, 0), // broadcastU16Z
  _V3(A64InstId.kDup, false, 0, 0, 0, 0, 0, 0, 0, 0), // broadcastU8
  _V3(A64InstId.kDup, false, 0, 0, 0, 1, 0, 1, 0, 0), // broadcastU16
  _V3(A64InstId.kDup, false, 0, 0, 0, 2, 0, 2, 0, 0), // broadcastU32
  _V3(A64InstId.kDup, false, 0, 0, 0, 3, 0, 3, 0, 0), // broadcastU64
  _V3(A64InstId.kDup, false, 0, 0, 0, 2, 0, 2, 0, 0), // broadcastF32
  _V3(A64InstId.kDup, false, 0, 0, 0, 3, 0, 3, 0, 0), // broadcastF64
  _V3(-1, false, 0, 0, 0, 2, 0, 2, 0, 0), // broadcastV128U32
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // broadcastV128U64
  _V3(-1, false, 0, 0, 0, 2, 0, 2, 0, 0), // broadcastV128F32
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // broadcastV128F64
  _V3(-1, false, 0, 0, 0, 2, 0, 2, 0, 0), // broadcastV256U32
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // broadcastV256U64
  _V3(-1, false, 0, 0, 0, 2, 0, 2, 0, 0), // broadcastV256F32
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // broadcastV256F64
  _V3(A64InstId.kAbs, true, 0, 0, 0, 0, 0, 0, 0, 0), // absI8
  _V3(A64InstId.kAbs, true, 0, 0, 0, 1, 0, 1, 0, 0), // absI16
  _V3(A64InstId.kAbs, true, 0, 0, 0, 2, 0, 2, 0, 0), // absI32
  _V3(A64InstId.kAbs, true, 0, 0, 0, 3, 0, 3, 0, 0), // absI64
  _V3(A64InstId.kMvn, true, 0, 0, 0, 0, 0, 0, 0, 0), // notU32
  _V3(A64InstId.kMvn, true, 0, 0, 0, 0, 0, 0, 0, 0), // notU64
  _V3(A64InstId.kSshll, false, 0, 0, 0, 1, 0, 0, 1, 0), // cvtI8LoToI16
  _V3(A64InstId.kSshll2, false, 0, 0, 0, 1, 0, 0, 2, 0), // cvtI8HiToI16
  _V3(A64InstId.kUshll, false, 0, 0, 0, 1, 0, 0, 1, 0), // cvtU8LoToU16
  _V3(A64InstId.kUshll2, false, 0, 0, 0, 1, 0, 0, 2, 0), // cvtU8HiToU16
  _V3(A64InstId.kSshll, false, 0, 0, 0, 2, 0, 0, 1, 0), // cvtI8ToI32
  _V3(A64InstId.kUshll, false, 0, 0, 0, 2, 0, 0, 1, 0), // cvtU8ToU32
  _V3(A64InstId.kSshll, false, 0, 0, 0, 2, 0, 1, 1, 0), // cvtI16LoToI32
  _V3(A64InstId.kSshll2, false, 0, 0, 0, 2, 0, 1, 2, 0), // cvtI16HiToI32
  _V3(A64InstId.kUshll, false, 0, 0, 0, 2, 0, 1, 1, 0), // cvtU16LoToU32
  _V3(A64InstId.kUshll2, false, 0, 0, 0, 2, 0, 1, 2, 0), // cvtU16HiToU32
  _V3(A64InstId.kSshll, false, 0, 0, 0, 3, 0, 2, 1, 0), // cvtI32LoToI64
  _V3(A64InstId.kSshll2, false, 0, 0, 0, 3, 0, 2, 2, 0), // cvtI32HiToI64
  _V3(A64InstId.kUshll, false, 0, 0, 0, 3, 0, 2, 1, 0), // cvtU32LoToU64
  _V3(A64InstId.kUshll2, false, 0, 0, 0, 3, 0, 2, 2, 0), // cvtU32HiToU64
  _V3(A64InstId.kFabs, true, 0, 0, 1, 2, 0, 2, 0, 0), // absF32S
  _V3(A64InstId.kFabs, true, 0, 0, 2, 3, 0, 3, 0, 0), // absF64S
  _V3(A64InstId.kFabs, true, 0, 0, 3, 2, 0, 2, 0, 0), // absF32
  _V3(A64InstId.kFabs, true, 0, 0, 4, 3, 0, 3, 0, 0), // absF64
  _V3(A64InstId.kFneg, true, 0, 0, 1, 2, 0, 2, 0, 0), // negF32S
  _V3(A64InstId.kFneg, true, 0, 0, 2, 3, 0, 3, 0, 0), // negF64S
  _V3(A64InstId.kFneg, true, 0, 0, 3, 2, 0, 2, 0, 0), // negF32
  _V3(A64InstId.kFneg, true, 0, 0, 4, 3, 0, 3, 0, 0), // negF64
  _V3(A64InstId.kMvn, true, 0, 0, 0, 0, 0, 0, 0, 0), // notF32
  _V3(A64InstId.kMvn, true, 0, 0, 0, 0, 0, 0, 0, 0), // notF64
  _V3(A64InstId.kFrintz, true, 0, 0, 1, 2, 0, 2, 0, 0), // truncF32S
  _V3(A64InstId.kFrintz, true, 0, 0, 2, 3, 0, 3, 0, 0), // truncF64S
  _V3(A64InstId.kFrintz, true, 0, 0, 3, 2, 0, 2, 0, 0), // truncF32
  _V3(A64InstId.kFrintz, true, 0, 0, 4, 3, 0, 3, 0, 0), // truncF64
  _V3(A64InstId.kFrintm, true, 0, 0, 1, 2, 0, 2, 0, 0), // floorF32S
  _V3(A64InstId.kFrintm, true, 0, 0, 2, 3, 0, 3, 0, 0), // floorF64S
  _V3(A64InstId.kFrintm, true, 0, 0, 3, 2, 0, 2, 0, 0), // floorF32
  _V3(A64InstId.kFrintm, true, 0, 0, 4, 3, 0, 3, 0, 0), // floorF64
  _V3(A64InstId.kFrintp, true, 0, 0, 1, 2, 0, 2, 0, 0), // ceilF32S
  _V3(A64InstId.kFrintp, true, 0, 0, 2, 3, 0, 3, 0, 0), // ceilF64S
  _V3(A64InstId.kFrintp, true, 0, 0, 3, 2, 0, 2, 0, 0), // ceilF32
  _V3(A64InstId.kFrintp, true, 0, 0, 4, 3, 0, 3, 0, 0), // ceilF64
  _V3(A64InstId.kFrintn, true, 0, 0, 1, 2, 0, 2, 0, 0), // roundEvenF32S
  _V3(A64InstId.kFrintn, true, 0, 0, 2, 3, 0, 3, 0, 0), // roundEvenF64S
  _V3(A64InstId.kFrintn, true, 0, 0, 3, 2, 0, 2, 0, 0), // roundEvenF32
  _V3(A64InstId.kFrintn, true, 0, 0, 4, 3, 0, 3, 0, 0), // roundEvenF64
  _V3(A64InstId.kFrinta, true, 0, 0, 1, 2, 0, 2, 0, 0), // roundHalfAwayF32S
  _V3(A64InstId.kFrinta, true, 0, 0, 2, 3, 0, 3, 0, 0), // roundHalfAwayF64S
  _V3(A64InstId.kFrinta, true, 0, 0, 3, 2, 0, 2, 0, 0), // roundHalfAwayF32
  _V3(A64InstId.kFrinta, true, 0, 0, 4, 3, 0, 3, 0, 0), // roundHalfAwayF64
  _V3(-1, false, 0, 0, 1, 2, 0, 2, 0, 0), // roundHalfUpF32S
  _V3(-1, false, 0, 0, 2, 3, 0, 3, 0, 0), // roundHalfUpF64S
  _V3(-1, false, 0, 0, 3, 2, 0, 2, 0, 0), // roundHalfUpF32
  _V3(-1, false, 0, 0, 4, 3, 0, 3, 0, 0), // roundHalfUpF64
  _V3(-1, false, 0, 0, 0, 2, 0, 2, 0, 0), // rcpF32
  _V3(-1, false, 0, 0, 0, 3, 0, 3, 0, 0), // rcpF64
  _V3(A64InstId.kFsqrt, true, 0, 0, 1, 2, 0, 2, 0, 0), // sqrtF32S
  _V3(A64InstId.kFsqrt, true, 0, 0, 2, 3, 0, 3, 0, 0), // sqrtF64S
  _V3(A64InstId.kFsqrt, true, 0, 0, 3, 2, 0, 2, 0, 0), // sqrtF32
  _V3(A64InstId.kFsqrt, true, 0, 0, 4, 3, 0, 3, 0, 0), // sqrtF64
  _V3(A64InstId.kFcvt, true, 0, 0, 2, 3, 0, 2, 0, 0), // cvtF32ToF64S
  _V3(A64InstId.kFcvt, true, 0, 0, 2, 2, 0, 3, 0, 0), // cvtF64ToF32S
  _V3(A64InstId.kScvtf, true, 0, 0, 3, 2, 0, 2, 0, 0), // cvtI32ToF32
  _V3(A64InstId.kFcvtl, true, 0, 0, 3, 3, 0, 2, 1, 0), // cvtF32LoToF64
  _V3(A64InstId.kFcvtl2, true, 0, 0, 3, 3, 0, 2, 2, 0), // cvtF32HiToF64
  _V3(A64InstId.kFcvtn, true, 0, 0, 4, 2, 1, 3, 0, 0), // cvtF64ToF32Lo
  _V3(A64InstId.kFcvtn2, true, 0, 0, 4, 2, 2, 3, 0, 0), // cvtF64ToF32Hi
  _V3(A64InstId.kSshll, false, 0, 0, 0, 3, 0, 2, 1, 0), // cvtI32LoToF64
  _V3(A64InstId.kSshll2, false, 0, 0, 0, 3, 0, 2, 2, 0), // cvtI32HiToF64
  _V3(A64InstId.kFcvtzs, true, 0, 0, 3, 2, 0, 2, 0, 0), // cvtTruncF32ToI32
  _V3(A64InstId.kFcvtzs, false, 0, 0, 4, 2, 1, 3, 1, 0), // cvtTruncF64ToI32Lo
  _V3(A64InstId.kFcvtzs, false, 0, 0, 4, 2, 2, 3, 2, 0), // cvtTruncF64ToI32Hi
  _V3(A64InstId.kFcvtns, true, 0, 0, 3, 2, 0, 2, 0, 0), // cvtRoundF32ToI32
  _V3(A64InstId.kFcvtns, false, 0, 0, 4, 2, 1, 3, 1, 0), // cvtRoundF64ToI32Lo
  _V3(A64InstId.kFcvtns, false, 0, 0, 4, 2, 2, 3, 2, 0), // cvtRoundF64ToI32Hi
];

/// `swizzle_32_data` (unicompiler_a64.cpp): for each 32-bit swizzle
/// (index `d << 6 | c << 4 | b << 2 | a`) up to three operations, one byte
/// each (`Swizzle32Data::Op`), and their targets in bits 24..29 (2 bits per
/// operation: 0 = dst, 1 = first source, 2 = second source, 3 = both).
const List<int> kA64Swizzle32Data = [
  0x00000003,
  0x00D29205,
  0x00E26224,
  0x02003403,
  0x0000C287,
  0x03000705,
  0x00E27224,
  0x02E23405,
  0x0000C227,
  0x0000B214,
  0x03005714,
  0x00B22214,
  0x00E22224,
  0x02003703,
  0x0000E224,
  0x03001714,
  0x0000C207,
  0x03008705,
  0x00D23234,
  0x0000D234,
  0x02000705,
  0x01001413,
  0x02622405,
  0x0062D234,
  0x00328214,
  0x00008214,
  0x00128214,
  0x03002405,
  0x02000734,
  0x00826214,
  0x02002405,
  0x0042D234,
  0x0000C247,
  0x00D2B205,
  0x03003714,
  0x02003427,
  0x0000C201,
  0x0012C201,
  0x0022C201,
  0x07072405,
  0x02002724,
  0x00009214,
  0x01001423,
  0x00922214,
  0x01001405,
  0x02003714,
  0x0082E224,
  0x01121405,
  0x00D21205,
  0x0000D205,
  0x02001703,
  0x03009714,
  0x02008734,
  0x00004214,
  0x0A170703,
  0x01001437,
  0x00003214,
  0x00000014,
  0x00001214,
  0x00002214,
  0x00326214,
  0x00006214,
  0x02001714,
  0x01001433,
  0x00008207,
  0x01000705,
  0x00006224,
  0x01002414,
  0x00000087,
  0x00001287,
  0x00007224,
  0x00721224,
  0x02002707,
  0x01008714,
  0x00004224,
  0x01002405,
  0x00002224,
  0x00003224,
  0x00000024,
  0x00001224,
  0x00000007,
  0x00002207,
  0x00B26224,
  0x0000E234,
  0x00006207,
  0x00000013,
  0x00B27224,
  0x02003413,
  0x02002713,
  0x00C28214,
  0x00B24224,
  0x00E27234,
  0x00B22224,
  0x0000C237,
  0x0000B224,
  0x03005724,
  0x02004707,
  0x01000714,
  0x01000723,
  0x0A342713,
  0x0000D201,
  0x00D21201,
  0x0022D201,
  0x00D23201,
  0x0062D201,
  0x0092C214,
  0x00824224,
  0x01922405,
  0x03001405,
  0x00328224,
  0x00008224,
  0x00128224,
  0x0012C205,
  0x0000C205,
  0x01000724,
  0x01000733,
  0x00D2B201,
  0x0000C257,
  0x02001713,
  0x03003724,
  0x02002734,
  0x0000C214,
  0x0012C214,
  0x0022C214,
  0x00922224,
  0x02003724,
  0x00009224,
  0x00921224,
  0x00004227,
  0x00009205,
  0x01002724,
  0x00009234,
  0x01002707,
  0x01002713,
  0x00C27224,
  0x01002734,
  0x00000027,
  0x00729205,
  0x00001227,
  0x00729234,
  0x0022C224,
  0x01002705,
  0x0000C224,
  0x01002733,
  0x00001234,
  0x00008205,
  0x00003234,
  0x00000034,
  0x02000714,
  0x00824205,
  0x00326234,
  0x00006234,
  0x02000723,
  0x03008714,
  0x00723234,
  0x00007234,
  0x0A073423,
  0x00826205,
  0x02002414,
  0x00004234,
  0x00000047,
  0x0000B205,
  0x00002247,
  0x0000B234,
  0x0000E201,
  0x03000714,
  0x00E22201,
  0x00E23201,
  0x00009227,
  0x00B27205,
  0x00000023,
  0x02003423,
  0x00E27201,
  0x02003723,
  0x0000C297,
  0x03001705,
  0x00001205,
  0x00000005,
  0x00003205,
  0x00002205,
  0x0A873423,
  0x00004205,
  0x02001734,
  0x00224205,
  0x00721205,
  0x00007205,
  0x0000C217,
  0x03009705,
  0x00621205,
  0x00006205,
  0x02001705,
  0x00622205,
  0x00824201,
  0x0092E205,
  0x0062D224,
  0x0092C234,
  0x00008201,
  0x00128201,
  0x03003405,
  0x02003405,
  0x01001703,
  0x05171413,
  0x0042D224,
  0x01001714,
  0x00728201,
  0x00D23224,
  0x0000D224,
  0x00D21224,
  0x01003703,
  0x0082E205,
  0x01003714,
  0x0000C234,
  0x00009201,
  0x00004237,
  0x00922201,
  0x01003724,
  0x02002705,
  0x01001713,
  0x01003723,
  0x00C27234,
  0x02000733,
  0x00000037,
  0x01003717,
  0x00001237,
  0x00004201,
  0x05971413,
  0x00224201,
  0x01009714,
  0x00000001,
  0x00001201,
  0x00002201,
  0x00003201,
  0x00006201,
  0x01001734,
  0x00008217,
  0x01001705,
  0x00007201,
  0x02003717,
  0x00000097,
  0x00001297,
  0x00B24201,
  0x0000E205,
  0x00E23205,
  0x00E22205,
  0x0000B201,
  0x00000057,
  0x01005717,
  0x00002257,
  0x02002733,
  0x0000E214,
  0x00000017,
  0x00002217,
  0x00B27201,
  0x00009237,
  0x00006217,
  0x00000033,
];

/// `interleaved_shuffle32_ops` (unicompiler_a64.cpp): up to three 11-bit
/// `InterleavedShuffle32Ops::Op` values (bits 0, 11 and 22) per 32-bit
/// interleaved shuffle, indexed by `d << 6 | c << 4 | b << 2 | a`.
const List<int> kA64InterleavedShuffle32Ops = [
  0x0001D0344,
  0x0FA228001,
  0x0F8A2830E,
  0x0FA22830F,
  0x0001C4450,
  0x0F8E28401,
  0x0284D5B47,
  0x0F8A2830F,
  0x0001C1450,
  0x0000D5B47,
  0x0001D234E,
  0x0FA628001,
  0x0F81A7B44,
  0x0001C1C50,
  0x0001C4C50,
  0x0001D034F,
  0x0EE200051,
  0x000050B48,
  0x03C5B7312,
  0x0FA028B0F,
  0x0001C4051,
  0x0EE200851,
  0x0DDDC1343,
  0x0F3DB4345,
  0x0F09B1451,
  0x0000ACB47,
  0x0EE201051,
  0x000050B4E,
  0x03C5B430F,
  0x0000AE343,
  0x0001C7051,
  0x0EE201851,
  0x0ECA0035E,
  0x03C5C4352,
  0x000050B42,
  0x0E3CD3B42,
  0x0F21B2452,
  0x0ECA00B5E,
  0x0F85C0344,
  0x03C5C1851,
  0x0001C135E,
  0x0000AD347,
  0x0ECA0135E,
  0x0DDDC4B44,
  0x06ADC034F,
  0x0001C1B57,
  0x0000AE349,
  0x0ECA01B5E,
  0x0EE20035F,
  0x0EE000B5F,
  0x0284AFB42,
  0x0EE187B5F,
  0x0001C435F,
  0x0EE200B5F,
  0x057081315,
  0x0D9CD4343,
  0x0F09B1453,
  0x0000ADB47,
  0x0EE20135F,
  0x0EF800B5F,
  0x0D9CAF801,
  0x0F0DB3C53,
  0x0001C735F,
  0x0EE201B5F,
  0x0001B4400,
  0x0001B4001,
  0x00008234E,
  0x0001B430F,
  0x000000348,
  0x0001B4401,
  0x000081348,
  0x000081B48,
  0x0001B7312,
  0x0001B731F,
  0x0001B4402,
  0x0001B7001,
  0x000083B48,
  0x0001B7313,
  0x00000034E,
  0x0001B4403,
  0x0ECE00451,
  0x0FA228801,
  0x0F8A28B0E,
  0x0FA228B0F,
  0x0001C4451,
  0x0001D0345,
  0x0ED1C4B43,
  0x0F8A28B0F,
  0x0001C1451,
  0x0FA628B1F,
  0x0F8E28C02,
  0x0FA628801,
  0x07EDC234F,
  0x0001C1C51,
  0x0001C4C51,
  0x0001D234F,
  0x0684AEB14,
  0x03C5C4357,
  0x0284ACB42,
  0x0569B430F,
  0x0000AD348,
  0x0EC5B2340,
  0x0EC1A0B45,
  0x0EC1B0B45,
  0x0F09B1C52,
  0x06ADC3851,
  0x0F95B4342,
  0x0F3DB1B42,
  0x06ADC234F,
  0x0F0DB4452,
  0x0000AEB49,
  0x0E3CD3B4F,
  0x0ECA0035F,
  0x03C5C4353,
  0x03C5C1051,
  0x0E3C80353,
  0x0000ADB48,
  0x0ECA00B5F,
  0x028483343,
  0x000050B43,
  0x0001C135F,
  0x06A9C3851,
  0x0ECA0135F,
  0x03C5C4B53,
  0x056DC234F,
  0x0001C1B5E,
  0x0000ADB4E,
  0x0ECA01B5F,
  0x0001B1400,
  0x0DC991401,
  0x0001B130E,
  0x0DC991403,
  0x0001C4352,
  0x0001B1401,
  0x0DC991C02,
  0x0001B130F,
  0x000000342,
  0x000080B42,
  0x0001B1402,
  0x000081B42,
  0x000083B42,
  0x0001C1851,
  0x0001C4B52,
  0x0001B1403,
  0x0EE60035F,
  0x0EE000B57,
  0x0695B7801,
  0x00008234F,
  0x0001C4357,
  0x0EE600B5F,
  0x0691B7801,
  0x000082B4F,
  0x0000ACB42,
  0x0F81A0B45,
  0x0EE60135F,
  0x00008334F,
  0x0EF992B17,
  0x0000AF343,
  0x0001C4B5F,
  0x0000D234F,
  0x0ECE00452,
  0x0FA229001,
  0x0F8A2930E,
  0x0FA22930F,
  0x0001C4452,
  0x0ECE00C52,
  0x0F81C2B41,
  0x0F8A2930F,
  0x0001C1452,
  0x0FA62931F,
  0x0001D0B44,
  0x0FA629001,
  0x06AC83B44,
  0x0001C1C52,
  0x0001C4C52,
  0x0F8E29403,
  0x0EE600051,
  0x0FF850B1E,
  0x03C5B4B12,
  0x0FA428B07,
  0x000100051,
  0x0EE600851,
  0x03C5B4B1F,
  0x03C5B4B13,
  0x0000ADB42,
  0x0FA428B1F,
  0x0EE601051,
  0x000050B49,
  0x03C5B4B07,
  0x0F0DB1453,
  0x0001C4851,
  0x0EE601851,
  0x0690AFB42,
  0x03C5C435F,
  0x057D9234E,
  0x0E3C80051,
  0x0000AFB48,
  0x0690AC345,
  0x0691B2B47,
  0x0691B0B47,
  0x0000AFB42,
  0x0FB9CA31F,
  0x07D1B2B47,
  0x03C5C735F,
  0x056080343,
  0x0000AC343,
  0x0000AC349,
  0x0EC5A3B45,
  0x0001B1C00,
  0x000082343,
  0x0001B1B07,
  0x0DCD93C03,
  0x0001C4353,
  0x0001B1C01,
  0x0DCD94402,
  0x0001B1B0E,
  0x0001C1051,
  0x000083343,
  0x0001B1C02,
  0x0DCD91403,
  0x000080343,
  0x000000343,
  0x0001C4B53,
  0x0001B1C03,
  0x0001B4C00,
  0x00012A801,
  0x000082349,
  0x0001B4B07,
  0x0001C4359,
  0x0001B4C01,
  0x000082B49,
  0x0DE590403,
  0x0001B4B12,
  0x0001B4B1F,
  0x0001B4C02,
  0x0001B4801,
  0x000080349,
  0x0001B4B13,
  0x000000349,
  0x0001B4C03,
  0x0ECE00453,
  0x0FA229801,
  0x0F8A29B0E,
  0x0FA229B0F,
  0x0001C4453,
  0x0ECE00C53,
  0x06B881315,
  0x0F8A29B0F,
  0x0001C1453,
  0x0FA629B1F,
  0x0ECE01453,
  0x0FA629801,
  0x06AC80343,
  0x0001C1C53,
  0x0001C4C53,
  0x0001D0B45,
];

/// `interleaved_shuffle32_ops_dst_same_as_b` (unicompiler_a64.cpp): up to three 11-bit
/// `InterleavedShuffle32Ops::Op` values (bits 0, 11 and 22) per 32-bit
/// interleaved shuffle, indexed by `d << 6 | c << 4 | b << 2 | a`.
const List<int> kA64InterleavedShuffle32OpsDstSameAsB = [
  0x0001D0344,
  0x0FA228001,
  0x0F8A2830E,
  0x0FA22830F,
  0x0001C4450,
  0x0F8E28401,
  0x0284D5B47,
  0x0F8A2830F,
  0x0001C1450,
  0x0000D5B47,
  0x0001D234E,
  0x0FA628001,
  0x0F81A7B44,
  0x0001C1C50,
  0x0001C4C50,
  0x0001D034F,
  0x0EE200051,
  0x000050B48,
  0x03C5B7312,
  0x0FA028B0F,
  0x0001C4051,
  0x0EE200851,
  0x0DDDC1343,
  0x0F3DB4345,
  0x0F09B1451,
  0x0000ACB47,
  0x0EE201051,
  0x000050B4E,
  0x03C5B430F,
  0x0000AE343,
  0x0001C7051,
  0x0EE201851,
  0x0ECA0035E,
  0x03C5C4352,
  0x000050B42,
  0x0E3CD3B42,
  0x0F21B2452,
  0x0ECA00B5E,
  0x0F85C0344,
  0x03C5C1851,
  0x0001C135E,
  0x0000AD347,
  0x0ECA0135E,
  0x0DDDC4B44,
  0x06ADC034F,
  0x0001C1B57,
  0x0000AE349,
  0x0ECA01B5E,
  0x0EE20035F,
  0x0EE000B5F,
  0x0284AFB42,
  0x0EE187B5F,
  0x0001C435F,
  0x0EE200B5F,
  0x0409C435F,
  0x0D9CD4343,
  0x0F09B1453,
  0x0000ADB47,
  0x0EE20135F,
  0x0EF800B5F,
  0x0D9CAF801,
  0x0F0DB3C53,
  0x0001C735F,
  0x0EE201B5F,
  0x0001B4400,
  0x0001B4001,
  0x00008234E,
  0x0001B430F,
  0x000000348,
  0x0001B4401,
  0x000081348,
  0x000081B48,
  0x0001B7312,
  0x0001B731F,
  0x0001B4402,
  0x0001B7001,
  0x000083B48,
  0x0001B7313,
  0x00000034E,
  0x0001B4403,
  0x0ECE00451,
  0x0FA228801,
  0x0F8A28B0E,
  0x0FA228B0F,
  0x0001C4451,
  0x0001D0345,
  0x0ED1C4B43,
  0x0F8A28B0F,
  0x0001C1451,
  0x0FA628B1F,
  0x0F8E28C02,
  0x0FA628801,
  0x07EDC234F,
  0x0001C1C51,
  0x0001C4C51,
  0x0001D234F,
  0x0684AEB14,
  0x03C5C4357,
  0x0284ACB42,
  0x040CAEB14,
  0x0000AD348,
  0x0EC5B2340,
  0x0EC1A0B45,
  0x0EC1B0B45,
  0x0F09B1C52,
  0x06ADC3851,
  0x0F95B4342,
  0x0F3DB1B42,
  0x06ADC234F,
  0x0F0DB4452,
  0x0000AEB49,
  0x0E3CD3B4F,
  0x0ECA0035F,
  0x03C5C4353,
  0x03C5C1051,
  0x0E3C80353,
  0x0000ADB48,
  0x0ECA00B5F,
  0x028483343,
  0x000050B43,
  0x0001C135F,
  0x06A9C3851,
  0x0ECA0135F,
  0x03C5C4B53,
  0x041DC135F,
  0x0001C1B5E,
  0x0000ADB4E,
  0x0ECA01B5F,
  0x0001B1400,
  0x0DC991401,
  0x0001B130E,
  0x0DC991403,
  0x0001C4352,
  0x0001B1401,
  0x0DC991C02,
  0x0001B130F,
  0x000000342,
  0x000080B42,
  0x0001B1402,
  0x000081B42,
  0x000083B42,
  0x0001C1851,
  0x0001C4B52,
  0x0001B1403,
  0x0EE60035F,
  0x0EE000B57,
  0x0695B7801,
  0x00008234F,
  0x0001C4357,
  0x0EE600B5F,
  0x0691B7801,
  0x000082B4F,
  0x0000ACB42,
  0x0F81A0B45,
  0x0EE60135F,
  0x00008334F,
  0x0EF992B17,
  0x0000AF343,
  0x0001C4B5F,
  0x0000D234F,
  0x0ECE00452,
  0x0FA229001,
  0x0F8A2930E,
  0x0FA22930F,
  0x0001C4452,
  0x0ECE00C52,
  0x0F81C2B41,
  0x0F8A2930F,
  0x0001C1452,
  0x0FA62931F,
  0x0001D0B44,
  0x0FA629001,
  0x06AC83B44,
  0x0001C1C52,
  0x0001C4C52,
  0x0F8E29403,
  0x0EE600051,
  0x0FF850B1E,
  0x03C5B4B12,
  0x0FA428B07,
  0x000100051,
  0x0EE600851,
  0x03C5B4B1F,
  0x03C5B4B13,
  0x0000ADB42,
  0x0FA428B1F,
  0x0EE601051,
  0x000050B49,
  0x03C5B4B07,
  0x0F0DB1453,
  0x0001C4851,
  0x0EE601851,
  0x0690AFB42,
  0x03C5C435F,
  0x0411B2B47,
  0x0E3C80051,
  0x0000AFB48,
  0x0690AC345,
  0x0691B2B47,
  0x0691B0B47,
  0x0000AFB42,
  0x0FB9CA31F,
  0x07D1B2B47,
  0x03C5C735F,
  0x0400AC343,
  0x0000AC343,
  0x0000AC349,
  0x0EC5A3B45,
  0x0001B1C00,
  0x000082343,
  0x0001B1B07,
  0x0DCD93C03,
  0x0001C4353,
  0x0001B1C01,
  0x0DCD94402,
  0x0001B1B0E,
  0x0001C1051,
  0x000083343,
  0x0001B1C02,
  0x0DCD91403,
  0x000080343,
  0x000000343,
  0x0001C4B53,
  0x0001B1C03,
  0x0001B4C00,
  0x00012A801,
  0x000082349,
  0x0001B4B07,
  0x0001C4359,
  0x0001B4C01,
  0x000082B49,
  0x0DE590403,
  0x0001B4B12,
  0x0001B4B1F,
  0x0001B4C02,
  0x0001B4801,
  0x000080349,
  0x0001B4B13,
  0x000000349,
  0x0001B4C03,
  0x0ECE00453,
  0x0FA229801,
  0x0F8A29B0E,
  0x0FA229B0F,
  0x0001C4453,
  0x0ECE00C53,
  0x06B881315,
  0x0F8A29B0F,
  0x0001C1453,
  0x0FA629B1F,
  0x0ECE01453,
  0x0FA629801,
  0x06AC80343,
  0x0001C1C53,
  0x0001C4C53,
  0x0001D0B45,
];
