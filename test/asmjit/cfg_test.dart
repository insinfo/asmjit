import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/x86/x86_compiler.dart';
import 'package:asmjit/src/asmjit/core/compiler.dart';
import 'package:test/test.dart';

void main() {
  group('CFGBuilder', () {
    test('Builds simple linear CFG', () {
      final builder = X86CodeBuilder.create();

      final b1 = builder.block(builder.newLabel());
      builder.mov(rax, 1);

      final b2 = builder.block(builder.newLabel());
      builder.mov(rax, 2);

      final analyzer = X86InstructionAnalyzer();
      final cfg = CFGBuilder(analyzer);
      cfg.run(builder.nodes);

      // b1 -> b2 (fallthrough)
      // Debug print
      print('B1 succs: ${b1.successors}');
      print('B2 preds: ${b2.predecessors}');

      expect(b1.successors.length, 1);
      expect(b1.successors.first, b2);
      expect(b2.predecessors.length, 1);
      expect(b2.predecessors.first, b1);
    });

    test('Builds CFG with Jumps', () {
      final builder = X86CodeBuilder.create();
      final labelTarget = builder.newLabel();
      final labelEnd = builder.newLabel();

      final bEntry = builder.block(builder.newLabel());
      builder.jmp(labelTarget);

      // Block 1 (Unreachable from fallthrough of entry, but reached via jump)
      final bTarget = builder.block(labelTarget);
      builder.je(labelEnd); // Jump to End or Fallthrough

      // Block End (Fallthrough from bTarget, and Jump target)
      final bEnd = builder.block(labelEnd);
      builder.ret();

      final analyzer = X86InstructionAnalyzer();
      final cfg = CFGBuilder(analyzer);
      cfg.run(builder.nodes);

      // bEntry -> bTarget
      expect(bEntry.successors, contains(bTarget));
      expect(bEntry.successors.length, 1); // Unconditional jump, no fallthrough

      // bTarget -> bEnd (Jump) AND bTarget -> bEnd (Fallthrough, since it's next)
      expect(bTarget.successors, contains(bEnd));

      // Should handle duplicate edges gracefully (unique successors)
      expect(bTarget.successors.length, 1);
      expect(bTarget.successors.first, bEnd);
    });
  });
}
