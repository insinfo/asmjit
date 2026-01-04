//C:\MyDartProjects\asmjit\benchmark\asmjit\chacha_debug.dart
import 'dart:typed_data';
import 'chacha20_impl/chacha20_asmjit_optimized.dart';

// dart compile exe benchmark/debug_chacha_opt.dart -o build/debug_chacha_opt.exe
//C:/gcc/bin/gdb.exe -ex "set pagination off" -ex "set logging enabled on" -ex "run" -ex "bt" --args build\debug_chacha_opt.exe
void main() {
  print('Starting ChaCha20 Debug Repro (Test Match)');

  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final nonce = Uint8List.fromList(List.generate(12, (i) => i * 3));
  final input = Uint8List(64); // Zeros
  final output = Uint8List(64);

  // Counter 0
  final chacha = ChaCha20AsmJitOptimized(key, nonce, initialCounter: 0);
  chacha.cryptInto(input, output);

  print('Output (first 16 bytes):');
  print(output
      .sublist(0, 16)
      .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
      .toList());
}
