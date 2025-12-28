import 'package:asmjit/asmjit.dart';

import 'package:asmjit/src/asmjit/core/builder.dart';
import 'package:test/test.dart';

void main() {
  group('A64CodeBuilder', () {
    test('Vector ops build correct IR', () {
      final builder = A64CodeBuilder.create();
      final v0 = builder.newVecReg(sizeBits: 128);
      final v1 = builder.newVecReg(sizeBits: 128);
      final v2 = builder.newVecReg(sizeBits: 128);

      builder.faddVec(v0, v1, v2);
      builder.fsubVec(v0, v1, v2);
      builder.fmulVec(v0, v1, v2);
      builder.fdivVec(v0, v1, v2);

      // Inspect nodes
      final nodes = builder.nodes.nodes.toList();
      expect(nodes.length, equals(4));

      final n0 = nodes[0] as InstNode;
      expect(n0.instId, equals(A64InstId.kFadd));
      expect(n0.operands.length, equals(3));

      final n1 = nodes[1] as InstNode;
      expect(n1.instId, equals(A64InstId.kFsub));

      // Finalize to bytes (requires valid runtime/allocator usually, but explicit build works?)
      // builder.finalize() creates FinalizedCode
      final finalized = builder.finalize();
      expect(
          finalized.textBytes.length, equals(16)); // 4 instructions * 4 bytes
    });
  });
}
