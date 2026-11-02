/// x86 lowering tables for UniCompiler.
///
/// Ported from `opcode_info_2v`, `opcode_info_2vi`, `opcode_info_3v`,
/// `opcode_info_3vi`, `opcode_info_4v`, `opcode_info_2vs`, `opcode_info_2vm` and
/// `opcode_info_2mv` in asmjit's
/// `ujit/unicompiler_x86.cpp`; one entry per [UniOpVV] / [UniOpVVI] /
/// [UniOpVVV] / [UniOpVVVI] / [UniOpVVVV] value
/// shared by all architectures, in enum order (upstream's x86-only
/// `kPermute*` 3v entries require AVX-512 and are not part of the Dart
/// enum).

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

/// `opcode_info_2vs`: one entry per [UniOpVR] value.
const List<X86UniOpVInfo> kX86OpcodeInfo2vs = [
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 0, 0,
      0), // mov
  _V(X86InstId.kMovd, 0, SSEExt.kSSE2, X86InstId.kVmovd, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 4, 2, 0, 0), // movU32
  _V(X86InstId.kMovq, 0, SSEExt.kSSE2, X86InstId.kVmovq, AVXExt.kAVX, 0, 0, 0,
      0, 0x00, 4, 3, 0, 0), // movU64
  _V(X86InstId.kPinsrb, 0, SSEExt.kSSE4_1, X86InstId.kVpinsrb, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 0, 0, 0), // insertU8
  _V(X86InstId.kPinsrw, 0, SSEExt.kSSE2, X86InstId.kVpinsrw, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 4, 1, 0, 0), // insertU16
  _V(X86InstId.kPinsrd, 0, SSEExt.kSSE4_1, X86InstId.kVpinsrd, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 2, 0, 0), // insertU32
  _V(X86InstId.kPinsrq, 0, SSEExt.kSSE4_1, X86InstId.kVpinsrq, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 3, 0, 0), // insertU64
  _V(X86InstId.kPextrb, 0, SSEExt.kSSE4_1, X86InstId.kVpextrb, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 0, 0, 0), // extractU8
  _V(X86InstId.kPextrw, 0, SSEExt.kSSE2, X86InstId.kVpextrw, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 4, 1, 0, 0), // extractU16
  _V(X86InstId.kPextrd, 0, SSEExt.kSSE4_1, X86InstId.kVpextrd, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 2, 0, 0), // extractU32
  _V(X86InstId.kPextrq, 0, SSEExt.kSSE4_1, X86InstId.kVpextrq, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 3, 0, 0), // extractU64
  _V(X86InstId.kCvtsi2ss, 0, SSEExt.kSSE2, X86InstId.kVcvtsi2ss, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 2, 0, 0), // cvtIntToF32
  _V(X86InstId.kCvtsi2sd, 0, SSEExt.kSSE2, X86InstId.kVcvtsi2sd, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 3, 0, 0), // cvtIntToF64
  _V(X86InstId.kCvttss2si, 0, SSEExt.kSSE2, X86InstId.kVcvttss2si, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 2, 0, 0), // cvtTruncF32ToInt
  _V(X86InstId.kCvtss2si, 0, SSEExt.kSSE2, X86InstId.kVcvtss2si, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 2, 0, 0), // cvtRoundF32ToInt
  _V(X86InstId.kCvttsd2si, 0, SSEExt.kSSE2, X86InstId.kVcvttsd2si, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 4, 3, 0, 0), // cvtTruncF64ToInt
  _V(X86InstId.kCvtsd2si, 0, SSEExt.kSSE2, X86InstId.kVcvtsd2si, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 4, 3, 0, 0), // cvtRoundF64ToInt
];

