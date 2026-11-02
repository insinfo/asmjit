/// x86 lowering tables for UniCompiler.
///
/// Ported from `opcode_info_3v` in asmjit's `ujit/unicompiler_x86.cpp`; one
/// entry per [UniOpVVV] value shared by all architectures, in enum order
/// (upstream's x86-only `kPermute*` entries require AVX-512 and are not
/// part of the Dart enum).

import '../x86/x86_inst_db.g.dart';
import 'unicompiler.dart' show SSEExt, AVXExt;

/// x86 `FloatMode`: scalar/vector f32/f64, or none.
const int kX86FmF32S = 0,
    kX86FmF64S = 1,
    kX86FmF32V = 2,
    kX86FmF64V = 3,
    kX86FmNone = 4;

/// `UniOpVInfo` of the x86 backend.
class X86UniOpVInfo {
  /// Legacy SSE instruction (-1 when none).
  final int sseInstId;
  final int sseOpCount;
  final SSEExt sseExt;

  /// VEX/EVEX instruction (-1 when none).
  final int avxInstId;
  final AVXExt avxExt;
  final int commutative;
  final int comparison;

  /// `SameVecOp`: 0 none, 1 zero, 2 ones, 3 src.
  final int sameVecOp;
  final int useImm;
  final int imm;
  final int floatMode;

  /// 0 = 8-bit .. 3 = 64-bit.
  final int elementSize;
  final int broadcastSize;

  /// `VecPart`: 0 = low (or n/a), 1 = high.
  final int hi;

  const X86UniOpVInfo(
      this.sseInstId,
      this.sseOpCount,
      this.sseExt,
      this.avxInstId,
      this.avxExt,
      this.commutative,
      this.comparison,
      this.sameVecOp,
      this.useImm,
      this.imm,
      this.floatMode,
      this.elementSize,
      this.broadcastSize,
      this.hi);
}

typedef _V = X86UniOpVInfo;

