//C:\MyDartProjects\asmjit\benchmark\asmjit\chacha20_impl\chacha20_ffi_pointer.dart
/// ChaCha20 - Implementação com ponteiros FFI (C-style)
/// Usa apenas Pointer<T> para acesso a dados, minimizando overhead de Dart


import 'dart:ffi' as ffi;
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;

/// Implementação do ChaCha20 usando apenas ponteiros FFI.
/// Todos os buffers são alocados em memória nativa.
class ChaCha20FFIPointer {
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  // Ponteiros para buffers nativos
  final ffi.Pointer<ffi.Uint32> _keyWords;
  final ffi.Pointer<ffi.Uint32> _nonceWords;
  final ffi.Pointer<ffi.Uint32> _state;
  final ffi.Pointer<ffi.Uint32> _working;
  final ffi.Pointer<ffi.Uint8> _block;

  final int initialCounter;
  bool _disposed = false;

  /// Rotação à esquerda de 32 bits
  static int _rotl32(int v, int c) {
    final v32 = v & 0xFFFFFFFF;
    return ((v32 << c) | (v32 >> (32 - c))) & 0xFFFFFFFF;
  }

  /// Load 32-bit little-endian
  static int _load32(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// Quarter round usando acesso direto a ponteiros
  void _quarterRound(int a, int b, int c, int d) {
    var va = _working[a];
    var vb = _working[b];
    var vc = _working[c];
    var vd = _working[d];

    va = (va + vb) & 0xFFFFFFFF;
    vd ^= va;
    vd = _rotl32(vd, 16);

    vc = (vc + vd) & 0xFFFFFFFF;
    vb ^= vc;
    vb = _rotl32(vb, 12);

    va = (va + vb) & 0xFFFFFFFF;
    vd ^= va;
    vd = _rotl32(vd, 8);

    vc = (vc + vd) & 0xFFFFFFFF;
    vb ^= vc;
    vb = _rotl32(vb, 7);

    _working[a] = va;
    _working[b] = vb;
    _working[c] = vc;
    _working[d] = vd;
  }

  /// Gera um bloco de keystream
  void _generateBlock(int counter) {
    // Inicializa estado
    _state[0] = _constants[0];
    _state[1] = _constants[1];
    _state[2] = _constants[2];
    _state[3] = _constants[3];
    for (var i = 0; i < 8; i++) {
      _state[4 + i] = _keyWords[i];
    }
    _state[12] = counter & 0xFFFFFFFF;
    _state[13] = _nonceWords[0];
    _state[14] = _nonceWords[1];
    _state[15] = _nonceWords[2];

    // Copia para working
    for (var i = 0; i < 16; i++) {
      _working[i] = _state[i];
    }

    // 10 double rounds
    for (var i = 0; i < 10; i++) {
      // Column rounds
      _quarterRound(0, 4, 8, 12);
      _quarterRound(1, 5, 9, 13);
      _quarterRound(2, 6, 10, 14);
      _quarterRound(3, 7, 11, 15);
      // Diagonal rounds
      _quarterRound(0, 5, 10, 15);
      _quarterRound(1, 6, 11, 12);
      _quarterRound(2, 7, 8, 13);
      _quarterRound(3, 4, 9, 14);
    }

    // Adiciona estado inicial e escreve no bloco
    for (var i = 0; i < 16; i++) {
      final v = (_working[i] + _state[i]) & 0xFFFFFFFF;
      _block[i * 4 + 0] = v & 0xFF;
      _block[i * 4 + 1] = (v >> 8) & 0xFF;
      _block[i * 4 + 2] = (v >> 16) & 0xFF;
      _block[i * 4 + 3] = (v >> 24) & 0xFF;
    }
  }

  /// Construtor - aloca todos os buffers em memória nativa
  ChaCha20FFIPointer(Uint8List key, Uint8List nonce, {this.initialCounter = 0})
      : _keyWords = pkgffi.calloc<ffi.Uint32>(8),
        _nonceWords = pkgffi.calloc<ffi.Uint32>(3),
        _state = pkgffi.calloc<ffi.Uint32>(16),
        _working = pkgffi.calloc<ffi.Uint32>(16),
        _block = pkgffi.calloc<ffi.Uint8>(64) {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be 12 bytes');
    }

    // Carrega key
    for (var i = 0; i < 8; i++) {
      _keyWords[i] = _load32(key, i * 4);
    }
    // Carrega nonce
    for (var i = 0; i < 3; i++) {
      _nonceWords[i] = _load32(nonce, i * 4);
    }
  }

