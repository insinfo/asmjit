import 'dart:ffi';
import 'package:ffi/ffi.dart' as ffi;
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

typedef SimdFunc = Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef SimdDart = void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);

void main() {
  group('UniCompiler SIMD High-Level Verification', () {
    late JitRuntime rt;

    setUp(() {
      rt = JitRuntime();
    });

    tearDown(() {
      rt.dispose();
    });

    void testUniBinary(
      String name,
      UniOpVVV op,
      List<int> src1Vals,
      List<int> src2Vals,
      List<int> expectedVals,
    ) {
      test(name, () {
        final code = CodeHolder(env: Environment.host());
        final cc = UniCompiler.auto(code: code);

        final signature = FuncSignature(retType: TypeId.void_, args: [
          TypeId.uintPtr,
          TypeId.uintPtr,
          TypeId.uintPtr
        ]); // dst, src1, src2
        cc.addFunc(signature);

        final dstPtr = cc.newGpPtr('dstPtr');
        final src1Ptr = cc.newGpPtr('src1Ptr');
        final src2Ptr = cc.newGpPtr('src2Ptr');

        cc.setArg(0, dstPtr);
        cc.setArg(1, src1Ptr);
        cc.setArg(2, src2Ptr);

        cc.initVecWidth(VecWidth.k128); // 128-bit SIMD

        final v0 = cc.newVec('v0');
        final v1 = cc.newVec('v1');
        final v2 = cc.newVec('v2');

        // Load src1 -> v0
        // Use manual load for UniCompiler? use emitVM with load128U32
        // _mem128 helper similar to ChaCha20
        BaseMem mem128(BaseReg base) {
          if (cc.isX86Family) return X86Mem.ptr(base as X86Gp).withSize(16);
          return A64Mem.baseOffset(base as A64Gp, 0); // offset 0
        }

        cc.emitVM(UniOpVM.load128U32, v0, mem128(src1Ptr));
        cc.emitVM(UniOpVM.load128U32, v1, mem128(src2Ptr));

        cc.emit3v(op, v2, v0, v1);

        cc.emitMV(UniOpMV.store128U32, mem128(dstPtr), v2);

        cc.ret();
        cc.endFunc();
        cc.finalize();

        final assembler = X86Assembler(code);
        cc.serializeToAssembler(assembler);

        final fn = rt.add(code);

        final dst = ffi.calloc<Uint32>(4);
        final src1 = ffi.calloc<Uint32>(4);
        final src2 = ffi.calloc<Uint32>(4);

        for (int i = 0; i < 4; i++) {
          src1[i] = src1Vals[i];
          src2[i] = src2Vals[i];
        }

        final exec =
            fn.pointer.cast<NativeFunction<SimdFunc>>().asFunction<SimdDart>();
        exec(dst.cast(), src1.cast(), src2.cast());

        for (int i = 0; i < 4; i++) {
          expect(dst[i], equals(expectedVals[i]),
              reason: 'Mismatch at index $i for $name');
        }

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
        ffi.calloc.free(src2);
      });
    }

    testUniBinary('UniOpVVV.addU32', UniOpVVV.addU32, [10, 20, 0xFFFFFFFF, 0],
        [5, 30, 1, 0xFFFFFFFF], [15, 50, 0, 0xFFFFFFFF]);

    testUniBinary(
        'UniOpVVV.xorU32',
        UniOpVVV.xorU32,
        [0x0F0F0F0F, 0xAAAAAAAA, 0, 0xFFFFFFFF],
        [0x00FF00FF, 0x55555555, 0xFFFFFFFF, 0],
        [0x0FF00FF0, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]);

    // Test Rotate Logic using UniCompiler calls
    test('UniCompiler ChaCha Rotate Logic (16)', () {
      final code = CodeHolder(env: Environment.host());
      final cc = UniCompiler.auto(code: code);
      cc.addFunc(FuncSignature(
          retType: TypeId.void_, args: [TypeId.uintPtr, TypeId.uintPtr]));

      final dstPtr = cc.newGpPtr('dstPtr');
      final srcPtr = cc.newGpPtr('srcPtr');
      cc.setArg(0, dstPtr);
      cc.setArg(1, srcPtr);

      cc.initVecWidth(VecWidth.k128);
      final v = cc.newVec('v');
      final tmp = cc.newVec('tmp');

      BaseMem mem128(BaseReg base) {
        if (cc.isX86Family) return X86Mem.ptr(base as X86Gp).withSize(16);
        return A64Mem.baseOffset(base as A64Gp, 0); // offset 0
      }

      cc.emitVM(UniOpVM.load128U32, v, mem128(srcPtr));

      // _rotateBits(cc, v, 16, tmp) logic from ChaCha20
      int n = 16;
      cc.emit2v(UniOpVV.mov, tmp, v);
      cc.emit2vi(UniOpVVI.sllU32, v, v, n);
      cc.emit2vi(UniOpVVI.srlU32, tmp, tmp, 32 - n);
      cc.emit3v(UniOpVVV.orU32, v, v, tmp);

      cc.emitMV(UniOpMV.store128U32, mem128(dstPtr), v);
      cc.ret();
      cc.endFunc();
      cc.finalize();

      final assembler = X86Assembler(code);
      cc.serializeToAssembler(assembler);

      final fn = rt.add(code);
      final dst = ffi.calloc<Uint32>(4);
      final src = ffi.calloc<Uint32>(4);
      src[0] = 0x80000000;
      src[1] = 0x00000001;
      src[2] = 0xF0F0F0F0;
      src[3] = 0xAABBCCDD;

      final exec = fn.pointer
          .cast<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>()
          .asFunction<void Function(Pointer<Void>, Pointer<Void>)>();
      exec(dst.cast(), src.cast());

      final rot = 16;
      for (int i = 0; i < 4; i++) {
        final expected =
            ((src[i] << rot) | (src[i] >>> (32 - rot))) & 0xFFFFFFFF;
        expect(dst[i], equals(expected), reason: 'Rotate 16 failed');
      }

      ffi.calloc.free(dst);
      ffi.calloc.free(src);
    });
  });
}
