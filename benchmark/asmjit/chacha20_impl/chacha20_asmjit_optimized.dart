//C:\MyDartProjects\asmjit\benchmark\asmjit\chacha20_impl\chacha20_asmjit_optimized.dart
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;

/// ChaCha20 optimized implementation using AsmJit.
/// 
/// Features:
/// - JIT-compiled kernel for block processing.
/// - SIMD optimizations (SSE/AVX on x86, NEON on ARM64).
/// - Loop hoisting (keeps state in registers).
/// - Minimized memory traffic.
class ChaCha20AsmJitOptimized {
  final Uint8List _key;
  final Uint8List _nonce;
  int _counter;

  static JitRuntime? _runtime;
  static JitFunction? _jitFunction;
  static Function? _implFunc;

  ChaCha20AsmJitOptimized(this._key, this._nonce, {int initialCounter = 0})
      : _counter = initialCounter;

  void cryptInto(Uint8List input, Uint8List output) {
    if (input.length != output.length) {
      throw ArgumentError('Input and output must be same length');
    }

    _ensureJitCompiled();

    // Allocate aligned memory for context and buffers
    final inputPtr = pkgffi.calloc<ffi.Uint8>(input.length);
    final outputPtr = pkgffi.calloc<ffi.Uint8>(output.length);
    final ctxPtr = pkgffi.calloc<ffi.Uint32>(16);

    try {
      // 1. Setup Context (64 bytes)
      // Layout:
      // 0-3: Constant
      // 4-11: Key (256-bit)
      // 12: Counter (32-bit)
      // 13-15: Nonce (96-bit)
      
      final ctxData = ctxPtr.asTypedList(16);
      final keyData = _key.buffer.asUint32List();
      final nonceData = _nonce.buffer.asUint32List();

      // Constant "expand 32-byte k"
      ctxData[0] = 0x61707865;
      ctxData[1] = 0x3320646e;
      ctxData[2] = 0x79622d32;
      ctxData[3] = 0x6b206574;

      // Key
      for (var i = 0; i < 8; i++) {
        ctxData[4 + i] = keyData[i];
      }

      // Counter
      ctxData[12] = _counter;

      // Nonce
      for (var i = 0; i < 3; i++) {
        ctxData[13 + i] = nonceData[i];
      }

      // 2. Prepare Data
      final inputList = inputPtr.asTypedList(input.length);
      inputList.setAll(0, input);

      // 3. Process Full Blocks via JIT
      int len = input.length;
      int processed = 0;
      
      // The JIT function handles multiples of 64 bytes
      // Signature: void func(output, input, len, ctx)
      if (len >= 64) {
        _implFunc!(outputPtr.address, inputPtr.address, len, ctxPtr.address);
        
        // Calculate how many blocks were processed to update our Dart-side counter tracking
        // (The JIT updates the counter in ctxPtr in-memory as well)
        final blocks = len ~/ 64;
        processed = blocks * 64;
        _counter += blocks; 
      }

      // 4. Handle Tail (remaining bytes < 64)
      if (processed < len) {
        final tailLen = len - processed;
        final tailInput = Uint8List(64);
        
        // Copy remaining input bytes to a temp block
        for(int i=0; i<tailLen; i++) {
          tailInput[i] = input[processed + i];
        }
        
        final tailInPtr = pkgffi.calloc<ffi.Uint8>(64);
        final tailOutPtr = pkgffi.calloc<ffi.Uint8>(64);
        tailInPtr.asTypedList(64).setAll(0, tailInput);
        
        // Update context counter for the last block
        // (If JIT ran, it updated ctx[12] ready for next block, otherwise use current)
        // Since JIT updates ctx in place, ctxData[12] is already correct for the next block.
        // If JIT didn't run (len < 64), ctxData[12] is initial counter. Correct.
        
        // Process one block
        _implFunc!(tailOutPtr.address, tailInPtr.address, 64, ctxPtr.address);
        
        // Copy relevant bytes back
        final tailResult = tailOutPtr.asTypedList(64);
        for(int i=0; i<tailLen; i++) {
          outputPtr[processed + i] = tailResult[i];
        }
        
        _counter++; // Increment for the tail block
        
        pkgffi.calloc.free(tailInPtr);
        pkgffi.calloc.free(tailOutPtr);
      }

      // 5. Copy Result Back
      final outputList = outputPtr.asTypedList(output.length);
      output.setAll(0, outputList);

    } finally {
      pkgffi.calloc.free(inputPtr);
      pkgffi.calloc.free(outputPtr);
      pkgffi.calloc.free(ctxPtr);
    }
  }