const List<X86UniOpVInfo> kX86OpcodeInfo2vi = [
  _V(X86InstId.kPsllw, 2, SSEExt.kSSE2, X86InstId.kVpsllw, AVXExt.kAVX512, 0, 0,
      0, 0, 0x00, 4, 1, 0, 0), // sllU16
  _V(X86InstId.kPslld, 2, SSEExt.kSSE2, X86InstId.kVpslld, AVXExt.kAVX512, 0, 0,
      0, 0, 0x00, 4, 2, 4, 0), // sllU32
  _V(X86InstId.kPsllq, 2, SSEExt.kSSE2, X86InstId.kVpsllq, AVXExt.kAVX512, 0, 0,
      0, 0, 0x00, 4, 3, 8, 0), // sllU64
  _V(X86InstId.kPsrlw, 2, SSEExt.kSSE2, X86InstId.kVpsrlw, AVXExt.kAVX512, 0, 0,
      0, 0, 0x00, 4, 1, 0, 0), // srlU16
  _V(X86InstId.kPsrld, 2, SSEExt.kSSE2, X86InstId.kVpsrld, AVXExt.kAVX512, 0, 0,
      0, 0, 0x00, 4, 2, 4, 0), // srlU32
  _V(X86InstId.kPsrlq, 2, SSEExt.kSSE2, X86InstId.kVpsrlq, AVXExt.kAVX512, 0, 0,
      0, 0, 0x00, 4, 3, 8, 0), // srlU64
  _V(X86InstId.kPsraw, 2, SSEExt.kSSE2, X86InstId.kVpsraw, AVXExt.kAVX512, 0, 0,
      0, 0, 0x00, 4, 1, 0, 0), // sraI16
  _V(X86InstId.kPsrad, 2, SSEExt.kSSE2, X86InstId.kVpsrad, AVXExt.kAVX512, 0, 0,
      0, 0, 0x00, 4, 2, 4, 0), // sraI32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpsraq, AVXExt.kAVX512, 0, 0, 0, 0, 0x00,
      4, 3, 8, 0), // sraI64
  _V(X86InstId.kPslldq, 2, SSEExt.kSSE2, X86InstId.kVpslldq, AVXExt.kAVX512, 0,
      0, 0, 0, 0x00, 4, 0, 0, 0), // sllbU128
  _V(X86InstId.kPsrldq, 2, SSEExt.kSSE2, X86InstId.kVpsrldq, AVXExt.kAVX512, 0,
      0, 0, 0, 0x00, 4, 0, 0, 0), // srlbU128
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 1, 0,
      0), // swizzleU16x4
  _V(X86InstId.kPshuflw, 3, SSEExt.kIntrin, X86InstId.kVpshuflw, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 1, 0, 0), // swizzleLoU16x4
  _V(X86InstId.kPshufhw, 3, SSEExt.kIntrin, X86InstId.kVpshufhw, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 1, 0, 0), // swizzleHiU16x4
  _V(X86InstId.kPshufd, 3, SSEExt.kIntrin, X86InstId.kVpshufd, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 2, 0, 0), // swizzleU32x4
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0,
      0), // swizzleU64x2
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 2, 2, 0,
      0), // swizzleF32x4
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 3, 0,
      0), // swizzleF64x2
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpermq, AVXExt.kIntrin, 0, 0, 0, 0, 0x00,
      4, 3, 0, 0), // swizzleU64x4
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpermq, AVXExt.kIntrin, 0, 0, 0, 0, 0x00,
      3, 3, 0, 0), // swizzleF64x4
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0,
      0), // extractV128I32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0,
      0), // extractV128I64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 2, 3, 0,
      0), // extractV128F32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 3, 0,
      0), // extractV128F64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0,
      0), // extractV256I32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0,
      0), // extractV256I64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 2, 3, 0,
      0), // extractV256F32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 3, 0,
      0), // extractV256F64
];

