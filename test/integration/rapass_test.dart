import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

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
        return n.operands.length == 2 &&
            n.operands[0] == rcx &&
            n.operands[1] == rax;
      });
      expect(hasMovRcxRax, isTrue);
    });

    test('Argumento spillado com newStack e recarregado', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final sig =
          FuncSignature.build([TypeId.intPtr], TypeId.intPtr, CallConvId.x64Windows);
      final funcNode = compiler.addFunc(sig);

      final arg = compiler.newGpPtr('arg');
      funcNode.setArg(0, 0, arg);

      final spillSlot = compiler.newStack(8, 8);
      final tmp = compiler.newGpPtr('tmp');

      compiler.mov(spillSlot, arg); // save incoming arg
      compiler.mov(tmp, spillSlot); // reload from stack slot
      compiler.mov(rax, tmp);
      compiler.ret();
      compiler.endFunc();

      compiler.finalize();

      // Verifica que o RAPass inseriu MOV rcx -> [rbp+disp] e MOV [rbp+disp] -> rax
      final nodes = compiler.nodes.instructions.toList();
      bool _isFrameBase(X86Mem m) => m.base == rbp || m.base == rsp;

      final hasStore = nodes.any((n) {
        if (n.instId != X86InstId.kMov) return false;
        final ops = n.operands;
        if (ops.length < 2) return false;
        final dst = ops[0];
        final src = ops[1];
        return dst is X86Mem && _isFrameBase(dst) && src is BaseReg;
      });

      final hasLoad = nodes.any((n) {
        if (n.instId != X86InstId.kMov) return false;
        final ops = n.operands;
        if (ops.length < 2) return false;
        final dst = ops[0];
        final src = ops[1];
        return dst is BaseReg && dst.isPhysical && src is X86Mem && _isFrameBase(src);
      });

      expect(hasStore, isTrue, reason: 'arg deve ser salvo em stack');
      expect(hasLoad, isTrue, reason: 'arg deve ser recarregado da stack');
    });
  });
}

// Custom matcher helper
final Matcher isPhysicalReg =
    predicate((x) => x is BaseReg && x.isPhysical, "is physical register");

// Helper to ignore specific ID but check physical
final Matcher changesAccordingToAllocation = anything;
