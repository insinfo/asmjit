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

      // dst = {s1[0], s1[1], s2[2], s2[3]}.
      cc.emit3vi(UniOpVVVI.interleaveShuffleU32x4, d, s1, s2,
          swizzle4(3, 2, 1, 0).value);

      cc.ret();
      cc.endFunc();
      cc.finalize();

      // Like asmjit, the shuffle is decomposed into at most three permute,
      // insert, DUP, EXT or REV64 operations from a table, without TBL.
      var node = compiler.nodes.first;
      var foundTbl = false;
      var simd = 0;
      while (node != null) {
        if (node is InstNode && node.operands.any((o) => o is A64Vec)) {
          if (node.instId == A64InstId.kTbl) foundTbl = true;
          simd++;
        }
        node = node.next;
      }
      expect(foundTbl, isFalse);
      expect(simd, lessThanOrEqualTo(3));
    });
  });
}
