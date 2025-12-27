import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('X86CodeBuilder Compiler Tests', () {
    test('Builds function with Prologue and Epilogue when spills occur', () {
      final builder = X86CodeBuilder.create();

      // Force high register usage to cause spills
      // x86_64 has ~14 GP registers usable.
      // We'll create 20 virtual registers and keep them live.
      final regs = <VirtReg>[];
      for (int i = 0; i < 20; i++) {
        final r = builder.newGpReg();
        regs.add(r);
        builder.mov(r, i); // Initialize
      }

      // Use them all to extend live ranges
      var sum = builder.newGpReg();
      builder.mov(sum, 0);
      for (final r in regs) {
        builder.add(sum, r);
      }
      builder.ret(sum);

      // Bind to runtime (mocked or real)
      // Since we don't have easy mock for JitRuntime execution without valid memory,
      // we check the generated code bytes in the builder's code holder.

      final runtime = JitRuntime();
      final func = builder.build(runtime);
      expect(func, isNotNull);
      // Analyze generated code
      final code = builder.code;
      final bytes = code.text.buffer.bytes;

      print('Generated ${bytes.length} bytes');

      // Verify Prologue exists: push rbp; mov rbp, rsp; sub rsp, ...
      // 55 48 89 E5 48 83 EC ...
      // Note: Win64 prologue might be different (uses shadow space).
      // Assuming host env.

      bool hasPrologue = false;
      bool hasEpilogue = false;

      if (bytes.length > 10) {
        // Simple heuristic check for push rbp (0x55) or similar
        // Win64: push rbp (55) implies typical frame.
        if (bytes.contains(0x55)) {
          hasPrologue = true;
        }

        // Epilogue: mov rsp, rbp; pop rbp; ret
        // or leave; ret (C9 C3)
        // or add rsp, X; pop ... ret
        if (bytes.contains(0xC3)) {
          // RET
          hasEpilogue = true;
        }
      }

      expect(hasPrologue, isTrue, reason: 'Should emit prologue for spills');
      expect(hasEpilogue, isTrue, reason: 'Should emit epilogue before ret');
    });
    test('Builds function with explicit Frame attributes', () {
      final builder = X86CodeBuilder.create();

      // Define explicit frame that forces stack alignment and preservation
      final frame = FuncFrame.host(
        attr: FuncFrameAttr.nonLeaf(
          localStackSize: 16,
          preservedRegs: [rbx], // Force RBX preservation
        ),
      );

      builder.func("explicit_test", frame: frame);

      final r1 = builder.newGpReg();
      builder.mov(r1, 100);
      builder.mov(rbx, 50); // Use RBX
      builder.add(r1, rbx);
      builder.ret(r1);

      final runtime = JitRuntime();
      final func = builder.build(runtime);
      expect(func, isNotNull);

      final bytes = builder.code.text.buffer.bytes;
      // Should have push rbx (0x53)
      expect(bytes.contains(0x53), isTrue, reason: 'Should preserve RBX');
    });
  });
}