const List<X86UniOpVInfo> kX86OpcodeInfo2v = [
  _V(X86InstId.kMovaps, 0, SSEExt.kIntrin, X86InstId.kVmovaps, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 0, 0, 0), // mov
  _V(X86InstId.kMovq, 0, SSEExt.kIntrin, X86InstId.kVmovq, AVXExt.kIntrin, 0, 0,
      0, 0, 0x00, 4, 3, 0, 0), // movU64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpbroadcastb, AVXExt.kIntrin, 0, 0, 0, 0,
      0x01, 4, 0, 0, 0), // broadcastU8Z
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpbroadcastw, AVXExt.kIntrin, 0, 0, 0, 0,
      0x01, 4, 1, 0, 0), // broadcastU16Z
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpbroadcastb, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // broadcastU8
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpbroadcastw, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 1, 0, 0), // broadcastU16
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpbroadcastd, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 2, 0, 0), // broadcastU32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpbroadcastq, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 3, 0, 0), // broadcastU64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcastss, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 2, 0, 0), // broadcastF32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcastsd, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 3, 0, 0), // broadcastF64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcasti32x4, AVXExt.kIntrin, 0, 0, 0,
      0, 0x00, 4, 2, 0, 0), // broadcastV128U32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcasti64x2, AVXExt.kIntrin, 0, 0, 0,
      0, 0x00, 4, 3, 0, 0), // broadcastV128U64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcastf32x4, AVXExt.kIntrin, 0, 0, 0,
      0, 0x00, 4, 2, 0, 0), // broadcastV128F32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcastf64x2, AVXExt.kIntrin, 0, 0, 0,
      0, 0x00, 4, 3, 0, 0), // broadcastV128F64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcasti32x8, AVXExt.kIntrin, 0, 0, 0,
      0, 0x00, 4, 2, 0, 0), // broadcastV256U32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcasti64x4, AVXExt.kIntrin, 0, 0, 0,
      0, 0x00, 4, 3, 0, 0), // broadcastV256U64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcasti32x8, AVXExt.kIntrin, 0, 0, 0,
      0, 0x00, 4, 2, 0, 0), // broadcastV256F32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVbroadcasti64x4, AVXExt.kIntrin, 0, 0, 0,
      0, 0x00, 4, 3, 0, 0), // broadcastV256F64
  _V(X86InstId.kPabsb, 2, SSEExt.kSSSE3, X86InstId.kVpabsb, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 4, 0, 0, 0), // absI8
  _V(X86InstId.kPabsw, 2, SSEExt.kSSSE3, X86InstId.kVpabsw, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 4, 1, 0, 0), // absI16
  _V(X86InstId.kPabsd, 2, SSEExt.kSSSE3, X86InstId.kVpabsd, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 4, 2, 4, 0), // absI32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVpabsq, AVXExt.kAVX512, 0, 0, 0, 0, 0x00,
      4, 3, 8, 0), // absI64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 4,
      0), // notU32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 8,
      0), // notU64
  _V(X86InstId.kPmovsxbw, 0, SSEExt.kIntrin, X86InstId.kVpmovsxbw,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 1, 0, 0), // cvtI8LoToI16
  _V(X86InstId.kPmovsxbw, 0, SSEExt.kIntrin, X86InstId.kVpmovsxbw,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 1, 0, 0), // cvtI8HiToI16
  _V(X86InstId.kPmovzxbw, 0, SSEExt.kIntrin, X86InstId.kVpmovzxbw,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 1, 0, 0), // cvtU8LoToU16
  _V(X86InstId.kPmovzxbw, 0, SSEExt.kIntrin, X86InstId.kVpmovzxbw,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 1, 0, 0), // cvtU8HiToU16
  _V(X86InstId.kPmovsxbd, 0, SSEExt.kIntrin, X86InstId.kVpmovsxbd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 0, 0), // cvtI8ToI32
  _V(X86InstId.kPmovzxbd, 0, SSEExt.kIntrin, X86InstId.kVpmovzxbd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 0, 0), // cvtU8ToU32
  _V(X86InstId.kPmovsxwd, 0, SSEExt.kIntrin, X86InstId.kVpmovsxwd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 0, 0), // cvtI16LoToI32
  _V(X86InstId.kPmovsxwd, 0, SSEExt.kIntrin, X86InstId.kVpmovsxwd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 0, 0), // cvtI16HiToI32
  _V(X86InstId.kPmovzxwd, 0, SSEExt.kIntrin, X86InstId.kVpmovzxwd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 0, 0), // cvtU16LoToU32
  _V(X86InstId.kPmovzxwd, 0, SSEExt.kIntrin, X86InstId.kVpmovzxwd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 0, 0), // cvtU16HiToU32
  _V(X86InstId.kPmovsxdq, 0, SSEExt.kIntrin, X86InstId.kVpmovsxdq,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0, 0), // cvtI32LoToI64
  _V(X86InstId.kPmovsxdq, 0, SSEExt.kIntrin, X86InstId.kVpmovsxdq,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0, 0), // cvtI32HiToI64
  _V(X86InstId.kPmovzxdq, 0, SSEExt.kIntrin, X86InstId.kVpmovzxdq,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0, 0), // cvtU32LoToU64
  _V(X86InstId.kPmovzxdq, 0, SSEExt.kIntrin, X86InstId.kVpmovzxdq,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 0, 0), // cvtU32HiToU64
  _V(X86InstId.kAndps, 0, SSEExt.kIntrin, X86InstId.kVandps, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 0, 2, 4, 0), // absF32S
  _V(X86InstId.kAndpd, 0, SSEExt.kIntrin, X86InstId.kVandpd, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 1, 3, 8, 0), // absF64S
  _V(X86InstId.kAndps, 0, SSEExt.kIntrin, X86InstId.kVandps, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 2, 2, 4, 0), // absF32
  _V(X86InstId.kAndpd, 0, SSEExt.kIntrin, X86InstId.kVandpd, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 3, 3, 8, 0), // absF64
  _V(X86InstId.kXorps, 0, SSEExt.kIntrin, X86InstId.kVxorps, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 0, 2, 4, 0), // negF32S
  _V(X86InstId.kXorpd, 0, SSEExt.kIntrin, X86InstId.kVxorpd, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 1, 3, 8, 0), // negF64S
  _V(X86InstId.kXorps, 0, SSEExt.kIntrin, X86InstId.kVxorps, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 2, 2, 4, 0), // negF32
  _V(X86InstId.kXorpd, 0, SSEExt.kIntrin, X86InstId.kVxorpd, AVXExt.kIntrin, 0,
      0, 0, 0, 0x00, 3, 3, 8, 0), // negF64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 4,
      0), // notF32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 8,
      0), // notF64
  _V(X86InstId.kRoundss, 2, SSEExt.kIntrin, X86InstId.kVroundss, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0B, 0, 2, 4, 0), // truncF32S
  _V(X86InstId.kRoundsd, 2, SSEExt.kIntrin, X86InstId.kVroundsd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0B, 1, 3, 8, 0), // truncF64S
  _V(X86InstId.kRoundps, 2, SSEExt.kIntrin, X86InstId.kVroundps, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0B, 2, 2, 4, 0), // truncF32
  _V(X86InstId.kRoundpd, 2, SSEExt.kIntrin, X86InstId.kVroundpd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0B, 3, 3, 8, 0), // truncF64
  _V(X86InstId.kRoundss, 2, SSEExt.kIntrin, X86InstId.kVroundss, AVXExt.kIntrin,
      0, 0, 0, 1, 0x09, 0, 2, 4, 0), // floorF32S
  _V(X86InstId.kRoundsd, 2, SSEExt.kIntrin, X86InstId.kVroundsd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x09, 1, 3, 8, 0), // floorF64S
  _V(X86InstId.kRoundps, 2, SSEExt.kIntrin, X86InstId.kVroundps, AVXExt.kIntrin,
      0, 0, 0, 1, 0x09, 2, 2, 4, 0), // floorF32
  _V(X86InstId.kRoundpd, 2, SSEExt.kIntrin, X86InstId.kVroundpd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x09, 3, 3, 8, 0), // floorF64
  _V(X86InstId.kRoundss, 2, SSEExt.kIntrin, X86InstId.kVroundss, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0A, 0, 2, 4, 0), // ceilF32S
  _V(X86InstId.kRoundsd, 2, SSEExt.kIntrin, X86InstId.kVroundsd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0A, 1, 3, 8, 0), // ceilF64S
  _V(X86InstId.kRoundps, 2, SSEExt.kIntrin, X86InstId.kVroundps, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0A, 2, 2, 4, 0), // ceilF32
  _V(X86InstId.kRoundpd, 2, SSEExt.kIntrin, X86InstId.kVroundpd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0A, 3, 3, 8, 0), // ceilF64
  _V(X86InstId.kRoundss, 2, SSEExt.kIntrin, X86InstId.kVroundss, AVXExt.kIntrin,
      0, 0, 0, 1, 0x08, 0, 2, 4, 0), // roundEvenF32S
  _V(X86InstId.kRoundsd, 2, SSEExt.kIntrin, X86InstId.kVroundsd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x08, 1, 3, 8, 0), // roundEvenF64S
  _V(X86InstId.kRoundps, 2, SSEExt.kIntrin, X86InstId.kVroundps, AVXExt.kIntrin,
      0, 0, 0, 1, 0x08, 2, 2, 4, 0), // roundEvenF32
  _V(X86InstId.kRoundpd, 2, SSEExt.kIntrin, X86InstId.kVroundpd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x08, 3, 3, 8, 0), // roundEvenF64
  _V(X86InstId.kRoundss, 2, SSEExt.kIntrin, X86InstId.kVroundss, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0B, 0, 2, 4, 0), // roundHalfAwayF32S
  _V(X86InstId.kRoundsd, 2, SSEExt.kIntrin, X86InstId.kVroundsd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0B, 1, 3, 8, 0), // roundHalfAwayF64S
  _V(X86InstId.kRoundps, 2, SSEExt.kIntrin, X86InstId.kVroundps, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0B, 2, 2, 4, 0), // roundHalfAwayF32
  _V(X86InstId.kRoundpd, 2, SSEExt.kIntrin, X86InstId.kVroundpd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x0B, 3, 3, 8, 0), // roundHalfAwayF64
  _V(X86InstId.kRoundss, 2, SSEExt.kIntrin, X86InstId.kVroundss, AVXExt.kIntrin,
      0, 0, 0, 1, 0x09, 0, 2, 4, 0), // roundHalfUpF32S
  _V(X86InstId.kRoundsd, 2, SSEExt.kIntrin, X86InstId.kVroundsd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x09, 1, 3, 8, 0), // roundHalfUpF64S
  _V(X86InstId.kRoundps, 2, SSEExt.kIntrin, X86InstId.kVroundps, AVXExt.kIntrin,
      0, 0, 0, 1, 0x09, 2, 2, 4, 0), // roundHalfUpF32
  _V(X86InstId.kRoundpd, 2, SSEExt.kIntrin, X86InstId.kVroundpd, AVXExt.kIntrin,
      0, 0, 0, 1, 0x09, 3, 3, 8, 0), // roundHalfUpF64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 2, 4,
      0), // rcpF32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 8,
      0), // rcpF64
  _V(X86InstId.kSqrtss, 2, SSEExt.kIntrin, X86InstId.kVsqrtss, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 0, 2, 4, 0), // sqrtF32S
  _V(X86InstId.kSqrtsd, 2, SSEExt.kIntrin, X86InstId.kVsqrtsd, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 1, 3, 8, 0), // sqrtF64S
  _V(X86InstId.kSqrtps, 2, SSEExt.kSSE2, X86InstId.kVsqrtps, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 2, 2, 4, 0), // sqrtF32
  _V(X86InstId.kSqrtpd, 2, SSEExt.kSSE2, X86InstId.kVsqrtpd, AVXExt.kAVX, 0, 0,
      0, 0, 0x00, 3, 3, 8, 0), // sqrtF64
  _V(X86InstId.kCvtss2sd, 2, SSEExt.kIntrin, X86InstId.kVcvtss2sd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 1, 3, 0, 0), // cvtF32ToF64S
  _V(X86InstId.kCvtsd2ss, 2, SSEExt.kIntrin, X86InstId.kVcvtsd2ss,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 1, 2, 0, 0), // cvtF64ToF32S
  _V(X86InstId.kCvtdq2ps, 2, SSEExt.kSSE2, X86InstId.kVcvtdq2ps, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 2, 2, 4, 0), // cvtI32ToF32
  _V(X86InstId.kCvtps2pd, 2, SSEExt.kSSE2, X86InstId.kVcvtps2pd, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 2, 3, 4, 0), // cvtF32LoToF64
  _V(X86InstId.kCvtps2pd, 2, SSEExt.kIntrin, X86InstId.kVcvtps2pd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 2, 3, 4, 1), // cvtF32HiToF64
  _V(X86InstId.kCvtpd2ps, 2, SSEExt.kSSE2, X86InstId.kVcvtpd2ps, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 3, 2, 4, 0), // cvtF64ToF32Lo
  _V(X86InstId.kCvtpd2ps, 2, SSEExt.kIntrin, X86InstId.kVcvtpd2ps,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 2, 4, 1), // cvtF64ToF32Hi
  _V(X86InstId.kCvtdq2pd, 2, SSEExt.kSSE2, X86InstId.kVcvtdq2pd, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 3, 4, 0), // cvtI32LoToF64
  _V(X86InstId.kCvtdq2pd, 2, SSEExt.kIntrin, X86InstId.kVcvtdq2pd,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 3, 4, 1), // cvtI32HiToF64
  _V(X86InstId.kCvttps2dq, 2, SSEExt.kSSE2, X86InstId.kVcvttps2dq, AVXExt.kAVX,
      0, 0, 0, 0, 0x00, 2, 2, 4, 0), // cvtTruncF32ToI32
  _V(X86InstId.kCvttpd2dq, 2, SSEExt.kSSE2, X86InstId.kVcvttpd2dq,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 2, 4, 0), // cvtTruncF64ToI32Lo
  _V(X86InstId.kCvttpd2dq, 2, SSEExt.kIntrin, X86InstId.kVcvttpd2dq,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 2, 4, 1), // cvtTruncF64ToI32Hi
  _V(X86InstId.kCvtps2dq, 2, SSEExt.kSSE2, X86InstId.kVcvtps2dq, AVXExt.kAVX, 0,
      0, 0, 0, 0x00, 2, 2, 4, 0), // cvtRoundF32ToI32
  _V(X86InstId.kCvtpd2dq, 2, SSEExt.kSSE2, X86InstId.kVcvtpd2dq, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 3, 2, 4, 0), // cvtRoundF64ToI32Lo
  _V(X86InstId.kCvtpd2dq, 2, SSEExt.kIntrin, X86InstId.kVcvtpd2dq,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 2, 4, 1), // cvtRoundF64ToI32Hi
];

