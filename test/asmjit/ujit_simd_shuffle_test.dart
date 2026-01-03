import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('UJIT SIMD Shuffle Tests', () {
    test('interleaveShuffleU32x4 (A64)', () {
      final code = CodeHolder(
          env: Environment(arch: Arch.aarch64, platform: TargetPlatform.linux));
      final compiler =
          A64Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.cdecl));

      final d = cc.newVec("d");
      final s1 = cc.newVec("s1");
      final s2 = cc.newVec("s2");

      // Shuffle with imm 0xE4 (3, 2, 1, 0)
      cc.emit3vi(UniOpVVVI.interleaveShuffleU32x4, d, s1, s2, 0xE4);

      cc.ret();
      cc.endFunc();
      cc.finalize();

      // Check for TBL instruction
      var node = compiler.nodes.first;
      bool foundTbl = false;
      while (node != null) {
        if (node is InstNode) {
          if (node.instId == A64InstId.kTbl) foundTbl = true;
        }
        node = node.next;
      }
      expect(foundTbl, isTrue, reason: "TBL instruction should be emitted for shuffle");
    });
  });
}
