import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  test('AVX Basic Encoding', () {
    final code = CodeHolder();
    final asm = X86Assembler(code);

    // VADDPS xmm0, xmm1, xmm2
    // C5 F0 58 C2
    asm.vaddpsXXX(xmm0, xmm1, xmm2);

    // VADDSS xmm0, xmm1, xmm2
    // C5 F2 58 C2
    asm.vaddssXXX(xmm0, xmm1, xmm2);

    // VBROADCASTSS xmm0, [rax]
    // C4 E2 79 18 00
    asm.vbroadcastssXM(xmm0, ptr(rax));

    // VMOVD xmm0, eax
    // C5 F9 6E C0
    asm.vmovdXR(xmm0, eax);

    // VSQRTPS xmm0, xmm1
    // C5 F8 51 C1
    asm.vsqrtpsXX(xmm0, xmm1);

    final finalBytes = code.finalize().textBytes;

    expect(
        finalBytes,
        equals([
          0xC5,
          0xF0,
          0x58,
          0xC2,
          0xC5,
          0xF2,
          0x58,
          0xC2,
          0xC4,
          0xE2,
          0x79,
          0x18,
          0x00,
          0xC5,
          0xF9,
          0x6E,
          0xC0,
          0xC5,
          0xF8,
          0x51,
          0xC1,
        ]));
  });
}