const List<X86UniOpVInfo> kX86OpcodeInfo3vi = [
  _V(X86InstId.kPalignr, 2, SSEExt.kIntrin, X86InstId.kVpalignr, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 0, 0, 0), // alignrU128
  _V(X86InstId.kShufps, 2, SSEExt.kIntrin, X86InstId.kVshufps, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 2, 4, 0), // interleaveShuffleU32x4
  _V(X86InstId.kShufpd, 2, SSEExt.kIntrin, X86InstId.kVshufpd, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 3, 8, 0), // interleaveShuffleU64x2
  _V(X86InstId.kShufps, 2, SSEExt.kIntrin, X86InstId.kVshufps, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 2, 4, 0), // interleaveShuffleF32x4
  _V(X86InstId.kShufpd, 2, SSEExt.kIntrin, X86InstId.kVshufpd, AVXExt.kIntrin,
      0, 0, 0, 0, 0x00, 4, 3, 8, 0), // interleaveShuffleF64x2
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVinserti32x4, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // insertV128U32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVinserti64x2, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // insertV128F32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVinsertf32x4, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // insertV128U64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVinsertf64x2, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // insertV128F64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVinserti32x8, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // insertV256U32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVinsertf32x8, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // insertV256F32
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVinserti64x4, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // insertV256U64
  _V(-1, 0, SSEExt.kIntrin, X86InstId.kVinsertf64x4, AVXExt.kIntrin, 0, 0, 0, 0,
      0x00, 4, 0, 0, 0), // insertV256F64
];

