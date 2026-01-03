//C:\MyDartProjects\asmjit\benchmark\asmjit\chacha20_impl\chacha20_optimized.dart
/// ChaCha20 - Implementação Dart otimizada
/// RFC 7539 - Versão otimizada com Uint32List, ByteData e buffers pré-alocados


import 'dart:math';
import 'dart:typed_data';

/// Implementação otimizada do ChaCha20 em Dart.
/// Usa Uint32List, buffers pré-alocados e minimiza alocações.
class ChaCha20Optimized {
  /// Constantes ChaCha20
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  // Buffers pré-alocados para evitar GC
  final Uint32List _keyWords = Uint32List(8);
  final Uint32List _nonceWords = Uint32List(3);
  final Uint8List _block = Uint8List(64);
  late final ByteData _blockData;

  final int initialCounter;

  /// Rotação à esquerda de 32 bits (inline para performance)
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

  /// Quarter round inline

  /// Gera um bloco de keystream in-place
  void _generateBlock(int counter) {
    // Inicializa estado localmente
    final state = Uint32List(16);
    state[0] = _constants[0];
    state[1] = _constants[1];
    state[2] = _constants[2];
    state[3] = _constants[3];
    for (var i = 0; i < 8; i++) {
      state[4 + i] = _keyWords[i];
    }
    state[12] = counter & 0xFFFFFFFF;
    state[13] = _nonceWords[0];
    state[14] = _nonceWords[1];
    state[15] = _nonceWords[2];

    // Copia para working
    final working = Uint32List(16);
    for (var i = 0; i < 16; i++) {
      working[i] = state[i];
    }

    void quarterRound(int a, int b, int c, int d) {
      working[a] = (working[a] + working[b]) & 0xFFFFFFFF;
      working[d] = working[d] ^ working[a];
      working[d] = _rotl32(working[d], 16);

      working[c] = (working[c] + working[d]) & 0xFFFFFFFF;
      working[b] = working[b] ^ working[c];
      working[b] = _rotl32(working[b], 12);

      working[a] = (working[a] + working[b]) & 0xFFFFFFFF;
      working[d] = working[d] ^ working[a];
      working[d] = _rotl32(working[d], 8);

      working[c] = (working[c] + working[d]) & 0xFFFFFFFF;
      working[b] = working[b] ^ working[c];
      working[b] = _rotl32(working[b], 7);
    }

    // 10 double rounds (20 rounds total)
    for (var i = 0; i < 10; i++) {
      // Column rounds
      quarterRound(0, 4, 8, 12);
      quarterRound(1, 5, 9, 13);
      quarterRound(2, 6, 10, 14);
      quarterRound(3, 7, 11, 15);
      // Diagonal rounds
      quarterRound(0, 5, 10, 15);
      quarterRound(1, 6, 11, 12);
      quarterRound(2, 7, 8, 13);
      quarterRound(3, 4, 9, 14);
    }

    // Adiciona estado inicial e escreve no buffer
    for (var i = 0; i < 16; i++) {
      final v = (working[i] + state[i]) & 0xFFFFFFFF;
      _blockData.setUint32(i * 4, v, Endian.little);
    }
  }

  /// Construtor
  ChaCha20Optimized(Uint8List key, Uint8List nonce, {this.initialCounter = 0})
      : _blockData = ByteData.sublistView(Uint8List(64)) {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be 12 bytes');
    }

    // Inicializa _blockData com o buffer correto
    _blockData.buffer.asUint8List().setAll(0, _block);

    // Pre-load key
    for (var i = 0; i < 8; i++) {
      _keyWords[i] = _load32(key, i * 4);
    }
    // Pre-load nonce
    for (var i = 0; i < 3; i++) {
      _nonceWords[i] = _load32(nonce, i * 4);
    }
  }

  /// Criptografa/Descriptografa
  Uint8List crypt(Uint8List input) {
    final output = Uint8List(input.length);
    cryptInto(input, output);
    return output;
  }

  /// Versão que escreve em buffer existente (zero allocation)
  void cryptInto(Uint8List input, Uint8List output) {
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
        output[offset + i] = input[offset + i] ^ _block[i];
      }
      offset += chunk;
    }
  }

  /// Gera apenas keystream
  void generateKeystreamInto(Uint8List output) {
    var counter = initialCounter;
    var offset = 0;

    while (offset < output.length) {
      _generateBlock(counter);
      counter++;

      final chunk = min(64, output.length - offset);
      output.setRange(offset, offset + chunk, _block);
      offset += chunk;
    }
  }
}

/// Versão com loop unrolling adicional
class ChaCha20OptimizedUnroll {
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  final Uint32List _keyWords = Uint32List(8);
  final Uint32List _nonceWords = Uint32List(3);
  final Uint8List _block = Uint8List(64);

  final int initialCounter;

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

  ChaCha20OptimizedUnroll(Uint8List key, Uint8List nonce,
      {this.initialCounter = 0}) {
    if (key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');

    for (var i = 0; i < 8; i++) {
      _keyWords[i] = _load32(key, i * 4);
    }
    for (var i = 0; i < 3; i++) {
      _nonceWords[i] = _load32(nonce, i * 4);
    }
  }

  /// Gera bloco com quarter rounds totalmente inline
  void _generateBlock(int counter) {
    // Load state
    var s0 = _constants[0],
        s1 = _constants[1],
        s2 = _constants[2],
        s3 = _constants[3];
    var s4 = _keyWords[0],
        s5 = _keyWords[1],
        s6 = _keyWords[2],
        s7 = _keyWords[3];
    var s8 = _keyWords[4],
        s9 = _keyWords[5],
        s10 = _keyWords[6],
        s11 = _keyWords[7];
    var s12 = counter & 0xFFFFFFFF;
    var s13 = _nonceWords[0], s14 = _nonceWords[1], s15 = _nonceWords[2];

    // Copy to working
    var w0 = s0, w1 = s1, w2 = s2, w3 = s3;
    var w4 = s4, w5 = s5, w6 = s6, w7 = s7;
    var w8 = s8, w9 = s9, w10 = s10, w11 = s11;
    var w12 = s12, w13 = s13, w14 = s14, w15 = s15;

    // 10 double rounds
    for (var i = 0; i < 10; i++) {
      // Column 0
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

      // Column 1
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

      // Column 2
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

      // Column 3
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

      // Diagonal 0
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

      // Diagonal 1
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

      // Diagonal 2
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

      // Diagonal 3
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

    // Add initial state and write
    final bd = ByteData.sublistView(_block);
    bd.setUint32(0, (w0 + s0) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(4, (w1 + s1) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(8, (w2 + s2) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(12, (w3 + s3) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(16, (w4 + s4) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(20, (w5 + s5) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(24, (w6 + s6) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(28, (w7 + s7) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(32, (w8 + s8) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(36, (w9 + s9) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(40, (w10 + s10) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(44, (w11 + s11) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(48, (w12 + s12) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(52, (w13 + s13) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(56, (w14 + s14) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(60, (w15 + s15) & 0xFFFFFFFF, Endian.little);
  }

  Uint8List crypt(Uint8List input) {
    final output = Uint8List(input.length);
    cryptInto(input, output);
    return output;
  }

  void cryptInto(Uint8List input, Uint8List output) {
    var counter = initialCounter;
    var offset = 0;

    while (offset < input.length) {
      _generateBlock(counter);
      counter++;

      final chunk = min(64, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ _block[i];
      }
      offset += chunk;
    }
  }
}
