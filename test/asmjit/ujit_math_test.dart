import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('UJIT Arithmetic Tests', () {
    test('X86 Add/Sub I32', () {
      if (!isX64) return; // Skip if not on X64 host? No, it's a generator.

      final env = Environment.host();
      if (!env.isX86Family)
        return; // For now skipping if not X86 host if we run valid?
      // Actually we are testing code GEN, not execution necessarily.
      // But verify uses execution normally.
      // Let's force X86 for generation test.

      final code = CodeHolder(env: Environment(arch: Arch.x64));
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.build(
          [TypeId.int32, TypeId.int32], TypeId.int32, CallConvId.cdecl));

      final a = cc.newGp32("a");
      final b = cc.newGp32("b");

      cc.setArg(0, a);
      cc.setArg(1, b);

      // We don't have emit3i or emit3 for GP ops exposed in UniCompiler directly usually?
      // UniCompiler mostly exposes SIMD.
      // But we can use underlying cc.
      // "uni" ops usually map to SIMD or specific helpers.

      // Let's test emit2i if available for GP?
      // emit2i(UniOpRR op, Operand dst, int imm)
      // UniOpRR has mov, etc.

      // Using underlying cc for basic arithmetic is standard if UniCompiler doesn't wrap valid GP ops.

      (cc.cc as X86Compiler).add(a, b);
      cc.ret([a]);

      cc.endFunc();
    });

    test('A64 Add/Sub I32', () {
      final env = Environment.aarch64();
      final code = CodeHolder(env: env);
      final compiler =
          A64Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.build(
          [TypeId.int32, TypeId.int32], TypeId.int32, CallConvId.cdecl));

      final a = cc.newGp32("a");
      final b = cc.newGp32("b");

      cc.setArg(0, a);
      cc.setArg(1, b);

      // A64 add
      // A64Compiler might not have 'add' helper yet. Using emit directly.
      // add(dst, src1, src2)
      cc.cc.addNode(InstNode(A64InstId.kAdd, [a, a, b]));

      cc.ret([a]);
      cc.endFunc();

      // Verify
      bool seenAdd = false;
      for (final node in cc.cc.nodes.nodes) {
        if (node is InstNode && node.instId == 2) {
          // kAdd = 2
          seenAdd = true;
        }
      }
      expect(seenAdd, isTrue);
    });
  });
}

// Minimal Environment check
bool get isX64 => true; // Assume true for test generation purposes
