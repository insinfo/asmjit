import 'dart:ffi';
import 'package:ffi/ffi.dart' as ffi;
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

typedef SimdFunc = Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef SimdDart = void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);

void main() {
  group('X86Compiler SIMD Integration Tests', () {
    late JitRuntime rt;

    setUp(() {
      rt = JitRuntime();
    });

    tearDown(() {
      rt.dispose();
    });

    test('SSE2 Integer Vector Addition (paddd)', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature = FuncSignature(
          retType: TypeId.void_,
          args: [TypeId.uintPtr, TypeId.uintPtr, TypeId.uintPtr]);

      compiler.addFunc(signature);

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final dstReg = isWindows ? rcx : rdi;
      final src1Reg = isWindows ? rdx : rsi;
      final src2Reg = isWindows ? r8 : rdx;

      final xmm0 = compiler.newXmm('xmm0');
      final xmm1 = compiler.newXmm('xmm1');

      // movdqu xmm0, [src1]
      compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(src1Reg)]);
      // movdqu xmm1, [src2]
      compiler.inst(X86InstId.kMovdqu, [xmm1, X86Mem.ptr(src2Reg)]);
      // paddd xmm0, xmm1
      compiler.inst(X86InstId.kPaddd, [xmm0, xmm1]);
      // movdqu [dst], xmm0
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg), xmm0]);

      compiler.ret();
      compiler.endFunc();

      print("Nodes before finalize: ${compiler.nodes.length}");
      for (var node = compiler.nodes.first; node != null; node = node.next) {
        print("Node: ${node.nodeType} ${node is InstNode ? node.instId : ''}");
      }

      compiler.finalize();

      print("Nodes after finalize: ${compiler.nodes.length}");
      for (var node = compiler.nodes.first; node != null; node = node.next) {
        print("Node: ${node.nodeType} ${node is InstNode ? node.instId : ''}");
      }

      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final finalized = code.finalize();
      print("SSE2 Hex Dump:\n${AsmFormatter.hexDump(finalized.textBytes)}");
      print("Platform: ${compiler.env.platform}");

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<SimdFunc>>()
            .asFunction<SimdDart>();

        final dst = ffi.calloc<Int32>(4);
        final src1 = ffi.calloc<Int32>(4);
        final src2 = ffi.calloc<Int32>(4);

        for (int i = 0; i < 4; i++) {
          src1[i] = i * 10;
          src2[i] = i;
        }

        exec(dst.cast(), src1.cast(), src2.cast());

        for (int i = 0; i < 4; i++) {
          expect(dst[i], equals(i * 11));
        }

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
        ffi.calloc.free(src2);
      } finally {
        fn.dispose();
      }
    });

    test('SSE2 Integer Vector Multiplication (pmullw)', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature = FuncSignature(
          retType: TypeId.void_,
          args: [TypeId.uintPtr, TypeId.uintPtr, TypeId.uintPtr]);

      compiler.addFunc(signature);

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final dstReg = isWindows ? rcx : rdi;
      final src1Reg = isWindows ? rdx : rsi;
      final src2Reg = isWindows ? r8 : rdx;

      final xmm0 = compiler.newXmm('xmm0');
      final xmm1 = compiler.newXmm('xmm1');

      // movdqu xmm0, [src1]
      compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(src1Reg)]);
      // movdqu xmm1, [src2]
      compiler.inst(X86InstId.kMovdqu, [xmm1, X86Mem.ptr(src2Reg)]);
      // pmullw xmm0, xmm1 (Multiply packed signed 16-bit integers)
      compiler.inst(X86InstId.kPmullw, [xmm0, xmm1]);
      // movdqu [dst], xmm0
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg), xmm0]);

      compiler.ret();
      compiler.endFunc();
      compiler.finalize();

      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<SimdFunc>>()
            .asFunction<SimdDart>();

        final dst = ffi.calloc<Int16>(8);
        final src1 = ffi.calloc<Int16>(8);
        final src2 = ffi.calloc<Int16>(8);

        for (int i = 0; i < 8; i++) {
          src1[i] = i + 1;
          src2[i] = 2;
        }

        exec(dst.cast(), src1.cast(), src2.cast());

        for (int i = 0; i < 8; i++) {
          expect(dst[i], equals((i + 1) * 2));
        }

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
        ffi.calloc.free(src2);
      } finally {
        fn.dispose();
      }
    });

    test('SSE2 Bitwise Operations (pand, por, pxor)', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature = FuncSignature(
          retType: TypeId.void_,
          args: [TypeId.uintPtr, TypeId.uintPtr, TypeId.uintPtr]);

      compiler.addFunc(signature);

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final dstReg = isWindows ? rcx : rdi;
      final src1Reg = isWindows ? rdx : rsi;
      final src2Reg = isWindows ? r8 : rdx;

      final xmm0 = compiler.newXmm('xmm0');
      final xmm1 = compiler.newXmm('xmm1');
      final xmm2 = compiler.newXmm('xmm2');

      // movdqu xmm0, [src1]
      compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(src1Reg)]);
      // movdqu xmm1, [src2]
      compiler.inst(X86InstId.kMovdqu, [xmm1, X86Mem.ptr(src2Reg)]);
      
      // pand xmm2, xmm0 (copy xmm0 to xmm2)
      compiler.inst(X86InstId.kMovdqu, [xmm2, xmm0]);
      // pand xmm2, xmm1 (xmm2 = xmm0 & xmm1)
      compiler.inst(X86InstId.kPand, [xmm2, xmm1]);
      
      // por xmm0, xmm1 (xmm0 = xmm0 | xmm1)
      compiler.inst(X86InstId.kPor, [xmm0, xmm1]);
      
      // pxor xmm1, xmm1 (xmm1 = 0)
      compiler.inst(X86InstId.kPxor, [xmm1, xmm1]);

      // Store results
      // [dst] = pand result
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg), xmm2]);
      // [dst + 16] = por result
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg, 16), xmm0]);
      // [dst + 32] = pxor result
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg, 32), xmm1]);

      compiler.ret();
      compiler.endFunc();
      compiler.finalize();

      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<SimdFunc>>()
            .asFunction<SimdDart>();

        final dst = ffi.calloc<Uint32>(12); // 3 vectors of 4 ints
        final src1 = ffi.calloc<Uint32>(4);
        final src2 = ffi.calloc<Uint32>(4);

        // src1: 0x0F0F0F0F, 0xF0F0F0F0, 0xFFFFFFFF, 0x00000000
        src1[0] = 0x0F0F0F0F;
        src1[1] = 0xF0F0F0F0;
        src1[2] = 0xFFFFFFFF;
        src1[3] = 0;

        // src2: 0x00FF00FF, 0xFF00FF00, 0xAAAAAAAA, 0x55555555
        src2[0] = 0x00FF00FF;
        src2[1] = 0xFF00FF00;
        src2[2] = 0xAAAAAAAA;
        src2[3] = 0x55555555;

        exec(dst.cast(), src1.cast(), src2.cast());

        // Check PAND (src1 & src2)
        expect(dst[0], equals(0x000F000F));
        expect(dst[1], equals(0xF000F000));
        expect(dst[2], equals(0xAAAAAAAA));
        expect(dst[3], equals(0));

        // Check POR (src1 | src2)
        // 0x0F0F0F0F | 0x00FF00FF = 0x0FFF0FFF
        expect(dst[4], equals(0x0FFF0FFF));
        expect(dst[5], equals(0xFFF0FFF0));
        expect(dst[6], equals(0xFFFFFFFF));
        expect(dst[7], equals(0x55555555));

        // Check PXOR (0)
        expect(dst[8], equals(0));
        expect(dst[9], equals(0));
        expect(dst[10], equals(0));
        expect(dst[11], equals(0));

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
        ffi.calloc.free(src2);
      } finally {
        fn.dispose();
      }
    });

    test('SSE2 Integer Arithmetic (psubd, pslld, psrld, pcmpeqd)', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature = FuncSignature(
          retType: TypeId.void_,
          args: [TypeId.uintPtr, TypeId.uintPtr, TypeId.uintPtr]);

      compiler.addFunc(signature);

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final dstReg = isWindows ? rcx : rdi;
      final src1Reg = isWindows ? rdx : rsi;
      final src2Reg = isWindows ? r8 : rdx;

      final xmm0 = compiler.newXmm('xmm0');
      final xmm1 = compiler.newXmm('xmm1');
      final xmm2 = compiler.newXmm('xmm2');
      final xmm3 = compiler.newXmm('xmm3');
      final xmm4 = compiler.newXmm('xmm4');
      final xmm5 = compiler.newXmm('xmm5');

      // movdqu xmm0, [src1]
      compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(src1Reg)]);
      // movdqu xmm1, [src2]
      compiler.inst(X86InstId.kMovdqu, [xmm1, X86Mem.ptr(src2Reg)]);

      // 1. psubd xmm2, xmm1 (xmm2 = xmm0 - xmm1)
      compiler.inst(X86InstId.kMovdqu, [xmm2, xmm0]);
      compiler.inst(X86InstId.kPsubd, [xmm2, xmm1]);
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg), xmm2]);

      // 2. pslld xmm3, 2 (xmm3 = xmm0 << 2)
      compiler.inst(X86InstId.kMovdqu, [xmm3, xmm0]);
      compiler.inst(X86InstId.kPslld, [xmm3, Imm(2)]);
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg, 16), xmm3]);

      // 3. psrld xmm4, 2 (xmm4 = xmm0 >> 2)
      compiler.inst(X86InstId.kMovdqu, [xmm4, xmm0]);
      compiler.inst(X86InstId.kPsrld, [xmm4, Imm(2)]);
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg, 32), xmm4]);

      // 4. pcmpeqd xmm5, xmm1 (xmm5 = (xmm0 == xmm1))
      compiler.inst(X86InstId.kMovdqu, [xmm5, xmm0]);
      compiler.inst(X86InstId.kPcmpeqd, [xmm5, xmm1]);
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg, 48), xmm5]);

      // 5. pshufd xmm0, xmm0, 0x1B (reverse dwords: 3, 2, 1, 0)
      // Reload xmm0 from src1
      compiler.inst(X86InstId.kMovdqu, [xmm0, X86Mem.ptr(src1Reg)]);
      compiler.inst(X86InstId.kPshufd, [xmm0, xmm0, Imm(0x1B)]);
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg, 64), xmm0]);

      compiler.ret();
      compiler.endFunc();
      compiler.finalize();

      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<SimdFunc>>()
            .asFunction<SimdDart>();

        final dst = ffi.calloc<Uint32>(20); // 5 vectors of 4 ints
        final src1 = ffi.calloc<Uint32>(4);
        final src2 = ffi.calloc<Uint32>(4);

        // src1: 10, 20, 30, 40
        src1[0] = 10;
        src1[1] = 20;
        src1[2] = 30;
        src1[3] = 40;

        // src2: 5, 20, 15, 40
        src2[0] = 5;
        src2[1] = 20;
        src2[2] = 15;
        src2[3] = 40;

        exec(dst.cast(), src1.cast(), src2.cast());

        // 1. psubd (src1 - src2)
        expect(dst[0], equals(5));  // 10 - 5
        expect(dst[1], equals(0));  // 20 - 20
        expect(dst[2], equals(15)); // 30 - 15
        expect(dst[3], equals(0));  // 40 - 40

        // 2. pslld (src1 << 2)
        expect(dst[4], equals(40));  // 10 << 2
        expect(dst[5], equals(80));  // 20 << 2
        expect(dst[6], equals(120)); // 30 << 2
        expect(dst[7], equals(160)); // 40 << 2

        // 3. psrld (src1 >> 2)
        expect(dst[8], equals(2));   // 10 >> 2
        expect(dst[9], equals(5));   // 20 >> 2
        expect(dst[10], equals(7));  // 30 >> 2
        expect(dst[11], equals(10)); // 40 >> 2

        // 4. pcmpeqd (src1 == src2)
        expect(dst[12], equals(0));          // 10 != 5
        expect(dst[13], equals(0xFFFFFFFF)); // 20 == 20
        expect(dst[14], equals(0));          // 30 != 15
        expect(dst[15], equals(0xFFFFFFFF)); // 40 == 40

        // 5. pshufd (reverse src1)
        expect(dst[16], equals(40));
        expect(dst[17], equals(30));
        expect(dst[18], equals(20));
        expect(dst[19], equals(10));

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
        ffi.calloc.free(src2);
      } finally {
        fn.dispose();
      }
    });

    test('SSE Packed Floating Point (minps, maxps, sqrtps, rsqrtps, rcpps)', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature = FuncSignature(
          retType: TypeId.void_,
          args: [TypeId.uintPtr, TypeId.uintPtr, TypeId.uintPtr]);

      compiler.addFunc(signature);

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final dstReg = isWindows ? rcx : rdi;
      final src1Reg = isWindows ? rdx : rsi;
      final src2Reg = isWindows ? r8 : rdx;

      final xmm0 = compiler.newXmm('xmm0');
      final xmm1 = compiler.newXmm('xmm1');
      final xmm2 = compiler.newXmm('xmm2');
      final xmm3 = compiler.newXmm('xmm3');
      final xmm4 = compiler.newXmm('xmm4');
      final xmm5 = compiler.newXmm('xmm5');

      // movups xmm0, [src1]
      compiler.inst(X86InstId.kMovups, [xmm0, X86Mem.ptr(src1Reg)]);
      // movups xmm1, [src2]
      compiler.inst(X86InstId.kMovups, [xmm1, X86Mem.ptr(src2Reg)]);

      // 1. minps xmm2, xmm1 (xmm2 = min(xmm0, xmm1))
      compiler.inst(X86InstId.kMovups, [xmm2, xmm0]);
      compiler.inst(X86InstId.kMinps, [xmm2, xmm1]);
      compiler.inst(X86InstId.kMovups, [X86Mem.ptr(dstReg), xmm2]);

      // 2. maxps xmm3, xmm1 (xmm3 = max(xmm0, xmm1))
      compiler.inst(X86InstId.kMovups, [xmm3, xmm0]);
      compiler.inst(X86InstId.kMaxps, [xmm3, xmm1]);
      compiler.inst(X86InstId.kMovups, [X86Mem.ptr(dstReg, 16), xmm3]);

      // 3. sqrtps xmm4, xmm0 (xmm4 = sqrt(xmm0))
      compiler.inst(X86InstId.kMovups, [xmm4, xmm0]);
      compiler.inst(X86InstId.kSqrtps, [xmm4, xmm4]); // sqrtps dst, src
      compiler.inst(X86InstId.kMovups, [X86Mem.ptr(dstReg, 32), xmm4]);

      // 4. rsqrtps xmm5, xmm0 (xmm5 = 1/sqrt(xmm0)) - approximate
      compiler.inst(X86InstId.kMovups, [xmm5, xmm0]);
      compiler.inst(X86InstId.kRsqrtps, [xmm5, xmm5]);
      compiler.inst(X86InstId.kMovups, [X86Mem.ptr(dstReg, 48), xmm5]);

      // 5. rcpps xmm0, xmm0 (xmm0 = 1/xmm0) - approximate
      // Reuse xmm0
      compiler.inst(X86InstId.kRcpps, [xmm0, xmm0]);
      compiler.inst(X86InstId.kMovups, [X86Mem.ptr(dstReg, 64), xmm0]);

      compiler.ret();
      compiler.endFunc();
      compiler.finalize();

      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<SimdFunc>>()
            .asFunction<SimdDart>();

        final dst = ffi.calloc<Float>(20); // 5 vectors of 4 floats
        final src1 = ffi.calloc<Float>(4);
        final src2 = ffi.calloc<Float>(4);

        // src1: 4.0, 16.0, 25.0, 100.0
        src1[0] = 4.0;
        src1[1] = 16.0;
        src1[2] = 25.0;
        src1[3] = 100.0;

        // src2: 2.0, 20.0, 10.0, 200.0
        src2[0] = 2.0;
        src2[1] = 20.0;
        src2[2] = 10.0;
        src2[3] = 200.0;

        exec(dst.cast(), src1.cast(), src2.cast());

        // 1. minps
        expect(dst[0], equals(2.0));
        expect(dst[1], equals(16.0));
        expect(dst[2], equals(10.0));
        expect(dst[3], equals(100.0));

        // 2. maxps
        expect(dst[4], equals(4.0));
        expect(dst[5], equals(20.0));
        expect(dst[6], equals(25.0));
        expect(dst[7], equals(200.0));

        // 3. sqrtps (sqrt(src1))
        expect(dst[8], equals(2.0));
        expect(dst[9], equals(4.0));
        expect(dst[10], equals(5.0));
        expect(dst[11], equals(10.0));

        // 4. rsqrtps (1/sqrt(src1)) - approx
        expect(dst[12], closeTo(0.5, 0.001));
        expect(dst[13], closeTo(0.25, 0.001));
        expect(dst[14], closeTo(0.2, 0.001));
        expect(dst[15], closeTo(0.1, 0.001));

        // 5. rcpps (1/src1) - approx
        expect(dst[16], closeTo(0.25, 0.001));
        expect(dst[17], closeTo(0.0625, 0.001));
        expect(dst[18], closeTo(0.04, 0.001));
        expect(dst[19], closeTo(0.01, 0.001));

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
        ffi.calloc.free(src2);
      } finally {
        fn.dispose();
      }
    });

    test('AVX Packed Floating Point (vminps, vmaxps, vsqrtps)', () {
      if (!CpuInfo.host().features.avx) {
        print('Skipping AVX test: Host CPU does not support AVX');
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
      final dstReg = isWindows ? rcx : rdi;
      final src1Reg = isWindows ? rdx : rsi;
      final src2Reg = isWindows ? r8 : rdx;

      final xmm0 = compiler.newXmm('xmm0');
      final xmm1 = compiler.newXmm('xmm1');
      final xmm2 = compiler.newXmm('xmm2');
      final xmm3 = compiler.newXmm('xmm3');
      final xmm4 = compiler.newXmm('xmm4');

      // vmovups xmm0, [src1]
      compiler.inst(X86InstId.kVmovups, [xmm0, X86Mem.ptr(src1Reg)]);
      // vmovups xmm1, [src2]
      compiler.inst(X86InstId.kVmovups, [xmm1, X86Mem.ptr(src2Reg)]);

      // 1. vminps xmm2, xmm0, xmm1
      compiler.inst(X86InstId.kVminps, [xmm2, xmm0, xmm1]);
      compiler.inst(X86InstId.kVmovups, [X86Mem.ptr(dstReg), xmm2]);

      // 2. vmaxps xmm3, xmm0, xmm1
      compiler.inst(X86InstId.kVmaxps, [xmm3, xmm0, xmm1]);
      compiler.inst(X86InstId.kVmovups, [X86Mem.ptr(dstReg, 16), xmm3]);

      // 3. vsqrtps xmm4, xmm0
      compiler.inst(X86InstId.kVsqrtps, [xmm4, xmm0]);
      compiler.inst(X86InstId.kVmovups, [X86Mem.ptr(dstReg, 32), xmm4]);

      compiler.ret();
      compiler.endFunc();
      compiler.finalize();

      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<SimdFunc>>()
            .asFunction<SimdDart>();

        final dst = ffi.calloc<Float>(12); // 3 vectors of 4 floats
        final src1 = ffi.calloc<Float>(4);
        final src2 = ffi.calloc<Float>(4);

        // src1: 4.0, 16.0, 25.0, 100.0
        src1[0] = 4.0;
        src1[1] = 16.0;
        src1[2] = 25.0;
        src1[3] = 100.0;

        // src2: 2.0, 20.0, 10.0, 200.0
        src2[0] = 2.0;
        src2[1] = 20.0;
        src2[2] = 10.0;
        src2[3] = 200.0;

        exec(dst.cast(), src1.cast(), src2.cast());

        // 1. vminps
        expect(dst[0], equals(2.0));
        expect(dst[1], equals(16.0));
        expect(dst[2], equals(10.0));
        expect(dst[3], equals(100.0));

        // 2. vmaxps
        expect(dst[4], equals(4.0));
        expect(dst[5], equals(20.0));
        expect(dst[6], equals(25.0));
        expect(dst[7], equals(200.0));

        // 3. vsqrtps (sqrt(src1))
        expect(dst[8], equals(2.0));
        expect(dst[9], equals(4.0));
        expect(dst[10], equals(5.0));
        expect(dst[11], equals(10.0));

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
        ffi.calloc.free(src2);
      } finally {
        fn.dispose();
      }
    });

    test('SSE Conversion (cvtdq2ps, cvtps2dq)', () {
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature = FuncSignature(
          retType: TypeId.void_,
          args: [TypeId.uintPtr, TypeId.uintPtr, TypeId.uintPtr]);

      compiler.addFunc(signature);

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final dstReg = isWindows ? rcx : rdi;
      final src1Reg = isWindows ? rdx : rsi;

      final xmm0 = compiler.newXmm('xmm0');
      final xmm1 = compiler.newXmm('xmm1');

      // 1. cvtdq2ps xmm0, [src1] (Int32 -> Float)
      compiler.inst(X86InstId.kCvtdq2ps, [xmm0, X86Mem.ptr(src1Reg)]);
      compiler.inst(X86InstId.kMovups, [X86Mem.ptr(dstReg), xmm0]);

      // 2. cvtps2dq xmm1, xmm0 (Float -> Int32)
      compiler.inst(X86InstId.kCvtps2dq, [xmm1, xmm0]);
      compiler.inst(X86InstId.kMovdqu, [X86Mem.ptr(dstReg, 16), xmm1]);

      compiler.ret();
      compiler.endFunc();
      compiler.finalize();

      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<SimdFunc>>()
            .asFunction<SimdDart>();

        final dst = ffi.calloc<Uint8>(32); // 16 bytes float + 16 bytes int
        final src1 = ffi.calloc<Int32>(4);

        src1[0] = 10;
        src1[1] = -20;
        src1[2] = 100;
        src1[3] = -50;

        exec(dst.cast(), src1.cast(), nullptr);

        final dstFloat = dst.cast<Float>();
        final dstInt = dst.cast<Uint8>().elementAt(16).cast<Int32>();

        // 1. cvtdq2ps
        expect(dstFloat[0], equals(10.0));
        expect(dstFloat[1], equals(-20.0));
        expect(dstFloat[2], equals(100.0));
        expect(dstFloat[3], equals(-50.0));

        // 2. cvtps2dq
        expect(dstInt[0], equals(10));
        expect(dstInt[1], equals(-20));
        expect(dstInt[2], equals(100));
        expect(dstInt[3], equals(-50));

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
      } finally {
        fn.dispose();
      }
    });

    test('AVX Float Vector Addition (vaddps)', () {
      // Check for AVX support
      if (!CpuInfo.host().features.avx) {
        print('Skipping AVX test: Host CPU does not support AVX');
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
      final dstReg = isWindows ? rcx : rdi;
      final src1Reg = isWindows ? rdx : rsi;
      final src2Reg = isWindows ? r8 : rdx;

      final xmm0 = compiler.newXmm('xmm0');
      final xmm1 = compiler.newXmm('xmm1');
      final xmm2 = compiler.newXmm('xmm2');

      // vmovups xmm0, [src1]
      compiler.inst(X86InstId.kVmovups, [xmm0, X86Mem.ptr(src1Reg)]);
      // vmovups xmm1, [src2]
      compiler.inst(X86InstId.kVmovups, [xmm1, X86Mem.ptr(src2Reg)]);
      // vaddps xmm2, xmm0, xmm1
      compiler.inst(X86InstId.kVaddps, [xmm2, xmm0, xmm1]);
      // vmovups [dst], xmm2
      compiler.inst(X86InstId.kVmovups, [X86Mem.ptr(dstReg), xmm2]);

      compiler.ret();
      compiler.endFunc();

      compiler.finalize();
      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<SimdFunc>>()
            .asFunction<SimdDart>();

        final dst = ffi.calloc<Float>(4);
        final src1 = ffi.calloc<Float>(4);
        final src2 = ffi.calloc<Float>(4);

        for (int i = 0; i < 4; i++) {
          src1[i] = i * 1.5;
          src2[i] = 0.5;
        }

        exec(dst.cast(), src1.cast(), src2.cast());

        for (int i = 0; i < 4; i++) {
          expect(dst[i], closeTo(i * 1.5 + 0.5, 0.0001));
        }

        ffi.calloc.free(dst);
        ffi.calloc.free(src1);
        ffi.calloc.free(src2);
      } finally {
        fn.dispose();
      }
    });
    test('AVX2 Broadcast (vpbroadcastd)', () {
      if (!CpuInfo.host().features.avx2) {
        print('Skipping AVX2 test: AVX2 not supported');
        return;
      }
      final code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);

      final signature = FuncSignature(
          retType: TypeId.void_,
          args: [TypeId.uintPtr, TypeId.uintPtr]);

      compiler.addFunc(signature);

      final isWindows = compiler.env.platform == TargetPlatform.windows;
      final dstReg = isWindows ? rcx : rdi;
      final srcReg = isWindows ? rdx : rsi;

      final xmm0 = compiler.newXmm('xmm0');

      // vpbroadcastd xmm0, [src]
      compiler.inst(X86InstId.kVpbroadcastd, [xmm0, X86Mem.ptr(srcReg)]);
      // vmovdqu [dst], xmm0
      compiler.inst(X86InstId.kVmovdqu, [X86Mem.ptr(dstReg), xmm0]);

      compiler.ret();
      compiler.endFunc();

      compiler.finalize();
      final assembler = X86Assembler(code);
      compiler.serializeToAssembler(assembler);

      final fn = rt.add(code);
      try {
        final exec = fn.pointer
            .cast<NativeFunction<Void Function(Pointer<Uint32>, Pointer<Uint32>)>>()
            .asFunction<void Function(Pointer<Uint32>, Pointer<Uint32>)>();

        final dst = ffi.calloc<Uint32>(4);
        final src = ffi.calloc<Uint32>(1);

        src[0] = 0x12345678;

        exec(dst, src);

        for (int i = 0; i < 4; i++) {
          expect(dst[i], equals(0x12345678));
        }

        ffi.calloc.free(dst);
        ffi.calloc.free(src);
      } finally {
        fn.dispose();
      }
    });
  });
}
