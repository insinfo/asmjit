import 'dart:typed_data';

import 'chacha20_impl/chacha20_asmjit_optimized.dart';

void main() {
  print('Starting ChaCha20 Debug Repro');

  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final nonce = Uint8List.fromList(List.generate(12, (i) => i));
  final input = Uint8List(64); // Encrypting 64 bytes of zeros
  final output = Uint8List(64);

  final chacha = ChaCha20AsmJitOptimized(key, nonce, initialCounter: 1);
  chacha.cryptInto(input, output);

  print('Output (first 16 bytes):');
  print(output
      .sublist(0, 16)
      .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
      .toList());

  // Expected: 0x35 ... (based on error message)
  // Got: 0x48/0xb0 ?
}