  /// Libera memória nativa
  void dispose() {
    if (_disposed) return;
    pkgffi.calloc.free(_keyWords);
    pkgffi.calloc.free(_nonceWords);
    pkgffi.calloc.free(_state);
    pkgffi.calloc.free(_working);
    pkgffi.calloc.free(_block);
    _disposed = true;
  }

  /// Criptografa usando ponteiros nativos para input/output
  void cryptNative(
    ffi.Pointer<ffi.Uint8> input,
    ffi.Pointer<ffi.Uint8> output,
    int length,
  ) {
    if (_disposed) throw StateError('Already disposed');

    var counter = initialCounter;
    var offset = 0;

    while (offset < length) {
      _generateBlock(counter);
      counter++;

      final chunk = min(64, length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ _block[i];
      }
      offset += chunk;
    }
  }

  /// Criptografa convertendo Uint8List para ponteiros
  Uint8List crypt(Uint8List input) {
    if (_disposed) throw StateError('Already disposed');

    final output = Uint8List(input.length);

    // Aloca buffers nativos temporários
    final inputPtr = pkgffi.calloc<ffi.Uint8>(input.length);
    final outputPtr = pkgffi.calloc<ffi.Uint8>(input.length);

    try {
      // Copia input para memória nativa
      for (var i = 0; i < input.length; i++) {
        inputPtr[i] = input[i];
      }

      // Processa
      cryptNative(inputPtr, outputPtr, input.length);

      // Copia output de volta
      for (var i = 0; i < input.length; i++) {
        output[i] = outputPtr[i];
      }
    } finally {
      pkgffi.calloc.free(inputPtr);
      pkgffi.calloc.free(outputPtr);
    }

    return output;
  }

  /// Versão que evita alocação extra usando asTypedList
  void cryptInto(Uint8List input, Uint8List output) {
    if (_disposed) throw StateError('Already disposed');
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    var counter = initialCounter;
    var offset = 0;

    // Usa view do bloco nativo
    final blockView = _block.asTypedList(64);

    while (offset < input.length) {
      _generateBlock(counter);
      counter++;

      final chunk = min(64, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ blockView[i];
      }
      offset += chunk;
    }
  }
}

/// Versão otimizada com acesso via .elementAt() e variáveis locais
class ChaCha20FFIPointerOptimized {
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  final ffi.Pointer<ffi.Uint32> _keyWords;
  final ffi.Pointer<ffi.Uint32> _nonceWords;
  final ffi.Pointer<ffi.Uint32> _state;
  final ffi.Pointer<ffi.Uint32> _working;
  final ffi.Pointer<ffi.Uint8> _block;

  final int initialCounter;
  bool _disposed = false;

  static int _rotl32(int v, int c) {
    final v32 = v & 0xFFFFFFFF;
    return ((v32 << c) | (v32 >> (32 - c))) & 0xFFFFFFFF;
  }