const List<X86UniOpVInfo> kX86OpcodeInfo4v = [
  _V(X86InstId.kPblendvb, 0, SSEExt.kIntrin, X86InstId.kVpblendvb,
      AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 4, 0, 0, 0), // blendvU8
  _V(X86InstId.kPmullw, 0, SSEExt.kIntrin, X86InstId.kVpmullw, AVXExt.kIntrin,
      1, 0, 0, 0, 0x00, 4, 1, 0, 0), // mAddU16
  _V(X86InstId.kPmulld, 0, SSEExt.kIntrin, X86InstId.kVpmulld, AVXExt.kIntrin,
      1, 0, 0, 0, 0x00, 4, 2, 4, 0), // mAddU32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 0, 2, 4,
      0), // mAddF32S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 1, 3, 8,
      0), // mAddF64S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 2, 2, 4,
      0), // mAddF32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x00, 3, 3, 8,
      0), // mAddF64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x01, 0, 2, 4,
      0), // mSubF32S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x01, 1, 3, 8,
      0), // mSubF64S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x01, 2, 2, 4,
      0), // mSubF32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x01, 3, 3, 8,
      0), // mSubF64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x02, 0, 2, 4,
      0), // nmAddF32S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x02, 1, 3, 8,
      0), // nmAddF64S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x02, 2, 2, 4,
      0), // nmAddF32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x02, 3, 3, 8,
      0), // nmAddF64
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x03, 0, 2, 4,
      0), // nmSubF32S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x03, 1, 3, 8,
      0), // nmSubF64S
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x03, 2, 2, 4,
      0), // nmSubF32
  _V(-1, 0, SSEExt.kIntrin, -1, AVXExt.kIntrin, 0, 0, 0, 0, 0x03, 3, 3, 8,
      0), // nmSubF64
];

