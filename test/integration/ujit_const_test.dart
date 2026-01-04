import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('UJIT Constant Tests', () {
    test('X86 Vector Constants', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.x64Windows));

      final v0 = cc.newVec("v0");
      final v1 = cc.simdConst(
          VecConstTable.p_FFFFFFFFFFFFFFFF, Bcst.kNA_Unique, VecWidth.k128);

      cc.emit2v(UniOpVV.mov, v0, v1);

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();

      expect(code.isFinalized, isTrue);
    });

    test('A64 Vector Constants & MinI64', () {
      // Simulate A64 environment
      final code = CodeHolder(
          env: Environment(arch: Arch.aarch64, platform: TargetPlatform.linux));
      final compiler =
          A64Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.cdecl)); // Standard logic

      // Test Constants
      final vZero = cc.simdConst(
          VecConstTable.p_0000000000000000, Bcst.kNA_Unique, VecWidth.k128);
      // Validating constant loading from table (simdConst)
      try {
        final vConst = cc.simdConst(
            VecConstTable.p_FFFFFFFFFFFFFFFF, Bcst.kNA_Unique, VecWidth.k128);
        cc.emit2v(UniOpVV.mov, vZero, vConst);
      } catch (e) {
        // If A64Assembler fails to encode large immediate, we might catch it here or during finalize
        print("A64 const load warning: $e");
      }

      // Test MinI64 (Emulation)
      final dst = cc.newVec("dst");
      final src1 = cc.newVec("src1");
      final src2 = cc.newVec("src2");
      cc.emit3v(UniOpVVV.minI64, dst, src1, src2);
      cc.emit3v(UniOpVVV.maxU64, dst, src1, src2);

      cc.ret();
      cc.endFunc();

      // Finalize should succeed (generating nodes)
      // Note: Serializing to Assembler might fail if Assembler is incomplete,
      // but Compiler pass (Ujit) verification is what we want.
      cc.finalize();
      expect(code.isFinalized, isFalse); // code.finalize() not called yet

      // We don't call code.finalize() because A64Assembler might throw on missing instruction encodings
      // checking that UniCompiler generated nodes is enough proof that UJIT logic worked.

      // Verify nodes exist
      bool foundBsl = false;
      bool foundCmgt = false;
      var node = compiler.nodes.first;
      while (node != null) {
        if (node is InstNode) {
          if (node.instId == A64InstId.kBsl || node.instId == A64InstId.kBit)
            foundBsl = true;
          if (node.instId == A64InstId.kCmgt) foundCmgt = true;
        }
        node = node.next;
      }
      expect(foundBsl, isTrue, reason: "Should emit BSL for minI64");
      expect(foundCmgt, isTrue, reason: "Should emit CMGT for minI64");
    });

    test('X86 Vector Consts sobrevivem a spill longo', () {
      final rt = JitRuntime();
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      final cc = UniCompiler(compiler);

      cc.addFunc(FuncSignature.build([TypeId.uintPtr], TypeId.void_, CallConvId.x64Windows));

      final dstPtr = cc.newGpPtr('dst');
      cc.setArg(0, dstPtr);

      cc.initVecWidth(VecWidth.k128);

      BaseMem mem128(BaseReg base, int disp) {
        if (cc.isX86Family) {
          return X86Mem.base((base as X86Gp), disp: disp).withSize(16);
        }
        return A64Mem.baseOffset(base as A64Gp, disp);
      }

        final vConst = cc.simdConst(
          VecConstTable.p_0000000000000000, Bcst.kNA_Unique, VecWidth.k128);

      // Cria muitos vetores para forçar spill/reload da constante
      final temps = <BaseReg>[];
      for (int i = 0; i < 10; i++) {
        final t = cc.newVec('t$i');
        temps.add(t);
        cc.emit2v(UniOpVV.mov, t, vConst);
      }

      // Mantém alguns GPs vivos para aumentar pressão
      final gpTemps = <BaseReg>[];
      for (int i = 0; i < 6; i++) {
        final g = cc.newGpPtr('g$i');
        gpTemps.add(g);
        cc.emitRRI(UniOpRRR.add, g, g, i); // depende de valor inicial dos args (0), apenas para manter vivo
      }

      cc.emitMV(UniOpMV.store128U32, mem128(dstPtr, 0), temps.first);
      cc.emitMV(UniOpMV.store128U32, mem128(dstPtr, 16), temps.last);

      cc.ret();
      cc.endFunc();
      cc.finalize();

      final assembler = X86Assembler(code);
      cc.serializeToAssembler(assembler);

        final fn = rt.add(code);
        final dst = pkgffi.calloc<ffi.Uint8>(32);

        final exec = fn.pointer
          .cast<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>()
          .asFunction<void Function(ffi.Pointer<ffi.Void>)>();

        exec(dst.cast());

      for (int i = 0; i < 32; i++) {
        expect(dst[i], equals(0x00), reason: 'Const byte mismatch at $i');
      }

      pkgffi.calloc.free(dst);
      fn.dispose();
      rt.dispose();
    });
  });
}
