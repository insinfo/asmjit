import 'dart:ffi';
import 'package:ffi/ffi.dart' as ffi;
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

typedef SimdFunc = Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef SimdDart = void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);

void main() {
  group('X86 SIMD Detailed Instruction Verification', () {
    late JitRuntime rt;

    setUp(() {
      rt = JitRuntime();
    });

    tearDown(() {
      rt.dispose();
    });

    // Helper to run a 2-operand SIMD instruction test
    // dst = op(src1, src2) or dst = op(dst, src)
    void testBinaryInt32(
      String name,
      int instId,
      List<int> src1Vals,
      List<int> src2Vals,
      List<int> expectedVals, {
      bool useAvx = false,
    }) {
      test('$name (${useAvx ? "AVX" : "SSE"})', () {
        if (useAvx && !CpuInfo.host().features.avx) {
          print('Skipping $name: AVX not supported');
          return;
        }

        final code = CodeHolder(env: Environment.host());
        final compiler =
            X86Compiler(env: code.env, labelManager: code.labelManager);

        final signature = FuncSignature(
            retType: TypeId.void_,
            args: [TypeId.uintPtr, TypeId.uintPtr, TypeId.uintPtr]);
        compiler.addFunc(signature);

        final isWindows = compiler.env.platform == TargetPlatform.windows;
        print('isWindows $isWindows');
        final dstReg = isWindows ? rcx : rdi;
        final src1Reg = isWindows ? rdx : rsi;
        final src2Reg = isWindows ? r8 : rdx;

        final xmm0 = compiler.newXmm('xmm0');
        final xmm1 = compiler.newXmm('xmm1');
        final xmm2 = compiler.newXmm('xmm2');

        // Load src1 -> xmm0
        if (useAvx) {
          compiler.inst(X86InstId.kVmovdqu, [xmm0, X86Mem.ptr(src1Reg)]);
          compiler.inst(X86InstId.kVmovdqu, [xmm1, X86Mem.ptr(src2Reg)]);
          // inst xmm2, xmm0, xmm1
          compiler.inst(instId, [xmm2, xmm0, xmm1]);
          compiler.inst(X86InstId.kVmovdqu, [X86Mem.ptr(dstReg), xmm2]);
        } else {
          compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(src1Reg)]);
          compiler.inst(X86InstId.kMovdqu, [xmm1, X86Mem.ptr(src2Reg)]);
          // inst xmm0, xmm1 (destructive)
          compiler.inst(instId, [xmm0, xmm1]);
          compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg), xmm0]);
        }

        compiler.ret();
        compiler.endFunc();
        compiler.finalize();

        final assembler = X86Assembler(code);
        compiler.serializeToAssembler(assembler);

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

    // PADDD / VPADDD
    testBinaryInt32('paddd', X86InstId.kPaddd, [10, 20, 0xFFFFFFFF, 0],
        [5, 30, 1, 0xFFFFFFFF], [15, 50, 0, 0xFFFFFFFF],
        useAvx: false);

    testBinaryInt32('vpaddd', X86InstId.kVpaddd, [10, 20, 0xFFFFFFFF, 0],
        [5, 30, 1, 0xFFFFFFFF], [15, 50, 0, 0xFFFFFFFF],
        useAvx: true);

    // PXOR / VPXOR
    testBinaryInt32(
        'pxor',
        X86InstId.kPxor,
        [0x0F0F0F0F, 0xAAAAAAAA, 0, 0xFFFFFFFF],
        [0x00FF00FF, 0x55555555, 0xFFFFFFFF, 0],
        [0x0FF00FF0, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF],
        useAvx: false);

    testBinaryInt32(
        'vpxor',
        X86InstId.kVpxor,
        [0x0F0F0F0F, 0xAAAAAAAA, 0, 0xFFFFFFFF],
        [0x00FF00FF, 0x55555555, 0xFFFFFFFF, 0],
        [0x0FF00FF0, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF],
        useAvx: true);

    // Rotation Simulation (ChaCha20 uses `v << n | v >> (32-n)`)
    // Tests pslld, psrld, por sequence
    void testRotate32(String name, int rot, {bool useAvx = false}) {
      test('Rotate Left 32-bit by $rot ($name)', () {
        if (useAvx && !CpuInfo.host().features.avx) return;

        final code = CodeHolder(env: Environment.host());
        final compiler =
            X86Compiler(env: code.env, labelManager: code.labelManager);

        final signature = FuncSignature(
            retType: TypeId.void_,
            args: [TypeId.uintPtr, TypeId.uintPtr]); // dst, src
        compiler.addFunc(signature);

        final isWindows = compiler.env.platform == TargetPlatform.windows;
        final dstReg = isWindows ? rcx : rdi;
        final srcReg = isWindows ? rdx : rsi;

        final xmm0 = compiler.newXmm('xmm0');
        final xmm1 = compiler.newXmm('xmm1');

        if (useAvx) {
          compiler.inst(X86InstId.kVmovdqu, [xmm0, X86Mem.ptr(srcReg)]);
          // Copy for SR: vmovdqa xmm1, xmm0
          compiler.inst(X86InstId.kVmovdqa, [xmm1, xmm0]);
          // SL: vpslld xmm0, xmm0, rot
          compiler.inst(X86InstId.kVpslld, [xmm0, xmm0, Imm(rot)]);
          // SR: vpsrld xmm1, xmm1, 32-rot
          compiler.inst(X86InstId.kVpsrld, [xmm1, xmm1, Imm(32 - rot)]);
          // OR: vpor xmm0, xmm0, xmm1
          compiler.inst(X86InstId.kVpor, [xmm0, xmm0, xmm1]);
          compiler.inst(X86InstId.kVmovdqu, [X86Mem.ptr(dstReg), xmm0]);
        } else {
          compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(srcReg)]);
          compiler.inst(X86InstId.kMovdqa, [xmm1, xmm0]);

          compiler.inst(X86InstId.kPslld, [xmm0, Imm(rot)]);
          compiler.inst(X86InstId.kPsrld, [xmm1, Imm(32 - rot)]);

          compiler.inst(X86InstId.kPor, [xmm0, xmm1]);
          compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg), xmm0]);
        }

        compiler.ret();
        compiler.endFunc();
        compiler.finalize();

        final assembler = X86Assembler(code);
        compiler.serializeToAssembler(assembler);

        final fn = rt.add(code);
        final dst = ffi.calloc<Uint32>(4);
        final src = ffi.calloc<Uint32>(4);

        // Test patterns
        src[0] = 0x80000000; // Single bit
        src[1] = 0x00000001;
        src[2] = 0xF0F0F0F0;
        src[3] = 0xAABBCCDD;

        final exec = fn.pointer
            .cast<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>()
            .asFunction<void Function(Pointer<Void>, Pointer<Void>)>();

        exec(dst.cast(), src.cast());

        // Check logic in Dart
        for (int i = 0; i < 4; i++) {
          final val = src[i];
          final expected = ((val << rot) | (val >>> (32 - rot))) & 0xFFFFFFFF;
          expect(dst[i], equals(expected),
              reason: 'Rotation $rot mismatch at $i');
        }

        ffi.calloc.free(dst);
        ffi.calloc.free(src);
      });
    }

    testRotate32('SSE Rotate 16', 16, useAvx: false);
    testRotate32('SSE Rotate 12', 12, useAvx: false);
    testRotate32('SSE Rotate 8', 8, useAvx: false);
    testRotate32('SSE Rotate 7', 7, useAvx: false);

    testRotate32('AVX Rotate 16', 16, useAvx: true);
    testRotate32('AVX Rotate 12', 12, useAvx: true);
    testRotate32('AVX Rotate 8', 8, useAvx: true);
    testRotate32('AVX Rotate 7', 7, useAvx: true);

    void testRotateRight32(String name, int rot, {bool useAvx = false}) {
      test('Rotate Right 32-bit by $rot ($name)', () {
        if (useAvx && !CpuInfo.host().features.avx) return;

        final code = CodeHolder(env: Environment.host());
        final compiler =
            X86Compiler(env: code.env, labelManager: code.labelManager);

        final signature = FuncSignature(
            retType: TypeId.void_, args: [TypeId.uintPtr, TypeId.uintPtr]);
        compiler.addFunc(signature);

        final isWindows = compiler.env.platform == TargetPlatform.windows;
        final dstReg = isWindows ? rcx : rdi;
        final srcReg = isWindows ? rdx : rsi;

        final xmm0 = compiler.newXmm('xmm0');
        final xmm1 = compiler.newXmm('xmm1');

        if (useAvx) {
          compiler.inst(X86InstId.kVmovdqu, [xmm0, X86Mem.ptr(srcReg)]);
          compiler.inst(X86InstId.kVmovdqa, [xmm1, xmm0]);
          compiler.inst(X86InstId.kVpsrld, [xmm0, xmm0, Imm(rot)]);
          compiler.inst(X86InstId.kVpslld, [xmm1, xmm1, Imm(32 - rot)]);
          compiler.inst(X86InstId.kVpor, [xmm0, xmm0, xmm1]);
          compiler.inst(X86InstId.kVmovdqu, [X86Mem.ptr(dstReg), xmm0]);
        } else {
          compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(srcReg)]);
          compiler.inst(X86InstId.kMovdqa, [xmm1, xmm0]);
          compiler.inst(X86InstId.kPsrld, [xmm0, Imm(rot)]);
          compiler.inst(X86InstId.kPslld, [xmm1, Imm(32 - rot)]);
          compiler.inst(X86InstId.kPor, [xmm0, xmm1]);
          compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg), xmm0]);
        }

        compiler.ret();
        compiler.endFunc();
        compiler.finalize();

        final assembler = X86Assembler(code);
        compiler.serializeToAssembler(assembler);

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

        for (int i = 0; i < 4; i++) {
          final val = src[i];
          final expected = ((val >>> rot) | (val << (32 - rot))) & 0xFFFFFFFF;
          expect(dst[i], equals(expected),
              reason: 'Rotate right $rot mismatch at $i');
        }

        ffi.calloc.free(dst);
        ffi.calloc.free(src);
      });
    }

    testRotateRight32('SSE Rotate Right 16', 16, useAvx: false);
    testRotateRight32('SSE Rotate Right 8', 8, useAvx: false);
    testRotateRight32('AVX Rotate Right 16', 16, useAvx: true);
    testRotateRight32('AVX Rotate Right 8', 8, useAvx: true);

    // Test PSHUFD / VPSHUFD
    void testShuffle(String name, int imm, List<int> input, List<int> expected,
        {bool useAvx = false}) {
      test('$name imm=0x${imm.toRadixString(16)}', () {
        if (useAvx && !CpuInfo.host().features.avx) return;

        final code = CodeHolder(env: Environment.host());
        final compiler =
            X86Compiler(env: code.env, labelManager: code.labelManager);

        final signature = FuncSignature(
            retType: TypeId.void_, args: [TypeId.uintPtr, TypeId.uintPtr]);
        compiler.addFunc(signature);

        final isWindows = compiler.env.platform == TargetPlatform.windows;
        final dstReg = isWindows ? rcx : rdi;
        final srcReg = isWindows ? rdx : rsi;

        final xmm0 = compiler.newXmm('xmm0');

        if (useAvx) {
          compiler.inst(X86InstId.kVmovdqu, [xmm0, X86Mem.ptr(srcReg)]);
          compiler.inst(X86InstId.kVpshufd, [xmm0, xmm0, Imm(imm)]);
          compiler.inst(X86InstId.kVmovdqu, [X86Mem.ptr(dstReg), xmm0]);
        } else {
          compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(srcReg)]);
          compiler.inst(X86InstId.kPshufd, [xmm0, xmm0, Imm(imm)]);
          compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg), xmm0]);
        }

        compiler.ret();
        compiler.endFunc();
        compiler.finalize();

        final assembler = X86Assembler(code);
        compiler.serializeToAssembler(assembler);

        final fn = rt.add(code);
        final dst = ffi.calloc<Uint32>(4);
        final src = ffi.calloc<Uint32>(4);

        for (int i = 0; i < 4; i++) src[i] = input[i];

        final exec = fn.pointer
            .cast<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>()
            .asFunction<void Function(Pointer<Void>, Pointer<Void>)>();

        exec(dst.cast(), src.cast());

        for (int i = 0; i < 4; i++) {
          expect(dst[i], equals(expected[i]), reason: 'Shuffle match');
        }

        ffi.calloc.free(dst);
        ffi.calloc.free(src);
      });
    }

    // ChaCha20 Rotations via PSHUFD:
    // Left 1: Indices [1, 2, 3, 0] -> Imm: (1<<0)|(2<<2)|(3<<4)|(0<<6) = 1 | 8 | 48 | 0 = 57 (0x39)
    testShuffle('SSE PSHUFD Rot 1', 0x39, [0, 1, 2, 3], [1, 2, 3, 0],
        useAvx: false);
    // Left 2: Indices [2, 3, 0, 1] -> Imm: (2)|(3<<2)|(0)|(1<<6) = 2 | 12 | 0 | 64 = 78 (0x4E)
    testShuffle('SSE PSHUFD Rot 2', 0x4E, [0, 1, 2, 3], [2, 3, 0, 1],
        useAvx: false);
    // Left 3: Indices [3, 0, 1, 2] -> Imm: (3)|(0)|(1<<4)|(2<<6) = 3 | 0 | 16 | 128 = 147 (0x93)
    testShuffle('SSE PSHUFD Rot 3', 0x93, [0, 1, 2, 3], [3, 0, 1, 2],
        useAvx: false);

    testShuffle('AVX VPSHUFD Rot 1', 0x39, [0, 1, 2, 3], [1, 2, 3, 0],
        useAvx: true);
    testShuffle('AVX VPSHUFD Rot 2', 0x4E, [0, 1, 2, 3], [2, 3, 0, 1],
        useAvx: true);
    testShuffle('AVX VPSHUFD Rot 3', 0x93, [0, 1, 2, 3], [3, 0, 1, 2],
        useAvx: true);
  });
}
