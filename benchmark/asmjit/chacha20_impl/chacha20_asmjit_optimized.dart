//C:\MyDartProjects\asmjit\benchmark\asmjit\chacha20_impl\chacha20_asmjit_optimized.dart
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;

/// ChaCha20 optimized implementation using AsmJit.
///
/// MITIGAÇÃO DE CRASH:
/// - Reduz pressão no alocador de registradores (menos spans longos).
/// - Recarrega estado base do ctx a cada bloco e atualiza contador no ctx por bloco.
/// - Mantém tudo em XMM 128-bit (VecWidth.k128).
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

    final inputPtr = pkgffi.calloc<ffi.Uint8>(input.length);
    final outputPtr = pkgffi.calloc<ffi.Uint8>(output.length);
    final ctxPtr = pkgffi.calloc<ffi.Uint32>(16);

    try {
      // Context (16x u32):
      // 0-3: Constant
      // 4-11: Key
      // 12: Counter
      // 13-15: Nonce
      final ctxData = ctxPtr.asTypedList(16);

      final keyData = _key.buffer.asUint32List(
        _key.offsetInBytes,
        _key.lengthInBytes ~/ 4,
      );
      final nonceData = _nonce.buffer.asUint32List(
        _nonce.offsetInBytes,
        _nonce.lengthInBytes ~/ 4,
      );

      ctxData[0] = 0x61707865;
      ctxData[1] = 0x3320646e;
      ctxData[2] = 0x79622d32;
      ctxData[3] = 0x6b206574;

      for (var i = 0; i < 8; i++) {
        ctxData[4 + i] = keyData[i];
      }

      ctxData[12] = _counter;

      for (var i = 0; i < 3; i++) {
        ctxData[13 + i] = nonceData[i];
      }

      inputPtr.asTypedList(input.length).setAll(0, input);

      int len = input.length;
      int processed = 0;

      if (len >= 64) {
        _implFunc!(outputPtr.address, inputPtr.address, len, ctxPtr.address);

        final blocks = len ~/ 64;
        processed = blocks * 64;
        _counter += blocks;
      }

      if (processed < len) {
        final tailLen = len - processed;

        final tailInput = Uint8List(64);
        for (int i = 0; i < tailLen; i++) {
          tailInput[i] = input[processed + i];
        }

        final tailInPtr = pkgffi.calloc<ffi.Uint8>(64);
        final tailOutPtr = pkgffi.calloc<ffi.Uint8>(64);
        try {
          tailInPtr.asTypedList(64).setAll(0, tailInput);

          // O ctx já está com counter atualizado pelo bloco anterior (se existiu).
          _implFunc!(tailOutPtr.address, tailInPtr.address, 64, ctxPtr.address);

          final tailResult = tailOutPtr.asTypedList(64);
          for (int i = 0; i < tailLen; i++) {
            outputPtr[processed + i] = tailResult[i];
          }

          _counter++;
        } finally {
          pkgffi.calloc.free(tailInPtr);
          pkgffi.calloc.free(tailOutPtr);
        }
      }

      output.setAll(0, outputPtr.asTypedList(output.length));
    } finally {
      pkgffi.calloc.free(inputPtr);
      pkgffi.calloc.free(outputPtr);
      pkgffi.calloc.free(ctxPtr);
    }
  }

  void dispose() {}

  static void disposeStatic() {
    _jitFunction?.dispose();
    _jitFunction = null;
    _runtime = null;
    _implFunc = null;
  }

  static void _ensureJitCompiled() {
    if (_implFunc != null) return;

    _runtime ??= JitRuntime();

    if (!_runtime!.environment.arch.isX86Family &&
        !_runtime!.environment.arch.isArmFamily) {
      throw UnsupportedError(
          'Optimized ChaCha20 not supported on this architecture.');
    }

    final code = _generateCode(_runtime!);
    _jitFunction = code;

    final fp = ffi.Pointer<
        ffi.NativeFunction<
            ffi.Void Function(
                ffi.IntPtr, ffi.IntPtr, ffi.IntPtr, ffi.IntPtr)>>.fromAddress(
      _jitFunction!.address,
    );
    _implFunc = fp.asFunction<void Function(int, int, int, int)>();
  }

  static JitFunction _generateCode(JitRuntime runtime) {
    final code = CodeHolder(env: runtime.environment);

    final cc = UniCompiler.auto(
      code,
      // Mantém tabela global para evitar RIP-rel/local-table quebrado.
      ctRef: const VecConstTableRef(null, VecConstTable.kSize),
    );

    // Sempre XMM (128-bit).
    cc.initVecWidth(VecWidth.k128);

    BaseReg _asXmm(BaseReg r) {
      if (cc.isX86Family && r is X86Vec) return r.xmm;
      return r;
    }

    // void chacha20_blocks(uint8_t* output, uint8_t* input, size_t len, uint32_t* ctx)
    final callConv =
        Platform.isWindows ? CallConvId.x64Windows : CallConvId.x64SystemV;

    cc.addFunc(
      FuncSignature.build(
        [TypeId.intPtr, TypeId.intPtr, TypeId.intPtr, TypeId.intPtr],
        TypeId.void_,
        callConv,
      ),
    );

    final output = cc.newGpPtr('output');
    final input = cc.newGpPtr('input');
    final len = cc.newGpPtr('len');
    final ctx = cc.newGpPtr('ctx');

    cc.setArg(0, output);
    cc.setArg(1, input);
    cc.setArg(2, len);
    cc.setArg(3, ctx);

    final v0 = _asXmm(cc.newVecWithWidth(VecWidth.k128, 'v0'));
    final v1 = _asXmm(cc.newVecWithWidth(VecWidth.k128, 'v1'));
    final v2 = _asXmm(cc.newVecWithWidth(VecWidth.k128, 'v2'));
    final v3 = _asXmm(cc.newVecWithWidth(VecWidth.k128, 'v3'));

    // tmp = temp único para rotates / loads / counter update.
    final tmp = _asXmm(cc.newVecWithWidth(VecWidth.k128, 'tmp'));

    // GP temporário para atualizar counter no ctx (scalar, evita pressão em XMM).
    final counterGp = cc.newGpPtr('counterGp');

    final loopStart = cc.newLabel();
    final loopEnd = cc.newLabel();

    cc.emitJIf(
      loopEnd,
      UniCondition(UniOpCond.compare, CondCode.kUnsignedLT, len, Imm(64)),
    );
    cc.bind(loopStart);

    // ---- Carrega estado base do ctx (a cada bloco) ----
    cc.emitVM(UniOpVM.load128U32, v0, _mem128(cc, ctx, 0));
    cc.emitVM(UniOpVM.load128U32, v1, _mem128(cc, ctx, 16));
    cc.emitVM(UniOpVM.load128U32, v2, _mem128(cc, ctx, 32));
    cc.emitVM(UniOpVM.load128U32, v3, _mem128(cc, ctx, 48));

    // ---- 20 rounds (10 double-rounds) ----
    for (int i = 0; i < 10; i++) {
      _quarterRoundSIMD(cc, v0, v1, v2, v3, tmp);

      _rotateVectorWords(cc, v1, v1, 1, tmp);
      _rotateVectorWords(cc, v2, v2, 2, tmp);
      _rotateVectorWords(cc, v3, v3, 3, tmp);

      _quarterRoundSIMD(cc, v0, v1, v2, v3, tmp);

      _rotateVectorWords(cc, v1, v1, 3, tmp);
      _rotateVectorWords(cc, v2, v2, 2, tmp);
      _rotateVectorWords(cc, v3, v3, 1, tmp);
    }

    // ---- Add original state (recarrega do ctx para reduzir liveness) ----
    cc.emitVM(UniOpVM.load128U32, tmp, _mem128(cc, ctx, 0));
    cc.emit3v(UniOpVVV.addU32, v0, v0, tmp);

    cc.emitVM(UniOpVM.load128U32, tmp, _mem128(cc, ctx, 16));
    cc.emit3v(UniOpVVV.addU32, v1, v1, tmp);

    cc.emitVM(UniOpVM.load128U32, tmp, _mem128(cc, ctx, 32));
    cc.emit3v(UniOpVVV.addU32, v2, v2, tmp);

    cc.emitVM(UniOpVM.load128U32, tmp, _mem128(cc, ctx, 48));
    cc.emit3v(UniOpVVV.addU32, v3, v3, tmp);

    // ---- XOR com input e store em output ----
    cc.emitVM(UniOpVM.load128U32, tmp, _mem128(cc, input, 0));
    cc.emit3v(UniOpVVV.xorU32, v0, v0, tmp);
    cc.emitMV(UniOpMV.store128U32, _mem128(cc, output, 0), v0);

    cc.emitVM(UniOpVM.load128U32, tmp, _mem128(cc, input, 16));
    cc.emit3v(UniOpVVV.xorU32, v1, v1, tmp);
    cc.emitMV(UniOpMV.store128U32, _mem128(cc, output, 16), v1);

    cc.emitVM(UniOpVM.load128U32, tmp, _mem128(cc, input, 32));
    cc.emit3v(UniOpVVV.xorU32, v2, v2, tmp);
    cc.emitMV(UniOpMV.store128U32, _mem128(cc, output, 32), v2);

    cc.emitVM(UniOpVM.load128U32, tmp, _mem128(cc, input, 48));
    cc.emit3v(UniOpVVV.xorU32, v3, v3, tmp);
    cc.emitMV(UniOpMV.store128U32, _mem128(cc, output, 48), v3);

    // ---- Incrementa counter no ctx (lane0) por bloco ----
    cc.emitRM(UniOpRM.loadU32, counterGp, _mem32(cc, ctx, 48));
    cc.emitRRI(UniOpRRR.add, counterGp, counterGp, 1);
    cc.emitMR(UniOpMR.storeU32, _mem32(cc, ctx, 48), counterGp);

    // ---- Avança pointers e len ----
    cc.emitRRI(UniOpRRR.add, input, input, 64);
    cc.emitRRI(UniOpRRR.add, output, output, 64);
    cc.emitRRI(UniOpRRR.add, len, len, -64);

    cc.emitJIf(
      loopStart,
      UniCondition(UniOpCond.compare, CondCode.kUnsignedGE, len, Imm(64)),
    );
    cc.bind(loopEnd);

    cc.ret();
    cc.endFunc();

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

  static dynamic _mem128(UniCompiler cc, BaseReg base, int offset) {
    if (cc.isX86Family) {
      return X86Mem.ptr(base as X86Gp, offset).withSize(16);
    } else {
      return A64Mem.baseOffset(base as A64Gp, offset);
    }
  }

  static dynamic _mem32(UniCompiler cc, BaseReg base, int offset) {
    if (cc.isX86Family) {
      return X86Mem.ptr(base as X86Gp, offset).withSize(4);
    } else {
      return A64Mem.baseOffset(base as A64Gp, offset);
    }
  }

  static void _quarterRoundSIMD(
    UniCompiler cc,
    BaseReg a,
    BaseReg b,
    BaseReg c,
    BaseReg d,
    BaseReg tmp,
  ) {
    cc.emit3v(UniOpVVV.addU32, a, a, b);
    cc.emit3v(UniOpVVV.xorU32, d, d, a);
    _rotateBits(cc, d, 16, tmp);

    cc.emit3v(UniOpVVV.addU32, c, c, d);
    cc.emit3v(UniOpVVV.xorU32, b, b, c);
    _rotateBits(cc, b, 12, tmp);

    cc.emit3v(UniOpVVV.addU32, a, a, b);
    cc.emit3v(UniOpVVV.xorU32, d, d, a);
    _rotateBits(cc, d, 8, tmp);

    cc.emit3v(UniOpVVV.addU32, c, c, d);
    cc.emit3v(UniOpVVV.xorU32, b, b, c);
    _rotateBits(cc, b, 7, tmp);
  }

  static void _rotateBits(UniCompiler cc, BaseReg v, int n, BaseReg tmp) {
    cc.emit2v(UniOpVV.mov, tmp, v);
    cc.emit2vi(UniOpVVI.sllU32, v, v, n);
    cc.emit2vi(UniOpVVI.srlU32, tmp, tmp, 32 - n);
    cc.emit3v(UniOpVVV.orU32, v, v, tmp);
  }

  static void _rotateVectorWords(
    UniCompiler cc,
    BaseReg dst,
    BaseReg src,
    int count,
    BaseReg tmp,
  ) {
    if (cc.isX86Family) {
      int imm = 0;
      for (int i = 0; i < 4; i++) {
        final srcIdx = (i + count) & 3;
        imm |= (srcIdx << (i * 2));
      }
      cc.emit2vi(UniOpVVI.swizzleU32x4, dst, src, imm);
    } else {
      final byteShift = (4 - count) * 4;
      cc.emit3vi(UniOpVVVI.alignrU128, dst, src, src, byteShift);
    }
  }
}
