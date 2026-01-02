import 'package:asmjit/asmjit.dart' as asmjit;
import 'benchmark_utils.dart';

enum InstForm { kReg, kMem }

void generateGpSequenceInternal(
  asmjit.BaseEmitter emitter,
  InstForm form,
  asmjit.BaseReg a,
  asmjit.BaseReg b,
  asmjit.BaseReg c,
  asmjit.BaseReg d,
) {
  // print("Running GP sequence...");
  final cc = emitter as asmjit.X86Assembler;

  // Move immediate values
  cc.emit(asmjit.X86InstId.kMov, [a, asmjit.Imm(0xAAAAAAAA)]);
  cc.emit(asmjit.X86InstId.kMov, [b, asmjit.Imm(0xBBBBBBBB)]);
  cc.emit(asmjit.X86InstId.kMov, [c, asmjit.Imm(0xCCCCCCCC)]);
  cc.emit(asmjit.X86InstId.kMov, [d, asmjit.Imm(0xFFFFFFFF)]);
  cc.emit(asmjit.X86InstId.kMov, [a, asmjit.Imm(0x1234567812345678)]);

  if (form == InstForm.kReg) {
    cc.emit(asmjit.X86InstId.kAdc, [a, b]);
    cc.emit(asmjit.X86InstId.kAdc, [b, c]);
    cc.emit(asmjit.X86InstId.kAdc, [c, d]);
    cc.emit(asmjit.X86InstId.kAdd, [a, b]);
    cc.emit(asmjit.X86InstId.kAdd, [b, c]);
    cc.emit(asmjit.X86InstId.kAdd, [c, d]);
    cc.emit(asmjit.X86InstId.kAnd, [a, b]);
    cc.emit(asmjit.X86InstId.kAnd, [b, c]);
    cc.emit(asmjit.X86InstId.kAnd, [c, d]);
    cc.emit(asmjit.X86InstId.kBsf, [a, b]);
    cc.emit(asmjit.X86InstId.kBsf, [b, c]);
    cc.emit(asmjit.X86InstId.kBsf, [c, d]);
    cc.emit(asmjit.X86InstId.kBsr, [a, b]);
    cc.emit(asmjit.X86InstId.kBsr, [b, c]);
    cc.emit(asmjit.X86InstId.kBsr, [c, d]);
    cc.emit(asmjit.X86InstId.kBswap, [a]);
    cc.emit(asmjit.X86InstId.kBswap, [b]);
    cc.emit(asmjit.X86InstId.kBswap, [c]);
    cc.emit(asmjit.X86InstId.kBt, [a, b]);
    cc.emit(asmjit.X86InstId.kBt, [b, c]);
    cc.emit(asmjit.X86InstId.kBt, [c, d]);
    cc.emit(asmjit.X86InstId.kBtc, [a, b]);
    cc.emit(asmjit.X86InstId.kBtc, [b, c]);
    cc.emit(asmjit.X86InstId.kBtc, [c, d]);
    cc.emit(asmjit.X86InstId.kBtr, [a, b]);
    cc.emit(asmjit.X86InstId.kBtr, [b, c]);
    cc.emit(asmjit.X86InstId.kBtr, [c, d]);
    cc.emit(asmjit.X86InstId.kBts, [a, b]);
    cc.emit(asmjit.X86InstId.kBts, [b, c]);
    cc.emit(asmjit.X86InstId.kBts, [c, d]);
    cc.emit(asmjit.X86InstId.kCmp, [a, b]);
    cc.emit(asmjit.X86InstId.kCmovb, [a, b]);
    cc.emit(asmjit.X86InstId.kCmp, [b, c]);
    cc.emit(asmjit.X86InstId.kCmovb, [b, c]);
    cc.emit(asmjit.X86InstId.kCmp, [c, d]);
    cc.emit(asmjit.X86InstId.kCmovb, [c, d]);
    cc.emit(asmjit.X86InstId.kDec, [a]);
    cc.emit(asmjit.X86InstId.kDec, [b]);
    cc.emit(asmjit.X86InstId.kDec, [c]);
    cc.emit(asmjit.X86InstId.kImul, [a, b]);
    cc.emit(asmjit.X86InstId.kImul, [b, c]);
    cc.emit(asmjit.X86InstId.kImul, [c, d]);

    cc.emit(asmjit.X86InstId.kNeg, [a]);
    cc.emit(asmjit.X86InstId.kNeg, [b]);
    cc.emit(asmjit.X86InstId.kNeg, [c]);
    cc.emit(asmjit.X86InstId.kNot, [a]);
    cc.emit(asmjit.X86InstId.kNot, [b]);
    cc.emit(asmjit.X86InstId.kNot, [c]);
    cc.emit(asmjit.X86InstId.kOr, [a, b]);
    cc.emit(asmjit.X86InstId.kOr, [b, c]);
    cc.emit(asmjit.X86InstId.kOr, [c, d]);
    cc.emit(asmjit.X86InstId.kSbb, [a, b]);
    cc.emit(asmjit.X86InstId.kSbb, [b, c]);
    cc.emit(asmjit.X86InstId.kSbb, [c, d]);
    cc.emit(asmjit.X86InstId.kSub, [a, b]);
    cc.emit(asmjit.X86InstId.kSub, [b, c]);
    cc.emit(asmjit.X86InstId.kSub, [c, d]);
    cc.emit(asmjit.X86InstId.kTest, [a, b]);
    cc.emit(asmjit.X86InstId.kTest, [b, c]);
    cc.emit(asmjit.X86InstId.kTest, [c, d]);
    cc.emit(asmjit.X86InstId.kXchg, [a, b]);
    cc.emit(asmjit.X86InstId.kXchg, [b, c]);
    cc.emit(asmjit.X86InstId.kXchg, [c, d]);
    cc.emit(asmjit.X86InstId.kRcl, [a, asmjit.Imm(1)]);
    cc.emit(asmjit.X86InstId.kRcr, [a, asmjit.Imm(1)]);
    cc.emit(asmjit.X86InstId.kRol, [a, asmjit.Imm(1)]);
    cc.emit(asmjit.X86InstId.kRor, [a, asmjit.Imm(1)]);
    cc.emit(asmjit.X86InstId.kShl, [a, asmjit.Imm(1)]);
    cc.emit(asmjit.X86InstId.kShr, [a, asmjit.Imm(1)]);
    cc.emit(asmjit.X86InstId.kSar, [a, asmjit.Imm(1)]);

    // movsx/movzx - using r8 subregisters for demonstration
    final al = (a as asmjit.X86Gp).as8;
    cc.emit(asmjit.X86InstId.kMovsx, [a, al]);
    cc.emit(asmjit.X86InstId.kMovzx, [a, al]);

    cc.emit(asmjit.X86InstId.kXor, [a, b]);
    cc.emit(asmjit.X86InstId.kXor, [b, c]);
    cc.emit(asmjit.X86InstId.kXor, [c, d]);
  } else {
    // Memory variant
    final m = asmjit.ptr(c);
    final m8 = asmjit.bytePtr(c, 1);
    final m16 = asmjit.wordPtr(c, 2);
    final m32 = asmjit.dwordPtr(c, 4);
    final m64 = asmjit.qwordPtr(c, 8);

    cc.emit(asmjit.X86InstId.kAdc, [a, m]);
    cc.emit(asmjit.X86InstId.kAdd, [a, m]);
    cc.emit(asmjit.X86InstId.kAnd, [a, m]);
    cc.emit(asmjit.X86InstId.kCmp, [a, m]);
    cc.emit(asmjit.X86InstId.kImul, [a, m]);
    cc.emit(asmjit.X86InstId.kOr, [a, m]);
    cc.emit(asmjit.X86InstId.kSbb, [a, m]);
    cc.emit(asmjit.X86InstId.kSub, [a, m]);
    cc.emit(asmjit.X86InstId.kTest, [a, m]);
    cc.emit(asmjit.X86InstId.kXor, [a, m]);

    // Use different sizes
    final al = (a as asmjit.X86Gp).as8;
    final ax = a.as16;
    final eax = a.as32;

    cc.emit(asmjit.X86InstId.kMov, [al, m8]);
    cc.emit(asmjit.X86InstId.kMov, [ax, m16]);
    cc.emit(asmjit.X86InstId.kMov, [eax, m32]);
    cc.emit(asmjit.X86InstId.kMov, [a, m64]);

    // Bit tests with memory
    cc.emit(asmjit.X86InstId.kBt, [m, a]);
    cc.emit(asmjit.X86InstId.kBtc, [m, a]);
    cc.emit(asmjit.X86InstId.kBtr, [m, a]);
    cc.emit(asmjit.X86InstId.kBts, [m, a]);
  }
}

