import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';
import 'package:asmjit/src/asmjit/ujit/unicompiler.dart';

void main() {
  group('UniCompiler', () {
    test('Basic GP and CMOV/Select', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.x64Windows));

      final a = cc.newGp32("a");
      final b = cc.newGp32("b");
      final r = cc.newGp32("r");

      cc.emitMov(a, Imm(10));
      cc.emitMov(b, Imm(20));

      // select: r = (a < b) ? a : b (min)
      cc.emitSelect(UniCondition.ucmp_lt(a, b), r, a, b);

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();

      // Ensure code is finalized
      expect(code.isFinalized, isTrue);
    });

    test('SIMD load/store (VM/MV)', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.x64Windows));

      final v = cc.newXmm("v");
      final mem = X86Mem.abs(0x1234, size: 16);

      cc.emitVM(UniOpVM.load128U32, v, mem);
      cc.emitMV(UniOpMV.store128U32, mem, v);

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();

      expect(code.isFinalized, isTrue);
    });

    test('Scalar SIMD Load/Store', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.x64Windows));

      final v = cc.newXmm("v");
      final mem = X86Mem.abs(0x3456, size: 4);

      // load32U32 -> movd
      cc.emitVM(UniOpVM.load32U32, v, mem);

      // store32U32 -> movd
      cc.emitMV(UniOpMV.store32U32, mem, v);

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();

      expect(code.isFinalized, isTrue);
    });

    test('Vector Constants', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.x64Windows));
      cc.hookFunc(); // Required for constants

      final v = cc.newVec("v");
      final c = cc.simdVecConst(
          VecConstTable.p_0000000000000000, Bcst.kNA, VecWidth.k128);

      cc.vMov(v, c);

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();

      expect(code.isFinalized, isTrue);
    });
  });
}
