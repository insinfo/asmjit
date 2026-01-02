import 'package:asmjit/asmjit.dart' as asmjit;
import 'benchmark_utils.dart';

void generateGpSequenceInternal(
  asmjit.BaseEmitter emitter,
  asmjit.A64Gp a,
  asmjit.A64Gp b,
  asmjit.A64Gp c,
  asmjit.A64Gp d,
) {
  final cc = emitter as asmjit.A64Assembler;

  final wa = a.w; // Fixed: .w is a getter
  final wb = b.w;
  final wc = c.w;
  final wd = d.w;

  final xa = a.x; // Fixed: .x is a getter
  final xb = b.x;
  final xc = c.x;
  final xd = d.x;

  cc.movz(wa, 0);
  cc.movz(wb, 1);
  cc.movz(wc, 2);
  cc.movz(wd, 3);

  cc.adc(wa, wb, wc);
  cc.adc(xa, xb, xc);
  cc.adc(wa, asmjit.wzr, wc);
  cc.adc(xa, asmjit.xzr, xc);

  cc.adcs(wa, wb, wc);
  cc.adcs(xa, xb, xc);

  cc.add(wa, wb, wc);
  cc.add(xa, xb, xc);
  cc.add(wa, wb, wc,
      shift: asmjit.A64Shift.lsl, amount: 3); // Check param names
  cc.add(xa, xb, xc, shift: asmjit.A64Shift.lsl, amount: 3);

  cc.adds(wa, wb, wc);
  cc.adds(xa, xb, xc);

  cc.adr(xa, 0);
  cc.adr(xa, 256);
  cc.adrp(xa, 4096);

  cc.and(wa, wb, wc); // Fixed: and_ -> and
  cc.and(xa, xb, xc);

  // Logical immediates not yet supported in A64Assembler/Encoder
  // cc.andImm(wa, wb, 1);
  // cc.andImm(xa, xb, 1);

  cc.ands(wa, wb, wc);
  cc.ands(xa, xb, xc);

  cc.asr(wa, wb, 15);
  cc.asr(xa, xb, 15);

  cc.bfc(wa, 8, 16);
  cc.bfc(xa, 8, 16);
  cc.bfi(wa, wb, 8, 16);
  cc.bfi(xa, xb, 8, 16);
  cc.bfm(wa, wb, 8, 16);
  cc.bfm(xa, xb, 8, 16);
  // bfxil is alias for bfm in assembler?
  // cc.bfxil(wa, wb, 8, 16);
  // cc.bfxil(xa, xb, 8, 16);

  // shift arg in bic is optional
  cc.bic(wa, wb, wc, shift: asmjit.A64Shift.lsl, amount: 4);
  cc.bic(xa, xb, xc, shift: asmjit.A64Shift.lsl, amount: 4);

  // Fixed: CondCode -> A64Cond and method names
  cc.ccmn(wa, wb, 3, asmjit.A64Cond.eq);
  cc.ccmn(xa, xb, 3, asmjit.A64Cond.eq);
  cc.ccmn(wa, 2, 3, asmjit.A64Cond.eq);
  cc.ccmn(xa, 2, 3, asmjit.A64Cond.eq);

  cc.ccmp(wa, wb, 3, asmjit.A64Cond.eq);
  cc.ccmp(xa, xb, 3, asmjit.A64Cond.eq);
  cc.ccmp(wa, 2, 3, asmjit.A64Cond.eq);
  cc.ccmp(xa, 2, 3, asmjit.A64Cond.eq);

  cc.cinc(wa, wb, asmjit.A64Cond.eq);
  cc.cinc(xa, xb, asmjit.A64Cond.eq);

  cc.cinv(wa, wb, asmjit.A64Cond.eq);
  cc.cinv(xa, xb, asmjit.A64Cond.eq);

  cc.cls(wa, wb);
  cc.cls(xa, xb);

  cc.clz(wa, wb);
  cc.clz(xa, xb);

  cc.cmn(wa, wb);
  cc.cmnImm(wa, 33);

  cc.cmp(wa, wb);
  cc.cmpImm(wa, 33);

  cc.crc32b(wa, wb, wc);
  cc.crc32cb(wa, wb, wc);
  cc.crc32ch(wa, wb, wc);
  cc.crc32cw(wa, wb, wc);
  cc.crc32cx(wa, wb, xc);

  cc.csel(wa, wb, wc, asmjit.A64Cond.eq);
  cc.csel(xa, xb, xc, asmjit.A64Cond.eq);

  cc.csinc(wa, wb, wc, asmjit.A64Cond.eq);
  cc.csinv(wa, wb, wc, asmjit.A64Cond.eq);
  cc.csneg(wa, wb, wc, asmjit.A64Cond.eq);

  cc.eon(wa, wb, wc);
  cc.eor(wa, wb, wc);
  // cc.eorImm(wa, wb, 0xFF);

  cc.extr(wa, wb, wc, 16);
  cc.extr(xa, xb, xc, 32);

  // Fixed: Use simple register loader since A64Mem overload is missing in A64Assembler
  cc.ldr(wa, xd);
  cc.ldr(xa, xd);
  cc.str(wa, xd);
  cc.str(xa, xd);

  cc.madd(wa, wb, wc, wd);
  cc.msub(wa, wb, wc, wd);
  cc.mul(wa, wb, wc);

  cc.neg(wa, wb);
  cc.orn(wa, wb, wc);
  cc.orr(wa, wb, wc);
  // cc.orrImm(wa, wb, 0xF0);

  cc.rbit(wa, wb);
  cc.rbit(xa, xb);

  cc.ret(asmjit.x30);
}

void main() {
  final env = asmjit.Environment.host();
  final code = asmjit.CodeHolder(env: env);
  final numIterations = 1000;

  // Only run AArch64 benchmark if host is AArch64 or simulator
  // Since we are compiling/running this on unknown host, we assume user knows what they are doing
  // or `bench` handles architecture checks.
  bench(
    code,
    asmjit.Arch.aarch64,
    numIterations,
    "A64 GP Sequence",
    0,
    (emitter) {
      final a = asmjit.x0;
      final b = asmjit.x1;
      final c = asmjit.x2;
      final d = asmjit.x3;
      generateGpSequenceInternal(emitter, a, b, c, d);
    },
  );
}