/// `UniOpVMInfo` (`opcode_info_2vm` / `opcode_info_2mv`) of the x86 backend.
class X86UniOpVMInfo {
  final int sseInstId;
  final int avxInstId;

  /// `WideningOp` of the load conversions (`sse_int_widen()`).
  final int cvt;
  final int memSize;
  final int memSizeShift;

  const X86UniOpVMInfo(this.sseInstId, this.avxInstId, this.cvt, this.memSize,
      this.memSizeShift);
}

typedef _VM = X86UniOpVMInfo;

const List<X86UniOpVMInfo> kX86OpcodeInfo2vm = [
  _VM(-1, -1, 0, 1, 0), // load8
  _VM(-1, X86InstId.kVmovsh, 0, 2, 0), // load16U16
  _VM(X86InstId.kMovd, X86InstId.kVmovd, 0, 4, 0), // load32U32
  _VM(X86InstId.kMovss, X86InstId.kVmovss, 0, 4, 0), // load32F32
  _VM(X86InstId.kMovq, X86InstId.kVmovq, 0, 8, 0), // load64U32
  _VM(X86InstId.kMovq, X86InstId.kVmovq, 0, 8, 0), // load64U64
  _VM(X86InstId.kMovq, X86InstId.kVmovq, 0, 8, 0), // load64F32
  _VM(X86InstId.kMovsd, X86InstId.kVmovsd, 0, 8, 0), // load64F64
  _VM(-1, -1, 0, 16, 0), // load128U32
  _VM(-1, -1, 0, 16, 0), // load128U64
  _VM(-1, -1, 0, 16, 0), // load128F32
  _VM(-1, -1, 0, 16, 0), // load128F64
  _VM(-1, -1, 0, 32, 0), // load256U32
  _VM(-1, -1, 0, 32, 0), // load256U64
  _VM(-1, -1, 0, 32, 0), // load256F32
  _VM(-1, -1, 0, 32, 0), // load256F64
  _VM(-1, -1, 0, 64, 0), // load512U32
  _VM(-1, -1, 0, 64, 0), // load512U64
  _VM(-1, -1, 0, 64, 0), // load512F32
  _VM(-1, -1, 0, 64, 0), // load512F64
  _VM(-1, -1, 0, 0, 0), // loadNU32
  _VM(-1, -1, 0, 0, 0), // loadNU64
  _VM(-1, -1, 0, 0, 0), // loadNF32
  _VM(-1, -1, 0, 0, 0), // loadNF64
  _VM(X86InstId.kPmovzxbq, X86InstId.kVpmovzxbq, 5, 2, 3), // loadCvt16U8ToU64
  _VM(X86InstId.kPmovzxbq, X86InstId.kVpmovzxbq, 5, 4, 3), // loadCvt32U8ToU64
  _VM(X86InstId.kPmovzxbq, X86InstId.kVpmovzxbq, 5, 8, 3), // loadCvt64U8ToU64
  _VM(X86InstId.kPmovsxbw, X86InstId.kVpmovsxbw, 1, 4, 1), // loadCvt32I8ToI16
  _VM(X86InstId.kPmovzxbw, X86InstId.kVpmovzxbw, 2, 4, 1), // loadCvt32U8ToU16
  _VM(X86InstId.kPmovsxbd, X86InstId.kVpmovsxbd, 3, 4, 2), // loadCvt32I8ToI32
  _VM(X86InstId.kPmovzxbd, X86InstId.kVpmovzxbd, 4, 4, 2), // loadCvt32U8ToU32
  _VM(X86InstId.kPmovsxwd, X86InstId.kVpmovsxwd, 6, 4, 1), // loadCvt32I16ToI32
  _VM(X86InstId.kPmovzxwd, X86InstId.kVpmovzxwd, 7, 4, 1), // loadCvt32U16ToU32
  _VM(X86InstId.kPmovsxdq, X86InstId.kVpmovsxdq, 8, 4, 1), // loadCvt32I32ToI64
  _VM(X86InstId.kPmovzxdq, X86InstId.kVpmovzxdq, 9, 4, 1), // loadCvt32U32ToU64
  _VM(X86InstId.kPmovsxbw, X86InstId.kVpmovsxbw, 1, 8, 1), // loadCvt64I8ToI16
  _VM(X86InstId.kPmovzxbw, X86InstId.kVpmovzxbw, 2, 8, 1), // loadCvt64U8ToU16
  _VM(X86InstId.kPmovsxbd, X86InstId.kVpmovsxbd, 3, 8, 2), // loadCvt64I8ToI32
  _VM(X86InstId.kPmovzxbd, X86InstId.kVpmovzxbd, 4, 8, 2), // loadCvt64U8ToU32
  _VM(X86InstId.kPmovsxwd, X86InstId.kVpmovsxwd, 6, 8, 1), // loadCvt64I16ToI32
  _VM(X86InstId.kPmovzxwd, X86InstId.kVpmovzxwd, 7, 8, 1), // loadCvt64U16ToU32
  _VM(X86InstId.kPmovsxdq, X86InstId.kVpmovsxdq, 8, 8, 1), // loadCvt64I32ToI64
  _VM(X86InstId.kPmovzxdq, X86InstId.kVpmovzxdq, 9, 8, 1), // loadCvt64U32ToU64
  _VM(-1, X86InstId.kVpmovsxbw, 1, 16, 3), // loadCvt128I8ToI16
  _VM(-1, X86InstId.kVpmovzxbw, 2, 16, 3), // loadCvt128U8ToU16
  _VM(-1, X86InstId.kVpmovsxbd, 3, 16, 2), // loadCvt128I8ToI32
  _VM(-1, X86InstId.kVpmovzxbd, 4, 16, 2), // loadCvt128U8ToU32
  _VM(-1, X86InstId.kVpmovsxwd, 6, 16, 1), // loadCvt128I16ToI32
  _VM(-1, X86InstId.kVpmovzxwd, 7, 16, 1), // loadCvt128U16ToU32
  _VM(-1, X86InstId.kVpmovsxdq, 8, 16, 1), // loadCvt128I32ToI64
  _VM(-1, X86InstId.kVpmovzxdq, 9, 16, 1), // loadCvt128U32ToU64
  _VM(-1, X86InstId.kVpmovsxbw, 1, 32, 1), // loadCvt256I8ToI16
  _VM(-1, X86InstId.kVpmovzxbw, 2, 32, 1), // loadCvt256U8ToU16
  _VM(-1, X86InstId.kVpmovsxwd, 6, 32, 1), // loadCvt256I16ToI32
  _VM(-1, X86InstId.kVpmovzxwd, 7, 32, 1), // loadCvt256U16ToU32
  _VM(-1, X86InstId.kVpmovsxdq, 8, 32, 1), // loadCvt256I32ToI64
  _VM(-1, X86InstId.kVpmovzxdq, 9, 32, 1), // loadCvt256U32ToU64
  _VM(X86InstId.kPmovzxbq, X86InstId.kVpmovzxbq, 5, 0, 3), // loadCvtNU8ToU64
  _VM(X86InstId.kPmovsxbw, X86InstId.kVpmovsxbw, 1, 0, 1), // loadCvtNI8ToI16
  _VM(X86InstId.kPmovzxbw, X86InstId.kVpmovzxbw, 2, 0, 1), // loadCvtNU8ToU16
  _VM(X86InstId.kPmovsxbd, X86InstId.kVpmovsxbd, 3, 0, 2), // loadCvtNI8ToI32
  _VM(X86InstId.kPmovzxbd, X86InstId.kVpmovzxbd, 4, 0, 2), // loadCvtNU8ToU32
  _VM(X86InstId.kPmovsxwd, X86InstId.kVpmovsxwd, 6, 0, 1), // loadCvtNI16ToI32
  _VM(X86InstId.kPmovzxwd, X86InstId.kVpmovzxwd, 7, 0, 1), // loadCvtNU16ToU32
  _VM(X86InstId.kPmovsxdq, X86InstId.kVpmovsxdq, 8, 0, 1), // loadCvtNI32ToI64
  _VM(X86InstId.kPmovzxdq, X86InstId.kVpmovzxdq, 9, 0, 1), // loadCvtNU32ToU64
  _VM(X86InstId.kPinsrb, X86InstId.kVpinsrb, 0, 1, 0), // loadInsertU8
  _VM(X86InstId.kPinsrw, X86InstId.kVpinsrw, 0, 2, 0), // loadInsertU16
  _VM(X86InstId.kPinsrd, X86InstId.kVpinsrd, 0, 4, 0), // loadInsertU32
  _VM(X86InstId.kPinsrq, X86InstId.kVpinsrq, 0, 8, 0), // loadInsertU64
  _VM(X86InstId.kInsertps, X86InstId.kVinsertps, 0, 4, 0), // loadInsertF32
  _VM(-1, -1, 0, 8, 0), // loadInsertF32x2
  _VM(-1, -1, 0, 8, 0), // loadInsertF64
];