  static int _load32(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  ChaCha20FFIPointerOptimized(Uint8List key, Uint8List nonce,
      {this.initialCounter = 0})
      : _keyWords = pkgffi.calloc<ffi.Uint32>(8),
        _nonceWords = pkgffi.calloc<ffi.Uint32>(3),
        _state = pkgffi.calloc<ffi.Uint32>(16),
        _working = pkgffi.calloc<ffi.Uint32>(16),
        _block = pkgffi.calloc<ffi.Uint8>(64) {
    if (key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');

    for (var i = 0; i < 8; i++) {
      _keyWords[i] = _load32(key, i * 4);
    }
    for (var i = 0; i < 3; i++) {
      _nonceWords[i] = _load32(nonce, i * 4);
    }
  }

  void dispose() {
    if (_disposed) return;
    pkgffi.calloc.free(_keyWords);
    pkgffi.calloc.free(_nonceWords);
    pkgffi.calloc.free(_state);
    pkgffi.calloc.free(_working);
    pkgffi.calloc.free(_block);
    _disposed = true;
  }

  /// Gera bloco com variáveis locais para evitar acesso repetido a ponteiros
  void _generateBlock(int counter) {
    // Carrega em variáveis locais
    var w0 = _constants[0],
        w1 = _constants[1],
        w2 = _constants[2],
        w3 = _constants[3];
    var w4 = _keyWords[0],
        w5 = _keyWords[1],
        w6 = _keyWords[2],
        w7 = _keyWords[3];
    var w8 = _keyWords[4],
        w9 = _keyWords[5],
        w10 = _keyWords[6],
        w11 = _keyWords[7];
    var w12 = counter & 0xFFFFFFFF;
    var w13 = _nonceWords[0], w14 = _nonceWords[1], w15 = _nonceWords[2];

    final s0 = w0, s1 = w1, s2 = w2, s3 = w3;
    final s4 = w4, s5 = w5, s6 = w6, s7 = w7;
    final s8 = w8, s9 = w9, s10 = w10, s11 = w11;
    final s12 = w12, s13 = w13, s14 = w14, s15 = w15;

    // 10 double rounds
    for (var i = 0; i < 10; i++) {
      // Column rounds
      w0 = (w0 + w4) & 0xFFFFFFFF;
      w12 ^= w0;
      w12 = _rotl32(w12, 16);
      w8 = (w8 + w12) & 0xFFFFFFFF;
      w4 ^= w8;
      w4 = _rotl32(w4, 12);
      w0 = (w0 + w4) & 0xFFFFFFFF;
      w12 ^= w0;
      w12 = _rotl32(w12, 8);
      w8 = (w8 + w12) & 0xFFFFFFFF;
      w4 ^= w8;
      w4 = _rotl32(w4, 7);

      w1 = (w1 + w5) & 0xFFFFFFFF;
      w13 ^= w1;
      w13 = _rotl32(w13, 16);
      w9 = (w9 + w13) & 0xFFFFFFFF;
      w5 ^= w9;
      w5 = _rotl32(w5, 12);
      w1 = (w1 + w5) & 0xFFFFFFFF;
      w13 ^= w1;
      w13 = _rotl32(w13, 8);
      w9 = (w9 + w13) & 0xFFFFFFFF;
      w5 ^= w9;
      w5 = _rotl32(w5, 7);

      w2 = (w2 + w6) & 0xFFFFFFFF;
      w14 ^= w2;
      w14 = _rotl32(w14, 16);
      w10 = (w10 + w14) & 0xFFFFFFFF;
      w6 ^= w10;
      w6 = _rotl32(w6, 12);
      w2 = (w2 + w6) & 0xFFFFFFFF;
      w14 ^= w2;
      w14 = _rotl32(w14, 8);
      w10 = (w10 + w14) & 0xFFFFFFFF;
      w6 ^= w10;
      w6 = _rotl32(w6, 7);

      w3 = (w3 + w7) & 0xFFFFFFFF;
      w15 ^= w3;
      w15 = _rotl32(w15, 16);
      w11 = (w11 + w15) & 0xFFFFFFFF;
      w7 ^= w11;
      w7 = _rotl32(w7, 12);
      w3 = (w3 + w7) & 0xFFFFFFFF;
      w15 ^= w3;
      w15 = _rotl32(w15, 8);
      w11 = (w11 + w15) & 0xFFFFFFFF;
      w7 ^= w11;
      w7 = _rotl32(w7, 7);

      // Diagonal rounds
      w0 = (w0 + w5) & 0xFFFFFFFF;
      w15 ^= w0;
      w15 = _rotl32(w15, 16);
      w10 = (w10 + w15) & 0xFFFFFFFF;
      w5 ^= w10;
      w5 = _rotl32(w5, 12);
      w0 = (w0 + w5) & 0xFFFFFFFF;
      w15 ^= w0;
      w15 = _rotl32(w15, 8);
      w10 = (w10 + w15) & 0xFFFFFFFF;
      w5 ^= w10;
      w5 = _rotl32(w5, 7);

      w1 = (w1 + w6) & 0xFFFFFFFF;
      w12 ^= w1;
      w12 = _rotl32(w12, 16);
      w11 = (w11 + w12) & 0xFFFFFFFF;
      w6 ^= w11;
      w6 = _rotl32(w6, 12);
      w1 = (w1 + w6) & 0xFFFFFFFF;
      w12 ^= w1;
      w12 = _rotl32(w12, 8);
      w11 = (w11 + w12) & 0xFFFFFFFF;
      w6 ^= w11;
      w6 = _rotl32(w6, 7);

      w2 = (w2 + w7) & 0xFFFFFFFF;
      w13 ^= w2;
      w13 = _rotl32(w13, 16);
      w8 = (w8 + w13) & 0xFFFFFFFF;
      w7 ^= w8;
      w7 = _rotl32(w7, 12);
      w2 = (w2 + w7) & 0xFFFFFFFF;
      w13 ^= w2;
      w13 = _rotl32(w13, 8);
      w8 = (w8 + w13) & 0xFFFFFFFF;
      w7 ^= w8;
      w7 = _rotl32(w7, 7);

      w3 = (w3 + w4) & 0xFFFFFFFF;
      w14 ^= w3;
      w14 = _rotl32(w14, 16);
      w9 = (w9 + w14) & 0xFFFFFFFF;
      w4 ^= w9;
      w4 = _rotl32(w4, 12);
      w3 = (w3 + w4) & 0xFFFFFFFF;
      w14 ^= w3;
      w14 = _rotl32(w14, 8);
      w9 = (w9 + w14) & 0xFFFFFFFF;
      w4 ^= w9;
      w4 = _rotl32(w4, 7);
    }

    // Add e store direto
    void store(int idx, int v) {
      _block[idx * 4 + 0] = v & 0xFF;
      _block[idx * 4 + 1] = (v >> 8) & 0xFF;
      _block[idx * 4 + 2] = (v >> 16) & 0xFF;
      _block[idx * 4 + 3] = (v >> 24) & 0xFF;
    }

    store(0, (w0 + s0) & 0xFFFFFFFF);
    store(1, (w1 + s1) & 0xFFFFFFFF);
    store(2, (w2 + s2) & 0xFFFFFFFF);
    store(3, (w3 + s3) & 0xFFFFFFFF);
    store(4, (w4 + s4) & 0xFFFFFFFF);
    store(5, (w5 + s5) & 0xFFFFFFFF);
    store(6, (w6 + s6) & 0xFFFFFFFF);
    store(7, (w7 + s7) & 0xFFFFFFFF);
    store(8, (w8 + s8) & 0xFFFFFFFF);
    store(9, (w9 + s9) & 0xFFFFFFFF);
    store(10, (w10 + s10) & 0xFFFFFFFF);
    store(11, (w11 + s11) & 0xFFFFFFFF);
    store(12, (w12 + s12) & 0xFFFFFFFF);
    store(13, (w13 + s13) & 0xFFFFFFFF);
    store(14, (w14 + s14) & 0xFFFFFFFF);
    store(15, (w15 + s15) & 0xFFFFFFFF);
  }

  void cryptInto(Uint8List input, Uint8List output) {
    if (_disposed) throw StateError('Already disposed');

    var counter = initialCounter;
    var offset = 0;
    final blockView = _block.asTypedList(64);

    while (offset < input.length) {
      _generateBlock(counter);
      counter++;

      final chunk = min(64, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ blockView[i];
      }
      offset += chunk;
    }
  }

  Uint8List crypt(Uint8List input) {
    final output = Uint8List(input.length);
    cryptInto(input, output);
    return output;
  }
}
