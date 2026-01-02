import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('RAPass Coalescing Tests', () {
    test('Coalesce simple move', () {
      final compiler = X86Compiler();
      compiler.addFunc(FuncSignature.i64());

      final v0 = compiler.newGp64('v0');
      final v1 = compiler.newGp64('v1');

      compiler.mov(v0, Imm(10));
      compiler.mov(v1, v0);
      compiler.ret([v1]);

      compiler.endFunc();
      compiler.finalize();

      // We can't easily inspect internal RA state without exposing it.
      // But we can check if the code runs (it naturally should).
      // To strictly verify coalescing, we would need to check if v0/v1 share the same physId or bundle.
      // For now, this test ensures the coalescing logic doesn't crash or produce invalid code structure.
    });

    test('Coalesce chain', () {
      final compiler = X86Compiler();
      compiler.addFunc(FuncSignature.i64());

      final v0 = compiler.newGp64('v0');
      final v1 = compiler.newGp64('v1');
      final v2 = compiler.newGp64('v2');

      compiler.mov(v0, Imm(10));
      compiler.mov(v1, v0);
      compiler.mov(v2, v1);
      compiler.ret([v2]);

      compiler.endFunc();
      compiler.finalize();
    });
  });
}
