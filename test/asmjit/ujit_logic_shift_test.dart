import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

// Test Logic and Shift operations (UniOpRRR)
void main() {
  group('UJIT Logic & Shift Ops', () {
    late JitRuntime rt;

    setUp(() {
      rt = JitRuntime();
    });

    tearDown(() {
      rt.dispose();
    });

    test('AND Operation (RRR)', () {
      final code = CodeHolder(env: rt.environment);
      BaseCompiler compiler;
      if (rt.environment.arch == Arch.x64) {
        compiler = X86Compiler(env: code.env, labelManager: code.labelManager);
      } else {
        compiler = A64Compiler(env: code.env, labelManager: code.labelManager);
      }
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.build(
          [TypeId.uint32, TypeId.uint32], TypeId.uint32, CallConvId.cdecl));

      final a = cc.newGp32("a");
      final b = cc.newGp32("b");
      cc.setArg(0, a);
      cc.setArg(1, b);

      final dst = cc.newGp32("dst");
      cc.emitRRR(UniOpRRR.and, dst, a, b);

      cc.ret([dst]);
      cc.endFunc();

      cc.finalize();

      // Verify instruction generation in IR
      bool foundAnd = false;
      for (var node in compiler.nodes.nodes) {
        if (node is InstNode) {
          // Basic check for AND instruction ID
          if (rt.environment.arch == Arch.x64) {
            if (node.instId == X86InstId.kAnd) foundAnd = true;
          } else {
            if (node.instId == A64InstId.kAnd) foundAnd = true;
          }
        }
      }
      expect(foundAnd, isTrue, reason: 'AND instruction should be generated');
      // On X86, we might have MOV if dst != a (reg alloction might assign same reg, but IR preserves virtuals before allocation)
      // Wait, finalize runs RA. So nodes AFTER finalize are not Virtual Register specific anymore?
      // RA modifies nodes? In AsmJit C++, RA pass rewrites the nodes or generates new sequence?
      // In Dart port, RA pass updates nodes.
    });

    test('Shift Operation (RRI)', () {
      final code = CodeHolder(env: rt.environment);
      BaseCompiler compiler;
      if (rt.environment.arch == Arch.x64) {
        compiler = X86Compiler(env: code.env, labelManager: code.labelManager);
      } else {
        compiler = A64Compiler(env: code.env, labelManager: code.labelManager);
      }
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.build(
          [TypeId.uint32], TypeId.uint32, CallConvId.cdecl));

      final a = cc.newGp32("a");
      cc.setArg(0, a);

      final dst = cc.newGp32("dst");
      cc.emitRRI(UniOpRRR.sll, dst, a, 5); // dst = a << 5

      cc.ret([dst]);
      cc.endFunc();

      cc.finalize();

      bool foundShift = false;
      for (var node in compiler.nodes.nodes) {
        if (node is InstNode) {
          if (rt.environment.arch == Arch.x64) {
            if (node.instId == X86InstId.kShl) foundShift = true;
          } else {
            if (node.instId == A64InstId.kLsl) foundShift = true;
          }
        }
      }
      expect(foundShift, isTrue,
          reason: 'Shift instruction should be generated');
    });
  });
}