void generateSseSequenceInternal(
  asmjit.BaseEmitter emitter,
  InstForm form,
  asmjit.BaseReg gp,
  asmjit.BaseReg xmm_a,
  asmjit.BaseReg xmm_b,
  asmjit.BaseReg xmm_c,
  asmjit.BaseReg xmm_d,
) {
  final cc = emitter as asmjit.X86Assembler;
  final gpd = (gp as asmjit.X86Gp).as32;

  cc.emit(asmjit.X86InstId.kXor, [gpd, gpd]);
  cc.emit(asmjit.X86InstId.kXorps, [xmm_a, xmm_a]);
  cc.emit(asmjit.X86InstId.kXorps, [xmm_b, xmm_b]);
  cc.emit(asmjit.X86InstId.kXorps, [xmm_c, xmm_c]);
  cc.emit(asmjit.X86InstId.kXorps, [xmm_d, xmm_d]);

  if (form == InstForm.kReg) {
    // SSE
    cc.emit(asmjit.X86InstId.kAddps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kAddss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kAndnps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kAndps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kCmpps, [xmm_a, xmm_b, asmjit.Imm(0)]);
    cc.emit(asmjit.X86InstId.kCmpss, [xmm_a, xmm_b, asmjit.Imm(0)]);
    cc.emit(asmjit.X86InstId.kComiss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kDivps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kDivss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMaxps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMaxss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMinps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMinss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMovaps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMovups, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMulps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMulss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kOrps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kRcpps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kRcpss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kSqrtps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kSqrtss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kSubps, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kSubss, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kXorps, [xmm_a, xmm_b]);

    // SSE2
    cc.emit(asmjit.X86InstId.kAddpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kAddsd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kAndnpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kAndpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kCmppd, [xmm_a, xmm_b, asmjit.Imm(0)]);
    cc.emit(asmjit.X86InstId.kCmpsd, [xmm_a, xmm_b, asmjit.Imm(0)]);
    cc.emit(asmjit.X86InstId.kDivpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kDivsd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMaxpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMaxsd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMinpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMinsd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMulpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kMulsd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kOrpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPacksswb, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPackssdw, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPackuswb, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPaddb, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPaddw, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPaddd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPaddq, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPand, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPandn, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPor, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kPxor, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kSubpd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kSubsd, [xmm_a, xmm_b]);
    cc.emit(asmjit.X86InstId.kXorpd, [xmm_a, xmm_b]);
  }
}

