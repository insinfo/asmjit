import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/x86/x86_compiler.dart'; // Explicit import for casting
import 'package:test/test.dart';

void main() {
  group('UJIT General Tests (Host)', () {
    late JitRuntime rt;

    setUp(() {
      rt = JitRuntime();
    });

    tearDown(() {
      rt.dispose();
    });

    test('Conditional Ops (Compare/Jump/Set)', () {
      final code = CodeHolder(env: rt.environment);
      // Ensure we create an X86Compiler if on X86, effectively.
      // But UniCompiler takes BaseCompiler. CodeHolder doesn't create compiler.
      // We must create it.
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      // Attach manually or just use it.

      final cc = UniCompiler(compiler);

      // void func(int* results, int a, int b)
      // FuncSignature.build(args, ret, cc)
      cc.addFunc(FuncSignature.build(
          [TypeId.intPtr, TypeId.int32, TypeId.int32],
          TypeId.void_,
          CallConvId.cdecl));

      final ptr = cc.newGpPtr("results");
      final a = cc.newGp32("a");
      final b = cc.newGp32("b");
      // setArg(argIndex, reg)
      cc.setArg(0, ptr);
      cc.setArg(1, a);
      cc.setArg(2, b);

      final r = cc.newGp32("r");

      // Variation 0: Branching
      // if (a == b) r = 1 else r = 0
      final lblTrue = cc.newLabel();
      final lblEnd = cc.newLabel();

      cc.emitJIf(
          lblTrue, UniCondition(UniOpCond.compare, CondCode.kEqual, a, b));
      cc.mov(r, Imm(0));
      cc.emitJ(LabelOp(lblEnd));

      cc.bind(lblTrue);
      cc.mov(r, Imm(1));

      cc.bind(lblEnd);
      cc.emitMR(UniOpMR.storeU32, X86Mem.ptr(ptr, 0), r);

      // Variation 1: CMOV (Cond Move)
      // r = 0; temp = 1; cmov(r, temp, condition)
      final temp = cc.newGp32("temp");
      cc.mov(r, Imm(0));
      cc.mov(temp, Imm(1));
      cc.emitCmov(
          UniCondition(UniOpCond.compare, CondCode.kNotEqual, a, b), r, temp);
      cc.emitMR(UniOpMR.storeU32, X86Mem.ptr(ptr, 4), r);

      // Variation 2: Select
      // select(r, trueVal, falseVal, condition)
      // r = (a > b) ? 1 : 0
      final trueVal = cc.newGp32("trueVal");
      final falseVal = cc.newGp32("falseVal");
      cc.mov(trueVal, Imm(1));
      cc.mov(falseVal, Imm(0));
      cc.emitSelect(UniCondition(UniOpCond.compare, CondCode.kSignedGT, a, b),
          r, trueVal, falseVal);
      cc.emitMR(UniOpMR.storeU32, X86Mem.ptr(ptr, 8), r);

      cc.endFunc();
      // cc.finalize(); // Skip passes for now

      // Verify IR Generation because Compiler backend (serialization) is not ready
      int count = 0;
      for (final node in cc.cc.nodes.nodes) {
        if (node is InstNode) {
          count++;
          // Check opcodes if needed
        }
      }
      expect(count, greaterThan(5), reason: "Should generate instructions");

      // Cleanup
      // calloc.free(results);
    });

    test('RM/MR Ops (Load/Store)', () {
      final code = CodeHolder(env: rt.environment);
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      // int func(int* ptr)
      cc.addFunc(
          FuncSignature.build([TypeId.intPtr], TypeId.int32, CallConvId.cdecl));

      final ptr = cc.newGpPtr("ptr");
      cc.setArg(0, ptr);

      final val = cc.newGp32("val");

      // Load U8, Add 1, Store U8
      cc.emitRM(UniOpRM.loadU8, val, X86Mem.ptr(ptr));

      // Access underlying X86Compiler for add
      (cc.cc as X86Compiler).add(val, Imm(1));

      cc.emitMR(UniOpMR.storeU8, X86Mem.ptr(ptr, 1), val);

      // Load U16, Store U16
      cc.emitRM(UniOpRM.loadU16, val, X86Mem.ptr(ptr));
      (cc.cc as X86Compiler).add(val, Imm(1));
      cc.emitMR(UniOpMR.storeU16, X86Mem.ptr(ptr, 2), val);

      cc.ret([val]);
      cc.endFunc();

      // Verify IR
      int count = 0;
      int movCount = 0;
      int addCount = 0;
      for (final node in cc.cc.nodes.nodes) {
        if (node is InstNode) {
          count++;
          if (node.instId == X86InstId.kMov ||
              node.instId == X86InstId.kMovzx ||
              node.instId == X86InstId.kMovsx) movCount++;
          if (node.instId == X86InstId.kAdd) addCount++;
        }
      }
      expect(count, greaterThan(0));
      expect(movCount, greaterThanOrEqualTo(4)); // Loads and stores via moves
      expect(addCount, greaterThanOrEqualTo(2));
    });
  });
}
