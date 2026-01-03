//C:\MyDartProjects\asmjit\benchmark\asmjit\chacha20_impl\chacha20_asmjit.dart
/// ChaCha20 - Implementação usando AsmJit para gerar código dinâmico
/// Usa a biblioteca asmjit para gerar código SSE2 em runtime


import 'dart:ffi' as ffi;
import 'dart:math';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;

/// ChaCha20 block function type
typedef ChaCha20BlockFunc = void Function(
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  ffi.Pointer<ffi.Uint8> constants,
  int counter,
  ffi.Pointer<ffi.Uint8> output,
);

/// ChaCha20 usando AsmJit para gerar código SSE2
class ChaCha20AsmJit {
  static final Uint8List _constantsBytes = Uint8List.fromList([
    0x65, 0x78, 0x70, 0x61, // "expa"
    0x6e, 0x64, 0x20, 0x33, // "nd 3"
    0x32, 0x2d, 0x62, 0x79, // "2-by"
    0x74, 0x65, 0x20, 0x6b, // "te k"
  ]);

  final Uint8List _key;
  final Uint8List _nonce;
  final int initialCounter;

  // Runtime e função gerada
  static JitRuntime? _runtime;
  static JitFunction? _jitFunction;
  static ChaCha20BlockFunc? _blockFunc;

  // Buffers nativos
  ffi.Pointer<ffi.Uint8>? _keyPtr;
  ffi.Pointer<ffi.Uint8>? _noncePtr;
  ffi.Pointer<ffi.Uint8>? _constantsPtr;
  ffi.Pointer<ffi.Uint8>? _outputPtr;
  final Uint8List _keystream = Uint8List(64);
  bool _disposed = false;

