import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:asmjit/asmjit.dart';

void main() {
  test('JitRuntime cache reuses pointer for same key', () {
    final runtime = JitRuntime();
    final bytes = Uint8List.fromList([0xC3]); // ret

    final fn1 = runtime.addBytesCached(bytes, key: 'ret');
    final fn2 = runtime.addBytesCached(bytes, key: 'ret');

    expect(identical(fn1, fn2), isTrue);
    expect(fn1.address, equals(fn2.address));

    runtime.dropCached('ret');
    final fn3 = runtime.addBytesCached(bytes, key: 'ret');
    expect(identical(fn1, fn3), isFalse);

    runtime.dispose();
  });
}
