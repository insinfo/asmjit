/// ChaCha20 - Implementação Dart pura (Baseline)
/// RFC 7539 - Versão simples para comparação de performance
library;

import 'dart:math';
import 'dart:typed_data';

/// Implementação baseline do ChaCha20 em Dart puro.
/// Usa List<int> e operações simples sem otimizações.
class ChaCha20Baseline {
  /// Constantes ChaCha20 "expand 32-byte k"
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  final List<int> _keyWords;
  final List<int> _nonceWords;
  final int initialCounter;
  final int rounds;

  /// Rotação à esquerda de 32 bits
  static int _rotl32(int v, int c) {
    final v32 = v & 0xFFFFFFFF;
    return ((v32 << c) | (v32 >> (32 - c))) & 0xFFFFFFFF;
  }

  /// Converte bytes para lista de palavras de 32 bits (little-endian)
  static List<int> _bytesToWords(Uint8List data) {
    final words = <int>[];
    final bd =
        ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    for (var i = 0; i < data.length; i += 4) {
      words.add(bd.getUint32(i, Endian.little));
    }
    return words;
  }

  /// Quarter round do ChaCha
  static void _quarterRound(List<int> x, int a, int b, int c, int d) {
    x[a] = (x[a] + x[b]) & 0xFFFFFFFF;
    x[d] = x[d] ^ x[a];
    x[d] = _rotl32(x[d], 16);

    x[c] = (x[c] + x[d]) & 0xFFFFFFFF;
    x[b] = x[b] ^ x[c];
    x[b] = _rotl32(x[b], 12);

    x[a] = (x[a] + x[b]) & 0xFFFFFFFF;
    x[d] = x[d] ^ x[a];
    x[d] = _rotl32(x[d], 8);

    x[c] = (x[c] + x[d]) & 0xFFFFFFFF;
    x[b] = x[b] ^ x[c];
    x[b] = _rotl32(x[b], 7);
  }

  /// Gera um bloco de keystream
  static List<int> _chachaBlock(
    List<int> keyWords,
    int counter,
    List<int> nonceWords,
    int rounds,
  ) {
    // Inicializa estado
    final state = List<int>.filled(16, 0);
    state.setRange(0, 4, _constants);
    state.setRange(4, 12, keyWords);
    state[12] = counter & 0xFFFFFFFF;
    state.setRange(13, 16, nonceWords);

    // Working state
    final working = List<int>.from(state, growable: false);

    // Aplica rounds
    for (var i = 0; i < rounds ~/ 2; i++) {
      // Column rounds
      _quarterRound(working, 0, 4, 8, 12);
      _quarterRound(working, 1, 5, 9, 13);
      _quarterRound(working, 2, 6, 10, 14);
      _quarterRound(working, 3, 7, 11, 15);
      // Diagonal rounds
      _quarterRound(working, 0, 5, 10, 15);
      _quarterRound(working, 1, 6, 11, 12);
      _quarterRound(working, 2, 7, 8, 13);
      _quarterRound(working, 3, 4, 9, 14);
    }

    // Adiciona estado inicial
    for (var i = 0; i < 16; i++) {
      working[i] = (working[i] + state[i]) & 0xFFFFFFFF;
    }

    return working;
  }

  /// Converte estado para bytes
  static Uint8List _wordsToBytes(List<int> state) {
    final out = Uint8List(64);
    final bd = ByteData.sublistView(out);
    for (var i = 0; i < 16; i++) {
      bd.setUint32(i * 4, state[i], Endian.little);
    }
    return out;
  }

  /// Construtor
  ChaCha20Baseline(
    Uint8List key,
    Uint8List nonce, {
    this.initialCounter = 0,
    this.rounds = 20,
  })  : _keyWords = _bytesToWords(key),
        _nonceWords = _bytesToWords(nonce) {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be 12 bytes');
    }
  }

  /// Criptografa/Descriptografa (operação XOR)
  Uint8List crypt(Uint8List input) {
    final output = Uint8List(input.length);
    cryptInto(input, output);
    return output;
  }

  /// Versão que escreve em buffer existente
  void cryptInto(Uint8List input, Uint8List output) {
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    const blockSize = 64;
    var counter = initialCounter;
    var offset = 0;

    while (offset < input.length) {
      final ksWords = _chachaBlock(_keyWords, counter, _nonceWords, rounds);
      final ksBytes = _wordsToBytes(ksWords);
      counter++;

      final chunk = min(blockSize, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ ksBytes[i];
      }
      offset += chunk;
    }
  }

  /// Gera apenas keystream (para benchmark)
  Uint8List generateKeystream(int length) {
    final output = Uint8List(length);
    const blockSize = 64;
    var counter = initialCounter;
    var offset = 0;

    while (offset < length) {
      final ksWords = _chachaBlock(_keyWords, counter, _nonceWords, rounds);
      final ksBytes = _wordsToBytes(ksWords);
      counter++;

      final chunk = min(blockSize, length - offset);
      output.setRange(offset, offset + chunk, ksBytes);
      offset += chunk;
    }

    return output;
  }
}
