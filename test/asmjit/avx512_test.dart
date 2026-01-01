import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  test('AVX-512 Basic Encoding (ZMM)', () {
    final code = CodeHolder();
    final asm = X86Assembler(code);

    // VPADDD zmm0, zmm1, zmm2
    // EVEX.512.66.0F38.W0 FE /r
    // 62 F1 75 48 FE C2
    // Payload Breakdown:
    // P0: 62 (EVEX)
    // P1: F1 (R=1, X=1, B=1, R'=1, 00, mm=01) -> All regs < 8, mm=0F? No 0F38 is map 2.
    // Let's recheck map encoding.
    // 0F=1, 0F38=2, 0F3A=3.
    // If mm=2 (10b), P1 bits 1:0 = 10.
    // Regs 0,1,2 -> R,X,B all 1 (inverted).
    // P1 should be: 11110010 = F2?
    // Wait, vpaddd is 66 0F FE (SSE) / VEX ...
    // AVX512 VPADDD is 66 0F38? No, let's check SDM.
    // VPADDD: EVEX.NDS.512.66.0F.W0 FE /r
    // Map is 0F (mm=1).
    // P1: R',R,X,B bits inverted. 0->1.
    // mm=01.
    // P1 = 11110001 = F1. Correct.
    // P2: W=0, vvvv=1110 (src1=zmm1->1->~1=1110), 1, pp=01 (66).
    // P2 = 0 1110 1 01 = 01110101 = 75. Correct.
    // P3: z=0, L'L=10 (512), b=0, V'=1 (vvvv<16), aaa=000.
    // P3 = 0 10 0 1 000 = 01001000 = 48. Correct.
    // Opcode: FE
    // ModRM: Mod=11, Reg=0(zmm0), RM=2(zmm2). C2.

    asm.vpadddZmmZmmZmm(zmm0, zmm1, zmm2);

    final finalBytes = code.finalize().textBytes;

    expect(finalBytes, equals([0x62, 0xF1, 0x75, 0x48, 0xFE, 0xC2]));
  });

  test('AVX-512 K-Reg Move', () {
    final code = CodeHolder();
    final asm = X86Assembler(code);

    // KMOVW k1, k2
    // VEX.L0.0F.W0 90 /r
    // C5 F8 90 CA
    // VEX2 (C5) is valid if maps to 0F and no extended regs.
    // R=1 (k1 not extended). vvvv=1111 (unused). L=0. pp=00.
    // C5 F8.
    // 90
    // CA (11 001 010) k1, k2.
    asm.kmovwKK(k1, k2);

    final finalBytes = code.finalize().textBytes;

    expect(finalBytes, equals([0xC5, 0xF8, 0x90, 0xCA]));
  });

  test('AVX-512 Masking', () {
    final code = CodeHolder();
    final asm = X86Assembler(code);

    // VPADDD zmm0 {k1}, zmm1, zmm2
    // EVEX.512.66.0F.W0 FE /r
    // payload P3 changes AAA to k1 (001).
    // P3 was 48 (0100 1000). Now 0100 1001 -> 49.
    // 62 F1 75 49 FE C2
    asm.vpadddZmmZmmZmmK(zmm0, zmm1, zmm2, k1);

    // VPADDD zmm0 {k1}{z}, zmm1, zmm2
    // Zeroing bit (z) in P3 is bit 7.
    // P3 was 49 (0100 1001). Now 1100 1001 -> C9.
    // 62 F1 75 C9 FE C2
    asm.vpadddZmmZmmZmmKz(zmm0, zmm1, zmm2, k1);

    final finalBytes = code.finalize().textBytes;

    expect(
        finalBytes,
        equals([
          0x62,
          0xF1,
          0x75,
          0x49,
          0xFE,
          0xC2,
          0x62,
          0xF1,
          0x75,
          0xC9,
          0xFE,
          0xC2,
        ]));
  });

  test('AVX-512 Ternary Logic', () {
    final code = CodeHolder();
    final asm = X86Assembler(code);

    // VPTERNLOGD zmm0, zmm1, zmm2, 0xFF
    // EVEX.512.66.0F3A.W0 25 /r ib
    // 0F3A map is 3 -> P1 mm=11.
    // P1: R',R,X,B=1. mm=11. -> F3.
    // P2: W=0, vvvv=1110 (src1=zmm1->14), 1, pp=01 (66) -> 75.
    // P3: z=0, L=10, b=0, V'=1, aaa=000 -> 48.
    // Opcode 25.
    // ModRM: zmm0 (0), zmm2 (2). -> C2.
    // Imm8: FF.
    // 62 F3 75 48 25 C2 FF
    asm.vpternlogdZmmZmmZmmI(zmm0, zmm1, zmm2, 0xFF);

    final finalBytes = code.finalize().textBytes;

    expect(finalBytes, equals([0x62, 0xF3, 0x75, 0x48, 0x25, 0xC2, 0xFF]));
  });
}
