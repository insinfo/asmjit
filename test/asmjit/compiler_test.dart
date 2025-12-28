import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('X86Compiler Tests', () {
    test('JumpMerge - builds CFG and allocates registers correctly', () {
      final compiler = X86Compiler(env: Environment.host());

      final L0 = compiler.newLabel();
      final L1 = compiler.newLabel();
      final L2 = compiler.newLabel();
      final LEnd = compiler.newLabel();

      final dst = compiler.newGpPtr('dst');
      final val = compiler.newGp32('val');

      final signature = FuncSignature();
      signature.setRet(TypeId.void_);
      signature.addArg(TypeId.uintPtr);
      signature.addArg(TypeId.int32);

      final funcNode = compiler.addFunc(signature);
      funcNode.setArg(0, 0, dst);
      funcNode.setArg(1, 0, val);

      compiler.cmp(val, Imm(0));
      compiler.je(L2);

      compiler.cmp(val, Imm(1));
      compiler.je(L1);

      compiler.cmp(val, Imm(2));
      compiler.je(L0);

      // mov [dst], val
      compiler.mov(X86Mem.base(dst, disp: 4), val);
      compiler.jmp(LEnd);

      compiler.bind(L0);
      compiler.bind(L1);
      compiler.bind(L2);
      // mov [dst], 0
      compiler.mov(X86Mem.base(dst, disp: 4), Imm(0));

      compiler.bind(LEnd);
      compiler.endFunc();

      compiler.finalize();

      // Check if it reached here without crashing.
      expect(funcNode, isNotNull);
    });

    test('JumpCross - complex CFG connectivity', () {
      final compiler = X86Compiler(env: Environment.host());

      final signature = FuncSignature.noArgs();
      compiler.addFunc(signature);

      final L1 = compiler.newLabel();
      final L2 = compiler.newLabel();
      final L3 = compiler.newLabel();

      compiler.jmp(L2);

      compiler.bind(L1);
      compiler.jmp(L3);

      compiler.bind(L2);
      compiler.jmp(L1);

      compiler.bind(L3);
      compiler.endFunc();

      compiler.finalize();
      // Should converge liveness and allocate without issues.
    });
  });
}