void main() {
  final code = asmjit.CodeHolder(env: asmjit.Environment.x64Windows());
  final numIterations = 1000;

  // Benchmark GP Reg Sequence
  bench(
    code,
    asmjit.Arch.x64,
    numIterations,
    "GP Reg Sequence",
    0,
    (emitter) {
      final a = asmjit.rax;
      final b = asmjit.rbx;
      final c = asmjit.rcx;
      final d = asmjit.rdx;
      generateGpSequenceInternal(emitter, InstForm.kReg, a, b, c, d);
    },
  );

  // Benchmark GP Mem Sequence
  bench(
    code,
    asmjit.Arch.x64,
    numIterations,
    "GP Mem Sequence",
    0,
    (emitter) {
      final a = asmjit.rax;
      final b = asmjit.rbx;
      final c = asmjit.rcx;
      final d = asmjit.rdx;
      generateGpSequenceInternal(emitter, InstForm.kMem, a, b, c, d);
    },
  );

  // Benchmark SSE Reg Sequence
  bench(
    code,
    asmjit.Arch.x64,
    numIterations,
    "SSE Reg Sequence",
    0,
    (emitter) {
      final gp = asmjit.rax;
      final xmm_a = asmjit.xmm0;
      final xmm_b = asmjit.xmm1;
      final xmm_c = asmjit.xmm2;
      final xmm_d = asmjit.xmm3;
      generateSseSequenceInternal(
          emitter, InstForm.kReg, gp, xmm_a, xmm_b, xmm_c, xmm_d);
    },
  );
}
