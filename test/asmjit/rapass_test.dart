import 'package:test/test.dart';
import 'package:asmjit/src/asmjit/core/compiler.dart';
import 'package:asmjit/src/asmjit/core/func.dart';
import 'package:asmjit/src/asmjit/core/operand.dart';
import 'package:asmjit/src/asmjit/x86/x86.dart';
import 'package:asmjit/src/asmjit/x86/x86_compiler.dart';

void main() {
  group('RAPass', () {
    test('Allocates registers for simple move', () {
      final compiler = X86Compiler();

      final func = compiler.newFunc(FuncSignature.noArgs());
      compiler.addFuncNode(func);

      // Manually create virtual registers since helper methods might be missing in simplified X86Compiler
      // We use id >= kMinVirtId (64)
      final v0 = X86Gp.r64(compiler.newVirtId());
      final v1 = X86Gp.r64(compiler.newVirtId());

      // Expected physical regs (assuming simplistic allocation starting at 0/rax)
      // Actually allocator picks available regs.

      // compiler.mov(v0, v1); // Removed extra instruction

      // This is invalid code logic (use before def) but RA should just allocate.
      // Wait, USE before DEF? v1 is used. It's live-in?
      // If v1 is used without def, RA assumes it's live-in or uninitialized?
      // RALocal might fail or assign safely.

      // Better:
      // mov v0, rax (phys)
      // mov v1, v0
      // mov rcx, v1

      compiler.mov(v0, rax);
      compiler.mov(v1, v0);
      compiler.mov(rcx, v1);

      compiler.runPasses(); // Should trigger RAPass

      // Verify operands
      final nodes =
          compiler.nodes.instructions.where((n) => n.instId == 57).toList();
      print(nodes);

      // O pipeline pode inserir MOV rbp, rsp (prologue), então não podemos
      // assumir que só sobra 1 MOV. O importante aqui é que o RAPass
      // tenha colapsado os movimentos virtuais em um MOV rcx, rax.
      final hasMovRcxRax = nodes.any((n) {
        return n.operands.length == 2 && n.operands[0] == rcx && n.operands[1] == rax;
      });
      expect(hasMovRcxRax, isTrue);
    });
  });
}

// Custom matcher helper
final Matcher isPhysicalReg =
    predicate((x) => x is BaseReg && x.isPhysical, "is physical register");

// Helper to ignore specific ID but check physical
final Matcher changesAccordingToAllocation = anything;
