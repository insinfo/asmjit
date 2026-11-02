// AVX-512 (EVEX) instructions through the serializer, as the compiler emits
// them. Expected bytes were cross-checked with the LLVM disassembler.
import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('AVX-512 Tests', () {
    test('X86Serializer emits AVX-512 instructions', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final serializer = X86Serializer(X86Assembler(code));

      // vaddps zmm0, zmm1, zmm2
      serializer.onInst(X86InstId.kVaddps, [xmm0.zmm, xmm1.zmm, xmm2.zmm], 0);
      // vaddpd zmm0, zmm1, zmm2
      serializer.onInst(X86InstId.kVaddpd, [xmm0.zmm, xmm1.zmm, xmm2.zmm], 0);

      expect(code.text.buffer.bytes, [
        0x62, 0xF1, 0x74, 0x48, 0x58, 0xC2, //
        0x62, 0xF1, 0xF5, 0x48, 0x58, 0xC2,
      ]);
    });
  });
}