  void dispose() {
    // Instance disposal (optional cleanup)
  }

  static void disposeStatic() {
    _jitFunction?.dispose();
    _jitFunction = null;
    _runtime = null;
    _implFunc = null;
  }

  static void _ensureJitCompiled() {
    if (_implFunc != null) return;

    _runtime ??= JitRuntime();
    
    // Check architecture
    if (!_runtime!.environment.arch.isX86Family && !_runtime!.environment.arch.isArmFamily) {
      throw UnsupportedError('Optimized ChaCha20 not supported on this architecture.');
    }

    final code = _generateCode(_runtime!);
    _jitFunction = code;
    
    final fp = ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.IntPtr, ffi.IntPtr, ffi.IntPtr, ffi.IntPtr)>>.fromAddress(_jitFunction!.address);
    _implFunc = fp.asFunction<void Function(int, int, int, int)>();
  }

  static JitFunction _generateCode(JitRuntime runtime) {
    final code = CodeHolder(env: runtime.environment);
    final cc = UniCompiler.auto(code);

    // Function: void chacha20_blocks(uint8_t* output, uint8_t* input, size_t len, uint32_t* ctx)
    final callConv = Platform.isWindows ? CallConvId.x64Windows : CallConvId.x64SystemV;
    
    cc.addFunc(FuncSignature.build(
        [TypeId.intPtr, TypeId.intPtr, TypeId.intPtr, TypeId.intPtr],
        TypeId.void_,
        callConv));

    final output = cc.newGpPtr('output');
    final input = cc.newGpPtr('input');
    final len = cc.newGpPtr('len');
    final ctx = cc.newGpPtr('ctx');

    cc.setArg(0, output);
    cc.setArg(1, input);
    cc.setArg(2, len);
    cc.setArg(3, ctx);

    final v0 = cc.newVec('v0');
    final v1 = cc.newVec('v1');
    final v2 = cc.newVec('v2');
    final v3 = cc.newVec('v3');
    
    final t0 = cc.newVec('t0'); // Temp for rotations/loading
    final t1 = cc.newVec('t1'); // Temp for input loading
    
    // Persistent state across blocks
    final saved0 = cc.newVec('saved0'); // Const
    final saved1 = cc.newVec('saved1'); // Key 0-3
    final saved2 = cc.newVec('saved2'); // Key 4-7
    final saved3 = cc.newVec('saved3'); // Cnt, Nonce
    
    final oneVec = cc.newVec('oneVec'); // [1, 0, 0, 0] for counter increment

    final loopStart = cc.newLabel();
    final loopEnd = cc.newLabel();

    // 1. Initialize Constants
    // Create vector constant [1, 0, 0, 0] for 32-bit counter increment
    final oneData = ByteData(16);
    oneData.setUint32(0, 1, Endian.little);
    final oneConst = VecConst(16, oneData.buffer.asUint8List());
    // Load constant into register
    cc.emit2v(UniOpVV.mov, oneVec, cc.simdConst(oneConst, Bcst.kNA, VecWidth.k128));

    // 2. Load Initial State (Hoist out of loop)
    // Row 0: Const (Offset 0)
    cc.emitVM(UniOpVM.load128U32, saved0, _mem(cc, ctx, 0));
    // Row 1: Key (Offset 16)
    cc.emitVM(UniOpVM.load128U32, saved1, _mem(cc, ctx, 16));
    // Row 2: Key (Offset 32)
    cc.emitVM(UniOpVM.load128U32, saved2, _mem(cc, ctx, 32));
    // Row 3: Counter + Nonce (Offset 48)
    cc.emitVM(UniOpVM.load128U32, saved3, _mem(cc, ctx, 48));

    // Check if we have at least 64 bytes to process
    cc.emitJIf(loopEnd, UniCondition(UniOpCond.compare, CondCode.kUnsignedLT, len, Imm(64)));

    cc.bind(loopStart);

    // 3. Prepare State for Rounds (Copy saved -> working)
    cc.emit2v(UniOpVV.mov, v0, saved0);
    cc.emit2v(UniOpVV.mov, v1, saved1);
    cc.emit2v(UniOpVV.mov, v2, saved2);
    cc.emit2v(UniOpVV.mov, v3, saved3);

    // 4. ChaCha20 Rounds (10 double-rounds)
    for (int i = 0; i < 10; i++) {
       // Column Round
       _quarterRoundSIMD(cc, v0, v1, v2, v3, t0);
       
       // Diagonal Round: Rotate rows to align diagonals to columns
       _rotateVectorWords(cc, v1, v1, 1, t0); // RotL 1
       _rotateVectorWords(cc, v2, v2, 2, t0); // RotL 2
       _rotateVectorWords(cc, v3, v3, 3, t0); // RotL 3
       
       _quarterRoundSIMD(cc, v0, v1, v2, v3, t0);
       
       // Restore columns (Inverse rotation)
       _rotateVectorWords(cc, v1, v1, 3, t0); // RotL 3 (Inv of 1)
       _rotateVectorWords(cc, v2, v2, 2, t0); // RotL 2 (Inv of 2)
       _rotateVectorWords(cc, v3, v3, 1, t0); // RotL 1 (Inv of 3)
    }

    // 5. Add Initial State
    cc.emit3v(UniOpVVV.addU32, v0, v0, saved0);
    cc.emit3v(UniOpVVV.addU32, v1, v1, saved1);
    cc.emit3v(UniOpVVV.addU32, v2, v2, saved2);
    cc.emit3v(UniOpVVV.addU32, v3, v3, saved3);

    // 6. XOR with Input
    // Load 64 bytes of input (4 vectors)
    cc.emitVM(UniOpVM.load128U32, t0, _mem(cc, input, 0));
    cc.emitVM(UniOpVM.load128U32, t1, _mem(cc, input, 16));
    cc.emit3v(UniOpVVV.xorU32, v0, v0, t0);
    cc.emit3v(UniOpVVV.xorU32, v1, v1, t1);
    
    cc.emitVM(UniOpVM.load128U32, t0, _mem(cc, input, 32));
    cc.emitVM(UniOpVM.load128U32, t1, _mem(cc, input, 48));
    cc.emit3v(UniOpVVV.xorU32, v2, v2, t0);
    cc.emit3v(UniOpVVV.xorU32, v3, v3, t1);

    // 7. Store Output
    cc.emitMV(UniOpMV.store128U32, _mem(cc, output, 0), v0);
    cc.emitMV(UniOpMV.store128U32, _mem(cc, output, 16), v1);
    cc.emitMV(UniOpMV.store128U32, _mem(cc, output, 32), v2);
    cc.emitMV(UniOpMV.store128U32, _mem(cc, output, 48), v3);

    // 8. Increment Counter
    // Increment the first 32-bit word of saved3 (Counter)
    cc.emit3v(UniOpVVV.addU32, saved3, saved3, oneVec);

    // 9. Advance Pointers and Loop
    cc.emitRRI(UniOpRRR.add, input, input, 64);
    cc.emitRRI(UniOpRRR.add, output, output, 64);
    cc.emitRRI(UniOpRRR.add, len, len, -64);
    
    cc.emitJIf(loopStart, UniCondition(UniOpCond.compare, CondCode.kUnsignedGE, len, Imm(64)));

    cc.bind(loopEnd);

    // 10. Writeback Counter to Memory
    // Update the context so subsequent calls continue the sequence correctly
    // saved3 contains [Cnt, N, N, N]. We only need to write back 16 bytes (safest) or just 4.
    // Writing full vector back to offset 48 updates Cnt and preserves Nonce.
    cc.emitMV(UniOpMV.store128U32, _mem(cc, ctx, 48), saved3);

    cc.ret();
    cc.endFunc();

    // Serialize to assembler
    cc.cc.finalize();
    if (code.env.arch == Arch.x64 || code.env.arch == Arch.x86) {
      final assembler = X86Assembler(code);
      cc.cc.serializeToAssembler(assembler);
    } else {
      final assembler = A64Assembler(code);
      cc.cc.serializeToAssembler(assembler);
    }
    
    return runtime.add(code);
  }
  
  static dynamic _mem(UniCompiler cc, BaseReg base, int offset) {
    if (cc.isX86Family) {
      return X86Mem.ptr(base, offset);
    } else {
      return A64Mem.baseOffset(base as A64Gp, offset);
    }
  }
  
  // ARX: Add, Rotate, Xor
  static void _quarterRoundSIMD(UniCompiler cc, BaseReg a, BaseReg b, BaseReg c, BaseReg d, BaseReg tmp) {
     // a += b; d ^= a; d <<<= 16
     cc.emit3v(UniOpVVV.addU32, a, a, b);
     cc.emit3v(UniOpVVV.xorU32, d, d, a);
     _rotateBits(cc, d, 16, tmp);
     
     // c += d; b ^= c; b <<<= 12
     cc.emit3v(UniOpVVV.addU32, c, c, d);
     cc.emit3v(UniOpVVV.xorU32, b, b, c);
     _rotateBits(cc, b, 12, tmp);
     
     // a += b; d ^= a; d <<<= 8
     cc.emit3v(UniOpVVV.addU32, a, a, b);
     cc.emit3v(UniOpVVV.xorU32, d, d, a);
     _rotateBits(cc, d, 8, tmp);
     
     // c += d; b ^= c; b <<<= 7
     cc.emit3v(UniOpVVV.addU32, c, c, d);
     cc.emit3v(UniOpVVV.xorU32, b, b, c);
     _rotateBits(cc, b, 7, tmp);
  }
  
  static void _rotateBits(UniCompiler cc, BaseReg v, int n, BaseReg tmp) {
    // Basic rotation: (x << n) | (x >> (32 - n))
    // Optimized: On AVX-512 use vprold, on XOP use vprotd.
    // Standard SSE/NEON: manual shift/or.
    
     cc.emit2v(UniOpVV.mov, tmp, v);
     cc.emit2vi(UniOpVVI.sllU32, v, v, n);
     cc.emit2vi(UniOpVVI.srlU32, tmp, tmp, 32 - n);
     cc.emit3v(UniOpVVV.orU32, v, v, tmp);
  }
  
  static void _rotateVectorWords(UniCompiler cc, BaseReg dst, BaseReg src, int count, BaseReg tmp) {
    // Rotates the 32-bit words within the 128-bit vector LEFT by count positions.
    // [0, 1, 2, 3] -> rot 1 -> [1, 2, 3, 0]
    
    if (cc.isX86Family) {
       // PSHUFD / VSHUFD
       // Imm8 encoding: [1:0] -> dest[0], [3:2] -> dest[1], ...
       // We want index i to take from (i + count) % 4
       int imm = 0;
       for (int i = 0; i < 4; i++) {
         int srcIdx = (i + count) % 4;
         imm |= (srcIdx << (i * 2));
       }
       cc.emit2vi(UniOpVVI.swizzleU32x4, dst, src, imm);
    } else {
       // AArch64 EXT (Extract)
       // EXT Vd, Vn, Vm, #imm -> Dest constructs from Vn:Vm shifted by imm bytes.
       // We want to simulate rotation.
       // To rotate [W3 W2 W1 W0] left by count words:
       // Use EXT dst, src, src, imm
       // imm is in bytes. Right shift of the 256-bit concat.
       // RotL 1 word (4 bytes) == RotR 3 words (12 bytes).
       // So imm = (4 - count) * 4.
       int byteShift = (4 - count) * 4;
       cc.emit3vi(UniOpVVVI.alignrU128, dst, src, src, byteShift);
    }
  }
}
