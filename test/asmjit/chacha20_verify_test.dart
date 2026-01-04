import 'dart:typed_data';
import 'package:test/test.dart';
import '../../benchmark/asmjit/chacha20_impl/chacha20_baseline.dart';
import '../../benchmark/asmjit/chacha20_impl/chacha20_asmjit_optimized.dart';

void main() {
  group('ChaCha20 Verification', () {
    test('Optimized AsmJit matches Baseline (20 rounds)', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final nonce = Uint8List.fromList(List.generate(12, (i) => i * 3));
      final data = Uint8List.fromList(List.generate(64, (i) => i + 10));

      // Baseline
      final baseline =
          ChaCha20Baseline(key, nonce, initialCounter: 0, rounds: 20);
      final expected = Uint8List(data.length);
      baseline.cryptInto(data, expected);

      // Optimized (Hardcoded 0 rounds)
      final optimized = ChaCha20AsmJitOptimized(key, nonce, initialCounter: 0);
      final actual = Uint8List(data.length);
      optimized.cryptInto(data, actual);

      // Compare
      for (var i = 0; i < data.length; i++) {
        if (expected[i] != actual[i]) {
          fail(
              'Mismatch at index $i: expected 0x${expected[i].toRadixString(16)}, got 0x${actual[i].toRadixString(16)}');
        }
      }
    });
  });
}
