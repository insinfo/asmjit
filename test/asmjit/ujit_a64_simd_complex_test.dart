import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('UJIT A64 Complex SIMD Tests', () {
    test('Interleave (ZIP) & Packs (SQXTN)', () {
      final code = CodeHolder(
          env: Environment(arch: Arch.aarch64, platform: TargetPlatform.linux));
      final compiler =
          A64Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.cdecl));

      final d = cc.newVec("d");
      final s1 = cc.newVec("s1");
      final s2 = cc.newVec("s2");

      // Interleave
      cc.emit3v(UniOpVVV.interleaveLoU8, d, s1, s2);
      cc.emit3v(UniOpVVV.interleaveHiU16, d, s1, s2);
      cc.emit3v(UniOpVVV.interleaveLoF64, d, s1, s2);

      // Packs
      cc.emit3v(UniOpVVV.packsI16I8, d, s1, s2); // Should emit SQXTN / SQXTN2

      // Swizzle
      cc.emit3v(UniOpVVV.swizzlevU8, d, s1, s2); // Should emit TBL

      cc.ret();
      cc.endFunc();
      cc.finalize();

      var node = compiler.nodes.first;
      bool foundZip1 = false;
      bool foundZip2 = false;
      bool foundSqxtn = false;
      bool foundSqxtn2 = false;
      bool foundTbl = false;

      while (node != null) {
        if (node is InstNode) {
          final id = node.instId;
          if (id == A64InstId.kZip1) foundZip1 = true;
          if (id == A64InstId.kZip2) foundZip2 = true;
          if (id == A64InstId.kSqxtn) foundSqxtn = true;
          if (id == A64InstId.kSqxtn2) foundSqxtn2 = true;
          if (id == A64InstId.kTbl) foundTbl = true;
        }
        node = node.next;
      }

      expect(foundZip1, isTrue, reason: "ZIP1 missing");
      expect(foundZip2, isTrue, reason: "ZIP2 missing");
      expect(foundSqxtn, isTrue, reason: "SQXTN missing");
      expect(foundSqxtn2, isTrue, reason: "SQXTN2 missing");
      expect(foundTbl, isTrue, reason: "TBL missing");
    });
  });
}
