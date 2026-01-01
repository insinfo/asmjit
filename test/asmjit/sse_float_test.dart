import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }

  group('SSE Floating-Point Instructions', () {
    test('addps/addpd/addss/addsd', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.addps(xmm0, xmm1);
      asm.addpsXM(xmm2, ptr(rax));
      asm.addpd(xmm3, xmm4);
      asm.addpdXM(xmm5, ptr(rbx));
      asm.addssXX(xmm6, xmm7);
      asm.addssXM(xmm0, ptr(rcx));
      asm.addsdXX(xmm1, xmm2);
      asm.addsdXM(xmm3, ptr(rdx));

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0x0F, 0x58, 0xC1, // addps xmm0, xmm1
            0x0F, 0x58, 0x10, // addps xmm2, [rax]
            0x66, 0x0F, 0x58, 0xDC, // addpd xmm3, xmm4
            0x66, 0x0F, 0x58, 0x2B, // addpd xmm5, [rbx]
            0xF3, 0x0F, 0x58, 0xF7, // addss xmm6, xmm7
            0xF3, 0x0F, 0x58, 0x01, // addss xmm0, [rcx]
            0xF2, 0x0F, 0x58, 0xCA, // addsd xmm1, xmm2
            0xF2, 0x0F, 0x58, 0x1A, // addsd xmm3, [rdx]
          ]));
    });

    test('subps/subpd/subss/subsd', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.subps(xmm0, xmm1);
      asm.subpsXM(xmm2, ptr(rax));
      asm.subpd(xmm3, xmm4);
      asm.subpdXM(xmm5, ptr(rbx));
      asm.subssXX(xmm6, xmm7);
      asm.subssXM(xmm0, ptr(rcx));
      asm.subsdXX(xmm1, xmm2);
      asm.subsdXM(xmm3, ptr(rdx));

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0x0F, 0x5C, 0xC1, // subps xmm0, xmm1
            0x0F, 0x5C, 0x10, // subps xmm2, [rax]
            0x66, 0x0F, 0x5C, 0xDC, // subpd xmm3, xmm4
            0x66, 0x0F, 0x5C, 0x2B, // subpd xmm5, [rbx]
            0xF3, 0x0F, 0x5C, 0xF7, // subss xmm6, xmm7
            0xF3, 0x0F, 0x5C, 0x01, // subss xmm0, [rcx]
            0xF2, 0x0F, 0x5C, 0xCA, // subsd xmm1, xmm2
            0xF2, 0x0F, 0x5C, 0x1A, // subsd xmm3, [rdx]
          ]));
    });

    test('mulps/mulpd/mulss/mulsd', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.mulps(xmm0, xmm1);
      asm.mulpsXM(xmm2, ptr(rax));
      asm.mulpd(xmm3, xmm4);
      asm.mulpdXM(xmm5, ptr(rbx));
      asm.mulssXX(xmm6, xmm7);
      asm.mulssXM(xmm0, ptr(rcx));
      asm.mulsdXX(xmm1, xmm2);
      asm.mulsdXM(xmm3, ptr(rdx));

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0x0F, 0x59, 0xC1, // mulps xmm0, xmm1
            0x0F, 0x59, 0x10, // mulps xmm2, [rax]
            0x66, 0x0F, 0x59, 0xDC, // mulpd xmm3, xmm4
            0x66, 0x0F, 0x59, 0x2B, // mulpd xmm5, [rbx]
            0xF3, 0x0F, 0x59, 0xF7, // mulss xmm6, xmm7
            0xF3, 0x0F, 0x59, 0x01, // mulss xmm0, [rcx]
            0xF2, 0x0F, 0x59, 0xCA, // mulsd xmm1, xmm2
            0xF2, 0x0F, 0x59, 0x1A, // mulsd xmm3, [rdx]
          ]));
    });

    test('divps/divpd/divss/divsd', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.divps(xmm0, xmm1);
      asm.divpsXM(xmm2, ptr(rax));
      asm.divpd(xmm3, xmm4);
      asm.divpdXM(xmm5, ptr(rbx));
      asm.divssXX(xmm6, xmm7);
      asm.divssXM(xmm0, ptr(rcx));
      asm.divsdXX(xmm1, xmm2);
      asm.divsdXM(xmm3, ptr(rdx));

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0x0F, 0x5E, 0xC1, // divps xmm0, xmm1
            0x0F, 0x5E, 0x10, // divps xmm2, [rax]
            0x66, 0x0F, 0x5E, 0xDC, // divpd xmm3, xmm4
            0x66, 0x0F, 0x5E, 0x2B, // divpd xmm5, [rbx]
            0xF3, 0x0F, 0x5E, 0xF7, // divss xmm6, xmm7
            0xF3, 0x0F, 0x5E, 0x01, // divss xmm0, [rcx]
            0xF2, 0x0F, 0x5E, 0xCA, // divsd xmm1, xmm2
            0xF2, 0x0F, 0x5E, 0x1A, // divsd xmm3, [rdx]
          ]));
    });

    test('min/max ps/pd/ss/sd', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.minps(xmm0, xmm1);
      asm.minpd(xmm2, xmm3);
      asm.minssXX(xmm4, xmm5);
      asm.minsdXX(xmm6, xmm7);
      asm.maxps(xmm0, xmm1);
      asm.maxpd(xmm2, xmm3);
      asm.maxssXX(xmm4, xmm5);
      asm.maxsdXX(xmm6, xmm7);

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0x0F, 0x5D, 0xC1, // minps
            0x66, 0x0F, 0x5D, 0xD3, // minpd
            0xF3, 0x0F, 0x5D, 0xE5, // minss
            0xF2, 0x0F, 0x5D, 0xF7, // minsd
            0x0F, 0x5F, 0xC1, // maxps
            0x66, 0x0F, 0x5F, 0xD3, // maxpd
            0xF3, 0x0F, 0x5F, 0xE5, // maxss
            0xF2, 0x0F, 0x5F, 0xF7, // maxsd
          ]));
    });

    test('sqrt ps/pd/ss/sd', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.sqrtps(xmm0, xmm1);
      asm.sqrtpd(xmm2, xmm3);
      asm.sqrtssXX(xmm4, xmm5);
      asm.sqrtsdXX(xmm6, xmm7);

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0x0F, 0x51, 0xC1, // sqrtps
            0x66, 0x0F, 0x51, 0xD3, // sqrtpd
            0xF3, 0x0F, 0x51, 0xE5, // sqrtss
            0xF2, 0x0F, 0x51, 0xF7, // sqrtsd
          ]));
    });

    test('rcp/rsqrt ps/ss', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.rcpps(xmm0, xmm1);
      asm.rcpssXX(xmm2, xmm3);
      asm.rsqrtps(xmm4, xmm5);
      asm.rsqrtssXX(xmm6, xmm7);

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0x0F, 0x53, 0xC1, // rcpps
            0xF3, 0x0F, 0x53, 0xD3, // rcpss
            0x0F, 0x52, 0xE5, // rsqrtps
            0xF3, 0x0F, 0x52, 0xF7, // rsqrtss
          ]));
    });

    test('cmp/comi', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.cmppsXXI(xmm0, xmm1, 0);
      asm.cmppdXXI(xmm2, xmm3, 1);
      asm.cmpssXXI(xmm4, xmm5, 2);
      asm.cmpsdXXI(xmm6, xmm7, 3);
      asm.comissXX(xmm0, xmm1);
      asm.comisdXX(xmm2, xmm3);
      asm.ucomissXX(xmm4, xmm5);
      asm.ucomisdXX(xmm6, xmm7);

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0x0F, 0xC2, 0xC1, 0x00, // cmpps
            0x66, 0x0F, 0xC2, 0xD3, 0x01, // cmppd
            0xF3, 0x0F, 0xC2, 0xE5, 0x02, // cmpss
            0xF2, 0x0F, 0xC2, 0xF7, 0x03, // cmpsd
            0x0F, 0x2F, 0xC1, // comiss
            0x66, 0x0F, 0x2F, 0xD3, // comisd
            0x0F, 0x2E, 0xE5, // ucomiss
            0x66, 0x0F, 0x2E, 0xF7, // ucomisd
          ]));
    });

    test('conversions', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);

      asm.cvtsi2ssXR(xmm0, rax);
      asm.cvtsi2sdXR(xmm1, rbx);
      asm.cvttss2siRX(rcx, xmm2);
      asm.cvttsd2siRX(rdx, xmm3);
      asm.cvtss2sdXX(xmm4, xmm5);
      asm.cvtsd2ssXX(xmm6, xmm7);
      asm.cvtps2dqXX(xmm0, xmm1);
      asm.cvtdq2psXX(xmm2, xmm3);
      asm.cvttps2dqXX(xmm4, xmm5);

      final finalized = code.finalize();
      expect(
          finalized.textBytes,
          equals([
            0xF3, 0x48, 0x0F, 0x2A, 0xC0, // cvtsi2ss
            0xF2, 0x48, 0x0F, 0x2A, 0xCB, // cvtsi2sd
            0xF3, 0x48, 0x0F, 0x2C, 0xCA, // cvttss2si
            0xF2, 0x48, 0x0F, 0x2C, 0xD3, // cvttsd2si
            0xF3, 0x0F, 0x5A, 0xE5, // cvtss2sd
            0xF2, 0x0F, 0x5A, 0xF7, // cvtsd2ss
            0x66, 0x0F, 0x5B, 0xC1, // cvtps2dq
            0x0F, 0x5B, 0xD3, // cvtdq2ps
            0xF3, 0x0F, 0x5B, 0xE5, // cvttps2dq
          ]));
    });
  });
}
