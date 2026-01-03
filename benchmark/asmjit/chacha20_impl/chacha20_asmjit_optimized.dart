//C:\MyDartProjects\asmjit\benchmark\asmjit\chacha20_impl\chacha20_asmjit_optimized.dart
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;

/// dart .\benchmark\asmjit\chacha20_benchmark.dart --quick --filter=AsmJit Opt
/// ChaCha20 optimized implementation 
/// using advanced features of AsmJit ujit SIMD etc
class ChaCha20AsmJitOptimized {
  final Uint8List _key;
  final Uint8List _nonce;
  final int initialCounter;

  // Runtime and generated function
  static JitRuntime? _runtime;
  static JitFunction? _jitFunction;
  static Function? _implFunc;

  // Buffers
  ffi.Pointer<ffi.Uint8>? _ctxPtr;

  ChaCha20AsmJitOptimized(this._key, this._nonce, {this.initialCounter = 0}) {
    if (_key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (_nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');
    _ensureInitialized();
    _initPointers();
  }

  static void _ensureInitialized() {
    if (_runtime != null) return;

    _runtime = JitRuntime();
    _jitFunction = _generateCode(_runtime!);

    // cast to function
    final funcPtr = _jitFunction!.pointer.cast<
        ffi.NativeFunction<
            ffi.Void Function(
              ffi.Pointer<ffi.Uint8> output,
              ffi.Pointer<ffi.Uint8> input,
              ffi.IntPtr len,
              ffi.Pointer<ffi.Uint8> ctx,
            )>>();
    _implFunc = funcPtr.asFunction<
        void Function(
          ffi.Pointer<ffi.Uint8>,
          ffi.Pointer<ffi.Uint8>,
          int,
          ffi.Pointer<ffi.Uint8>,
        )>();
  }

  void _initPointers() {
    // Context layout:
    // [0..31]   key (32 bytes)
    // [32..43]  nonce (12 bytes)
    // [44..47]  counter (u32 little-endian)
    _ctxPtr = pkgffi.calloc<ffi.Uint8>(48);
    for (var i = 0; i < 32; i++) _ctxPtr![i] = _key[i];
    for (var i = 0; i < 12; i++) _ctxPtr![32 + i] = _nonce[i];
    (_ctxPtr! + 44).cast<ffi.Uint32>().value = initialCounter;
  }

  void dispose() {
    if (_ctxPtr != null) pkgffi.calloc.free(_ctxPtr!);
  }

  static void disposeStatic() {
    _jitFunction?.dispose();
    _runtime?.dispose();
    _jitFunction = null;
    _runtime = null;
    _implFunc = null;
  }

  void cryptInto(Uint8List input, Uint8List output) {
    if (input.length != output.length) throw ArgumentError('Length mismatch');

    final size = input.length;
    final inpPtr = pkgffi.calloc<ffi.Uint8>(size);
    final outPtr = pkgffi.calloc<ffi.Uint8>(size);

    // Copy input
    final inpList = inpPtr.asTypedList(size);
    inpList.setAll(0, input);

    // Call JIT
    (_implFunc as dynamic)(outPtr, inpPtr, size, _ctxPtr);

    // Copy output back
    final outList = outPtr.asTypedList(size);
    output.setAll(0, outList);

    pkgffi.calloc.free(inpPtr);
    pkgffi.calloc.free(outPtr);
  }

  static JitFunction _generateCode(JitRuntime runtime) {
    final code = CodeHolder(env: runtime.environment);
    final x86cc = X86Compiler(env: code.env, labelManager: code.labelManager);
    final cc = UniCompiler(x86cc);

    // void chacha20(output, input, len, ctx)
    cc.addFunc(FuncSignature.build(
        [TypeId.intPtr, TypeId.intPtr, TypeId.intPtr, TypeId.intPtr],
        TypeId.void_,
        CallConvId.x64Windows));

    // Definir registradores virtuais para os argumentos
    final output = cc.newGpPtr('output');
    final input = cc.newGpPtr('input');
    final len = cc.newGpPtr('len');
    final ctx = cc.newGpPtr('ctx');

    // Mapear manualmente os argumentos físicos (Win64) para os virtuais
    // O RAPass cuidará de preservar/restaurar se necessário
    x86cc.mov(output, rcx);
    x86cc.mov(input, rdx);
    x86cc.mov(len, r8);
    x86cc.mov(ctx, r9);

    // State registers (16 x u32)
    final state = List.generate(16, (i) => cc.newGp32('s$i'));
    // Saved state registers (16 x u32) - replaces manual stack
    final savedState = List.generate(16, (i) => cc.newGp32('saved$i'));

    // Main encryption loop
    final loopStart = cc.newLabel();
    final loopEnd = cc.newLabel();

    // Test if len >= 64
    x86cc.cmp(len, Imm(64));
    x86cc.jb(loopEnd);

    cc.bind(loopStart);

    // Load initial state from context
    // Constants: "expand 32-byte k"
    cc.mov(state[0], Imm(0x61707865));
    cc.mov(state[1], Imm(0x3320646e));
    cc.mov(state[2], Imm(0x79622d32));
    cc.mov(state[3], Imm(0x6b206574));

    // Load key (8 x u32 from ctx[0..31])
    for (int i = 0; i < 8; i++) {
      x86cc.mov(state[4 + i], X86Mem.ptr(ctx, i * 4));
    }

    // Load counter (ctx[44..47])
    x86cc.mov(state[12], X86Mem.ptr(ctx, 44));

    // Load nonce (ctx[32..43])
    for (int i = 0; i < 3; i++) {
      x86cc.mov(state[13 + i], X86Mem.ptr(ctx, 32 + i * 4));
    }

    // Save initial state to "savedState" registers
    // The Allocator will handle spilling these to stack if needed
    for (int i = 0; i < 16; i++) {
      cc.mov(savedState[i], state[i]);
    }

    // 20 rounds (10 double-rounds)
    for (int round = 0; round < 10; round++) {
      // Column round
      _quarterRound(cc, state, 0, 4, 8, 12);
      _quarterRound(cc, state, 1, 5, 9, 13);
      _quarterRound(cc, state, 2, 6, 10, 14);
      _quarterRound(cc, state, 3, 7, 11, 15);

      // Diagonal round
      _quarterRound(cc, state, 0, 5, 10, 15);
      _quarterRound(cc, state, 1, 6, 11, 12);
      _quarterRound(cc, state, 2, 7, 8, 13);
      _quarterRound(cc, state, 3, 4, 9, 14);
    }

    // Add initial state back to working state
    for (int i = 0; i < 16; i++) {
      cc.emitRRR(UniOpRRR.add, state[i], state[i], savedState[i]);
    }

    // XOR output with keystream and store to output
    for (int i = 0; i < 16; i++) {
      final inData = cc.newGp32('inData$i');
      x86cc.mov(inData, X86Mem.ptr(input, i * 4));
      cc.emitRRR(UniOpRRR.xor, state[i], state[i], inData);
      x86cc.mov(X86Mem.ptr(output, i * 4), state[i]);
    }

    // Increment counter in context
    final counter = cc.newGp32('counter');
    x86cc.mov(counter, X86Mem.ptr(ctx, 44));
    x86cc.inc(counter);
    x86cc.mov(X86Mem.ptr(ctx, 44), counter);

    // Advance pointers by 64 bytes
    x86cc.add(output, Imm(64));
    x86cc.add(input, Imm(64));
    x86cc.sub(len, Imm(64));

    // Loop if len >= 64
    x86cc.cmp(len, Imm(64));
    x86cc.jae(loopStart);

    cc.bind(loopEnd);

    cc.ret();
    cc.endFunc();

    x86cc.finalize();

    final asm = X86Assembler(code);
    x86cc.serializeToAssembler(asm);

    return runtime.add(code);
  }

  static void _quarterRound(
      UniCompiler cc, List<X86Gp> state, int a, int b, int c, int d) {
    cc.emitRRR(UniOpRRR.add, state[a], state[a], state[b]);
    cc.emitRRR(UniOpRRR.xor, state[d], state[d], state[a]);
    cc.emitRRI(UniOpRRR.rol, state[d], state[d], 16);

    cc.emitRRR(UniOpRRR.add, state[c], state[c], state[d]);
    cc.emitRRR(UniOpRRR.xor, state[b], state[b], state[c]);
    cc.emitRRI(UniOpRRR.rol, state[b], state[b], 12);

    cc.emitRRR(UniOpRRR.add, state[a], state[a], state[b]);
    cc.emitRRR(UniOpRRR.xor, state[d], state[d], state[a]);
    cc.emitRRI(UniOpRRR.rol, state[d], state[d], 8);

    cc.emitRRR(UniOpRRR.add, state[c], state[c], state[d]);
    cc.emitRRR(UniOpRRR.xor, state[b], state[b], state[c]);
    cc.emitRRI(UniOpRRR.rol, state[b], state[b], 7);
  }
}
