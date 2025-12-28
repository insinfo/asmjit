/// AsmJit Unit Tests - Compiler IR
///
/// Tests for high-level IR compiler functionality.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/core/compiler.dart' as ir;

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }

  group('X86CodeBuilder - Frame and Arguments', () {
    test('Builds function with default frame', () {
      final env = Environment.host();
      final builder = X86CodeBuilder(env: env);

      builder.addFunc(FuncSignature.noArgs(ret: TypeId.int32));
      builder.movRI(eax, 42);
      builder.endFunc();

      final code = builder.finalize();
      expect(code, isNotNull);

      final bytes = builder.code.text.buffer.bytes;
      expect(bytes, isNotEmpty);
      // Optional: search for ret (0xC3)
      expect(bytes.contains(0xC3), isTrue);
    });

    test('Builds function with explicit Frame attributes', () {
      final env = Environment.host();
      final builder = X86CodeBuilder(env: env);

      // Force rbx as preserved and use non-leaf frame
      final frame = FuncFrame.host(
        attr: FuncFrameAttributes.nonLeaf(
          localStackSize: 16,
          preservedRegs: [rbx],
        ),
      );

      builder.addFunc(FuncSignature.noArgs(ret: TypeId.int32), frame: frame);
      builder.movRI(ebx, 1);
      builder.movRR(eax, ebx);
      builder.endFunc();

      final func = builder.finalize();
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

      final signature = FuncSignature()
        ..setCallConvId(callConv)
        ..setRet(TypeId.int64)
        ..addArg(TypeId.int64)
        ..addArg(TypeId.int64)
        ..addArg(TypeId.int64)
        ..addArg(TypeId.int64)
        ..addArg(TypeId.int64)
        ..addArg(TypeId.int64)
        ..addArg(TypeId.int64)
        ..addArg(TypeId.float64);

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