const List<X86UniOpVMInfo> kX86OpcodeInfo2mv = [
  _VM(-1, -1, 0, 1, 0), // store8
  _VM(-1, -1, 0, 2, 0), // store16U16
  _VM(X86InstId.kMovd, X86InstId.kVmovd, 0, 4, 0), // store32U32
  _VM(X86InstId.kMovss, X86InstId.kVmovss, 0, 4, 0), // store32F32
  _VM(X86InstId.kMovq, X86InstId.kVmovq, 0, 8, 0), // store64U32
  _VM(X86InstId.kMovq, X86InstId.kVmovq, 0, 8, 0), // store64U64
  _VM(X86InstId.kMovq, X86InstId.kVmovq, 0, 8, 0), // store64F32
  _VM(X86InstId.kMovsd, X86InstId.kVmovsd, 0, 8, 0), // store64F64
  _VM(-1, -1, 0, 16, 0), // store128U32
  _VM(-1, -1, 0, 16, 0), // store128U64
  _VM(-1, -1, 0, 16, 0), // store128F32
  _VM(-1, -1, 0, 16, 0), // store128F64
  _VM(-1, -1, 0, 32, 0), // store256U32
  _VM(-1, -1, 0, 32, 0), // store256U64
  _VM(-1, -1, 0, 32, 0), // store256F32
  _VM(-1, -1, 0, 32, 0), // store256F64
  _VM(-1, -1, 0, 64, 0), // store512U32
  _VM(-1, -1, 0, 64, 0), // store512U64
  _VM(-1, -1, 0, 64, 0), // store512F32
  _VM(-1, -1, 0, 64, 0), // store512F64
  _VM(-1, -1, 0, 0, 0), // storeNU32
  _VM(-1, -1, 0, 0, 0), // storeNU64
  _VM(-1, -1, 0, 0, 0), // storeNF32
  _VM(-1, -1, 0, 0, 0), // storeNF64
  _VM(X86InstId.kPextrw, X86InstId.kVpextrw, 0, 2, 0), // storeExtractU16
  _VM(X86InstId.kPextrd, X86InstId.kVpextrd, 0, 4, 0), // storeExtractU32
  _VM(X86InstId.kPextrq, X86InstId.kVpextrq, 0, 8, 0), // storeExtractU64
];
