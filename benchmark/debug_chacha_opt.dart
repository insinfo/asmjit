//C:\MyDartProjects\asmjit\benchmark\debug_chacha_opt.dart
import 'dart:typed_data';
import 'asmjit/chacha20_impl/chacha20_asmjit_optimized.dart';

void main() {
  print('Debug ChaCha20 AsmJit Optimized');
  print('=' * 50);

  try {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final nonce = Uint8List.fromList(List.generate(12, (i) => i * 3));

    print('Creating instance...');
    final impl = ChaCha20AsmJitOptimized(key, nonce);
    print('✓ Instance created');

    print('\nTesting 64-byte encryption...');
    final input = Uint8List(64);
    final output = Uint8List(64);
    for (int i = 0; i < 64; i++) {
      input[i] = i;
    }

    print('Calling cryptInto...');
    impl.cryptInto(input, output);
    print('✓ Encryption succeeded');

    print('\nOutput (first 32 bytes):');
    print(output.sublist(0, 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));

    impl.dispose();
    ChaCha20AsmJitOptimized.disposeStatic();

    print('\n✓ All tests passed!');
  } catch (e, st) {
    print('\n✗ Error: $e');
    print('Stack trace:');
    print(st);
  }
}
