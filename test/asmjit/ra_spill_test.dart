import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('RAPass Spilling Tests', () {
    test('Spill registers when pressure exceeds available registers', () {
      final compiler = X86Compiler();

      // Define a function returning int
      final funcNode = compiler.addFunc(FuncSignature.i64());

      // Create 20 virtual registers (more than 15 available GPs in x64)
      final regs = <X86Gp>[];
      for (int i = 0; i < 20; i++) {
        regs.add(compiler.newGp64('v$i'));
      }

      // Initialize them all to ensure they are live
      for (int i = 0; i < 20; i++) {
        compiler.mov(regs[i], Imm(i));
      }

      // Force them to be live simultaneously by using them all in a summation
      final sum = compiler.newGp64('sum');
      compiler.mov(sum, Imm(0));

      for (int i = 0; i < 20; i++) {
        compiler.add(sum, regs[i]);
      }

      compiler.ret([sum]);
      compiler.endFunc();

      // Run passes (CFG, RA)
      compiler.finalize();

      // Verify stack usage
      final frame = funcNode.frame;
      // We expect some spilling, so localStackSize should be > 0
      expect(frame.localStackSize, greaterThan(0));
      expect(frame.frameSize, greaterThan(0));

      // Verify generated instructions contain spills (moves to/from stack)
      // Since we don't have an easy instruction inspector for generated code stream
      // without serializing, we verify the frame properties which are improved by our RAPass.
    });
  });
}