  ChaCha20AsmJit(this._key, this._nonce, {this.initialCounter = 0}) {
    if (_key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (_nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');
    _ensureInitialized();
    _initPointers();
  }

  static void _ensureInitialized() {
    if (_runtime != null) return;

    _runtime = JitRuntime();
    _jitFunction = _generateCode(_runtime!);

    final funcPtr = _jitFunction!.pointer.cast<
        ffi.NativeFunction<
            ffi.Void Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Int32,
              ffi.Pointer<ffi.Uint8>,
            )>>();
    _blockFunc = funcPtr.asFunction();
  }

  void _initPointers() {
    _keyPtr = pkgffi.calloc<ffi.Uint8>(32);
    _noncePtr = pkgffi.calloc<ffi.Uint8>(12);
    _constantsPtr = pkgffi.calloc<ffi.Uint8>(16);
    _outputPtr = pkgffi.calloc<ffi.Uint8>(64);

    for (var i = 0; i < 32; i++) _keyPtr![i] = _key[i];
    for (var i = 0; i < 12; i++) _noncePtr![i] = _nonce[i];
    for (var i = 0; i < 16; i++) _constantsPtr![i] = _constantsBytes[i];
  }

  void dispose() {
    if (_disposed) return;
    if (_keyPtr != null) pkgffi.calloc.free(_keyPtr!);
    if (_noncePtr != null) pkgffi.calloc.free(_noncePtr!);
    if (_constantsPtr != null) pkgffi.calloc.free(_constantsPtr!);
    if (_outputPtr != null) pkgffi.calloc.free(_outputPtr!);
    _disposed = true;
  }

  /// Libera recursos estáticos (chame ao final do programa)
  static void disposeStatic() {
    _jitFunction?.dispose();
    _runtime?.dispose();
    _jitFunction = null;
    _runtime = null;
    _blockFunc = null;
  }

  /// Gera código usando AsmJit
  static JitFunction _generateCode(JitRuntime runtime) {
    final env = Environment.host();
    final code = CodeHolder(env: env);
    final a = X86Assembler(code);

    // Windows x64: RCX=key, RDX=nonce, R8=constants, R9D=counter, [RSP+40]=output
    // Vamos usar uma abordagem simplificada com prolog/epilog padrão

    // Prólogo
    a.push(rbx);
    a.push(r12);
    a.push(r13);
    a.push(r14);
    a.push(r15);
    a.subRI(rsp, 160); // Shadow space + XMM saves

    // Salva XMM6-XMM11 (Windows)
    a.movapsMX(ptr(rsp, 0), xmm6);
    a.movapsMX(ptr(rsp, 16), xmm7);
    a.movapsMX(ptr(rsp, 32), xmm8);
    a.movapsMX(ptr(rsp, 48), xmm9);
    a.movapsMX(ptr(rsp, 64), xmm10);
    a.movapsMX(ptr(rsp, 80), xmm11);

    // Salva parâmetros em registradores não-voláteis
    a.movRR(rbx, rcx); // key
    a.movRR(r12, rdx); // nonce
    a.movRR(r13, r8); // constants
    a.movRR(r14d, r9d); // counter
    // output está em [RSP + 160 + 40 + 40] = [RSP + 240]
    a.movRM(r15, ptr(rsp, 240));

    // Carrega estado inicial
    // XMM0 = constants
    a.movupsXM(xmm0, ptr(r13, 0));
    // XMM1 = key[0:16]
    a.movupsXM(xmm1, ptr(rbx, 0));
    // XMM2 = key[16:32]
    a.movupsXM(xmm2, ptr(rbx, 16));

    // Constrói XMM3 = [counter, nonce[0], nonce[1], nonce[2]]
    a.movdXR(xmm3, r14d); // xmm3[0] = counter
    a.movdXM(xmm4, ptr(r12, 0)); // tmp = nonce[0]
    a.pslldXI(xmm4, 4); // shift left
    a.porXX(xmm3, xmm4);
    a.movdXM(xmm4, ptr(r12, 4)); // tmp = nonce[1]
    a.pslldXI(xmm4, 8);
    a.porXX(xmm3, xmm4);
    a.movdXM(xmm4, ptr(r12, 8)); // tmp = nonce[2]
    a.pslldXI(xmm4, 12);
    a.porXX(xmm3, xmm4);

    // Salva estado inicial em XMM8-XMM11
    a.movapsXX(xmm8, xmm0);
    a.movapsXX(xmm9, xmm1);
    a.movapsXX(xmm10, xmm2);
    a.movapsXX(xmm11, xmm3);

    // Loop counter
    a.movRI(ecx, 10); // 10 double rounds

    // Loop label
    final loopLabel = a.newLabel();
    a.bind(loopLabel);

    // Column round
    _emitQuarterRound(a);

    // Shuffle para diagonal
    a.pshufdXXI(xmm1, xmm1, 0x39);
    a.pshufdXXI(xmm2, xmm2, 0x4E);
    a.pshufdXXI(xmm3, xmm3, 0x93);

    // Diagonal round
    _emitQuarterRound(a);

    // Unshuffle
    a.pshufdXXI(xmm1, xmm1, 0x93);
    a.pshufdXXI(xmm2, xmm2, 0x4E);
    a.pshufdXXI(xmm3, xmm3, 0x39);

    // Loop
    a.dec(ecx);
    a.jnz(loopLabel);

    // Adiciona estado inicial
    a.padddXX(xmm0, xmm8);
    a.padddXX(xmm1, xmm9);
    a.padddXX(xmm2, xmm10);
    a.padddXX(xmm3, xmm11);

    // Escreve output
    a.movupsMX(ptr(r15, 0), xmm0);
    a.movupsMX(ptr(r15, 16), xmm1);
    a.movupsMX(ptr(r15, 32), xmm2);
    a.movupsMX(ptr(r15, 48), xmm3);

    // Restaura XMM
    a.movapsXM(xmm6, ptr(rsp, 0));
    a.movapsXM(xmm7, ptr(rsp, 16));
    a.movapsXM(xmm8, ptr(rsp, 32));
    a.movapsXM(xmm9, ptr(rsp, 48));
    a.movapsXM(xmm10, ptr(rsp, 64));
    a.movapsXM(xmm11, ptr(rsp, 80));

    // Epílogo
    a.addRI(rsp, 160);
    a.pop(r15);
    a.pop(r14);
    a.pop(r13);
    a.pop(r12);
    a.pop(rbx);
    a.ret();

    return runtime.add(code);
  }

  /// Emite um quarter round usando XMM0-XMM3, XMM4 como temp
  static void _emitQuarterRound(X86Assembler a) {
    // a += b
    a.padddXX(xmm0, xmm1);
    // d ^= a
    a.pxorXX(xmm3,
        xmm0); // Note: pxorXX needs to be verified if available or we used logical XMM op
    // d <<<= 16
    a.movapsXX(xmm4, xmm3);
    a.pslldXI(xmm4, 16);
    a.psrldXI(xmm3, 16);
    a.porXX(xmm3, xmm4);

    // c += d
    a.padddXX(xmm2, xmm3);
    // b ^= c
    a.pxorXX(xmm1, xmm2);
    // b <<<= 12
    a.movapsXX(xmm4, xmm1);
    a.pslldXI(xmm4, 12);
    a.psrldXI(xmm1, 20);
    a.porXX(xmm1, xmm4);

    // a += b
    a.padddXX(xmm0, xmm1);
    // d ^= a
    a.pxorXX(xmm3, xmm0);
    // d <<<= 8
    a.movapsXX(xmm4, xmm3);
    a.pslldXI(xmm4, 8);
    a.psrldXI(xmm3, 24);
    a.porXX(xmm3, xmm4);

    // c += d
    a.padddXX(xmm2, xmm3);
    // b ^= c
    a.pxorXX(xmm1, xmm2);
    // b <<<= 7
    a.movapsXX(xmm4, xmm1);
    a.pslldXI(xmm4, 7);
    a.psrldXI(xmm1, 25);
    a.porXX(xmm1, xmm4);
  }

  /// Gera um bloco de keystream
  void _generateBlock(int counter) {
    _blockFunc!(_keyPtr!, _noncePtr!, _constantsPtr!, counter, _outputPtr!);
    for (var i = 0; i < 64; i++) {
      _keystream[i] = _outputPtr![i];
    }
  }

  /// Criptografa/Descriptografa
  Uint8List crypt(Uint8List input) {
    if (_disposed) throw StateError('Already disposed');

    final output = Uint8List(input.length);
    cryptInto(input, output);
    return output;
  }

  void cryptInto(Uint8List input, Uint8List output) {
    xor(input, output);
  }

  void xor(Uint8List input, Uint8List output) {
    if (_disposed) throw StateError('Already disposed');
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    var counter = initialCounter;
    var offset = 0;

    while (offset < input.length) {
      _generateBlock(counter);
      counter++;

      final chunk = min(64, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ _keystream[i];
      }
      offset += chunk;
    }
  }
}

/// Versão usando builder para comparação
// ChaCha20AsmJitBuilder removido para simplificar benchmark