const List<X86UniOpVInfo> kX86OpcodeInfo3v = [
  _V(X86InstId.kPand, 2, SSEExt.kSSE2, X86InstId.kVpandd, AVXExt.kAVX, 1, 0, 3,
      0, 0x00, 4, 2, 4, 0), // andU32
  _V(X86InstId.kPand, 2, SSEExt.kSSE2, X86InstId.kVpandq, AVXExt.kAVX, 1, 0, 3,
      0, 0x00, 4, 3, 8, 0), // andU64
  _V(X86InstId.kPor, 2, SSEExt.kSSE2, X86InstId.kVpord, AVXExt.kAVX, 1, 0, 3, 0,
      0x00, 4, 2, 4, 0), // orU32
  _V(X86InstId.kPor, 2, SSEExt.kSSE2, X86InstId.kVporq, AVXExt.kAVX, 1, 0, 3, 0,
      0x00, 4, 3, 8, 0), // orU64
  _V(X86InstId.kPxor, 2, SSEExt.kSSE2, X86InstId.kVpxord, AVXExt.kAVX, 1, 0, 1,
      0, 0x00, 4, 2, 4, 0), // xorU32
  _V(X86InstId.kPxor, 2, SSEExt.kSSE2, X86InstId.kVpxorq, AVXExt.kAVX, 1, 0, 1,
      0, 0x00, 4, 3, 8, 0), // xorU64
  _V(X86InstId.kPandn, 2, SSEExt.kSSE2, X86InstId.kVpandnd, AVXExt.kAVX, 0, 0,
      1, 0, 0x00, 4, 2, 4, 0), // andnU32
  _V(X86InstId.kPandn, 2, SSEExt.kSSE2, X86InstId.kVpandnq, AVXExt.kAVX, 0, 0,
      1, 0, 0x00, 4, 3, 8, 0), // andnU64
  _V(X86InstId.kPandn, 0, SSEExt.kIntrin, X86InstId.kVpandnd, AVXExt.kIntrin, 0,
      0, 1, 0, 0x00, 4, 2, 4, 0), // bicU32
  _V(X86InstId.kPandn, 0, SSEExt.kIntrin, X86InstId.kVpandnq, AVXExt.kIntrin, 0,
      0, 1, 0, 0x00, 4, 3, 8, 0), // bicU64
  _V(X86InstId.kPavgb, 2, SSEExt.kSSE2, X86InstId.kVpavgb, AVXExt.kAVX, 1, 0, 3,
      0, 0x00, 4, 0, 0, 0), // avgrU8
  _V(X86InstId.kPavgw, 2, SSEExt.kSSE2, X86InstId.kVpavgw, AVXExt.kAVX, 1, 0, 3,
      0, 0x00, 4, 1, 0, 0), // avgrU16
  _V(X86InstId.kPaddb, 2, SSEExt.kSSE2, X86InstId.kVpaddb, AVXExt.kAVX, 1, 0, 0,
      0, 0x00, 4, 0, 0, 0), // addU8
  _V(X86InstId.kPaddw, 2, SSEExt.kSSE2, X86InstId.kVpaddw, AVXExt.kAVX, 1, 0, 0,
      0, 0x00, 4, 1, 0, 0), // addU16
  _V(X86InstId.kPaddd, 2, SSEExt.kSSE2, X86InstId.kVpaddd, AVXExt.kAVX, 1, 0, 0,
      0, 0x00, 4, 2, 4, 0), // addU32
  _V(X86InstId.kPaddq, 2, SSEExt.kSSE2, X86InstId.kVpaddq, AVXExt.kAVX, 1, 0, 0,
      0, 0x00, 4, 3, 8, 0), // addU64
  _V(X86InstId.kPsubb, 2, SSEExt.kSSE2, X86InstId.kVpsubb, AVXExt.kAVX, 0, 0, 1,
      0, 0x00, 4, 0, 0, 0), // subU8
  _V(X86InstId.kPsubw, 2, SSEExt.kSSE2, X86InstId.kVpsubw, AVXExt.kAVX, 0, 0, 1,
      0, 0x00, 4, 1, 0, 0), // subU16
  _V(X86InstId.kPsubd, 2, SSEExt.kSSE2, X86InstId.kVpsubd, AVXExt.kAVX, 0, 0, 1,
      0, 0x00, 4, 2, 4, 0), // subU32
  _V(X86InstId.kPsubq, 2, SSEExt.kSSE2, X86InstId.kVpsubq, AVXExt.kAVX, 0, 0, 1,
      0, 0x00, 4, 3, 8, 0), // subU64
  _V(X86InstId.kPaddsb, 2, SSEExt.kSSE2, X86InstId.kVpaddsb, AVXExt.kAVX, 1, 0,
      0, 0, 0x00, 4, 0, 0, 0), // addsI8
  _V(X86InstId.kPaddusb, 2, SSEExt.kSSE2, X86InstId.kVpaddusb, AVXExt.kAVX, 1,
      0, 0, 0, 0x00, 4, 0, 0, 0), // addsU8
  _V(X86InstId.kPaddsw, 2, SSEExt.kSSE2, X86InstId.kVpaddsw, AVXExt.kAVX, 1, 0,
      0, 0, 0x00, 4, 1, 0, 0), // addsI16
  _V(X86InstId.kPaddusw, 2, SSEExt.kSSE2, X86InstId.kVpaddusw, AVXExt.kAVX, 1,
      0, 0, 0, 0x00, 4, 1, 0, 0), // addsU16
  _V(X86InstId.kPsubsb, 2, SSEExt.kSSE2, X86InstId.kVpsubsb, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 4, 0, 0, 0), // subsI8
  _V(X86InstId.kPsubusb, 2, SSEExt.kSSE2, X86InstId.kVpsubusb, AVXExt.kAVX, 0,
      0, 1, 0, 0x00, 4, 0, 0, 0), // subsU8
  _V(X86InstId.kPsubsw, 2, SSEExt.kSSE2, X86InstId.kVpsubsw, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 4, 1, 0, 0), // subsI16
  _V(X86InstId.kPsubusw, 2, SSEExt.kSSE2, X86InstId.kVpsubusw, AVXExt.kAVX, 0,
      0, 1, 0, 0x00, 4, 1, 0, 0), // subsU16
  _V(X86InstId.kPmullw, 2, SSEExt.kSSE2, X86InstId.kVpmullw, AVXExt.kAVX, 1, 0,
      0, 0, 0x00, 4, 1, 0, 0), // mulU16
  _V(X86InstId.kPmulld, 2, SSEExt.kSSE4_1, X86InstId.kVpmulld, AVXExt.kAVX, 1,
      0, 0, 0, 0x00, 4, 2, 4, 0), // mulU32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpmullq, AVXExt.kAVX512, 1, 0, 0, 0,
      0x00, 4, 3, 8, 0), // mulU64
  _V(X86InstId.kPmulhw, 2, SSEExt.kSSE2, X86InstId.kVpmulhw, AVXExt.kAVX, 1, 0,
      0, 0, 0x00, 4, 1, 0, 0), // mulhI16
  _V(X86InstId.kPmulhuw, 2, SSEExt.kSSE2, X86InstId.kVpmulhuw, AVXExt.kAVX, 1,
      0, 0, 0, 0x00, 4, 1, 0, 0), // mulhU16
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 1, 0,
      0), // mulU64LoU32
  _V(X86InstId.kPmaddwd, 2, SSEExt.kSSE2, X86InstId.kVpmaddwd, AVXExt.kAVX, 1,
      0, 0, 0, 0x00, 4, 1, 0, 0), // mHAddI16I32
  _V(X86InstId.kPminsb, 2, SSEExt.kSSE4_1, X86InstId.kVpminsb, AVXExt.kAVX, 1,
      0, 3, 0, 0x00, 4, 0, 0, 0), // minI8
  _V(X86InstId.kPminub, 2, SSEExt.kSSE2, X86InstId.kVpminub, AVXExt.kAVX, 1, 0,
      3, 0, 0x00, 4, 0, 0, 0), // minU8
  _V(X86InstId.kPminsw, 2, SSEExt.kSSE2, X86InstId.kVpminsw, AVXExt.kAVX, 1, 0,
      3, 0, 0x00, 4, 1, 0, 0), // minI16
  _V(X86InstId.kPminuw, 2, SSEExt.kSSE4_1, X86InstId.kVpminuw, AVXExt.kAVX, 1,
      0, 3, 0, 0x00, 4, 1, 0, 0), // minU16
  _V(X86InstId.kPminsd, 2, SSEExt.kSSE4_1, X86InstId.kVpminsd, AVXExt.kAVX, 1,
      0, 3, 0, 0x00, 4, 2, 4, 0), // minI32
  _V(X86InstId.kPminud, 2, SSEExt.kSSE4_1, X86InstId.kVpminud, AVXExt.kAVX, 1,
      0, 3, 0, 0x00, 4, 2, 4, 0), // minU32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpminsq, AVXExt.kAVX512, 1, 0, 3, 0,
      0x00, 4, 3, 8, 0), // minI64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpminuq, AVXExt.kAVX512, 1, 0, 3, 0,
      0x00, 4, 3, 8, 0), // minU64
  _V(X86InstId.kPmaxsb, 2, SSEExt.kSSE4_1, X86InstId.kVpmaxsb, AVXExt.kAVX, 1,
      0, 3, 0, 0x00, 4, 0, 0, 0), // maxI8
  _V(X86InstId.kPmaxub, 2, SSEExt.kSSE2, X86InstId.kVpmaxub, AVXExt.kAVX, 1, 0,
      3, 0, 0x00, 4, 0, 0, 0), // maxU8
  _V(X86InstId.kPmaxsw, 2, SSEExt.kSSE2, X86InstId.kVpmaxsw, AVXExt.kAVX, 1, 0,
      3, 0, 0x00, 4, 1, 0, 0), // maxI16
  _V(X86InstId.kPmaxuw, 2, SSEExt.kSSE4_1, X86InstId.kVpmaxuw, AVXExt.kAVX, 1,
      0, 3, 0, 0x00, 4, 1, 0, 0), // maxU16
  _V(X86InstId.kPmaxsd, 2, SSEExt.kSSE4_1, X86InstId.kVpmaxsd, AVXExt.kAVX, 1,
      0, 3, 0, 0x00, 4, 2, 4, 0), // maxI32
  _V(X86InstId.kPmaxud, 2, SSEExt.kSSE4_1, X86InstId.kVpmaxud, AVXExt.kAVX, 1,
      0, 3, 0, 0x00, 4, 2, 4, 0), // maxU32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpmaxsq, AVXExt.kAVX512, 1, 0, 3, 0,
      0x00, 4, 3, 8, 0), // maxI64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpmaxuq, AVXExt.kAVX512, 1, 0, 3, 0,
      0x00, 4, 3, 8, 0), // maxU64
  _V(X86InstId.kPcmpeqb, 2, SSEExt.kSSE2, X86InstId.kVpcmpeqb, AVXExt.kAVX, 1,
      1, 2, 0, 0x00, 4, 0, 0, 0), // cmpEqU8
  _V(X86InstId.kPcmpeqw, 2, SSEExt.kSSE2, X86InstId.kVpcmpeqw, AVXExt.kAVX, 1,
      1, 2, 0, 0x00, 4, 1, 0, 0), // cmpEqU16
  _V(X86InstId.kPcmpeqd, 2, SSEExt.kSSE2, X86InstId.kVpcmpeqd, AVXExt.kAVX, 1,
      1, 2, 0, 0x00, 4, 2, 4, 0), // cmpEqU32
  _V(X86InstId.kPcmpeqq, 2, SSEExt.kSSE4_1, X86InstId.kVpcmpeqq, AVXExt.kAVX, 1,
      1, 2, 0, 0x00, 4, 3, 8, 0), // cmpEqU64
  _V(X86InstId.kPcmpgtb, 2, SSEExt.kSSE2, X86InstId.kVpcmpgtb, AVXExt.kAVX, 0,
      1, 1, 0, 0x00, 4, 0, 0, 0), // cmpGtI8
  _V(X86InstId.kPcmpgtb, 0, SSEExt.kIntrin, X86InstId.kVpcmpub, AVXExt.kAVX512,
      0, 1, 1, 1, 0x06, 4, 0, 0, 0), // cmpGtU8
  _V(X86InstId.kPcmpgtw, 2, SSEExt.kSSE2, X86InstId.kVpcmpgtw, AVXExt.kAVX, 0,
      1, 1, 0, 0x00, 4, 1, 0, 0), // cmpGtI16
  _V(X86InstId.kPcmpgtw, 0, SSEExt.kIntrin, X86InstId.kVpcmpuw, AVXExt.kAVX512,
      0, 1, 1, 1, 0x06, 4, 1, 0, 0), // cmpGtU16
  _V(X86InstId.kPcmpgtd, 2, SSEExt.kSSE2, X86InstId.kVpcmpgtd, AVXExt.kAVX, 0,
      1, 1, 0, 0x00, 4, 2, 4, 0), // cmpGtI32
  _V(X86InstId.kPcmpgtd, 0, SSEExt.kIntrin, X86InstId.kVpcmpud, AVXExt.kAVX512,
      0, 1, 1, 1, 0x06, 4, 2, 4, 0), // cmpGtU32
  _V(X86InstId.kPcmpgtq, 2, SSEExt.kSSE4_2, X86InstId.kVpcmpgtq, AVXExt.kAVX, 0,
      1, 1, 0, 0x00, 4, 3, 8, 0), // cmpGtI64
  _V(X86InstId.kPcmpgtq, 0, SSEExt.kIntrin, X86InstId.kVpcmpuq, AVXExt.kAVX512,
      0, 1, 1, 1, 0x06, 4, 3, 8, 0), // cmpGtU64
  _V(X86InstId.kPcmpgtb, 0, SSEExt.kIntrin, X86InstId.kVpcmpb, AVXExt.kAVX512,
      0, 1, 2, 1, 0x05, 4, 0, 0, 0), // cmpGeI8
  _V(X86InstId.kPcmpgtb, 0, SSEExt.kIntrin, X86InstId.kVpcmpub, AVXExt.kAVX512,
      0, 1, 2, 1, 0x05, 4, 0, 0, 0), // cmpGeU8
  _V(X86InstId.kPcmpgtw, 0, SSEExt.kIntrin, X86InstId.kVpcmpw, AVXExt.kAVX512,
      0, 1, 2, 1, 0x05, 4, 1, 0, 0), // cmpGeI16
  _V(X86InstId.kPcmpgtw, 0, SSEExt.kIntrin, X86InstId.kVpcmpuw, AVXExt.kAVX512,
      0, 1, 2, 1, 0x05, 4, 1, 0, 0), // cmpGeU16
  _V(X86InstId.kPcmpgtd, 0, SSEExt.kIntrin, X86InstId.kVpcmpd, AVXExt.kAVX512,
      0, 1, 2, 1, 0x05, 4, 2, 4, 0), // cmpGeI32
  _V(X86InstId.kPcmpgtd, 0, SSEExt.kIntrin, X86InstId.kVpcmpud, AVXExt.kAVX512,
      0, 1, 2, 1, 0x05, 4, 2, 4, 0), // cmpGeU32
  _V(X86InstId.kPcmpgtq, 0, SSEExt.kIntrin, X86InstId.kVpcmpq, AVXExt.kAVX512,
      0, 1, 2, 1, 0x05, 4, 3, 8, 0), // cmpGeI64
  _V(X86InstId.kPcmpgtq, 0, SSEExt.kIntrin, X86InstId.kVpcmpuq, AVXExt.kAVX512,
      0, 1, 2, 1, 0x05, 4, 3, 8, 0), // cmpGeU64
  _V(X86InstId.kPcmpgtb, 0, SSEExt.kIntrin, X86InstId.kVpcmpb, AVXExt.kAVX512,
      0, 1, 1, 1, 0x01, 4, 0, 0, 0), // cmpLtI8
  _V(X86InstId.kPcmpgtb, 0, SSEExt.kIntrin, X86InstId.kVpcmpub, AVXExt.kAVX512,
      0, 1, 1, 1, 0x01, 4, 0, 0, 0), // cmpLtU8
  _V(X86InstId.kPcmpgtw, 0, SSEExt.kIntrin, X86InstId.kVpcmpw, AVXExt.kAVX512,
      0, 1, 1, 1, 0x01, 4, 1, 0, 0), // cmpLtI16
  _V(X86InstId.kPcmpgtw, 0, SSEExt.kIntrin, X86InstId.kVpcmpuw, AVXExt.kAVX512,
      0, 1, 1, 1, 0x01, 4, 1, 0, 0), // cmpLtU16
  _V(X86InstId.kPcmpgtd, 0, SSEExt.kIntrin, X86InstId.kVpcmpd, AVXExt.kAVX512,
      0, 1, 1, 1, 0x01, 4, 2, 4, 0), // cmpLtI32
  _V(X86InstId.kPcmpgtd, 0, SSEExt.kIntrin, X86InstId.kVpcmpud, AVXExt.kAVX512,
      0, 1, 1, 1, 0x01, 4, 2, 4, 0), // cmpLtU32
  _V(X86InstId.kPcmpgtq, 0, SSEExt.kIntrin, X86InstId.kVpcmpq, AVXExt.kAVX512,
      0, 1, 1, 1, 0x01, 4, 3, 8, 0), // cmpLtI64
  _V(X86InstId.kPcmpgtq, 0, SSEExt.kIntrin, X86InstId.kVpcmpuq, AVXExt.kAVX512,
      0, 1, 1, 1, 0x01, 4, 3, 8, 0), // cmpLtU64
  _V(X86InstId.kPcmpgtb, 0, SSEExt.kIntrin, X86InstId.kVpcmpb, AVXExt.kAVX512,
      0, 1, 2, 1, 0x02, 4, 0, 0, 0), // cmpLeI8
  _V(X86InstId.kPcmpgtb, 0, SSEExt.kIntrin, X86InstId.kVpcmpub, AVXExt.kAVX512,
      0, 1, 2, 1, 0x02, 4, 0, 0, 0), // cmpLeU8
  _V(X86InstId.kPcmpgtw, 0, SSEExt.kIntrin, X86InstId.kVpcmpw, AVXExt.kAVX512,
      0, 1, 2, 1, 0x02, 4, 1, 0, 0), // cmpLeI16
  _V(X86InstId.kPcmpgtw, 0, SSEExt.kIntrin, X86InstId.kVpcmpuw, AVXExt.kAVX512,
      0, 1, 2, 1, 0x02, 4, 1, 0, 0), // cmpLeU16
  _V(X86InstId.kPcmpgtd, 0, SSEExt.kIntrin, X86InstId.kVpcmpd, AVXExt.kAVX512,
      0, 1, 2, 1, 0x02, 4, 2, 4, 0), // cmpLeI32
  _V(X86InstId.kPcmpgtd, 0, SSEExt.kIntrin, X86InstId.kVpcmpud, AVXExt.kAVX512,
      0, 1, 2, 1, 0x02, 4, 2, 4, 0), // cmpLeU32
  _V(X86InstId.kPcmpgtq, 0, SSEExt.kIntrin, X86InstId.kVpcmpq, AVXExt.kAVX512,
      0, 1, 2, 1, 0x02, 4, 3, 8, 0), // cmpLeI64
  _V(X86InstId.kPcmpgtq, 0, SSEExt.kIntrin, X86InstId.kVpcmpuq, AVXExt.kAVX512,
      0, 1, 2, 1, 0x02, 4, 3, 8, 0), // cmpLeU64
  _V(X86InstId.kAndps, 2, SSEExt.kSSE2, X86InstId.kVandps, AVXExt.kAVX, 1, 0, 3,
      0, 0x00, 2, 2, 4, 0), // andF32
  _V(X86InstId.kAndpd, 2, SSEExt.kSSE2, X86InstId.kVandpd, AVXExt.kAVX, 1, 0, 3,
      0, 0x00, 3, 3, 8, 0), // andF64
  _V(X86InstId.kOrps, 2, SSEExt.kSSE2, X86InstId.kVorps, AVXExt.kAVX, 1, 0, 3,
      0, 0x00, 2, 2, 4, 0), // orF32
  _V(X86InstId.kOrpd, 2, SSEExt.kSSE2, X86InstId.kVorpd, AVXExt.kAVX, 1, 0, 3,
      0, 0x00, 3, 3, 8, 0), // orF64
  _V(X86InstId.kXorps, 2, SSEExt.kSSE2, X86InstId.kVxorps, AVXExt.kAVX, 1, 0, 1,
      0, 0x00, 2, 2, 4, 0), // xorF32
  _V(X86InstId.kXorpd, 2, SSEExt.kSSE2, X86InstId.kVxorpd, AVXExt.kAVX, 1, 0, 1,
      0, 0x00, 3, 3, 8, 0), // xorF64
  _V(X86InstId.kAndnps, 2, SSEExt.kSSE2, X86InstId.kVandnps, AVXExt.kAVX, 0, 0,
      1, 0, 0x00, 2, 2, 4, 0), // andnF32
  _V(X86InstId.kAndnpd, 2, SSEExt.kSSE2, X86InstId.kVandnpd, AVXExt.kAVX, 0, 0,
      1, 0, 0x00, 3, 3, 8, 0), // andnF64
  _V(X86InstId.kAndnps, 0, SSEExt.kIntrin, X86InstId.kVandnps, AVXExt.kIntrin,
      0, 0, 1, 0, 0x00, 2, 2, 4, 0), // bicF32
  _V(X86InstId.kAndnpd, 0, SSEExt.kIntrin, X86InstId.kVandnpd, AVXExt.kIntrin,
      0, 0, 1, 0, 0x00, 3, 3, 8, 0), // bicF64
  _V(X86InstId.kAddss, 2, SSEExt.kSSE2, X86InstId.kVaddss, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 0, 2, 4, 0), // addF32S
  _V(X86InstId.kAddsd, 2, SSEExt.kSSE2, X86InstId.kVaddsd, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 1, 3, 8, 0), // addF64S
  _V(X86InstId.kAddps, 2, SSEExt.kSSE2, X86InstId.kVaddps, AVXExt.kAVX, 1, 0, 0,
      0, 0x00, 2, 2, 4, 0), // addF32
  _V(X86InstId.kAddpd, 2, SSEExt.kSSE2, X86InstId.kVaddpd, AVXExt.kAVX, 1, 0, 0,
      0, 0x00, 3, 3, 8, 0), // addF64
  _V(X86InstId.kSubss, 2, SSEExt.kSSE2, X86InstId.kVsubss, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 0, 2, 4, 0), // subF32S
  _V(X86InstId.kSubsd, 2, SSEExt.kSSE2, X86InstId.kVsubsd, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 1, 3, 8, 0), // subF64S
  _V(X86InstId.kSubps, 2, SSEExt.kSSE2, X86InstId.kVsubps, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 2, 2, 4, 0), // subF32
  _V(X86InstId.kSubpd, 2, SSEExt.kSSE2, X86InstId.kVsubpd, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 3, 3, 8, 0), // subF64
  _V(X86InstId.kMulss, 2, SSEExt.kSSE2, X86InstId.kVmulss, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 0, 2, 4, 0), // mulF32S
  _V(X86InstId.kMulsd, 2, SSEExt.kSSE2, X86InstId.kVmulsd, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 1, 3, 8, 0), // mulF64S
  _V(X86InstId.kMulps, 2, SSEExt.kSSE2, X86InstId.kVmulps, AVXExt.kAVX, 1, 0, 0,
      0, 0x00, 2, 2, 4, 0), // mulF32
  _V(X86InstId.kMulpd, 2, SSEExt.kSSE2, X86InstId.kVmulpd, AVXExt.kAVX, 1, 0, 0,
      0, 0x00, 3, 3, 8, 0), // mulF64
  _V(X86InstId.kDivss, 2, SSEExt.kSSE2, X86InstId.kVdivss, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 0, 2, 4, 0), // divF32S
  _V(X86InstId.kDivsd, 2, SSEExt.kSSE2, X86InstId.kVdivsd, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 1, 3, 8, 0), // divF64S
  _V(X86InstId.kDivps, 2, SSEExt.kSSE2, X86InstId.kVdivps, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 2, 2, 4, 0), // divF32
  _V(X86InstId.kDivpd, 2, SSEExt.kSSE2, X86InstId.kVdivpd, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 3, 3, 8, 0), // divF64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 0, 2, 4,
      0), // modF32S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 1, 3, 8,
      0), // modF64S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 2, 2, 4,
      0), // modF32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 3, 8,
      0), // modF64
  _V(X86InstId.kMinss, 2, SSEExt.kSSE2, X86InstId.kVminss, AVXExt.kAVX, 0, 0, 3,
      0, 0x00, 0, 2, 4, 0), // minF32S
  _V(X86InstId.kMinsd, 2, SSEExt.kSSE2, X86InstId.kVminsd, AVXExt.kAVX, 0, 0, 3,
      0, 0x00, 1, 3, 8, 0), // minF64S
  _V(X86InstId.kMinps, 2, SSEExt.kSSE2, X86InstId.kVminps, AVXExt.kAVX, 0, 0, 3,
      0, 0x00, 2, 2, 4, 0), // minF32
  _V(X86InstId.kMinpd, 2, SSEExt.kSSE2, X86InstId.kVminpd, AVXExt.kAVX, 0, 0, 3,
      0, 0x00, 3, 3, 8, 0), // minF64
  _V(X86InstId.kMaxss, 2, SSEExt.kSSE2, X86InstId.kVmaxss, AVXExt.kAVX, 0, 0, 3,
      0, 0x00, 0, 2, 4, 0), // maxF32S
  _V(X86InstId.kMaxsd, 2, SSEExt.kSSE2, X86InstId.kVmaxsd, AVXExt.kAVX, 0, 0, 3,
      0, 0x00, 1, 3, 8, 0), // maxF64S
  _V(X86InstId.kMaxps, 2, SSEExt.kSSE2, X86InstId.kVmaxps, AVXExt.kAVX, 0, 0, 3,
      0, 0x00, 2, 2, 4, 0), // maxF32
  _V(X86InstId.kMaxpd, 2, SSEExt.kSSE2, X86InstId.kVmaxpd, AVXExt.kAVX, 0, 0, 3,
      0, 0x00, 3, 3, 8, 0), // maxF64
  _V(X86InstId.kCmpss, 2, SSEExt.kIntrin, X86InstId.kVcmpss, AVXExt.kAVX, 1, 1,
      0, 1, 0x00, 0, 2, 4, 0), // cmpEqF32S
  _V(X86InstId.kCmpsd, 2, SSEExt.kIntrin, X86InstId.kVcmpsd, AVXExt.kAVX, 1, 1,
      0, 1, 0x00, 1, 3, 8, 0), // cmpEqF64S
  _V(X86InstId.kCmpps, 2, SSEExt.kIntrin, X86InstId.kVcmpps, AVXExt.kAVX, 1, 1,
      0, 1, 0x00, 2, 2, 4, 0), // cmpEqF32
  _V(X86InstId.kCmppd, 2, SSEExt.kIntrin, X86InstId.kVcmppd, AVXExt.kAVX, 1, 1,
      0, 1, 0x00, 3, 3, 8, 0), // cmpEqF64
  _V(X86InstId.kCmpss, 2, SSEExt.kIntrin, X86InstId.kVcmpss, AVXExt.kAVX, 1, 1,
      0, 1, 0x04, 0, 2, 4, 0), // cmpNeF32S
  _V(X86InstId.kCmpsd, 2, SSEExt.kIntrin, X86InstId.kVcmpsd, AVXExt.kAVX, 1, 1,
      0, 1, 0x04, 1, 3, 8, 0), // cmpNeF64S
  _V(X86InstId.kCmpps, 2, SSEExt.kIntrin, X86InstId.kVcmpps, AVXExt.kAVX, 1, 1,
      0, 1, 0x04, 2, 2, 4, 0), // cmpNeF32
  _V(X86InstId.kCmppd, 2, SSEExt.kIntrin, X86InstId.kVcmppd, AVXExt.kAVX, 1, 1,
      0, 1, 0x04, 3, 3, 8, 0), // cmpNeF64
  _V(X86InstId.kCmpss, 2, SSEExt.kIntrin, X86InstId.kVcmpss, AVXExt.kAVX, 0, 1,
      0, 1, 0x1E, 0, 2, 4, 0), // cmpGtF32S
  _V(X86InstId.kCmpsd, 2, SSEExt.kIntrin, X86InstId.kVcmpsd, AVXExt.kAVX, 0, 1,
      0, 1, 0x1E, 1, 3, 8, 0), // cmpGtF64S
  _V(X86InstId.kCmpps, 2, SSEExt.kIntrin, X86InstId.kVcmpps, AVXExt.kAVX, 0, 1,
      0, 1, 0x1E, 2, 2, 4, 0), // cmpGtF32
  _V(X86InstId.kCmppd, 2, SSEExt.kIntrin, X86InstId.kVcmppd, AVXExt.kAVX, 0, 1,
      0, 1, 0x1E, 3, 3, 8, 0), // cmpGtF64
  _V(X86InstId.kCmpss, 2, SSEExt.kIntrin, X86InstId.kVcmpss, AVXExt.kAVX, 0, 1,
      0, 1, 0x1D, 0, 2, 4, 0), // cmpGeF32S
  _V(X86InstId.kCmpsd, 2, SSEExt.kIntrin, X86InstId.kVcmpsd, AVXExt.kAVX, 0, 1,
      0, 1, 0x1D, 1, 3, 8, 0), // cmpGeF64S
  _V(X86InstId.kCmpps, 2, SSEExt.kIntrin, X86InstId.kVcmpps, AVXExt.kAVX, 0, 1,
      0, 1, 0x1D, 2, 2, 4, 0), // cmpGeF32
  _V(X86InstId.kCmppd, 2, SSEExt.kIntrin, X86InstId.kVcmppd, AVXExt.kAVX, 0, 1,
      0, 1, 0x1D, 3, 3, 8, 0), // cmpGeF64
  _V(X86InstId.kCmpss, 2, SSEExt.kIntrin, X86InstId.kVcmpss, AVXExt.kAVX, 0, 1,
      0, 1, 0x11, 0, 2, 4, 0), // cmpLtF32S
  _V(X86InstId.kCmpsd, 2, SSEExt.kIntrin, X86InstId.kVcmpsd, AVXExt.kAVX, 0, 1,
      0, 1, 0x11, 1, 3, 8, 0), // cmpLtF64S
  _V(X86InstId.kCmpps, 2, SSEExt.kIntrin, X86InstId.kVcmpps, AVXExt.kAVX, 0, 1,
      0, 1, 0x11, 2, 2, 4, 0), // cmpLtF32
  _V(X86InstId.kCmppd, 2, SSEExt.kIntrin, X86InstId.kVcmppd, AVXExt.kAVX, 0, 1,
      0, 1, 0x11, 3, 3, 8, 0), // cmpLtF64
  _V(X86InstId.kCmpss, 2, SSEExt.kIntrin, X86InstId.kVcmpss, AVXExt.kAVX, 0, 1,
      0, 1, 0x12, 0, 2, 4, 0), // cmpLeF32S
  _V(X86InstId.kCmpsd, 2, SSEExt.kIntrin, X86InstId.kVcmpsd, AVXExt.kAVX, 0, 1,
      0, 1, 0x12, 1, 3, 8, 0), // cmpLeF64S
  _V(X86InstId.kCmpps, 2, SSEExt.kIntrin, X86InstId.kVcmpps, AVXExt.kAVX, 0, 1,
      0, 1, 0x12, 2, 2, 4, 0), // cmpLeF32
  _V(X86InstId.kCmppd, 2, SSEExt.kIntrin, X86InstId.kVcmppd, AVXExt.kAVX, 0, 1,
      0, 1, 0x12, 3, 3, 8, 0), // cmpLeF64
  _V(X86InstId.kCmpss, 2, SSEExt.kIntrin, X86InstId.kVcmpss, AVXExt.kAVX, 1, 1,
      0, 1, 0x07, 0, 2, 4, 0), // cmpOrdF32S
  _V(X86InstId.kCmpsd, 2, SSEExt.kIntrin, X86InstId.kVcmpsd, AVXExt.kAVX, 1, 1,
      0, 1, 0x07, 1, 3, 8, 0), // cmpOrdF64S
  _V(X86InstId.kCmpps, 2, SSEExt.kIntrin, X86InstId.kVcmpps, AVXExt.kAVX, 1, 1,
      0, 1, 0x07, 2, 2, 4, 0), // cmpOrdF32
  _V(X86InstId.kCmppd, 2, SSEExt.kIntrin, X86InstId.kVcmppd, AVXExt.kAVX, 1, 1,
      0, 1, 0x07, 3, 3, 8, 0), // cmpOrdF64
  _V(X86InstId.kCmpss, 2, SSEExt.kIntrin, X86InstId.kVcmpss, AVXExt.kAVX, 1, 1,
      0, 1, 0x03, 0, 2, 4, 0), // cmpUnordF32S
  _V(X86InstId.kCmpsd, 2, SSEExt.kIntrin, X86InstId.kVcmpsd, AVXExt.kAVX, 1, 1,
      0, 1, 0x03, 1, 3, 8, 0), // cmpUnordF64S
  _V(X86InstId.kCmpps, 2, SSEExt.kIntrin, X86InstId.kVcmpps, AVXExt.kAVX, 1, 1,
      0, 1, 0x03, 2, 2, 4, 0), // cmpUnordF32
  _V(X86InstId.kCmppd, 2, SSEExt.kIntrin, X86InstId.kVcmppd, AVXExt.kAVX, 1, 1,
      0, 1, 0x03, 3, 3, 8, 0), // cmpUnordF64
  _V(X86InstId.kHaddpd, 2, SSEExt.kSSE3, X86InstId.kVhaddpd, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 3, 3, 0, 0), // hAddF64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0,
      0), // combineLoHiU64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0,
      0), // combineLoHiF64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 3, 0, 0x00, 4, 3, 0,
      0), // combineHiLoU64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 3, 0, 0x00, 4, 3, 0,
      0), // combineHiLoF64
  _V(X86InstId.kPunpcklbw, 2, SSEExt.kSSE2, X86InstId.kVpunpcklbw, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 0, 0, 0), // interleaveLoU8
  _V(X86InstId.kPunpckhbw, 2, SSEExt.kSSE2, X86InstId.kVpunpckhbw, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 0, 0, 1), // interleaveHiU8
  _V(X86InstId.kPunpcklwd, 2, SSEExt.kSSE2, X86InstId.kVpunpcklwd, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 1, 0, 0), // interleaveLoU16
  _V(X86InstId.kPunpckhwd, 2, SSEExt.kSSE2, X86InstId.kVpunpckhwd, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 1, 0, 1), // interleaveHiU16
  _V(X86InstId.kPunpckldq, 2, SSEExt.kSSE2, X86InstId.kVpunpckldq, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 2, 0, 0), // interleaveLoU32
  _V(X86InstId.kPunpckhdq, 2, SSEExt.kSSE2, X86InstId.kVpunpckhdq, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 2, 0, 1), // interleaveHiU32
  _V(X86InstId.kPunpcklqdq, 2, SSEExt.kSSE2, X86InstId.kVpunpcklqdq,
      AVXExt.kAVX, 0, 0, 0, 0, 0x00, 4, 3, 0, 0), // interleaveLoU64
  _V(X86InstId.kPunpckhqdq, 2, SSEExt.kSSE2, X86InstId.kVpunpckhqdq,
      AVXExt.kAVX, 0, 0, 0, 0, 0x00, 4, 3, 0, 1), // interleaveHiU64
  _V(X86InstId.kUnpcklps, 2, SSEExt.kSSE2, X86InstId.kVunpcklps, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 2, 0, 0), // interleaveLoF32
  _V(X86InstId.kUnpckhps, 2, SSEExt.kSSE2, X86InstId.kVunpckhps, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 2, 0, 1), // interleaveHiF32
  _V(X86InstId.kUnpcklpd, 2, SSEExt.kSSE2, X86InstId.kVunpcklpd, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 3, 0, 0), // interleaveLoF64
  _V(X86InstId.kUnpckhpd, 2, SSEExt.kSSE2, X86InstId.kVunpckhpd, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 3, 0, 1), // interleaveHiF64
  _V(X86InstId.kPacksswb, 2, SSEExt.kSSE2, X86InstId.kVpacksswb, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 1, 0, 0), // packsI16I8
  _V(X86InstId.kPackuswb, 2, SSEExt.kSSE2, X86InstId.kVpackuswb, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 1, 0, 0), // packsI16U8
  _V(X86InstId.kPackssdw, 2, SSEExt.kSSE2, X86InstId.kVpackssdw, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 2, 0, 0), // packsI32I16
  _V(X86InstId.kPackusdw, 2, SSEExt.kSSE4_1, X86InstId.kVpackusdw, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 2, 0, 0), // packsI32U16
  _V(X86InstId.kPshufb, 2, SSEExt.kSSSE3, X86InstId.kVpshufb, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 4, 0, 0, 0), // swizzlevU8
];
