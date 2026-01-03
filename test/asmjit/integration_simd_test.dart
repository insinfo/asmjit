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
  });
}
