import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('UJIT Float Arithmetic Ops', () {
    late JitRuntime rt;

    setUp(() {
      rt = JitRuntime();
    });

    tearDown(() {
      rt.dispose();
    });

    test('Float Add (F32)', () {
      final code = CodeHolder(env: rt.environment);
      BaseCompiler compiler;
      if (rt.environment.arch == Arch.x64) {
        compiler = X86Compiler(env: code.env, labelManager: code.labelManager);
      } else {
        compiler = A64Compiler(env: code.env, labelManager: code.labelManager);
      }
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.build(
          [TypeId.float32, TypeId.float32], TypeId.float32, CallConvId.cdecl));
      // Scalar float: passed in XMM/V0 but treated as scalar.
      // UniCompiler setArg maps to standard calling convention.
      // For F32, it's usually XMM/V register.

      // Let's assume input is vector logic for verify.
      final v1 = cc.newVec("v1");
      final v2 = cc.newVec("v2");
      final dst = cc.newVec("dst");

      if (rt.environment.arch == Arch.x64) {
        // X86: addps dst, v1, v2
        cc.emit3v(UniOpVVV.addF32, dst, v1, v2);
      } else {
        // A64: fadd dst.4s, v1.4s, v2.4s
        cc.emit3v(UniOpVVV.addF32, dst, v1, v2);
      }

      cc.ret();
      cc.endFunc();

      bool foundAdd = false;
      for (var node in compiler.nodes.nodes) {
        if (node is InstNode) {
          if (rt.environment.arch == Arch.x64) {
            // addps = kAddps
            if (node.instId == X86InstId.kAddps) foundAdd = true;
          } else {
            // fadd = kFadd
            if (node.instId == A64InstId.kFadd) foundAdd = true;
          }
        }
      }
      expect(foundAdd, isTrue,
          reason: 'Float Add instruction should be generated');
    });

    test('Float Mul (F64)', () {
      final code = CodeHolder(env: rt.environment);
      BaseCompiler compiler;
      if (rt.environment.arch == Arch.x64) {
        compiler = X86Compiler(env: code.env, labelManager: code.labelManager);
      } else {
        compiler = A64Compiler(env: code.env, labelManager: code.labelManager);
      }
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.build([], TypeId.void_, CallConvId.cdecl));
      final v1 = cc.newVec("v1");
      final v2 = cc.newVec("v2");
      final dst = cc.newVec("dst");

      cc.emit3v(UniOpVVV.mulF64, dst, v1, v2);

      cc.ret();
      cc.endFunc();

      bool foundMul = false;
      for (var node in compiler.nodes.nodes) {
        if (node is InstNode) {
          if (rt.environment.arch == Arch.x64) {
            if (node.instId == X86InstId.kMulpd) foundMul = true;
          } else {
            if (node.instId == A64InstId.kFmul) foundMul = true;
          }
        }
      }
      expect(foundMul, isTrue,
          reason: 'Float Mul instruction should be generated');
    });
  });
}
