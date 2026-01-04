//C:\MyDartProjects\asmjit\benchmark\debug_chacha_opt.dart
import 'dart:typed_data';
import 'asmjit/chacha20_impl/chacha20_asmjit_optimized.dart';
import 'asmjit/chacha20_impl/chacha20_baseline.dart';

void main() {
  print('Debug ChaCha20 AsmJit Optimized vs Baseline');
  print('=' * 50);

  try {
    // 1. Setup Test Vectors
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final nonce = Uint8List.fromList(List.generate(12, (i) => i));
    
    print('Key:   ${key.sublist(0, 8)}...');
    print('Nonce: ${nonce}...');

    // 2. Create Instances
    print('\nCreating instances...');
    final baseline = ChaCha20Baseline(key, nonce);
    final optimized = ChaCha20AsmJitOptimized(key, nonce);
    print('✓ Instances created');

    // 3. Test 1: Single Block (64 bytes)
    print('\nTest 1: Single Block (64 bytes)');
    _runTest(baseline, optimized, 64);

    // 4. Test 2: Multiple Blocks (128 bytes)
    print('\nTest 2: Multiple Blocks (128 bytes)');
    _runTest(baseline, optimized, 128);

    // 5. Test 3: Partial Block (100 bytes)
    print('\nTest 3: Partial Block (100 bytes)');
    _runTest(baseline, optimized, 100);

    // 6. Test 4: Large Buffer (1024 bytes)
    print('\nTest 4: Large Buffer (1024 bytes)');
    _runTest(baseline, optimized, 1024);

    optimized.dispose();
    ChaCha20AsmJitOptimized.disposeStatic();

    print('\n✓ All comparison tests passed!');
  } catch (e, st) {
    print('\n✗ Error: $e');
    print('Stack trace:');
    print(st);
  }
}

void _runTest(ChaCha20Baseline baseline, ChaCha20AsmJitOptimized optimized, int length) {
  final input = Uint8List(length);
  for (int i = 0; i < length; i++) {
    input[i] = i % 256;
  }

  final outBaseline = Uint8List(length);
  final outOptimized = Uint8List(length);

  // Reset counters if possible or create new instances? 
  // The implementations maintain state (counter). 
  // Since we are reusing instances, the counter increments.
  // We must ensure both are in sync.
  // ChaCha20Baseline increments counter internally.
  // ChaCha20AsmJitOptimized increments counter internally.
  // As long as we call them in the same order with same lengths, they should match.

  baseline.cryptInto(input, outBaseline);
  optimized.cryptInto(input, outOptimized);

  bool match = true;
  for (int i = 0; i < length; i++) {
    if (outBaseline[i] != outOptimized[i]) {
      match = false;
      print('Mismatch at byte $i: Baseline=${outBaseline[i].toRadixString(16)} Optimized=${outOptimized[i].toRadixString(16)}');
      break;
    }
  }

  if (match) {
    print('✓ Output matches');
  } else {
    throw Exception('Output mismatch for length $length | outOptimized: $outOptimized | outBaseline $outBaseline');
  }
}
