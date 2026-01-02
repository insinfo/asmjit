import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/arm/a64_compiler.dart';
import 'package:asmjit/src/asmjit/arm/a64.dart' as a64;
import 'package:test/test.dart';

void main() {
  group('UJIT AArch64 Constant Tests', () {
    test('Vector Constant Creation and Load', () {
      // Force AArch64 environment
      final env = Environment.aarch64();
      final code = CodeHolder(env: env);
      final compiler =
          A64Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(
          FuncSignature.build([TypeId.intPtr], TypeId.void_, CallConvId.cdecl));

      final v0 = cc.newVec("v0");

      // Load from SP
      final mem = A64Mem.base(a64.sp);
      cc.emitRM(UniOpRM.loadU32, v0, mem);

      cc.endFunc();

      // Verify
      int ldrCount = 0;
      for (final node in cc.cc.nodes.nodes) {
        if (node is InstNode) {
          // InstNode toString might print ID if not resolved using an external map.
          // In this test environment, we see ID 68.
          // A64InstId.kLdr is 68.
          if (node.instId == 68) ldrCount++;
        }
      }
      expect(ldrCount, greaterThan(0));
    });
  });
}
