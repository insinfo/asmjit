import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';
import 'package:asmjit/src/asmjit/core/builder.dart' as ir;

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
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

  group('X86IrCompiler IR Tests', () {
    test('Emits multiple functions with invoke and mixed args', () {
      final env = Environment.host();
      final callConv = env.callingConvention == CallingConvention.win64
          ? CallConvId.x64Windows
          : CallConvId.x64SystemV;

      final signature = FuncSignature(
        callConvId: callConv,
        retType: TypeId.int64,
        args: [
          TypeId.int64,
          TypeId.int64,
          TypeId.int64,
          TypeId.int64,
          TypeId.int64,
          TypeId.int64,
          TypeId.int64,
          TypeId.float64,
        ],
      );

      final builder = ir.BaseBuilder();
      final calleeLabel = builder.newLabel();
      builder.addNode(ir.FuncNode('callee', signature: signature));
      builder.label(calleeLabel);
      builder.inst(
        X86InstId.kMov,
        [ir.RegOperand(rax), ir.ImmOperand(42)],
      );
      builder.addNode(ir.FuncRetNode());

      final callerLabel = builder.newLabel();
      builder.addNode(ir.FuncNode('caller', signature: signature));
      builder.label(callerLabel);

      final stackMem = X86Mem.baseDisp(rbp, -16, size: 8);
      builder.addNode(
        ir.InvokeNode(
          target: calleeLabel,
          args: [
            ir.RegOperand(rbx),
            ir.ImmOperand(5),
            ir.RegOperand(r12),
            ir.ImmOperand(7),
            ir.RegOperand(r13),
            ir.ImmOperand(9),
            ir.MemOperand(stackMem),
            ir.RegOperand(xmm2),
          ],
          ret: r10,
          signature: signature,
        ),
      );
      builder.inst(
        X86InstId.kMov,
        [ir.RegOperand(rax), ir.RegOperand(r10)],
      );
      builder.addNode(ir.FuncRetNode());

      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);
      X86IrCompiler(env: env).emitBuilder(builder, asm);

      final bytes = code.text.buffer.bytes;
      expect(bytes, isNotEmpty);
      expect(bytes.contains(0xE8), isTrue, reason: 'CALL rel32 expected');
      final retCount = bytes.where((b) => b == 0xC3).length;
      expect(retCount, greaterThanOrEqualTo(2));
    });
  });
}
